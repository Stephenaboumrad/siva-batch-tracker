-- ============================================================
-- Migration 0032 - vides_sanitaires : chef_bande can CLOSE an open record
-- ------------------------------------------------------------
-- 0031 (applied in prod, IMMUTABLE - this file is purely additive) gave
-- chef_bande SELECT + INSERT only. Real workflow : the chef OPENS the
-- record when the building empties (date_entree unknown) and comes back
-- DAYS LATER to fill date_fin_nettoyage / date_entree / produits. Under
-- 0031 he cannot (UPDATE is manager-only) - every closure would need the
-- manager to re-key the chef's field data.
--
-- This migration adds ONE permissive UPDATE policy for chef_bande :
--   - USING      : the row is still OPEN (date_entree is null). Once the
--                  building is re-occupied the record freezes for the
--                  chef ; corrections become manager-only again (rls31).
--   - WITH CHECK : the record identity is UNCHANGED - batiment and
--                  date_sortie must keep their stored values (the chef
--                  closes a record, he does not re-key it). RLS cannot
--                  compare OLD/NEW directly, so the check correlates the
--                  NEW row against the STORED row by id : the subquery
--                  runs on the statement snapshot, which still holds the
--                  pre-update tuple. The 0031 SELECT policy makes that
--                  row visible to the chef, and the SELECT policy itself
--                  contains no subquery, so there is no policy recursion.
--                  Side effect of the id correlation : changing id is
--                  rejected too (no stored row would match).
--
-- Net effect for chef_bande : may fill/correct date_fin_nettoyage,
-- date_entree, produits, operateur, controle_visuel, observations of an
-- OPEN record ; may NOT re-key batiment / date_sortie ; may NOT touch a
-- closed record ; still cannot DELETE. Manager policies (rls31_*), the
-- grants and the anon revoke of 0031 are NOT touched. No table/column
-- change, no date-ordering check constraint (saving must never block).
--
-- Idempotent : to_regclass + drop policy if exists. ASCII only, no
-- comment at end of statement lines, no semicolon inside comments.
-- TO BE RUN MANUALLY in the Supabase SQL Editor. Rollback : 0032_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.vides_sanitaires') is null then
    raise notice '0032: table vides_sanitaires absente (0031 non appliquee ?) - migration ignoree.';
    return;
  end if;

  drop policy if exists "rls32_vides_sanitaires_update_chef" on public.vides_sanitaires;
  create policy "rls32_vides_sanitaires_update_chef" on public.vides_sanitaires
    for update to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and date_entree is null
    )
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and exists (
        select 1
        from public.vides_sanitaires prev
        where prev.id = vides_sanitaires.id
          and prev.batiment = vides_sanitaires.batiment
          and prev.date_sortie = vides_sanitaires.date_sortie
      )
    );
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Policies (expected : exactly 5 rows - the 4 rls31_* untouched
--    plus the new rls32 UPDATE) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'vides_sanitaires'
--    order by policyname;
--   -- expected :
--   --   rls31_vides_sanitaires_delete      | DELETE
--   --   rls31_vides_sanitaires_insert      | INSERT
--   --   rls31_vides_sanitaires_select      | SELECT
--   --   rls31_vides_sanitaires_update      | UPDATE
--   --   rls32_vides_sanitaires_update_chef | UPDATE
--
-- 2. anon still has no access (expected : 0 rows) :
--   select grantee, privilege_type from information_schema.role_table_grants
--    where table_schema = 'public' and table_name = 'vides_sanitaires'
--      and grantee = 'anon';
--
-- 3. Functional test (chef_bande session, browser console, on a row of a
--    TEST building - <ID> is the row's uuid) :
--   a) close an OPEN record (expected : accepted) :
--     sb.from('vides_sanitaires')
--       .update({date_entree:'2026-08-01', date_fin_nettoyage:'2026-07-20'})
--       .eq('id','<ID>').select()
--   b) re-key the identity of an OPEN record (expected : RLS error
--      "new row violates row-level security policy") :
--     sb.from('vides_sanitaires')
--       .update({batiment:'AUTRE'}).eq('id','<ID>').select()
--   c) touch the record once CLOSED (expected : 0 rows affected) :
--     sb.from('vides_sanitaires')
--       .update({observations:'x'}).eq('id','<ID>').select()
--   d) the manager session still updates/deletes anything (rls31 intact).
-- ============================================================
