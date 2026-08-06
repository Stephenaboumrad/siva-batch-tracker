-- ============================================================
-- Migration 0043 - non_conformites : effectiveness check frozen for chef
-- ------------------------------------------------------------
-- Re-delivery of the ex-#119 amendment (closed unmerged) as an ADDITIVE
-- migration : 0033 has been EXECUTED in production and is therefore
-- immutable - this file replaces the relevant 0033 policies in place of
-- amending that file.
--
-- WHY : verification_efficacite / date_verification are the MANAGER-ONLY
-- effectiveness check of a deviation. The check is only worth anything if
-- it is INDEPENDENT - whoever reports the deviation and takes the
-- corrective action cannot be the one certifying the action worked.
-- Today the UI hides the block from the chef (CSS only) but the DB
-- accepts any value the chef sends : self-validation is possible at the
-- database level. This migration makes it impossible THERE ; the UI mask
-- and the front no longer sending those keys for the chef are defence in
-- depth, not the barrier.
--
-- WHAT (policy surface only - no table/column change) :
--   - INSERT split per role (0018 precedent). Manager : free.
--     chef_bande : the row cannot be born already 'cloturee' (closing is
--     manager-only) and the effectiveness check must be EMPTY at
--     creation (no self-validation one verb earlier either). The legacy
--     shared policy rls33_non_conformites_insert is dropped.
--   - chef UPDATE : identity freeze (id / source / date_constat, 0033)
--     EXTENDED to verification_efficacite / date_verification via the
--     same EXISTS-on-stored-row technique (0032). NULLABILITY : both
--     verification columns are nullable and are null on precisely the
--     rows the chef works on, so the comparison MUST be null-safe
--     ("is not distinct from") - a plain "=" would evaluate to null on
--     (null, null) and silently reject EVERY chef update.
--   - select / update_manager / delete : UNTOUCHED.
-- Policy names stay rls33_* (same table, same register - this file only
-- re-cuts their content ; pg_policies must never show both generations).
--
-- HARD PREREQUISITE : public.non_conformites must exist (0033 executed).
-- Loud abort otherwise - a silent skip would drop the freeze forever if
-- the migrations were run out of order.
--
-- Idempotent : drop policy if exists + create. ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- Rollback : 0043_rollback.sql (restores the 0033-as-executed policies).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Hard prerequisite : 0033 must have been executed
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.non_conformites') is null then
    raise exception '0043: table non_conformites absente - executer 0033 d''abord (aucune policy modifiee).';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) INSERT split per role + chef UPDATE freeze extended
-- ------------------------------------------------------------
do $$
begin
  -- INSERT : drop the legacy shared policy, split per role.
  drop policy if exists "rls33_non_conformites_insert" on public.non_conformites;

  drop policy if exists "rls33_non_conformites_insert_manager" on public.non_conformites;
  create policy "rls33_non_conformites_insert_manager" on public.non_conformites
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  drop policy if exists "rls33_non_conformites_insert_chef" on public.non_conformites;
  create policy "rls33_non_conformites_insert_chef" on public.non_conformites
    for insert to authenticated
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and statut <> 'cloturee'
      and verification_efficacite is null
      and date_verification is null
    );

  -- chef UPDATE : 0033 freeze (id / source / date_constat) + the two
  -- verification columns, null-safe (see header).
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
          and prev.verification_efficacite is not distinct from non_conformites.verification_efficacite
          and prev.date_verification is not distinct from non_conformites.date_verification
      )
    );
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Policies (expected : exactly 6 rows, all rls33_* - the legacy shared
--    name rls33_non_conformites_insert must NOT appear) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'non_conformites'
--    order by policyname;
--   -- expected :
--   --   rls33_non_conformites_delete         | DELETE
--   --   rls33_non_conformites_insert_chef    | INSERT
--   --   rls33_non_conformites_insert_manager | INSERT
--   --   rls33_non_conformites_select         | SELECT
--   --   rls33_non_conformites_update_chef    | UPDATE
--   --   rls33_non_conformites_update_manager | UPDATE
--
-- 2. Functional test (chef_bande session, browser console, on an OPEN row
--    with verification_efficacite still null - <ID> is the row's uuid) :
--   a) progress the record WITHOUT touching the check (expected :
--      accepted - proves the null-safe comparison lets normal chef
--      updates through) :
--     sb.from('non_conformites')
--       .update({statut:'en_cours', action_corrective:'x'})
--       .eq('id','<ID>').select()
--   b) set the check as chef (expected : RLS error "new row violates
--      row-level security policy") :
--     sb.from('non_conformites')
--       .update({verification_efficacite:'efficace'}).eq('id','<ID>').select()
--   c) insert born-verified as chef (expected : same RLS error) :
--     sb.from('non_conformites').insert({source:'saisie',
--       date_constat:'2026-08-06', description:'t', gravite:'mineure',
--       verification_efficacite:'x'}).select()
--   d) insert born-closed as chef (expected : same RLS error) :
--     sb.from('non_conformites').insert({source:'saisie',
--       date_constat:'2026-08-06', description:'t', gravite:'mineure',
--       statut:'cloturee'}).select()
--   e) as MANAGER, set the check on the same row (expected : accepted).
--
-- 3. On a row whose check IS set (after 2e), chef update of any other
--    field resending nothing about the check (expected : accepted - the
--    front no longer sends those keys for the chef) ; chef update
--    explicitly nulling it (expected : RLS error) :
--     sb.from('non_conformites')
--       .update({verification_efficacite:null}).eq('id','<ID>').select()
-- ============================================================
