-- ═══════════════════════════════════════════════════════════════════
-- COQORICO / SIVA — Migration 0002 : fondations multi-sites & POS / caisse
-- Société Ivoirienne de Volaille et Assimilés — Les Terres du Sud, Azaguié
--
-- BUT : poser le socle schéma pour un réseau de distribution (sites de
-- production/abattage/HQ, points de vente retail, caisse/POS, mouvements de
-- stock inter-sites, paiements & encours client) SANS casser l'exploitation
-- mono-site actuelle.
--
-- PROPRIÉTÉS :
--   • ADDITIF & NON DESTRUCTIF : aucune colonne/table existante n'est
--     supprimée ni modifiée de façon incompatible. Les nouvelles colonnes
--     sur les tables existantes sont NULLABLE → les lignes actuelles
--     continuent de fonctionner telles quelles.
--   • IDEMPOTENT : `create table if not exists`, `add column if not exists`,
--     `create index if not exists`, `on conflict do nothing`,
--     `create or replace view`. Re-jouable sans risque.
--   • RÉTRO-COMPATIBLE CÔTÉ APP : l'app lit en `select('*')` (les nouvelles
--     colonnes apparaissent simplement) et écrit des payloads à champs
--     explicites (les colonnes omises prennent leur DEFAULT/NULL). Les
--     nouvelles tables ne sont PAS chargées par l'app tant qu'aucune UI
--     multi-sites n'existe → la migration peut être jouée avant OU après le
--     déploiement applicatif.
--
-- À EXÉCUTER UNE FOIS dans Supabase → SQL Editor. Convention reprise du
-- schéma existant (supabase-setup.sql) : chaque table a
--   id uuid pk default gen_random_uuid(), created_at timestamptz, et une
--   clé métier `<entité>_id text unique not null` ; les FK référencent la
--   CLÉ MÉTIER texte (pas l'uuid).
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- 1. SITES — lieux physiques (production / abattage / HQ / distribution)
-- ═══════════════════════════════════════════════════════════════════
create table if not exists sites (
  id           uuid        primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  site_id      text        unique not null,
  nom          text        not null,
  type         text,                          -- 'production' | 'abattage' | 'hq' | 'distribution' | 'mixte'
  ville        text,
  adresse      text,
  telephone    text,
  responsable  text,
  statut       text        default 'actif',
  note         text
);

-- Site par défaut « Azaguié » — DOIT exister avant le backfill des FK plus bas.
-- La clé métier 'site-azaguie' est reprise telle quelle par la constante
-- applicative DEFAULT_SITE_ID (index.html).
insert into sites (site_id, nom, type, ville, statut) values
  ('site-azaguie', 'Les Terres du Sud — Azaguié', 'production', 'Azaguié', 'actif')
on conflict (site_id) do nothing;


-- ═══════════════════════════════════════════════════════════════════
-- 2. POINTS DE VENTE — retail (FK site optionnelle)
-- ═══════════════════════════════════════════════════════════════════
create table if not exists points_de_vente (
  id           uuid        primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  pdv_id       text        unique not null,
  nom          text        not null,
  site_id      text        references sites(site_id) on delete set null,   -- rattachement optionnel
  type         text,                          -- 'boutique' | 'kiosque' | 'marche' | 'ambulant'
  adresse      text,
  ville        text,
  telephone    text,
  responsable  text,
  statut       text        default 'actif',
  note         text
);


-- ═══════════════════════════════════════════════════════════════════
-- 3. POS / CAISSE — transactions (en-tête) + lignes
--    Calqué sur commandes / lignes_commande.
-- ═══════════════════════════════════════════════════════════════════
create table if not exists pos_transactions (
  id                  uuid        primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  transaction_id      text        unique not null,
  pdv_id              text        references points_de_vente(pdv_id) on delete set null,
  site_id             text        references sites(site_id)          on delete set null,
  vendeur_id          text        references employes(employe_id)    on delete set null,
  client_id           text        references clients(client_id)      on delete set null,  -- optionnel (vente au comptoir)
  date_transaction    timestamptz default now(),
  mode_paiement       text,                          -- tender : 'especes' | 'mobile_money' | 'carte' | 'credit' | 'cheque'
  reference_paiement  text,
  remise_fcfa         numeric     default 0,
  montant_total_fcfa  numeric     default 0,
  statut              text        default 'finalisee',  -- 'finalisee' | 'annulee' | 'remboursee'
  note                text
);

create table if not exists lignes_transaction (
  id              uuid        primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  ligne_id        text        unique not null,
  transaction_id  text        not null references pos_transactions(transaction_id) on delete cascade,
  produit         text,
  description     text,
  bande_id        text        references bandes(bande_id) on delete set null,  -- traçabilité lot d'origine
  numero_lot      text,
  quantite_kg     numeric     default 0,        -- qty (au kg, comme lignes_commande)
  prix_kg_fcfa    numeric     default 0,        -- prix unitaire (au kg)
  montant_fcfa    numeric     default 0
  -- NOTE : si le retail vend à l'UNITÉ (poulet entier) plutôt qu'au kg,
  --        ajouter ultérieurement quantite / unite / prix_unitaire_fcfa.
  --        Laissé hors périmètre ici pour rester aligné sur lignes_commande.
);


-- ═══════════════════════════════════════════════════════════════════
-- 4. MOUVEMENTS DE STOCK — flux ferme → abattage → distribution → POS
--    Emplacements polymorphes : un site OU un point de vente (tous nullables).
-- ═══════════════════════════════════════════════════════════════════
create table if not exists mouvements_stock (
  id                  uuid        primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  mouvement_id        text        unique not null,
  date_mouvement      timestamptz default now(),
  type_mouvement      text,                          -- 'transfert' | 'entree' | 'sortie' | 'ajustement' | 'vente'
  from_site_id        text        references sites(site_id)            on delete set null,
  from_pdv_id         text        references points_de_vente(pdv_id)   on delete set null,
  to_site_id          text        references sites(site_id)            on delete set null,
  to_pdv_id           text        references points_de_vente(pdv_id)   on delete set null,
  stock_id            text        references stocks(stock_id)          on delete set null,
  bande_id            text        references bandes(bande_id)          on delete set null,  -- lot d'origine
  numero_lot          text,
  type_produit        text,
  quantite            numeric     default 0,
  unite               text,
  cout_unitaire_fcfa  numeric     default 0,
  cout_total_fcfa     numeric     default 0,
  reference           text,                          -- ex : transaction_id / commande_id / reception_id lié
  statut              text        default 'valide',  -- 'valide' | 'en_transit' | 'annule'
  responsable         text,
  note                text
);


-- ═══════════════════════════════════════════════════════════════════
-- 5. PAIEMENTS + ENCOURS CLIENT (AR)
-- ═══════════════════════════════════════════════════════════════════
create table if not exists paiements (
  id              uuid        primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  paiement_id     text        unique not null,
  date_paiement   timestamptz default now(),
  client_id       text        references clients(client_id)             on delete set null,
  commande_id     text        references commandes(commande_id)         on delete set null,
  transaction_id  text        references pos_transactions(transaction_id) on delete set null,
  pdv_id          text        references points_de_vente(pdv_id)        on delete set null,
  site_id         text        references sites(site_id)                 on delete set null,
  sens            text        default 'encaissement',  -- 'encaissement' (client → SIVA) | 'remboursement'
  mode_paiement   text,                          -- 'especes' | 'mobile_money' | 'carte' | 'cheque' | 'virement'
  reference       text,
  montant_fcfa    numeric     default 0,
  encaisse_par    text        references employes(employe_id) on delete set null,
  statut          text        default 'confirme',  -- 'confirme' | 'en_attente' | 'annule'
  note            text
);

-- Mécanisme d'encours/solde client :
--   • Colonnes additives sur clients (cache de solde + limite de crédit) pour
--     un futur suivi explicite côté app. Nullable / default 0 → non destructif.
alter table clients add column if not exists solde_fcfa          numeric default 0;
alter table clients add column if not exists limite_credit_fcfa  numeric default 0;

--   • Vue CALCULÉE (source de vérité immédiate, aucune écriture requise) :
--     encours = total facturé (commandes livrées) − total encaissé (paiements).
create or replace view v_client_soldes as
select
  c.client_id,
  c.nom,
  coalesce(f.total_facture_fcfa, 0)                                as total_facture_fcfa,
  coalesce(p.total_paye_fcfa, 0)                                   as total_paye_fcfa,
  coalesce(f.total_facture_fcfa, 0) - coalesce(p.total_paye_fcfa, 0) as solde_fcfa
from clients c
left join (
  select client_id, sum(montant_total_fcfa) as total_facture_fcfa
  from commandes
  where statut = 'livree' and client_id is not null
  group by client_id
) f on f.client_id = c.client_id
left join (
  select client_id, sum(montant_fcfa) as total_paye_fcfa
  from paiements
  where sens = 'encaissement' and statut = 'confirme' and client_id is not null
  group by client_id
) p on p.client_id = c.client_id;


-- ═══════════════════════════════════════════════════════════════════
-- 6. FK NULLABLES sur les tables existantes (dimension localisation)
--    Nullable → les lignes existantes restent valides. Un DEFAULT de
--    transition = 'site-azaguie' attribue automatiquement les NOUVELLES
--    lignes créées par l'app (qui n'envoie pas encore site_id) au site par
--    défaut, sans aucune modification du code d'écriture. L'app surchargera
--    ce DEFAULT explicitement quand le vrai multi-sites arrivera.
--    pdv_id n'est ajouté qu'où une attribution retail a du sens
--    (stocks, commandes) — pas sur bandes/abattages (artefacts de production).
-- ═══════════════════════════════════════════════════════════════════

