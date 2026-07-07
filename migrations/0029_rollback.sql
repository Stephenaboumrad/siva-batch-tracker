-- ============================================================
-- Rollback 0029 - retire saisies.cause_5m
-- ------------------------------------------------------------
-- ATTENTION : perd les categorisations 5M deja saisies. Les saisies
-- elles-memes (mortalite, aliment, eau...) ne sont PAS touchees.
-- Idempotent : to_regclass + drop column if exists.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.saisies') is null then
    raise notice '0029 rollback: table saisies absente - rien a faire.';
    return;
  end if;

  alter table public.saisies
    drop column if exists cause_5m;
end $$;

-- VERIFICATION (attendu : 0 ligne)
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'saisies'
--      and column_name = 'cause_5m';
