-- ============================================================
-- Migration 0018 - Registre des traitements medicamenteux (PIECE 3 socle veto)
-- ------------------------------------------------------------
-- Les actes de SOUTIEN / TRAITEMENTS (hepatoprotecteur, vitamine, anticoccidien,
-- diuretique, acide organique, antibiotique...) NE SONT PAS des vaccins. Ils ne
-- doivent PAS aller dans le carnet de vaccination (0017). On cree donc un
-- registre dedie, calque sur le modele deux-tables de 0017 :
--
--   1) protocole_traitements : PLAN de REFERENCE GLOBAL (pas de bande_id). Le
--      "programme previsionnel type" recommande par le veto (jour_cible = age en
--      jours, voie/duree libres, conditionnel pour les actes "si necessaire").
--      Aucune valeur medicale imposee : le delai d'attente N'EST PAS stocke ici
--      (il depend du produit reel employe et se saisit a l'execution).
--
--   2) traitements : REGISTRE d'EXECUTION PAR BANDE (1 ligne par acte realise).
--      Reference proto_trait_id (FK, nullable) et FIGE un instantane produit/jour
--      (reste lisible si le protocole change/disparait). Porte le delai d'attente
--      SAISI (nullable = "a renseigner", jamais devine ; reutilise la logique de
--      trace 0015-0016), sa source, un flag "critique OMSA" pose par l'utilisateur,
--      et une observation libre. PAS d'index unique (bande, proto) : un traitement
--      peut se REPETER (ex : hepatoprotecteur a chaque transition alimentaire).
--
-- SEPARATION VACCINS / TRAITEMENTS : les vaccins restent dans protocole_vaccinal
-- / vaccinations (0017) ; ce registre ne contient QUE des traitements.
--
-- AUCUNE COLONNE FINANCIERE : ce registre sanitaire ne porte NI cout, NI prix, NI
-- marge (les couts restent sur bandes/intrants/abattages). La RLS Postgres etant
-- row-level et manager/chef_bande partageant le meme role 'authenticated' (cf.
-- 0014), on ne peut pas masquer une colonne par role ; on garantit donc
-- l'exigence "chef_bande ne voit aucune donnee financiere" PAR CONSTRUCTION :
-- il n'y a rien de financier a masquer sur ces tables.
--
-- Modele de validation intermediaire "fait (a valider)" identique a 0017 :
-- statut_validation in ('a_valider','valide'), chef_bande cree en 'a_valider'
-- (RLS l'y contraint), manager cree en 'valide' ou confirme par UPDATE.
--
-- EXTENSIBILITE couvoir : colonne origine ('ferme'|'couvoir', defaut 'ferme') sur
-- protocole_traitements pour brancher plus tard un plan couvoir sans migration
-- cassante. Aucune UI/plan couvoir livre ici.
--
-- STRICTEMENT ADDITIF : nouvelles tables uniquement. Aucune table/colonne
-- existante touchee. NO-OP pour l'app tant que le front ne lit/n'ecrit pas ces
-- tables. RLS calquee sur 0017/0009 (role lu dans app_metadata du JWT ; anon =
-- aucun acces). Idempotent : create table/index if not exists + drop policy if
-- exists. Garde de dependance : echec LOUD (raise) si bandes absente, pour ne
-- PAS rejouer le silence de 0004 (rollback total non vu). ASCII uniquement, pas
-- de commentaire en fin de ligne d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0018_rollback.sql.
-- ============================================================

-- -- 0) Garde de dependance : bandes doit exister (echec explicite sinon) --
do $$
begin
  if to_regclass('public.bandes') is null then
    raise exception '0018: table bandes absente - migration interrompue (aucune table creee).';
  end if;
end $$;

-- -- 1) Plan de reference global des traitements ------------------------
create table if not exists protocole_traitements (
  id             uuid        primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  proto_trait_id text        unique not null,
  nom_produit    text        not null,
  molecule       text,
  type_acte      text,
  jour_cible     int         not null,
  jour_max       int,
  voie           text,
  duree_jours    int,
  conditionnel   boolean     not null default false,
  origine        text        not null default 'ferme',
  note           text,
  ordre          int         not null default 0,
  actif          boolean     not null default true,
  constraint protocole_traitements_jour_chk    check (jour_cible >= 0),
  constraint protocole_traitements_jourmax_chk check (jour_max is null or jour_max >= jour_cible),
  constraint protocole_traitements_duree_chk   check (duree_jours is null or duree_jours >= 0),
  constraint protocole_traitements_origine_chk check (origine in ('ferme','couvoir'))
);

create index if not exists idx_protocole_traitements_actif   on protocole_traitements(actif);
create index if not exists idx_protocole_traitements_ordre   on protocole_traitements(ordre);
create index if not exists idx_protocole_traitements_origine on protocole_traitements(origine);

-- -- 2) Registre d'execution par bande ----------------------------------
create table if not exists traitements (
  id                   uuid        primary key default gen_random_uuid(),
  created_at           timestamptz not null default now(),
  traitement_id        text        unique not null,
  bande_id             text        not null references bandes(bande_id) on delete cascade,
  proto_trait_id       text        references protocole_traitements(proto_trait_id) on delete set null,
  nom_produit          text        not null,
  molecule             text,
  type_acte            text,
  date_traitement      timestamptz not null,
  jour_cible           int,
  dose                 text,
  voie                 text,
  duree_jours          int,
  delai_attente_jours  int,
  delai_attente_source text,
  critique_omsa        boolean     not null default false,
  fait_par             text,
  statut_validation    text        not null default 'a_valider',
  valide_par           text,
  valide_at            timestamptz,
  observation          text,
  constraint traitements_statut_validation_chk check (statut_validation in ('a_valider','valide')),
  constraint traitements_delai_chk             check (delai_attente_jours is null or delai_attente_jours >= 0),
  constraint traitements_duree_chk             check (duree_jours is null or duree_jours >= 0)
);

create index if not exists idx_traitements_bande_id on traitements(bande_id);
create index if not exists idx_traitements_proto    on traitements(proto_trait_id);
create index if not exists idx_traitements_date     on traitements(date_traitement);

-- -- 3) RLS protocole_traitements : lecture roles internes, ecriture manager --
alter table protocole_traitements enable row level security;
revoke all on protocole_traitements from anon;
grant select, insert, update, delete on protocole_traitements to authenticated;

drop policy if exists "rls18_proto_trait_select" on protocole_traitements;
create policy "rls18_proto_trait_select" on protocole_traitements
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

drop policy if exists "rls18_proto_trait_write" on protocole_traitements;
create policy "rls18_proto_trait_write" on protocole_traitements
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- -- 4) RLS traitements : SELECT roles internes ; INSERT chef_bande (a_valider)
--    et manager (libre) ; UPDATE/DELETE manager uniquement -------------
alter table traitements enable row level security;
revoke all on traitements from anon;
grant select, insert, update, delete on traitements to authenticated;

drop policy if exists "rls18_trait_select" on traitements;
create policy "rls18_trait_select" on traitements
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

drop policy if exists "rls18_trait_insert_chef" on traitements;
create policy "rls18_trait_insert_chef" on traitements
  for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
    and statut_validation = 'a_valider'
  );

drop policy if exists "rls18_trait_insert_manager" on traitements;
create policy "rls18_trait_insert_manager" on traitements
  for insert to authenticated
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls18_trait_update_manager" on traitements;
create policy "rls18_trait_update_manager" on traitements
  for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls18_trait_delete_manager" on traitements;
create policy "rls18_trait_delete_manager" on traitements
  for delete to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : voir le corps de la PR.
-- ============================================================