-- bandes : site de production
alter table bandes    add column if not exists site_id text references sites(site_id) on delete set null;
update      bandes    set site_id = 'site-azaguie' where site_id is null;
alter table bandes    alter column site_id set default 'site-azaguie';

-- abattages : site d'abattage / transformation
alter table abattages add column if not exists site_id text references sites(site_id) on delete set null;
update      abattages set site_id = 'site-azaguie' where site_id is null;
alter table abattages alter column site_id set default 'site-azaguie';

-- stocks : site + point de vente (un stock peut être en site ou en PDV)
alter table stocks    add column if not exists site_id text references sites(site_id)          on delete set null;
alter table stocks    add column if not exists pdv_id  text references points_de_vente(pdv_id) on delete set null;
update      stocks    set site_id = 'site-azaguie' where site_id is null;
alter table stocks    alter column site_id set default 'site-azaguie';

-- commandes : site de préparation + PDV de vente
alter table commandes add column if not exists site_id text references sites(site_id)          on delete set null;
alter table commandes add column if not exists pdv_id  text references points_de_vente(pdv_id) on delete set null;
update      commandes set site_id = 'site-azaguie' where site_id is null;
alter table commandes alter column site_id set default 'site-azaguie';


-- ═══════════════════════════════════════════════════════════════════
-- 7. INDEX — sur chaque FK et colonne de date filtrante (convention existante)
-- ═══════════════════════════════════════════════════════════════════
create index if not exists idx_points_de_vente_site_id      on points_de_vente(site_id);

