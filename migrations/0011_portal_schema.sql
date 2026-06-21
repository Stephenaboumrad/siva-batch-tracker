-- ============================================================
-- Migration 0011 - Schema portail B2B (additif)
-- ------------------------------------------------------------
-- Deux ajouts strictement additifs, prerequis du portail client :
--   1) commandes.source : partitionne les commandes internes vs portail.
--      Defaut 'interne' plus backfill des lignes existantes (NULL devient
--      'interne'). La RPC place_order (0012) ecrira la valeur 'portail_client'.
--   2) clients.auth_user_id : lien compte Auth Supabase vers fiche client,
--      pour audit et revocation. Colonne NULLABLE, index unique partiel.
--
-- Aucune colonne existante supprimee ni renommee. Aucune RLS modifiee ici.
-- Idempotent, gardes to_regclass et IF NOT EXISTS. ASCII uniquement, pas de
-- commentaire en fin de ligne d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor (role proprietaire qui
-- contourne la RLS). Rollback : 0011_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.commandes') is not null then
    alter table public.commandes add column if not exists source text default 'interne';
    update public.commandes set source = 'interne' where source is null;
  end if;

  if to_regclass('public.clients') is not null then
    alter table public.clients add column if not exists auth_user_id uuid;
    create unique index if not exists uq_clients_auth_user_id
      on public.clients(auth_user_id)
      where auth_user_id is not null;
  end if;
end $$;
