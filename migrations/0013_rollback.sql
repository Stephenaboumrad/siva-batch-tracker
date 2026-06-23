-- ============================================================
-- Migration 0013 - ROLLBACK
-- ------------------------------------------------------------
-- Supprime les trois overlays client. La baseline rls7 reste intacte, donc un
-- compte client repasse a zero ligne partout (etat d'avant le portail). Les
-- tables restent en RLS activee. Idempotent, gardes to_regclass.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.commandes') is not null then
    drop policy if exists "rls_client_commandes_select" on public.commandes;
  end if;

  if to_regclass('public.clients') is not null then
    drop policy if exists "rls_client_clients_select" on public.clients;
  end if;

  if to_regclass('public.lignes_commande') is not null then
    drop policy if exists "rls_client_lignes_select" on public.lignes_commande;
  end if;
end $$;
