-- ═══════════════════════════════════════════════════════════════════
-- COQORICO / SIVA — Supabase Setup Script
-- Société Ivoirienne de Volaille et Assimilés
-- Les Terres du Sud — Azaguié, Côte d'Ivoire
--
-- IDEMPOTENT: safe to re-run. Drops all tables then recreates.
-- Paste this entire script into the Supabase SQL Editor and click Run.
-- ═══════════════════════════════════════════════════════════════════

-- ── DROP children first, then parents ──────────────────────────────
drop table if exists notifications   cascade;
drop table if exists depenses_rh     cascade;
drop table if exists paies           cascade;
drop table if exists employes        cascade;
drop table if exists lignes_commande cascade;
drop table if exists commandes       cascade;
drop table if exists clients         cascade;
drop table if exists inspections     cascade;
drop table if exists receptions      cascade;
drop table if exists stocks          cascade;
drop table if exists fournisseurs    cascade;
drop table if exists formulations_mp cascade;
drop table if exists aliments_phases cascade;
drop table if exists matieres        cascade;
drop table if exists intrants        cascade;
drop table if exists saisies         cascade;
drop table if exists abattages       cascade;
drop table if exists bandes          cascade;


-- ═══════════════════════════════════════════════════════════════════
-- PARENT TABLES
-- ═══════════════════════════════════════════════════════════════════

-- ── Bandes (batches) ───────────────────────────────────────────────
create table bandes (
  id                          uuid        primary key default gen_random_uuid(),
  created_at                  timestamptz not null default now(),
  bande_id                    text        unique not null,
  nom_bande                   text        not null,
  date_entree                 timestamptz,
  nb_poussins_entree          int,
  fournisseur_poussins        text,
  prix_poussin_unitaire       numeric,
  poids_initial_moyen_g       numeric,
  cout_aliment_kg             numeric,
  statut                      text        default 'en_cours',
  date_sortie                 timestamptz,
  nb_oiseaux_sortie           int,
  poids_vif_moyen_sortie_g    numeric,
  rendement_carcasse_pct      numeric,
  prix_vente_carcasse_kg      numeric
);

-- ── Matières premières (raw materials catalog) ─────────────────────
create table matieres (
  id          uuid    primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  matiere_id  text    unique not null,
  nom         text    not null,
  unite       text    default 'kg',
  actif       boolean default true
);

-- ── Fournisseurs (suppliers) ───────────────────────────────────────
create table fournisseurs (
  id              uuid    primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  fournisseur_id  text    unique not null,
  nom             text    not null,
  type            text,
  contact_nom     text,
  telephone       text,
  email           text,
  adresse         text,
  pays            text,
  statut          text    default 'actif',
  note            text
);

-- ── Clients ────────────────────────────────────────────────────────
create table clients (
  id          uuid    primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  client_id   text    unique not null,
  nom         text    not null,
  type        text,
  contact_nom text,
  telephone   text,
  email       text,
  adresse     text,
  ville       text,
  statut      text    default 'actif',
  note        text
);

-- ── Employés ───────────────────────────────────────────────────────
create table employes (
  id                  uuid    primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  employe_id          text    unique not null,
  nom                 text    not null,
  prenom              text,
  poste               text,
  type                text,
  date_embauche       timestamptz,
  salaire_base_fcfa   numeric default 0,
  taux_journalier_fcfa numeric default 0,
  cnps_patronal_pct   numeric default 0,
  telephone           text,
  statut              text    default 'actif',
  note                text
);

-- ── Stocks ─────────────────────────────────────────────────────────
create table stocks (
  id                    uuid    primary key default gen_random_uuid(),
  created_at            timestamptz not null default now(),
  stock_id              text    unique not null,
  type_produit          text,
  categorie             text,
  quantite_actuelle     numeric default 0,
  unite                 text,
  seuil_alerte          numeric default 0,
  emplacement           text,
  derniere_mise_a_jour  timestamptz
);


-- ═══════════════════════════════════════════════════════════════════
-- CHILD TABLES
-- ═══════════════════════════════════════════════════════════════════

