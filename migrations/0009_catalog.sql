-- ============================================================
-- Migration 0009 - Catalogue produits (portail B2B, etape 1)
--   table produits + vue v_catalogue_client + RLS rls9_*.
-- ------------------------------------------------------------
-- Additif, idempotent. A EXECUTER MANUELLEMENT dans Supabase SQL Editor
-- (role proprietaire -> contourne RLS). Rollback : 0009_rollback.sql.
--
-- Version DURCIE (correctif de l'echec 42601) : aucun commentaire en fin de
-- ligne d'instruction, aucun caractere non-ASCII ni point-virgule dans un
-- commentaire, une instruction par bloc, chaque instruction terminee proprement.
--
-- Modele de roles (rappel prod) : role lu dans le JWT
--   auth.jwt() -> 'app_metadata' ->> 'role' parmi {manager, chef_bande, (futur) client}.
-- anon : aucune policy = aucun acces.
--
-- Surete fuite : produits ne porte QUE le prix de vente public
-- (prix_base_kg_fcfa). Aucune colonne de cout/marge -> exposition au futur
-- role 'client' sans risque. Les couts restent sur bandes/intrants/abattages.
--
-- Rappel RLS : une table avec RLS activee mais SANS policy = refus total pour
-- tout le monde (managers compris). Les policies ci-dessous sont donc creees.
-- ============================================================

-- Table catalogue. Prix de vente public uniquement, aucune colonne de cout.
create table if not exists produits (
  id                 uuid        primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  produit_id         text        unique not null,
  nom                text        not null,
  categorie          text,
  calibre            text,
  prix_base_kg_fcfa  numeric     not null default 0,
  unite              text        not null default 'kg',
  disponible         boolean     not null default false,
  description        text,
  ordre_affichage    int         not null default 0,
  image_url          text,
  constraint produits_unite_chk check (unite in ('kg','unite'))
);

create index if not exists idx_produits_disponible on produits(disponible);
create index if not exists idx_produits_categorie  on produits(categorie);
create index if not exists idx_produits_ordre      on produits(ordre_affichage);

alter table produits enable row level security;

revoke all on produits from anon;
grant select, insert, update, delete on produits to authenticated;

drop policy if exists "rls9_produits_select" on produits;
drop policy if exists "rls9_produits_write" on produits;

-- SELECT : roles internes voient tout, sinon (futur client) seulement publie.
create policy "rls9_produits_select" on produits
  for select to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande')
    or disponible = true
  );

-- ECRITURE : manager uniquement.
create policy "rls9_produits_write" on produits
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- Vue catalogue client. security_invoker herite la RLS de produits.
-- Expression de prix isolee : un futur per-client pricing (tarifs_clients)
-- remplacera prix_base_kg_fcfa par coalesce(tc.prix_fcfa, prix_base_kg_fcfa)
-- sans changer les consommateurs de la vue.
drop view if exists v_catalogue_client;
create view v_catalogue_client with (security_invoker = true) as
select
  produit_id,
  nom,
  categorie,
  calibre,
  unite,
  prix_base_kg_fcfa as prix_kg_fcfa,
  description,
  image_url,
  ordre_affichage
from produits
where disponible = true;

revoke all on v_catalogue_client from anon;
grant select on v_catalogue_client to authenticated;