create index if not exists idx_pos_transactions_pdv_id      on pos_transactions(pdv_id);
create index if not exists idx_pos_transactions_site_id     on pos_transactions(site_id);
create index if not exists idx_pos_transactions_vendeur_id  on pos_transactions(vendeur_id);
create index if not exists idx_pos_transactions_client_id   on pos_transactions(client_id);
create index if not exists idx_pos_transactions_date        on pos_transactions(date_transaction);

create index if not exists idx_lignes_transaction_trans_id  on lignes_transaction(transaction_id);
create index if not exists idx_lignes_transaction_bande_id  on lignes_transaction(bande_id);

create index if not exists idx_mouvements_stock_from_site   on mouvements_stock(from_site_id);
create index if not exists idx_mouvements_stock_to_site     on mouvements_stock(to_site_id);
create index if not exists idx_mouvements_stock_from_pdv    on mouvements_stock(from_pdv_id);
create index if not exists idx_mouvements_stock_to_pdv      on mouvements_stock(to_pdv_id);
create index if not exists idx_mouvements_stock_stock_id    on mouvements_stock(stock_id);
create index if not exists idx_mouvements_stock_bande_id    on mouvements_stock(bande_id);
create index if not exists idx_mouvements_stock_date        on mouvements_stock(date_mouvement);

