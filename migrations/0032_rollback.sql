-- ============================================================
-- Rollback 0032 - vides_sanitaires : remove the chef_bande UPDATE policy
-- ------------------------------------------------------------
-- Drops the single policy added by 0032. The 0031 policies, grants,
-- anon revoke and table are untouched (back to : chef SELECT + INSERT
-- only, UPDATE/DELETE manager-only). Idempotent (to_regclass + drop
-- policy if exists). ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.vides_sanitaires') is null then
    raise notice '0032 rollback: table vides_sanitaires absente - rien a faire.';
    return;
  end if;

  drop policy if exists "rls32_vides_sanitaires_update_chef" on public.vides_sanitaires;
end $$;
