-- ============================================================
-- Migration 0044 - notifications : per-verb RLS (close the last known
-- server-side hole before cycle 1)
-- ------------------------------------------------------------
-- TODAY : notifications carries the 0007 blanket policy
-- rls7_internal_all (FOR ALL, manager + chef_bande, full R/W). The
-- validate/reject workflow is therefore UI-ONLY on the server side : a
-- chef session can UPDATE any notification (self-validate his own
-- declarations, rewrite payload_json, erase a manager note) or DELETE
-- the whole queue from the browser console. RLS must be the barrier.
--
-- TARGET (cockpit lot D) :
--   - SELECT  : manager + chef_bande (the panel shows pending titles to
--               both ; the chef polls his own outcomes).
--   - INSERT  : manager free ; chef_bande only rows BORN pending
--               (statut 'en_attente', no valide_par, no date_validation)
--               - the front no longer creates auto-validated 'saisie'
--               journal rows (removed in the same PR).
--   - UPDATE  : manager ONLY (claim/unclaim + note + incidental lu_par).
--               The chef read-state lives in device localStorage, not in
--               the table - no chef UPDATE path exists in the front.
--   - DELETE  : manager ONLY (future purge ; no UI today).
--
-- FORM : flat top-level DDL (0043 precedent - the Supabase SQL editor
-- rejected create policy inside do $$ although vanilla PostgreSQL
-- accepts it). Safety unchanged : one paste = one implicit transaction
-- (the section 0 abort skips everything) ; run separately, every
-- statement fails loudly by itself on a missing table.
--
-- HARD PREREQUISITE : public.notifications must exist. Loud abort
-- otherwise.
--
-- Idempotent : drop policy if exists + create. ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- Rollback : 0044_rollback.sql (restores the 0007 blanket policy).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Hard prerequisite
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.notifications') is null then
    raise exception '0044: table notifications absente - rien a modifier.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Replace the blanket policy with per-verb policies
-- ------------------------------------------------------------

drop policy if exists "rls7_internal_all" on public.notifications;

drop policy if exists "rls44_notifications_select" on public.notifications;

create policy "rls44_notifications_select" on public.notifications
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

drop policy if exists "rls44_notifications_insert_manager" on public.notifications;

create policy "rls44_notifications_insert_manager" on public.notifications
  for insert to authenticated
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls44_notifications_insert_chef" on public.notifications;

create policy "rls44_notifications_insert_chef" on public.notifications
  for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
    and statut = 'en_attente'
    and coalesce(valide_par, '') = ''
    and date_validation is null
  );

drop policy if exists "rls44_notifications_update_manager" on public.notifications;

create policy "rls44_notifications_update_manager" on public.notifications
  for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls44_notifications_delete_manager" on public.notifications;

create policy "rls44_notifications_delete_manager" on public.notifications
  for delete to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Policies (expected : exactly 5 rows, all rls44_* - the blanket
--    rls7_internal_all must NOT appear on THIS table ; it stays on the
--    other internal tables) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'notifications'
--    order by policyname;
--   -- expected :
--   --   rls44_notifications_delete_manager   | DELETE
--   --   rls44_notifications_insert_chef      | INSERT
--   --   rls44_notifications_insert_manager   | INSERT
--   --   rls44_notifications_select           | SELECT
--   --   rls44_notifications_update_manager   | UPDATE
--
-- 2. Functional test (chef_bande session, browser console) :
--   a) read still works (expected : rows) :
--     sb.from('notifications').select('notif_id,statut').limit(3)
--   b) create a pending declaration (expected : accepted) :
--     sb.from('notifications').insert({notif_id:'notif-test-0044',
--       type:'intrant', action:'test 0044', auteur_matricule:'TEST',
--       auteur_nom:'Test', date_action:new Date().toISOString(),
--       statut:'en_attente', valide_par:'', payload_json:'{}',
--       note_manager:'', lu_par:''}).select()
--   c) create born-validated (expected : RLS error "new row violates
--      row-level security policy") :
--     sb.from('notifications').insert({notif_id:'notif-test-0044b',
--       type:'intrant', action:'test', auteur_matricule:'TEST',
--       auteur_nom:'Test', date_action:new Date().toISOString(),
--       statut:'validee', valide_par:'moi', payload_json:'{}'}).select()
--   d) self-validate as chef (expected : 0 rows updated - policy filters
--      them out) :
--     sb.from('notifications').update({statut:'validee'})
--       .eq('notif_id','notif-test-0044').select()
--   e) delete as chef (expected : 0 rows) :
--     sb.from('notifications').delete()
--       .eq('notif_id','notif-test-0044').select()
--   f) as MANAGER : claim the test row with the CAS shape the front uses
--      (expected : 1 row) :
--     sb.from('notifications').update({statut:'validee',valide_par:'M'})
--       .eq('notif_id','notif-test-0044').eq('statut','en_attente').select()
--      then re-run the SAME statement (expected : 0 rows - the CAS) ;
--      finally clean up :
--     sb.from('notifications').delete().eq('notif_id','notif-test-0044')
-- ============================================================