create index if not exists idx_paiements_client_id          on paiements(client_id);
create index if not exists idx_paiements_commande_id        on paiements(commande_id);
create index if not exists idx_paiements_transaction_id     on paiements(transaction_id);
create index if not exists idx_paiements_pdv_id             on paiements(pdv_id);
create index if not exists idx_paiements_date               on paiements(date_paiement);

create index if not exists idx_bandes_site_id              on bandes(site_id);
create index if not exists idx_abattages_site_id           on abattages(site_id);
create index if not exists idx_stocks_site_id              on stocks(site_id);
create index if not exists idx_stocks_pdv_id               on stocks(pdv_id);
create index if not exists idx_commandes_site_id           on commandes(site_id);
create index if not exists idx_commandes_pdv_id            on commandes(pdv_id);


-- ═══════════════════════════════════════════════════════════════════
-- 8. ROW LEVEL SECURITY
--    Politiques PERMISSIVES (using(true)/with check(true)) sur les nouvelles
--    tables — STRICTEMENT cohérentes avec le reste du schéma (la clé anon de
--    l'app lit/écrit toutes les tables). Indispensable pour ne RIEN casser.
-- ═══════════════════════════════════════════════════════════════════
alter table sites              enable row level security;
alter table points_de_vente    enable row level security;
alter table pos_transactions   enable row level security;
alter table lignes_transaction enable row level security;
alter table mouvements_stock   enable row level security;
alter table paiements          enable row level security;

-- Pattern idempotent : drop if exists puis create (Postgres n'a pas de
-- `create policy if not exists`). Re-jouable sans erreur « policy exists ».
drop policy if exists "Allow all select on sites" on sites;
drop policy if exists "Allow all insert on sites" on sites;
drop policy if exists "Allow all update on sites" on sites;
drop policy if exists "Allow all delete on sites" on sites;
create policy "Allow all select on sites" on sites for select using (true);
create policy "Allow all insert on sites" on sites for insert with check (true);
create policy "Allow all update on sites" on sites for update using (true) with check (true);
create policy "Allow all delete on sites" on sites for delete using (true);

drop policy if exists "Allow all select on points_de_vente" on points_de_vente;
drop policy if exists "Allow all insert on points_de_vente" on points_de_vente;
drop policy if exists "Allow all update on points_de_vente" on points_de_vente;
drop policy if exists "Allow all delete on points_de_vente" on points_de_vente;
create policy "Allow all select on points_de_vente" on points_de_vente for select using (true);
create policy "Allow all insert on points_de_vente" on points_de_vente for insert with check (true);
create policy "Allow all update on points_de_vente" on points_de_vente for update using (true) with check (true);
create policy "Allow all delete on points_de_vente" on points_de_vente for delete using (true);

drop policy if exists "Allow all select on pos_transactions" on pos_transactions;
drop policy if exists "Allow all insert on pos_transactions" on pos_transactions;
drop policy if exists "Allow all update on pos_transactions" on pos_transactions;
drop policy if exists "Allow all delete on pos_transactions" on pos_transactions;
create policy "Allow all select on pos_transactions" on pos_transactions for select using (true);
create policy "Allow all insert on pos_transactions" on pos_transactions for insert with check (true);
create policy "Allow all update on pos_transactions" on pos_transactions for update using (true) with check (true);
create policy "Allow all delete on pos_transactions" on pos_transactions for delete using (true);

drop policy if exists "Allow all select on lignes_transaction" on lignes_transaction;
drop policy if exists "Allow all insert on lignes_transaction" on lignes_transaction;
drop policy if exists "Allow all update on lignes_transaction" on lignes_transaction;
drop policy if exists "Allow all delete on lignes_transaction" on lignes_transaction;
create policy "Allow all select on lignes_transaction" on lignes_transaction for select using (true);
create policy "Allow all insert on lignes_transaction" on lignes_transaction for insert with check (true);
create policy "Allow all update on lignes_transaction" on lignes_transaction for update using (true) with check (true);
create policy "Allow all delete on lignes_transaction" on lignes_transaction for delete using (true);

drop policy if exists "Allow all select on mouvements_stock" on mouvements_stock;
drop policy if exists "Allow all insert on mouvements_stock" on mouvements_stock;
drop policy if exists "Allow all update on mouvements_stock" on mouvements_stock;
drop policy if exists "Allow all delete on mouvements_stock" on mouvements_stock;
create policy "Allow all select on mouvements_stock" on mouvements_stock for select using (true);
create policy "Allow all insert on mouvements_stock" on mouvements_stock for insert with check (true);
create policy "Allow all update on mouvements_stock" on mouvements_stock for update using (true) with check (true);
create policy "Allow all delete on mouvements_stock" on mouvements_stock for delete using (true);

drop policy if exists "Allow all select on paiements" on paiements;
drop policy if exists "Allow all insert on paiements" on paiements;
drop policy if exists "Allow all update on paiements" on paiements;
drop policy if exists "Allow all delete on paiements" on paiements;
create policy "Allow all select on paiements" on paiements for select using (true);
create policy "Allow all insert on paiements" on paiements for insert with check (true);
create policy "Allow all update on paiements" on paiements for update using (true) with check (true);
create policy "Allow all delete on paiements" on paiements for delete using (true);

-- ────────────────────────────────────────────────────────────────────
-- RLS — STUBS de politiques SCOPÉES PAR site_id (COMMENTÉS, pour revue).
-- NE PAS activer tel quel : à substituer aux politiques permissives une fois
-- l'authentification par utilisateur en place (chaque utilisateur portant un
-- site). Deux patterns courants :
--
--   (a) Claim JWT 'site_id' (Supabase Auth, app_metadata) :
--   -- create policy "site_scope_select_stocks" on stocks for select using (
--   --   site_id is null
--   --   or site_id = (auth.jwt() -> 'app_metadata' ->> 'site_id')
--   -- );
--
--   (b) GUC posée par l'app à chaque requête (set_config('app.site_id', …)) :
--   -- create policy "site_scope_select_stocks" on stocks for select using (
--   --   site_id is null
--   --   or site_id = current_setting('app.site_id', true)
--   -- );
--
-- Décliner pour SELECT/INSERT/UPDATE/DELETE sur les tables porteuses de
-- site_id : sites, points_de_vente, bandes, abattages, stocks, commandes,
-- pos_transactions, lignes_transaction (via sa transaction), mouvements_stock,
-- paiements. Conserver « site_id is null » dans le USING pendant la transition
-- pour que les lignes mono-site héritées (backfillées) restent visibles.
-- ────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════
-- FIN. Nouvelles tables : 6 (sites, points_de_vente, pos_transactions,
-- lignes_transaction, mouvements_stock, paiements) | Vue : 1
-- (v_client_soldes) | Colonnes ajoutées : clients(+2),
-- bandes/abattages(+site_id), stocks/commandes(+site_id,+pdv_id) | Seed : 1
-- site (Azaguié) | Backfill : bandes/abattages/stocks/commandes → site-azaguie
-- ═══════════════════════════════════════════════════════════════════