-- ── Saisies (daily entries) ────────────────────────────────────────
create table saisies (
  id                  uuid    primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  saisie_id           text    unique not null,
  bande_id            text    not null references bandes(bande_id) on delete cascade,
  date_saisie         timestamptz,
  jour_bande          int,
  mortalite_jour      int     default 0,
  aliment_consomme_kg numeric default 0,
  nb_oiseaux_peses    int     default 0,
  poids_vif_moyen_g   numeric default 0
);

-- ── Intrants (inputs: vaccines, meds, etc.) ────────────────────────
create table intrants (
  id              uuid    primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  intrant_id      text    unique not null,
  bande_id        text    not null references bandes(bande_id) on delete cascade,
  date_intrant    timestamptz,
  type            text,
  nom_produit     text,
  quantite        numeric default 0,
  unite           text,
  cout_total_fcfa numeric default 0
);

-- ── Aliments Phases (feed formulation per phase) ───────────────────
create table aliments_phases (
  id              uuid    primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  ap_id           text    unique not null,
  bande_id        text    not null references bandes(bande_id) on delete cascade,
  phase           text,
  mp_id           text,
  nom_mp          text,
  quantite_kg     numeric default 0,
  prix_unitaire   numeric default 0,
  cout_total      numeric default 0,
  date_livraison  timestamptz
);

-- ── Formulations MP (raw material formulation detail) ──────────────
create table formulations_mp (
  id                  uuid    primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  mp_id               text    unique not null,
  bande_id            text    not null references bandes(bande_id) on delete cascade,
  phase               text,
  matiere_id          text,
  quantite_kg         numeric default 0,
  prix_unitaire_fcfa  numeric default 0,
  cout_total_fcfa     numeric default 0,
  date_livraison      timestamptz
);

-- ── Réceptions (deliveries) ────────────────────────────────────────
create table receptions (
  id                  uuid    primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  reception_id        text    unique not null,
  fournisseur_id      text    references fournisseurs(fournisseur_id) on delete set null,
  date_reception      timestamptz,
  type_produit        text,
  categorie           text,
  quantite            numeric default 0,
  unite               text,
  prix_unitaire_fcfa  numeric default 0,
  cout_total_fcfa     numeric default 0,
  bande_id            text    references bandes(bande_id) on delete set null,
  numero_lot          text,
  date_peremption     timestamptz
);

-- ── Inspections (quality control) ──────────────────────────────────
create table inspections (
  id                uuid    primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  inspection_id     text    unique not null,
  reception_id      text    references receptions(reception_id) on delete cascade,
  date_inspection   timestamptz,
  inspecteur        text,
  aspect_visuel     text,
  odeur             text,
  humidite_pct      numeric,
  temperature_c     numeric,
  resultat_global   text,
  commentaire       text
);

-- ── Commandes (orders) ─────────────────────────────────────────────
create table commandes (
  id                        uuid    primary key default gen_random_uuid(),
  created_at                timestamptz not null default now(),
  commande_id               text    unique not null,
  client_id                 text    references clients(client_id) on delete set null,
  date_commande             timestamptz,
  date_livraison_souhaitee  timestamptz,
  bande_id                  text    references bandes(bande_id) on delete set null,
  statut                    text    default 'brouillon',
  note                      text,
  montant_total_fcfa        numeric default 0
);

-- ── Lignes de commande (order lines) ───────────────────────────────
create table lignes_commande (
  id            uuid    primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  ligne_id      text    unique not null,
  commande_id   text    not null references commandes(commande_id) on delete cascade,
  produit       text,
  description   text,
  quantite_kg   numeric default 0,
  prix_kg_fcfa  numeric default 0,
  montant_fcfa  numeric default 0
);

