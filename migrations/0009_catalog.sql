-- ═══════════════════════════════════════════════════════════════════
-- Migration 0009 — Catalogue produits (portail B2B, étape 1) :
--   table produits (granulaire, au kg) + vue v_catalogue_client + RLS rls9_*.
-- ───────────────────────────────────────────────────────────────────
-- ADDITIF : aucune table/colonne existante modifiée. IDEMPOTENT.
-- Rappel RLS (leçon du modèle rls7_*) : une table avec RLS ACTIVÉE mais SANS
-- aucune policy = REFUS TOTAL pour tout le monde (managers compris). On crée
-- donc explicitement les policies ci-dessous, sinon produits serait verrouillé.
--
-- MODÈLE DE RÔLES (rappel prod) : rôle lu dans le JWT
--   auth.jwt() -> 'app_metadata' ->> 'role' ∈ {manager, chef_bande, (futur) client}
--   • manager / chef_bande = utilisateurs internes
--   • anon                 = aucun accès (aucune policy anon)
--
-- SÛRETÉ FUITE : produits ne porte QUE le prix de vente public
-- (prix_base_kg_fcfa). AUCUNE colonne de coût/marge → exposition au futur rôle
-- 'client' sans risque. Les coûts restent sur bandes/intrants/abattages (RLS
-- manager-only / vue bandes_ops).
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase, rôle propriétaire → contourne
-- RLS). Rollback : 0009_rollback.sql.
-- ═══════════════════════════════════════════════════════════════════

-- 1) Table catalogue ── prix de vente UNIQUEMENT (aucune colonne de coût/marge).
create table if not exists produits (
  id                 uuid        primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  produit_id         text        unique not null,        -- clé métier (FK future : lignes_commande, tarifs_clients)
  nom                text        not null,                -- SKU granulaire (cuisse, aile, filet, "poulet entier 1100-1300g"…)
  categorie          text,                                -- 'poulet_entier' | 'decoupe' | 'abats' | 'autre'
  calibre            text,                                -- grade de poids (volailles entières) ; null pour les découpes
  prix_base_kg_fcfa  numeric     not null default 0,      -- prix de vente public au kg (PAS un coût)
  unite              text        not null default 'kg',   -- figé 'kg' (MVP) ; colonne pour extension future
  disponible         boolean     not null default false,  -- publié/commandable (le manager bascule)
  description        text,
  ordre_affichage    int         not null default 0,
  image_url          text,
  constraint produits_unite_chk check (unite in ('kg','unite'))
);

create index if not exists idx_produits_disponible on produits(disponible);
create index if not exists idx_produits_categorie  on produits(categorie);
create index if not exists idx_produits_ordre      on produits(ordre_affichage);

-- 2) RLS
alter table produits enable row level security;

revoke all on produits from anon;                 -- anon : aucun accès (ceinture+bretelles ; RLS le refuse déjà)
grant select, insert, update, delete on produits to authenticated;  -- RLS filtre ensuite par rôle

-- Pattern idempotent : drop if exists puis create (pas de « create policy if not exists »).
drop policy if exists "rls9_produits_select" on produits;
drop policy if exists "rls9_produits_write"  on produits;

-- SELECT : internes voient TOUT (admin) ; tout autre authentifié (futur 'client')
-- ne voit QUE les produits publiés. Sûr : aucune colonne coût sur produits.
create policy "rls9_produits_select" on produits
  for select to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande')
    or disponible = true
  );

-- ÉCRITURE : manager UNIQUEMENT (catalogue géré par les managers).
create policy "rls9_produits_write" on produits
  for all to authenticated
  using      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- 3) Vue catalogue client (security_invoker → hérite la RLS de produits).
--    L'expression de prix est ISOLÉE → SWAP futur (tarifs_clients) sans toucher
--    les consommateurs : remplacer par
--      coalesce(tc.prix_fcfa, p.prix_base_kg_fcfa) as prix_kg_fcfa
--    + LEFT JOIN tarifs_clients tc on (tc.produit_id = produit_id
--      and tc.client_id = auth.jwt()->'app_metadata'->>'client_id' and tc.actif).
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

-- ═══════════════════════════════════════════════════════════════════
-- VÉRIFICATION (à lancer APRÈS — voir aussi la description de la PR)
-- ───────────────────────────────────────────────────────────────────
-- 1) Policies présentes :
--      select tablename, policyname, cmd, roles, qual from pg_policies where tablename='produits';
--      → rls9_produits_select (SELECT) + rls9_produits_write (ALL, role='manager').
-- 2) security_invoker actif sur la vue :
--      select relname, reloptions from pg_class where relname='v_catalogue_client';
--      → reloptions contient security_invoker=true.
-- 3) Tests de rôle (JWT simulé) :
--      begin; set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"client"}}';
--        insert into produits(produit_id,nom) values ('prd-test','x'); -- attendu : ERREUR (RLS write)
--        select count(*) from produits where disponible=false;          -- attendu : 0 (client ne voit pas le non-publié)
--      rollback;
--      begin; set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"manager"}}';
--        select count(*) from produits;                                 -- attendu : tout (publié + non publié)
--      rollback;
--      begin; set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--        select count(*) from produits;                                 -- attendu : tout (lecture)
--        insert into produits(produit_id,nom) values ('prd-test2','y'); -- attendu : ERREUR (RLS write)
--      rollback;
-- ═══════════════════════════════════════════════════════════════════
