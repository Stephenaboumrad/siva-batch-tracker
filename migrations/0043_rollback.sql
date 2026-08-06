-- ============================================================
-- Rollback 0043 - restore the 0033-as-executed policy surface
-- ------------------------------------------------------------
-- Drops the per-role INSERT split and the extended chef UPDATE freeze,
-- restores the shared INSERT policy and the 0033 chef UPDATE policy
-- (identity freeze only, no verification freeze).
-- Idempotent ; loud abort if the table is absent. ASCII only.
-- ============================================================

do $$
begin
  if to_regclass('public.non_conformites') is null then
    raise exception '0043_rollback: table non_conformites absente - rien a restaurer.';
  end if;
end $$;

do $$
begin
  drop policy if exists "rls33_non_conformites_insert_manager" on public.non_conformites;
  drop policy if exists "rls33_non_conformites_insert_chef" on public.non_conformites;

  drop policy if exists "rls33_non_conformites_insert" on public.non_conformites;
  create policy "rls33_non_conformites_insert" on public.non_conformites
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls33_non_conformites_update_chef" on public.non_conformites;
  create policy "rls33_non_conformites_update_chef" on public.non_conformites
    for update to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and statut <> 'cloturee'
    )
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and statut <> 'cloturee'
      and exists (
        select 1
        from public.non_conformites prev
        where prev.id = non_conformites.id
          and prev.source = non_conformites.source
          and prev.date_constat = non_conformites.date_constat
      )
    );
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- select policyname, cmd from pg_policies
--  where schemaname = 'public' and tablename = 'non_conformites'
--  order by policyname;
-- -- expected : exactly 5 rows (0033 surface) :
-- --   rls33_non_conformites_delete         | DELETE
-- --   rls33_non_conformites_insert         | INSERT
-- --   rls33_non_conformites_select         | SELECT
-- --   rls33_non_conformites_update_chef    | UPDATE
-- --   rls33_non_conformites_update_manager | UPDATE
-- ============================================================