-- ── Abattages (slaughter sessions) ─────────────────────────────────
create table abattages (
  id                              uuid    primary key default gen_random_uuid(),
  created_at                      timestamptz not null default now(),
  abattage_id                     text    unique not null,
  bande_id                        text    not null references bandes(bande_id) on delete cascade,
  date_abattage                   timestamptz,
  heure_debut                     text,
  heure_fin                       text,
  responsable                     text,
  nb_oiseaux_present_veille       int     default 0,
  nb_oiseaux_abattus              int     default 0,
  nb_oiseaux_morts_avant_abattage int     default 0,
  nb_oiseaux_saisis               int     default 0,
  nb_oiseaux_echappe              int     default 0,
  poids_vif_total_kg              numeric default 0,
  poids_vif_moyen_kg              numeric default 0,
  rendement_carcasse_pct          numeric default 0,
  poids_carcasse_total_kg         numeric default 0,
  poids_carcasse_moyen_kg         numeric default 0,
  nb_workers_jour                 int     default 0,
  cout_workers_fcfa               numeric default 0,
  cout_transport_fcfa             numeric default 0,
  cout_emballage_fcfa             numeric default 0,
  cout_autres_fcfa                numeric default 0,
  note_autres                     text,
  statut                          text    default 'brouillon',
  valide_par                      text,
  note                            text
);

-- ── Paies (payroll) ────────────────────────────────────────────────
create table paies (
  id                        uuid    primary key default gen_random_uuid(),
  created_at                timestamptz not null default now(),
  paie_id                   text    unique not null,
  employe_id                text    not null references employes(employe_id) on delete cascade,
  mois                      text,
  salaire_base_fcfa         numeric default 0,
  nb_jours_travailles       int     default 0,
  montant_brut_fcfa         numeric default 0,
  cnps_patronal_fcfa        numeric default 0,
  primes_fcfa               numeric default 0,
  avances_fcfa              numeric default 0,
  montant_net_fcfa          numeric default 0,
  montant_total_charge_fcfa numeric default 0,
  statut                    text    default 'en_attente',
  date_paiement             timestamptz,
  note                      text
);

-- ── Dépenses RH (HR expenses) ─────────────────────────────────────
create table depenses_rh (
  id            uuid    primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  depense_id    text    unique not null,
  date_depense  timestamptz,
  type          text,
  description   text,
  montant_fcfa  numeric default 0,
  employe_id    text    references employes(employe_id) on delete set null,
  note          text
);

-- ── Notifications (activity log) ───────────────────────────────────
create table notifications (
  id                uuid    primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  notif_id          text    unique not null,
  type              text,
  action            text,
  bande_id          text    references bandes(bande_id) on delete set null,
  bande_nom         text,
  auteur_matricule  text,
  auteur_nom        text,
  date_action       timestamptz,
  statut            text    default 'en_attente',
  valide_par        text,
  date_validation   timestamptz,
  payload_json      text,
  note_manager      text,
  lu_par            text
);


-- ═══════════════════════════════════════════════════════════════════
-- INDEXES — on every FK and on date columns used for filtering
-- ═══════════════════════════════════════════════════════════════════

-- Saisies
create index idx_saisies_bande_id    on saisies(bande_id);
create index idx_saisies_date        on saisies(date_saisie);

-- Intrants
create index idx_intrants_bande_id   on intrants(bande_id);
create index idx_intrants_date       on intrants(date_intrant);

-- Aliments Phases
create index idx_aliments_phases_bande_id on aliments_phases(bande_id);

-- Formulations MP
create index idx_formulations_mp_bande_id on formulations_mp(bande_id);

-- Réceptions
create index idx_receptions_fournisseur_id on receptions(fournisseur_id);
create index idx_receptions_bande_id       on receptions(bande_id);
create index idx_receptions_date           on receptions(date_reception);

-- Inspections
create index idx_inspections_reception_id on inspections(reception_id);
create index idx_inspections_date         on inspections(date_inspection);

-- Commandes
create index idx_commandes_client_id on commandes(client_id);
create index idx_commandes_bande_id  on commandes(bande_id);
create index idx_commandes_date      on commandes(date_commande);
create index idx_commandes_livraison on commandes(date_livraison_souhaitee);

-- Lignes Commande
create index idx_lignes_commande_commande_id on lignes_commande(commande_id);

-- Abattages
create index idx_abattages_bande_id on abattages(bande_id);
create index idx_abattages_date     on abattages(date_abattage);

