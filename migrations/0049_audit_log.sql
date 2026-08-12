-- ============================================================
-- Migration 0049 - Journal d'audit (audit_log) : trigger generique,
--                  append-only, lecture manager
-- ------------------------------------------------------------
-- ARCHITECTURE (dernier chantier du plan directeur) - DEUX concepts :
--   1. JOURNAL D'AUDIT (cette migration) : public.audit_log, immuable,
--      alimente PAR TRIGGERS cote serveur - tout le monde, toutes les
--      operations, y compris les ecritures console (le trigger lit le
--      JWT de la session : une ecriture console est capturee comme une
--      ecriture app, avec le meme acteur).
--   2. FILE DE VALIDATION : la table notifications (0044) - le
--      SOUS-ENSEMBLE qui exige l'approbation manager. INCHANGEE ici.
--
-- SONDE FILE DE VALIDATION (partie 2 du brief - resultat) :
--   - corrections de pointage : UPDATE pointages = rls45 (manager) +
--     rls46 (employe : remplissage heure_depart de SA ligne du jour
--     uniquement). chef_bande : AUCUNE policy. Les CORRECTIONS
--     (horaires arbitraires + corrige_par) sont MANAGER-ONLY ->
--     JOURNAL SEULEMENT, aucun chemin de validation a construire.
--   - avances : rls46_avances_manager_all -> creation manager-only ->
--     JOURNAL SEULEMENT.
--   => La file de validation reste legitimement = declarations
--      chef_bande (intrant / reception / abattage, flux 0021/0044).
--      AUCUNE extension de schema notifications necessaire - on ne
--      construit pas de flux d'approbation pour des actions que seul
--      le manager peut faire.
--
-- DENY-LIST COLONNES SENSIBLES (sonde) : AUCUNE colonne type mot de
-- passe / token / secret n'existe dans le schema public (verifie sur
-- toutes les migrations ; l'auth vit dans auth.users, hors perimetre).
-- Le mecanisme de masquage est NEANMOINS implemente (garde future) :
-- toute colonne dont le nom matche la deny-list est journalisee avec
-- old/new = '<masque>'.
--
-- DEVIATION assumee vs brief : acteur_id est NULLABLE (le brief disait
-- not null default auth.uid()). Raison : dans le SQL Editor / contextes
-- service, auth.uid() est NULL - un NOT NULL ferait ECHOUER toute
-- ecriture manuelle sur les 20 tables auditees (y compris les scripts
-- ops). acteur NULL + acteur_role 'sans_jwt' = trace honnete d'une
-- ecriture hors session.
--
-- ORDRE DES TRIGGERS : nom prefixe zz_ -> s'execute EN DERNIER
-- (ordre alphabetique Postgres), apres les triggers metier existants
-- (pointages_horodatage 0045, commandes_paiement_guard 0014,
-- bandes_delete_guard 0021) - on journalise l'etat FINAL de la ligne.
--
-- _ops NOTE (raisonnement explicite) : cette migration n'ajoute, ne
-- renomme et ne supprime AUCUNE colonne - des triggers purs ne changent
-- pas la forme des tables, donc les neuf vues _ops de 0040 (qui figent
-- leurs colonnes a la creation) restent exactes : AUCUN rejeu 0040
-- section 1. Verifie : rien ici ne touche une colonne des neuf tables.
--
-- RETENTION : aucune purge pour l'instant (append-only a vie). Une
-- migration de purge/archivage pourra venir plus tard - notee au plan.
--
-- APPEND-ONLY : garanti par (a) aucune policy INSERT/UPDATE/DELETE pour
-- aucun role (les ecritures passent UNIQUEMENT par le trigger SECURITY
-- DEFINER, proprietaire de la table), (b) revoke insert/update/delete
-- a authenticated, (c) revoke total a anon.
--
-- FORM : DDL a plat quand possible ; les create trigger dynamiques
-- vivent dans do $$ (seul create policy y est rejete par l'editeur -
-- precedent 0043+). Idempotent : create table if not exists, create or
-- replace function, drop trigger if exists. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- Rollback : 0049_rollback.sql (detruit le journal et les triggers).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Table du journal (append-only) + index + grants + RLS
-- ------------------------------------------------------------
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  at timestamptz not null default now(),
  acteur_id uuid,
  acteur_matricule text,
  acteur_role text,
  table_name text not null,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE')),
  row_pk text not null,
  changed jsonb
);

