-- ============================================================
-- Migration 0011 - ROLLBACK
-- ------------------------------------------------------------
-- Retire l'index unique et la colonne clients.auth_user_id, puis la colonne
-- commandes.source. NE TOUCHE AUCUNE autre donnee. Apres ce rollback, la
-- distinction interne vs portail (source) est perdue et le lien compte Auth
-- vers fiche client disparait. Idempotent, gardes to_regclass.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.clients') is not null then
    drop index if exists uq_clients_auth_user_id;
    alter table public.clients drop column if exists auth_user_id;
  end if;

  if to_regclass('public.commandes') is not null then
    alter table public.commandes drop column if exists source;
  end if;
end $$;