-- Paies
create index idx_paies_employe_id on paies(employe_id);
create index idx_paies_mois       on paies(mois);

-- Dépenses RH
create index idx_depenses_rh_employe_id on depenses_rh(employe_id);
create index idx_depenses_rh_date       on depenses_rh(date_depense);

-- Notifications
create index idx_notifications_bande_id on notifications(bande_id);
create index idx_notifications_statut   on notifications(statut);
create index idx_notifications_date     on notifications(date_action);

-- Bandes
create index idx_bandes_statut on bandes(statut);
create index idx_bandes_date   on bandes(date_entree);


-- ═══════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- TODO: These policies are fully permissive (using(true) with check(true)).
--       They MUST be tightened before production deployment.
--       Recommended: add user authentication and restrict access by role.
-- ═══════════════════════════════════════════════════════════════════

alter table bandes          enable row level security;
alter table saisies         enable row level security;
alter table intrants        enable row level security;
alter table aliments_phases enable row level security;
alter table matieres        enable row level security;
alter table formulations_mp enable row level security;
alter table fournisseurs    enable row level security;
alter table receptions      enable row level security;
alter table inspections     enable row level security;
alter table stocks          enable row level security;
alter table clients         enable row level security;
alter table commandes       enable row level security;
alter table lignes_commande enable row level security;
alter table abattages       enable row level security;
alter table employes        enable row level security;
alter table paies           enable row level security;
alter table depenses_rh     enable row level security;
alter table notifications   enable row level security;

-- Permissive policies for all operations (anon + authenticated)
-- TODO: tighten these before production!
create policy "Allow all select on bandes"          on bandes          for select using (true);
create policy "Allow all insert on bandes"          on bandes          for insert with check (true);
create policy "Allow all update on bandes"          on bandes          for update using (true) with check (true);
create policy "Allow all delete on bandes"          on bandes          for delete using (true);

create policy "Allow all select on saisies"         on saisies         for select using (true);
create policy "Allow all insert on saisies"         on saisies         for insert with check (true);
create policy "Allow all update on saisies"         on saisies         for update using (true) with check (true);
create policy "Allow all delete on saisies"         on saisies         for delete using (true);

create policy "Allow all select on intrants"        on intrants        for select using (true);
create policy "Allow all insert on intrants"        on intrants        for insert with check (true);
create policy "Allow all update on intrants"        on intrants        for update using (true) with check (true);
create policy "Allow all delete on intrants"        on intrants        for delete using (true);

create policy "Allow all select on aliments_phases" on aliments_phases for select using (true);
create policy "Allow all insert on aliments_phases" on aliments_phases for insert with check (true);
create policy "Allow all update on aliments_phases" on aliments_phases for update using (true) with check (true);
create policy "Allow all delete on aliments_phases" on aliments_phases for delete using (true);

create policy "Allow all select on matieres"        on matieres        for select using (true);
create policy "Allow all insert on matieres"        on matieres        for insert with check (true);
create policy "Allow all update on matieres"        on matieres        for update using (true) with check (true);
create policy "Allow all delete on matieres"        on matieres        for delete using (true);

create policy "Allow all select on formulations_mp" on formulations_mp for select using (true);
create policy "Allow all insert on formulations_mp" on formulations_mp for insert with check (true);
create policy "Allow all update on formulations_mp" on formulations_mp for update using (true) with check (true);
create policy "Allow all delete on formulations_mp" on formulations_mp for delete using (true);

create policy "Allow all select on fournisseurs"    on fournisseurs    for select using (true);
create policy "Allow all insert on fournisseurs"    on fournisseurs    for insert with check (true);
create policy "Allow all update on fournisseurs"    on fournisseurs    for update using (true) with check (true);
create policy "Allow all delete on fournisseurs"    on fournisseurs    for delete using (true);

create policy "Allow all select on receptions"      on receptions      for select using (true);
create policy "Allow all insert on receptions"      on receptions      for insert with check (true);
create policy "Allow all update on receptions"      on receptions      for update using (true) with check (true);
create policy "Allow all delete on receptions"      on receptions      for delete using (true);