create index if not exists audit_log_at_idx on public.audit_log (at desc);
create index if not exists audit_log_table_idx on public.audit_log (table_name);
create index if not exists audit_log_acteur_idx on public.audit_log (acteur_matricule);

revoke all on public.audit_log from anon;

grant select on public.audit_log to authenticated;

revoke insert, update, delete on public.audit_log from authenticated;

alter table public.audit_log enable row level security;

drop policy if exists "rls49_audit_select_manager" on public.audit_log;

create policy "rls49_audit_select_manager" on public.audit_log
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ------------------------------------------------------------
-- 2) Fonction trigger generique (SECURITY DEFINER, search_path fige).
--    TG_ARGV[0] = nom de la colonne pk de la table auditee (resolue a
--    la pose du trigger, section 3).
-- ------------------------------------------------------------
create or replace function public.trg_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_claims jsonb;
  v_matricule text;
  v_role text;
  v_pk text;
  v_changed jsonb;
  v_key text;
  v_old jsonb;
  v_new jsonb;
  deny constant text[] := array['password','mot_de_passe','token','secret','api_key','cle_api'];
begin
  -- Acteur depuis le JWT de la session (les ecritures console d'une
  -- session authentifiee portent le MEME JWT que l'app). Hors session
  -- (SQL editor, service) : claims null -> role 'sans_jwt'.
  begin
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  exception when others then
    v_claims := null;
  end;
  v_matricule := upper(v_claims -> 'app_metadata' ->> 'matricule');
  v_role := coalesce(v_claims -> 'app_metadata' ->> 'role',
                     case when v_claims is null then 'sans_jwt' end);

  v_pk := coalesce(to_jsonb(coalesce(NEW, OLD)) ->> TG_ARGV[0], '?');

  if TG_OP = 'UPDATE' then
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_changed := '{}'::jsonb;
    for v_key in select jsonb_object_keys(v_new) loop
      if v_old -> v_key is distinct from v_new -> v_key then
        if v_key = any(deny) then
          v_changed := v_changed || jsonb_build_object(v_key,
            jsonb_build_object('old', '<masque>', 'new', '<masque>'));
        else
          v_changed := v_changed || jsonb_build_object(v_key,
            jsonb_build_object('old', v_old -> v_key, 'new', v_new -> v_key));
        end if;
      end if;
    end loop;
    -- UPDATE sans changement effectif : pas de bruit au journal.
    if v_changed = '{}'::jsonb then
      return null;
    end if;
  else
    -- INSERT / DELETE : instantane complet de la ligne, deny-list
    -- masquee aussi.
    v_changed := to_jsonb(coalesce(NEW, OLD));
    foreach v_key in array deny loop
      if v_changed ? v_key then
        v_changed := jsonb_set(v_changed, array[v_key], '"<masque>"'::jsonb);
      end if;
    end loop;
  end if;

  insert into public.audit_log
    (acteur_id, acteur_matricule, acteur_role, table_name, operation, row_pk, changed)
  values
    (auth.uid(), v_matricule, v_role, TG_TABLE_NAME, TG_OP, v_pk, v_changed);

  return null;
end;
$$;

-- ------------------------------------------------------------
-- 3) Pose des triggers (20 tables, pk resolue dynamiquement via
--    pg_index - les tables heritees ont des noms de pk varies).
--    Table absente = NOTICE + skip. JAMAIS sur audit_log elle-meme.
-- ------------------------------------------------------------
do $$
declare
  t text;
  v_pk text;
