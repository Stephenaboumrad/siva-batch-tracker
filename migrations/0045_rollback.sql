-- ============================================================
-- Rollback 0045 - drop table pointages + trigger function
-- ------------------------------------------------------------
-- WARNING : DESTROYS ALL POINTAGE DATA. Dropping the table also drops
-- its policies, trigger and unique constraint ; the function is
-- dropped separately (it lives outside the table).
-- The 'employe' auth accounts are NOT touched (created manually by
-- Stephen in Supabase Auth, outside migrations) - after this rollback
-- an employe session simply has no table to write to.
-- FLAT top-level DDL (0043/0044 editor constraint). Idempotent.
-- ASCII only. TO BE RUN MANUALLY in the Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.pointages') is null then
    raise notice '0045_rollback: table pointages deja absente - drops idempotents.';
  else
    raise notice '0045_rollback: suppression de public.pointages (donnees comprises).';
  end if;
end $$;

drop table if exists public.pointages;

drop function if exists public.trg_pointages_horodatage();

-- ============================================================
-- VERIFICATION (executable - RAISEs NOTICEs, reads catalogs only)
-- ------------------------------------------------------------
do $$
begin
  raise notice '0045_rollback verify: table pointages absente = %',
    (to_regclass('public.pointages') is null);
  raise notice '0045_rollback verify: fonction trg_pointages_horodatage absente = %',
    (to_regprocedure('public.trg_pointages_horodatage()') is null);
end $$;