create policy "Allow all select on inspections"     on inspections     for select using (true);
create policy "Allow all insert on inspections"     on inspections     for insert with check (true);
create policy "Allow all update on inspections"     on inspections     for update using (true) with check (true);
create policy "Allow all delete on inspections"     on inspections     for delete using (true);

create policy "Allow all select on stocks"          on stocks          for select using (true);
create policy "Allow all insert on stocks"          on stocks          for insert with check (true);
create policy "Allow all update on stocks"          on stocks          for update using (true) with check (true);
create policy "Allow all delete on stocks"          on stocks          for delete using (true);

create policy "Allow all select on clients"         on clients         for select using (true);
create policy "Allow all insert on clients"         on clients         for insert with check (true);
create policy "Allow all update on clients"         on clients         for update using (true) with check (true);
create policy "Allow all delete on clients"         on clients         for delete using (true);

create policy "Allow all select on commandes"       on commandes       for select using (true);
create policy "Allow all insert on commandes"       on commandes       for insert with check (true);
create policy "Allow all update on commandes"       on commandes       for update using (true) with check (true);
create policy "Allow all delete on commandes"       on commandes       for delete using (true);

create policy "Allow all select on lignes_commande" on lignes_commande for select using (true);
create policy "Allow all insert on lignes_commande" on lignes_commande for insert with check (true);
create policy "Allow all update on lignes_commande" on lignes_commande for update using (true) with check (true);
create policy "Allow all delete on lignes_commande" on lignes_commande for delete using (true);

create policy "Allow all select on abattages"       on abattages       for select using (true);
create policy "Allow all insert on abattages"       on abattages       for insert with check (true);
create policy "Allow all update on abattages"       on abattages       for update using (true) with check (true);
create policy "Allow all delete on abattages"       on abattages       for delete using (true);

create policy "Allow all select on employes"        on employes        for select using (true);
create policy "Allow all insert on employes"        on employes        for insert with check (true);
create policy "Allow all update on employes"        on employes        for update using (true) with check (true);
create policy "Allow all delete on employes"        on employes        for delete using (true);

create policy "Allow all select on paies"           on paies           for select using (true);
create policy "Allow all insert on paies"           on paies           for insert with check (true);
create policy "Allow all update on paies"           on paies           for update using (true) with check (true);
create policy "Allow all delete on paies"           on paies           for delete using (true);

create policy "Allow all select on depenses_rh"     on depenses_rh     for select using (true);
create policy "Allow all insert on depenses_rh"     on depenses_rh     for insert with check (true);
create policy "Allow all update on depenses_rh"     on depenses_rh     for update using (true) with check (true);
create policy "Allow all delete on depenses_rh"     on depenses_rh     for delete using (true);

create policy "Allow all select on notifications"   on notifications   for select using (true);
create policy "Allow all insert on notifications"   on notifications   for insert with check (true);
create policy "Allow all update on notifications"   on notifications   for update using (true) with check (true);
create policy "Allow all delete on notifications"   on notifications   for delete using (true);


-- ═══════════════════════════════════════════════════════════════════
-- SEED DATA — Default matières premières (raw materials catalog)
-- ═══════════════════════════════════════════════════════════════════

insert into matieres (matiere_id, nom, unite, actif) values
  ('mp-001', 'Maïs',                       'kg', true),
  ('mp-002', 'Tourteau de soja',           'kg', true),
  ('mp-003', 'Prémix vitamines-minéraux',  'kg', true),
  ('mp-004', 'Farine de poisson',          'kg', true),
  ('mp-005', 'Huile de palme',             'kg', true),
  ('mp-006', 'Lysine',                     'kg', true),
  ('mp-007', 'Carbonate de calcium',       'kg', true),
  ('mp-008', 'Sel',                        'kg', true),
  ('mp-009', 'Son de blé',                 'kg', true),
  ('mp-010', 'Autre',                      'kg', true)
on conflict (matiere_id) do nothing;

-- ═══════════════════════════════════════════════════════════════════
-- Done. Tables: 18 | Indexes: 22 | Seed rows: 10 (matieres)
-- ═══════════════════════════════════════════════════════════════════
