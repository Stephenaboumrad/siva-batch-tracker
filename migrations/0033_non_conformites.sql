-- ============================================================
-- Migration 0033 - Table non_conformites : deviation register
-- ------------------------------------------------------------
-- The app records SYMPTOMS (mortality, clinical signs, downtime) but has
-- no "deviation -> corrective action -> effectiveness check" workflow.
-- This register is a prerequisite for food-safety certification and is
-- useful for daily operations right away. One row per deviation :
--   - source        : where the deviation was spotted
--                     ('saisie' | 'traitement' | 'vide_sanitaire' |
--                      'audit' | 'autre')
--   - bande_id      : batch concerned (nullable - a deviation can be
--                     site-wide, e.g. building or audit finding).
--                     FK to bandes(id) (uuid PK), on delete set null :
--                     deleting a batch must never destroy the record.
--   - date_constat / description / gravite : the finding
--                     (gravite : 'mineure' | 'majeure' | 'critique')
--   - action_corrective / responsable / echeance : the response
--   - verification_efficacite / date_verification : the effectiveness
--                     check (manager surface in the UI)
--   - statut        : 'ouverte' | 'en_cours' | 'cloturee'
--   - created_by    : defaults to auth.uid() (null from SQL Editor)
--
-- Enum-style CHECK constraints on source / gravite / statut protect the
-- register's vocabulary. NO date-ordering constraints ON PURPOSE : field
-- entry must always be recordable, then corrected by the manager.
--
-- REGISTER ONLY : nothing auto-creates rows from mortality thresholds or
-- any other detection logic - that is a separate decision.
--
-- ROLE MODEL : auth.jwt() -> 'app_metadata' ->> 'role' (convention
-- 0021/0031/0032). chef_bande : SELECT + INSERT (reports what he sees on
-- the ground) + UPDATE of NON-CLOSED rows with identity frozen (id,
-- source, date_constat - same EXISTS-on-stored-row technique as 0032)
-- and WITHOUT the power to close (new statut may not be 'cloturee').
-- Closing is MANAGER-ONLY, enforced HERE, not only in the UI.
-- manager : full access ; anon : no policy + revoke = no access.
--
-- STRICTLY ADDITIVE : one new table only, no existing table/column/policy
-- touched. NO-OP for the app until the front reads/writes it (the front
-- treats the table as OPTIONAL and falls back to [] until this runs).
-- Idempotent : create table/index if not exists + to_regclass + drop
-- policy if exists. ASCII only, no comment at end of statement lines,
-- no semicolon inside comments.
-- TO BE RUN MANUALLY in the Supabase SQL Editor. Rollback : 0033_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 0) Dependency guard : bandes must exist (loud failure otherwise)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.bandes') is null then
    raise exception '0033: table bandes absente - migration interrompue (aucune table creee).';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Table
-- ------------------------------------------------------------
create table if not exists public.non_conformites (
  id                      uuid        primary key default gen_random_uuid(),
  created_at              timestamptz not null default now(),
  created_by              uuid        default auth.uid(),
  source                  text        not null,
  bande_id                uuid        references public.bandes(id) on delete set null,
  date_constat            date        not null,
  description             text        not null,
  gravite                 text        not null,
  action_corrective       text,
  responsable             text,
  echeance                date,
  verification_efficacite text,
  date_verification       date,
  statut                  text        not null default 'ouverte',
  constraint non_conformites_source_chk
    check (source in ('saisie','traitement','vide_sanitaire','audit','autre')),
  constraint non_conformites_gravite_chk
    check (gravite in ('mineure','majeure','critique')),
  constraint non_conformites_statut_chk
    check (statut in ('ouverte','en_cours','cloturee'))
);

create index if not exists idx_non_conformites_bande   on public.non_conformites(bande_id);
create index if not exists idx_non_conformites_statut  on public.non_conformites(statut);
create index if not exists idx_non_conformites_constat on public.non_conformites(date_constat);

-- ------------------------------------------------------------
-- 2) RLS per verb (style 0021/0031/0032) : SELECT + INSERT both internal
--    roles ; chef UPDATE limited to non-closed rows, identity frozen,
--    closing excluded ; UPDATE/DELETE manager otherwise
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.non_conformites') is null then
    raise notice '0033: table non_conformites absente - section 2 (RLS) ignoree.';
    return;
  end if;

  alter table public.non_conformites enable row level security;

  revoke all on public.non_conformites from anon;
  grant select, insert, update, delete on public.non_conformites to authenticated;

  drop policy if exists "rls33_non_conformites_select" on public.non_conformites;
  create policy "rls33_non_conformites_select" on public.non_conformites
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls33_non_conformites_insert" on public.non_conformites;
  create policy "rls33_non_conformites_insert" on public.non_conformites
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls33_non_conformites_update_manager" on public.non_conformites;
  create policy "rls33_non_conformites_update_manager" on public.non_conformites
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  -- chef_bande UPDATE : only rows not yet closed (USING) ; the NEW row
  -- must keep the stored identity - id / source / date_constat - via the
  -- 0032 EXISTS-on-stored-row technique (the subquery runs on the
  -- statement snapshot = pre-update tuple ; the SELECT policy above makes
  -- it visible and holds no subquery itself, so no policy recursion) -
  -- and must NOT be closed : statut -> 'cloturee' is manager-only.
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

  drop policy if exists "rls33_non_conformites_delete" on public.non_conformites;
  create policy "rls33_non_conformites_delete" on public.non_conformites
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Table present :
--   select to_regclass('public.non_conformites');
--   -- expected : public.non_conformites (not null).
--
-- 2. Columns :
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'non_conformites'
--    order by ordinal_position;
--   -- expected : 14 rows (id, created_at, created_by, source, bande_id,
--   -- date_constat, description, gravite, action_corrective, responsable,
--   -- echeance, verification_efficacite, date_verification, statut).
--
-- 3. RLS enabled :
--   select relrowsecurity from pg_class
--    where oid = 'public.non_conformites'::regclass;
--   -- expected : true.
--
-- 4. Policies (expected : exactly 5 rows, all rls33_*) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'non_conformites'
--    order by policyname;
--   -- expected :
--   --   rls33_non_conformites_delete         | DELETE
--   --   rls33_non_conformites_insert         | INSERT
--   --   rls33_non_conformites_select         | SELECT
--   --   rls33_non_conformites_update_chef    | UPDATE
--   --   rls33_non_conformites_update_manager | UPDATE
--
-- 5. anon has no access (expected : 0 rows) :
--   select grantee, privilege_type from information_schema.role_table_grants
--    where table_schema = 'public' and table_name = 'non_conformites'
--      and grantee = 'anon';
--
-- 6. Functional test (chef_bande session, browser console, on a row the
--    chef created - <ID> is the row's uuid) :
--   a) progress an OPEN record (expected : accepted) :
--     sb.from('non_conformites')
--       .update({statut:'en_cours', action_corrective:'x', responsable:'y'})
--       .eq('id','<ID>').select()
--   b) CLOSE it as chef (expected : RLS error "new row violates
--      row-level security policy") :
--     sb.from('non_conformites')
--       .update({statut:'cloturee'}).eq('id','<ID>').select()
--   c) re-key the identity (expected : same RLS error) :
--     sb.from('non_conformites')
--       .update({date_constat:'2020-01-01'}).eq('id','<ID>').select()
--   d) as MANAGER, close it (expected : accepted), then as chef try any
--      update on the closed row (expected : 0 rows affected).
-- ============================================================
