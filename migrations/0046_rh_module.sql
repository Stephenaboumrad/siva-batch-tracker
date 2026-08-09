-- ============================================================
-- Migration 0046 - RH lot 2 : module RH manager (fiche employe
--                  etendue, absences, avances, trace de correction
--                  des pointages)
-- ------------------------------------------------------------
-- SCOPE (lot RH-2) : surface manager du module RH (page RH du front).
-- AUCUN calcul de paie ici (lot RH-3 ulterieur). paies / depenses_rh
-- NON touchees.
--
-- IMPORTANT - ALIASING DES COLONNES employes (deviation du brief,
-- signalee) : le brief listait poste, type_contrat, date_embauche,
-- numero_cnps, taux_journalier, salaire_mensuel, actif, telephone,
-- notes. Or la table employes EXISTE deja avec la fiche du module
-- RH & Paie (Tresorerie) et porte deja ces concepts sous d'autres
-- noms, LUS PAR LE CODE DE PAIE en place :
--   brief            -> colonne existante (canonique, conservee)
--   poste            -> poste
--   type_contrat     -> type ('permanent'|'journalier'|'prestataire')
--   date_embauche    -> date_embauche
--   taux_journalier  -> taux_journalier_fcfa
--   salaire_mensuel  -> salaire_base_fcfa
--   actif            -> statut ('actif'|'inactif')
--   telephone        -> telephone
--   notes            -> note
-- Creer les noms du brief en plus aurait cree des doublons semantiques
-- (double verite, la generation des paies lisant les anciens noms).
-- Conformement au brief lui-meme (« probe existing columns first ; add
-- only missing ones »), 0046 n'ajoute que ce qui MANQUE vraiment :
--   - matricule    text : cle de jointure vers pointages/absences/
--                  avances (employe_matricule) et vers les comptes
--                  auth (app_metadata.matricule). Nullable : un
--                  journalier sans compte peut rester sans matricule.
--                  Unicite partielle (index) quand renseigne.
--   - numero_cnps  text : numero d'immatriculation CNPS (distinct du
--                  cnps_patronal_pct existant, qui est un taux).
-- La section 0 imprime l'etat reel des colonnes AVANT modification.
--
-- NOUVELLES TABLES (manager-only strict) :
--   absences : conges/maladies/absences par matricule, bornees
--              date_debut..date_fin. CHECK date_fin >= date_debut :
--              demande EXPLICITE du brief - deroge a la regle maison
--              « pas de CHECK d'ordre de dates » (signale).
--   avances  : avances sur salaire par matricule, montant > 0 (CHECK
--              explicite du brief), mode wave/especes + reference Wave
--              (rapprochement manuel, aucune API), drapeau rembourse.
--
-- POINTAGES - trace de correction : pointages n'a PAS de colonnes de
-- trace (0045 verifie) -> ajout corrige_par uuid + corrige_le
-- timestamptz, remplis par le front manager a chaque correction
-- manuelle. CONSEQUENCE RLS (0045 execute donc immuable -> additif) :
-- les policies employe de 0045 gelent les colonnes par liste explicite
-- et ne connaissent pas les nouvelles -> un employe pourrait les
-- estampiller lui-meme. 0046 remplace donc rls45_pointages_insert_
-- employe et rls45_pointages_update_employe par des versions rls46_*
-- identiques + gel des deux colonnes de trace (naissance a NULL cote
-- employe ; immuables ensuite). Les policies manager/select/delete de
-- 0045 restent en place, inchangees.
--
-- ACCES :
--   employes : deja RLS + rls7_manager_all (0007) - AUCUNE nouvelle
--              policy necessaire, l'etat est verifie en section 5.
--   absences / avances : manager-only FOR ALL (rls46_*), meme
--              mecanisme JWT app_metadata->>role que partout.
--              Le role employe n'a AUCUN acces dans ce lot.
--
-- COLONNES FINANCIERES (confirmation demandee par le brief) :
-- salaire_base_fcfa / taux_journalier_fcfa (employes) et
-- avances.montant ne sont lisibles par AUCUN chemin non-manager :
-- employes est manager-only (rls7_manager_all), absences/avances
-- naissent manager-only (rls46_*), et AUCUNE vue ne les expose (les
-- seules vues du schema sont les neuf *_ops de 0040, bandes_pos et
-- v_client_soldes - aucune ne lit ces trois tables ; verifie).
-- pointages ne porte aucune colonne financiere.
--
-- _ops NOTE (dit explicitement) : employes, absences, avances et
-- pointages ne font PAS partie des neuf tables _ops de 0040 section 1
-- (bandes, intrants, receptions, abattages, aliments_phases,
-- formulations_mp, commandes, lignes_commande, clients) - aucun rejeu
-- de vues 0040 n'est requis.
--
-- PREREQUIS DURS : employes ET pointages doivent exister (0045
-- executee). Abort bruyant sinon.
--
-- FORM : DDL a plat au premier niveau (precedent 0043/0044/0045 -
-- l'editeur SQL Supabase rejette create policy dans do $$). Un collage
-- = une transaction implicite ; l'abort de la section 0 saute tout.
--
-- Idempotent : add column if not exists + drop policy if exists +
-- create. ASCII uniquement. A EXECUTER MANUELLEMENT dans le SQL
-- Editor. Rollback : 0046_rollback.sql (DETRUIT absences/avances et
-- les colonnes ajoutees).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Prerequis durs + sonde des colonnes existantes (NOTICEs)
-- ------------------------------------------------------------
do $$
declare
  c text;
  probe text[] := array[
    'matricule','numero_cnps',
    'poste','type','type_contrat','date_embauche',
    'taux_journalier','taux_journalier_fcfa',
    'salaire_mensuel','salaire_base_fcfa','cnps_patronal_pct',
    'actif','statut','telephone','note','notes'
  ];
begin
  if to_regclass('public.employes') is null then
    raise exception '0046: table employes absente - abort.';
  end if;
  if to_regclass('public.pointages') is null then
    raise exception '0046: table pointages absente (0045 non executee ?) - abort.';
  end if;
  raise notice '0046 pre-state: colonnes employes (sonde brief + existant) :';
  foreach c in array probe loop
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'employes'
         and column_name = c
    ) then
      raise notice '0046 pre-state:   % : EXISTE', c;
    else
      raise notice '0046 pre-state:   % : absente', c;
    end if;
  end loop;
  raise notice '0046 pre-state: pointages.corrige_par existe = %',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'pointages'
               and column_name = 'corrige_par');