begin
  foreach t in array array[
    'saisies', 'receptions', 'pointages', 'absences', 'avances',
    'paies', 'commandes', 'lignes_commande', 'pos_transactions',
    'lignes_transaction', 'paiements', 'cloture_caisse',
    'mouvements_stock', 'produits', 'employes', 'clients',
    'parametres', 'traitements', 'vaccinations', 'bandes',
    'notifications'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0049: table % absente - trigger ignore.', t;
      continue;
    end if;
    select a.attname into v_pk
      from pg_index i
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
     where i.indrelid = format('public.%I', t)::regclass
       and i.indisprimary
     order by a.attnum
     limit 1;
    if v_pk is null then
      raise notice '0049: % SANS cle primaire - trigger ignore (A SIGNALER).', t;
      continue;
    end if;
    execute format('drop trigger if exists zz_audit_log on public.%I', t);
    execute format(
      'create trigger zz_audit_log after insert or update or delete on public.%I for each row execute function public.trg_audit_log(%L)',
      t, v_pk);
    raise notice '0049: trigger zz_audit_log pose sur % (pk = %).', t, v_pk;
  end loop;
end $$;

-- ============================================================
-- VERIFICATION (executable - NOTICEs, catalogues en lecture seule)
-- ------------------------------------------------------------
do $$
declare
  r record;
  n integer := 0;
  v_rls boolean;
begin
  raise notice '0049 verify: triggers zz_audit_log poses :';
  for r in
    select c.relname as tbl
      from pg_trigger g
      join pg_class c on c.oid = g.tgrelid
     where g.tgname = 'zz_audit_log' and not g.tgisinternal
     order by c.relname
  loop
    n := n + 1;
    raise notice '0049 verify:   %', r.tbl;
  end loop;
  raise notice '0049 verify: % trigger(s) au total (attendu : 21 si toutes les tables existent).', n;

  select relrowsecurity into v_rls
    from pg_class where oid = 'public.audit_log'::regclass;
  raise notice '0049 verify: audit_log rls = %', v_rls;
  for r in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'audit_log'
     order by policyname
  loop
    raise notice '0049 verify:   policy % | % (attendu : UNE seule, SELECT manager)', r.policyname, r.cmd;
  end loop;
end $$;

-- ------------------------------------------------------------
-- SONDES MANUELLES POST-EXECUTION (Stephen - AUCUNE donnee de test
-- n'est ecrite par la migration elle-meme) :
--
-- 1. SQL Editor (role postgres, sans JWT) :
--    update public.parametres set value = value where key = 'vet_params';
--    -- UPDATE sans changement -> attendu : AUCUNE ligne d'audit (anti-bruit).
--    select * from public.audit_log order by at desc limit 5;
--
-- 2. App manager : modifier le PRIX d'un produit au Catalogue ->
--    cloche > Historique : la ligne 'produits / UPDATE' apparait avec
--    prix_base_kg_fcfa : ancien -> nouveau, acteur = votre matricule.
--
-- 3. Console d'une session NON-manager certifiee (discipline getSession,
--    ex. chef SIVA-003) :
--    sb.from('saisies').update({observations:'test audit'})
--      .eq('saisie_id','<ID D UNE SAISIE DU JOUR DU CHEF>').select()
--    -- puis en manager :
--    select acteur_matricule, acteur_role, table_name, operation, changed
--      from public.audit_log order by at desc limit 3;
--    -- attendu : la ligne portee par SIVA-003 / chef_bande.
--
-- 4. Session employe / client / chef :
--    sb.from('audit_log').select('*')  -- attendu : data [] (RLS manager).
--
-- 5. Tentative d'ecriture directe (toute session app) :
--    sb.from('audit_log').insert({table_name:'x',operation:'INSERT',row_pk:'1'})
--    -- attendu : erreur permission denied (aucun grant insert).
-- ============================================================
