-- ============================================================
-- Migration 0051 - saisies : edition par l'auteur chef_bande (tracee,
--                  re-validee), motif d'immuabilite rls35/rls46
-- ------------------------------------------------------------
-- OBJET : autoriser un chef_bande a CORRIGER ses propres saisies (pas
-- de fenetre temporelle : une saisie J26 peut etre corrigee plus tard,
-- le journal 0049 couvre le risque). Le manager garde son UPDATE total
-- (rls21_saisies_update, INCHANGE). Cote front, une edition chef cree
-- une notification 'saisie' en_attente (modification) que le manager
-- re-valide - hierarchie.
--
-- SONDE COLONNE D'AUTEUR (exigee par le brief) : la table saisies est
-- HERITEE (aucun DDL dans le depot ; le payload addSaisie n'envoie
-- aucun created_by ; 0021 ne mentionne pas d'auteur). Impossible de
-- garantir qu'une colonne d'auteur existe. La migration est donc
-- AUTO-ADAPTATIVE : add column if not exists created_by / created_at
-- (idempotent - no-op si le schema herite les porte deja). CONSEQUENCE
-- assumee : les saisies EXISTANTES prennent created_by = NULL (auth.uid()
-- vaut NULL a l'ALTER dans le SQL editor) -> NON editables par le chef
-- (seul le manager les corrige). Les NOUVELLES saisies du chef prennent
-- created_by = auth.uid() par DEFAUT a l'insert (aucun changement front
-- necessaire, motif 0045/0046). created_at sert d'ancre de gel.
--
-- _ops NOTE : saisies n'est PAS une des neuf tables _ops de 0040
-- section 1 (bandes, intrants, receptions, abattages, aliments_phases,
-- formulations_mp, commandes, lignes_commande, clients) - l'ajout de
-- colonnes ici n'exige AUCUN rejeu de vues. Verifie.
--
-- IMMUABILITE (motif rls35_releves_nuisibles_update_chef / rls46) : le
-- chef edite UNIQUEMENT ses lignes (created_by = auth.uid()) ; le
-- WITH CHECK gele created_by et created_at contre la ligne STOCKEE
-- (sous-requete EXISTS sur l'instantane pre-update, visible via la
-- policy SELECT sans sous-requete -> pas de recursion). Les autres
-- colonnes (donnees terrain) restent editables : corriger une saisie,
-- c'est exactement ca. Aucune colonne de validation cote saisies (la
-- validation vit dans notifications) - rien d'autre a geler.
--
-- FORM : DDL a plat (precedent 0043+). Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- Rollback : 0051_rollback.sql (drop la policy chef ; les colonnes
-- created_by/created_at sont CONSERVEES - inoffensives, potentiellement
-- deja heritees).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Prerequis dur
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.saisies') is null then
    raise exception '0051: table saisies absente - abort.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Colonnes d'auteur (auto-adaptatif ; no-op si deja heritees)
-- ------------------------------------------------------------
alter table public.saisies add column if not exists created_by uuid default auth.uid();

alter table public.saisies add column if not exists created_at timestamptz default now();

-- ------------------------------------------------------------
-- 2) Policy UPDATE chef_bande sur ses propres lignes (rls21 intacte)
-- ------------------------------------------------------------
drop policy if exists "rls51_saisies_update_chef" on public.saisies;

create policy "rls51_saisies_update_chef" on public.saisies
  for update to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
    and created_by = auth.uid()
  )
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
    and created_by = auth.uid()
    and exists (
      select 1
      from public.saisies prev
      where prev.saisie_id = saisies.saisie_id
        and prev.created_by is not distinct from saisies.created_by
        and prev.created_at is not distinct from saisies.created_at
    )
  );

-- ============================================================
-- VERIFICATION (executable - NOTICEs, catalogues en lecture seule)
-- ------------------------------------------------------------
do $$
declare
  p record;
  n integer := 0;
begin
  raise notice '0051 verify: colonnes saisies.created_by = % ; saisies.created_at = %',
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='saisies' and column_name='created_by'),
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='saisies' and column_name='created_at');
  raise notice '0051 verify: policies sur saisies (attendu : 4 rls21_* + rls51_saisies_update_chef) :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'saisies'
     order by policyname
  loop
    n := n + 1;
    raise notice '0051 verify:   % | %', p.policyname, p.cmd;
  end loop;
  if exists (select 1 from pg_policies where schemaname='public' and tablename='saisies'
              and policyname='rls51_saisies_update_chef')
     and exists (select 1 from pg_policies where schemaname='public' and tablename='saisies'
              and policyname='rls21_saisies_update') then
    raise notice '0051 verify: OK - UPDATE chef additif, UPDATE manager (rls21) conservee.';
  else
    raise notice '0051 verify: ATTENTION - etat inattendu (% policies). Relire la liste.', n;
  end if;
end $$;

-- ------------------------------------------------------------
-- SONDES MANUELLES POST-EXECUTION (Stephen - discipline RLS : certifier
-- getSession, un role par profil/incognito) :
--
-- 1. chef SIVA-003 edite une saisie QU'IL A CREEE APRES 0051 (donc
--    created_by = son uid) :
--    sb.from('saisies').update({mortalite_jour:4})
--      .eq('saisie_id','<SA SAISIE>').select()
--    -- attendu : 1 ligne ; puis en manager, cloche > Journal (0049) :
--    -- la ligne saisies/UPDATE porte le diff mortalite_jour : X -> 4.
--
-- 2. chef edite une saisie d'un AUTRE (ou anterieure a 0051, created_by
--    NULL) :
--    -- attendu : 0 ligne (la policy filtre).
--
-- 3. chef tente de reassigner l'auteur / l'horodatage de creation :
--    sb.from('saisies').update({created_by:'00000000-0000-0000-0000-000000000000'})
--      .eq('saisie_id','<SA SAISIE>').select()
--    -- attendu : erreur RLS "new row violates row-level security policy"
--    -- (gel du WITH CHECK).
--
-- 4. manager edite n'importe quelle saisie : accepte (rls21_saisies_update).
-- ============================================================