end $$;

-- ------------------------------------------------------------
-- 1) employes : colonnes reellement manquantes
-- ------------------------------------------------------------
alter table public.employes add column if not exists matricule text;

alter table public.employes add column if not exists numero_cnps text;

create unique index if not exists employes_matricule_uniq
  on public.employes (matricule)
  where matricule is not null;

-- ------------------------------------------------------------
-- 2) absences (manager-only)
-- ------------------------------------------------------------
create table if not exists public.absences (
  id uuid primary key default gen_random_uuid(),
  employe_matricule text not null,
  date_debut date not null,
  date_fin date not null,
  type text not null,
  justifiee boolean,
  commentaire text,
  created_by uuid default auth.uid(),
  created_at timestamptz default now(),
  constraint absences_dates_ordre check (date_fin >= date_debut)
);

revoke all on public.absences from anon;

grant select, insert, update, delete on public.absences to authenticated;

alter table public.absences enable row level security;

drop policy if exists "rls46_absences_manager_all" on public.absences;

create policy "rls46_absences_manager_all" on public.absences
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ------------------------------------------------------------
-- 3) avances (manager-only)
-- ------------------------------------------------------------
create table if not exists public.avances (
  id uuid primary key default gen_random_uuid(),
  employe_matricule text not null,
  date_avance date not null default current_date,
  montant numeric not null check (montant > 0),
  mode_paiement text,
  reference_wave text,
  rembourse boolean default false,
  commentaire text,
  created_by uuid default auth.uid(),
  created_at timestamptz default now()
);

revoke all on public.avances from anon;

grant select, insert, update, delete on public.avances to authenticated;

alter table public.avances enable row level security;

drop policy if exists "rls46_avances_manager_all" on public.avances;

create policy "rls46_avances_manager_all" on public.avances
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ------------------------------------------------------------
-- 4) pointages : trace de correction + gel cote employe
-- ------------------------------------------------------------
alter table public.pointages add column if not exists corrige_par uuid;

alter table public.pointages add column if not exists corrige_le timestamptz;

-- Remplacement des deux policies employe de 0045 (0045 est executee et
-- immuable ; remplacer une policy par une nouvelle version numerotee
-- est le motif 0044). Versions identiques a 0045 PLUS :
--   INSERT : les colonnes de trace naissent NULL cote employe.
--   UPDATE : les colonnes de trace sont gelees (is not distinct from).

drop policy if exists "rls45_pointages_insert_employe" on public.pointages;

drop policy if exists "rls46_pointages_insert_employe" on public.pointages;

