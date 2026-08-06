-- ============================================================
-- Rollback 0044 - restore the 0007 blanket policy on notifications
-- ------------------------------------------------------------
-- Drops the five per-verb rls44_* policies and recreates
-- rls7_internal_all exactly as 0007 generated it for this table.
-- FLAT top-level DDL (0043/0044 editor constraint) ; loud abort if the
-- table is absent. Idempotent. ASCII only.
-- ============================================================

do $$
begin
  if to_regclass('public.notifications') is null then
    raise exception '0044_rollback: table notifications absente - rien a restaurer.';
  end if;
end $$;

drop policy if exists "rls44_notifications_select" on public.notifications;

drop policy if exists "rls44_notifications_insert_manager" on public.notifications;

drop policy if exists "rls44_notifications_insert_chef" on public.notifications;

drop policy if exists "rls44_notifications_update_manager" on public.notifications;

drop policy if exists "rls44_notifications_delete_manager" on public.notifications;

drop policy if exists "rls7_internal_all" on public.notifications;

create policy "rls7_internal_all" on public.notifications
  for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'))
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- select policyname, cmd from pg_policies
--  where schemaname = 'public' and tablename = 'notifications'
--  order by policyname;
-- -- expected : exactly 1 row :
-- --   rls7_internal_all | ALL
-- ============================================================
