-- ============================================================
-- Migration 0017 - Carnet de vaccination (PIECE 2 socle veterinaire)
-- ------------------------------------------------------------
-- Deux tables, modele CONFIGURABLE (aucune valeur medicale en dur) :
--
--   1) protocole_vaccinal : protocole de REFERENCE GLOBAL (pas de bande_id).
--      Saisi par le manager (nom_vaccin, jour_cible = age en jours J1=entree,
--      voie = TEXTE LIBRE non contraint, ordre, actif). Applique a chaque bande
--      par sa date_entree cote app. Aucun vaccin precharge.
--
--   2) vaccinations : statut d'EXECUTION PAR BANDE (1 ligne creee seulement au
--      "marquer fait"). Reference proto_id (FK) et FIGE un instantane
--      nom_vaccin/jour_cible (reste lisible si le protocole change/disparait).
--      Index unique partiel (bande_id, proto_id) -> une seule execution par
--      (bande, entree de protocole) : la confirmation manager est un UPDATE,
--      pas une 2e ligne.
--
-- Modele de validation intermediaire "fait (a valider)" :
--   statut_validation in ('a_valider','valide'), defaut 'a_valider'.
--   - chef_bande (Mounir) cree la ligne en 'a_valider' (RLS l'y contraint).
--   - manager cree directement en 'valide', OU confirme une ligne 'a_valider'
--     par UPDATE (valide_par / valide_at).
--   Cote app, le rappel se vide des qu'UNE ligne existe (a_valider OU valide) :
--   statut_validation ne sert qu'a l'affichage/au controle, pas au rappel.
--
-- STRICTEMENT ADDITIF : nouvelles tables uniquement. Aucune table/colonne
-- existante touchee. Ne touche NI FCR/IC, NI marge / cout de revient, NI
-- abattage / delai d'attente, NI tresorerie. NO-OP pour l'app tant que le front
-- (PR-2) ne lit/n'ecrit pas ces tables.
--
-- RLS : calquee sur 0009 (role lu dans app_metadata du JWT ; anon = aucun acces).
-- Idempotent : create table/index if not exists + drop policy if exists. ASCII
-- uniquement, pas de commentaire en fin de ligne d'instruction, pas de
-- point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0017_rollback.sql.
-- ============================================================

-- ── 1) Protocole de reference global ───────────────────────────────
create table if not exists protocole_vaccinal (
  id          uuid        primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  proto_id    text        unique not null,
  nom_vaccin  text        not null,
  jour_cible  int         not null,
  voie        text,
  note        text,
  ordre       int         not null default 0,
  actif       boolean     not null default true,
  constraint protocole_vaccinal_jour_chk check (jour_cible >= 0)
);

create index if not exists idx_protocole_vaccinal_actif on protocole_vaccinal(actif);
create index if not exists idx_protocole_vaccinal_ordre on protocole_vaccinal(ordre);

-- ── 2) Statut d'execution par bande ────────────────────────────────
create table if not exists vaccinations (
  id                uuid        primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  vacc_id           text        unique not null,
  bande_id          text        not null references bandes(bande_id) on delete cascade,
  proto_id          text        references protocole_vaccinal(proto_id) on delete set null,
  nom_vaccin        text,
  jour_cible        int,
  date_faite        timestamptz not null,
  voie              text,
  fait_par          text,
  statut_validation text        not null default 'a_valider',
  valide_par        text,
  valide_at         timestamptz,
  note              text,
  constraint vaccinations_statut_validation_chk check (statut_validation in ('a_valider','valide'))
);

create index if not exists idx_vaccinations_bande_id on vaccinations(bande_id);
create index if not exists idx_vaccinations_proto_id on vaccinations(proto_id);
create unique index if not exists uq_vaccinations_bande_proto
  on vaccinations(bande_id, proto_id) where proto_id is not null;

-- ── 3) RLS protocole_vaccinal : lecture roles internes, ecriture manager ──
alter table protocole_vaccinal enable row level security;
revoke all on protocole_vaccinal from anon;
grant select, insert, update, delete on protocole_vaccinal to authenticated;

drop policy if exists "rls17_proto_select" on protocole_vaccinal;
create policy "rls17_proto_select" on protocole_vaccinal
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

drop policy if exists "rls17_proto_write" on protocole_vaccinal;
create policy "rls17_proto_write" on protocole_vaccinal
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ── 4) RLS vaccinations : SELECT roles internes ; INSERT chef_bande (a_valider)
--    et manager (libre) ; UPDATE/DELETE manager uniquement ─────────────
alter table vaccinations enable row level security;
revoke all on vaccinations from anon;
grant select, insert, update, delete on vaccinations to authenticated;

drop policy if exists "rls17_vacc_select" on vaccinations;
create policy "rls17_vacc_select" on vaccinations
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

drop policy if exists "rls17_vacc_insert_chef" on vaccinations;
create policy "rls17_vacc_insert_chef" on vaccinations
  for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
    and statut_validation = 'a_valider'
  );

drop policy if exists "rls17_vacc_insert_manager" on vaccinations;
create policy "rls17_vacc_insert_manager" on vaccinations
  for insert to authenticated
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls17_vacc_update_manager" on vaccinations;
create policy "rls17_vacc_update_manager" on vaccinations
  for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls17_vacc_delete_manager" on vaccinations;
create policy "rls17_vacc_delete_manager" on vaccinations
  for delete to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : voir le corps de la PR.
-- ============================================================