create policy "rls46_pointages_insert_employe" on public.pointages
  for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
    and date_pointage = current_date
    and employe_matricule = upper(coalesce(auth.jwt() -> 'app_metadata' ->> 'matricule', ''))
    and heure_arrivee is not null
    and heure_depart is null
    and corrige_par is null
    and corrige_le is null
  );

drop policy if exists "rls45_pointages_update_employe" on public.pointages;

drop policy if exists "rls46_pointages_update_employe" on public.pointages;

create policy "rls46_pointages_update_employe" on public.pointages
  for update to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
    and date_pointage = current_date
  )
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and heure_depart is not null
    and exists (
      select 1
      from public.pointages prev
      where prev.id = pointages.id
        and prev.employe_matricule is not distinct from pointages.employe_matricule
        and prev.employe_nom       is not distinct from pointages.employe_nom
        and prev.date_pointage     is not distinct from pointages.date_pointage
        and prev.heure_arrivee     is not distinct from pointages.heure_arrivee
        and prev.created_by        is not distinct from pointages.created_by
        and prev.created_at        is not distinct from pointages.created_at
        and prev.corrige_par       is not distinct from pointages.corrige_par
        and prev.corrige_le        is not distinct from pointages.corrige_le
        and prev.heure_depart is null
    )
  );

-- ============================================================
-- 5) VERIFICATION (executable - NOTICEs, catalogues en lecture seule)
-- ------------------------------------------------------------
do $$
declare
  p record;
  t text;
  n integer;
  v_rls boolean;
begin
  foreach t in array array['employes','absences','avances','pointages'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0046 verify: ATTENTION - table % ABSENTE.', t;
      continue;
    end if;
    select relrowsecurity into v_rls
      from pg_class where oid = format('public.%I', t)::regclass;
    n := 0;
    raise notice '0046 verify: % (rls=%) - policies :', t, v_rls;
    for p in
      select policyname, cmd from pg_policies
       where schemaname = 'public' and tablename = t
       order by policyname
    loop
      n := n + 1;
      raise notice '0046 verify:   % | %', p.policyname, p.cmd;
    end loop;
    if n = 0 then
      raise notice '0046 verify:   (aucune policy)';
    end if;
  end loop;

  raise notice '0046 verify: employes.matricule = % ; employes.numero_cnps = % ; index unique matricule = %',
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='employes' and column_name='matricule'),
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='employes' and column_name='numero_cnps'),
    exists (select 1 from pg_indexes
             where schemaname='public' and tablename='employes' and indexname='employes_matricule_uniq');

  raise notice '0046 verify: pointages.corrige_par = % ; pointages.corrige_le = %',
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='pointages' and column_name='corrige_par'),
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='pointages' and column_name='corrige_le');

  raise notice '0046 verify: attendu - employes : 1 policy rls7_manager_all (ALL) ; absences/avances : 1 policy rls46_*_manager_all (ALL) chacune ; pointages : 7 policies dont insert/update employe en rls46_* (les 5 autres restent rls45_*).';
end $$;

-- ------------------------------------------------------------
-- Sondes fonctionnelles (console navigateur - discipline RLS : certifier
-- l'identite de session AVANT, un role par profil Chrome/incognito,
-- cible confirmee avant de conclure sur un resultat vide) :
--   const s = await sb.auth.getSession();
--   console.log(s.data.session.user.email, s.data.session.user.app_metadata);
--
-- session employe (non-regression 0045 + gel de la trace) :
--   a) pointage arrivee normal (attendu : 1 ligne) - comme 0045 (a).
--   b) arrivee avec trace estampillee (attendu : erreur RLS) :
--     sb.from('pointages').insert({employe_matricule:'<SON-MATRICULE>',
--       employe_nom:'X', heure_arrivee:new Date().toISOString(),
--       corrige_le:new Date().toISOString()}).select()
--   c) depart normal (attendu : 1 ligne) - comme 0045 (d).
--   d) depart + tentative d'ecrire corrige_par (attendu : erreur RLS).
--   e) lecture absences/avances (attendu : 0 ligne, aucune erreur) :
--     sb.from('absences').select('*') ; sb.from('avances').select('*')
--   f) insertion absences/avances (attendu : erreur RLS).
--
-- session manager :
--   g) CRUD complet absences/avances (attendu : OK) ; verifier le CHECK :
--     insert absences avec date_fin < date_debut (attendu : erreur
--     absences_dates_ordre) ; insert avances montant 0 (attendu : erreur
--     check montant).
--   h) correction pointage avec corrige_par/corrige_le (attendu : OK,
--      valeurs conservees - le trigger 0045 ne reecrit pas le manager).
-- ============================================================
