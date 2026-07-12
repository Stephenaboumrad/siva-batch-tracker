-- ============================================================
-- Migration 0035 - Tables postes_appatage + releves_nuisibles : pest control
-- ------------------------------------------------------------
-- Pest control register (rodents, insects, wild birds - direct disease
-- vectors on a poultry site). Core prerequisite programme, nothing is
-- recorded today. PERIODIC by nature, NOT per-batch : deliberately a
-- separate register from the vide sanitaire module. Two tables :
--
--   1) postes_appatage : bait stations / traps (one row per station).
--      - numero UNIQUE ("P1", "P2"...) / localisation / type
--        ('rongeurs' | 'insectes' | 'oiseaux')
--      - actif : soft retirement (station removed from the round without
--        losing its history - no delete in the UI)
--
--   2) releves_nuisibles : the periodic checks (one row per station and
--      per round date - UNIQUE (poste_id, date_releve)).
--      - constat : 'ras' | 'traces' | 'capture' | 'appat_consomme'
--      - quantite (nullable, number of catches) / appat_remplace /
--        produit / numero_lot : what was found and what was re-baited
--      - action : action taken if infestation
--      - releve_par / observations : execution trace
--      - created_by : defaults to auth.uid() (null from SQL Editor)
--
-- ROLE MODEL : auth.jwt() -> 'app_metadata' ->> 'role' (convention
-- 0021/0031/0034). manager : full access on both tables. chef_bande :
-- SELECT on both + INSERT on releves_nuisibles (he does the rounds) +
-- UPDATE of his OWN SAME-DAY rows only : created_by = auth.uid() and
-- created_at::date = current_date - he may fix a mistake during the day
-- he recorded it, after that corrections are manager-only.
--   - TIMEZONE : Supabase evaluates current_date in UTC ; Cote d'Ivoire
--     is UTC+0 year-round (no DST), so the UTC day IS the farm-local day.
--   - The WITH CHECK freezes created_by and created_at against the
--     stored row (EXISTS-on-stored-row technique, 0032/0033) : without
--     it the chef could bump created_at to re-open his edit window
--     forever, or reassign ownership. Everything ELSE stays editable ON
--     PURPOSE : correcting a wrongly picked station or date the same day
--     is precisely what this window is for.
--   - created_by is nullable -> null-safe "is not distinct from" ;
--     created_at is not null -> plain "=" (0033 lesson).
-- anon : no policy + revoke = no access.
--
-- STRICTLY ADDITIVE : two new tables only, no existing table/column/
-- policy touched. NO-OP for the app until the front reads/writes them
-- (the front treats both as OPTIONAL and falls back to [] until this
-- runs). No dependency on bandes. NO date-ordering CHECK constraints :
-- field entry must always be recordable, then corrected by the manager.
-- Idempotent : create table/index if not exists + to_regclass + drop
-- policy if exists. ASCII only, no comment at end of statement lines,
-- no semicolon inside comments.
-- TO BE RUN MANUALLY in the Supabase SQL Editor. Rollback : 0035_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Tables (postes_appatage first : releves_nuisibles references it)
-- ------------------------------------------------------------
create table if not exists public.postes_appatage (
  id            uuid        primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  numero        text        not null,
  localisation  text        not null,
  type          text        not null,
  actif         boolean     not null default true,
  constraint postes_appatage_numero_uniq unique (numero),
  constraint postes_appatage_type_chk
    check (type in ('rongeurs','insectes','oiseaux'))
);

create table if not exists public.releves_nuisibles (
  id              uuid        primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  created_by      uuid        default auth.uid(),
  poste_id        uuid        not null references public.postes_appatage(id) on delete cascade,
  date_releve     date        not null,
  constat         text        not null,
  quantite        int,
  appat_remplace  boolean     not null default false,
  produit         text,
  numero_lot      text,
  action          text,
  releve_par      text,
  observations    text,
  constraint releves_nuisibles_constat_chk
    check (constat in ('ras','traces','capture','appat_consomme')),
  constraint releves_nuisibles_quantite_chk
    check (quantite is null or quantite >= 0),
  constraint releves_nuisibles_poste_date_uniq unique (poste_id, date_releve)
);

create index if not exists idx_postes_appatage_actif  on public.postes_appatage(actif);
create index if not exists idx_releves_nuisibles_date on public.releves_nuisibles(date_releve);

-- ------------------------------------------------------------
-- 2) RLS postes_appatage : SELECT internal roles, writes manager only
--    (style 0018/0034 select + write pair)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.postes_appatage') is null then
    raise notice '0035: table postes_appatage absente - section 2 (RLS) ignoree.';
    return;
  end if;

  alter table public.postes_appatage enable row level security;

  revoke all on public.postes_appatage from anon;
  grant select, insert, update, delete on public.postes_appatage to authenticated;

  drop policy if exists "rls35_postes_appatage_select" on public.postes_appatage;
  create policy "rls35_postes_appatage_select" on public.postes_appatage
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls35_postes_appatage_write" on public.postes_appatage;
  create policy "rls35_postes_appatage_write" on public.postes_appatage
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ------------------------------------------------------------
-- 3) RLS releves_nuisibles : SELECT internal roles, INSERT chef_bande +
--    manager, chef UPDATE limited to his own same-day rows,
--    UPDATE/DELETE manager otherwise
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.releves_nuisibles') is null then
    raise notice '0035: table releves_nuisibles absente - section 3 (RLS) ignoree.';
    return;
  end if;

  alter table public.releves_nuisibles enable row level security;

  revoke all on public.releves_nuisibles from anon;
  grant select, insert, update, delete on public.releves_nuisibles to authenticated;

  drop policy if exists "rls35_releves_nuisibles_select" on public.releves_nuisibles;
  create policy "rls35_releves_nuisibles_select" on public.releves_nuisibles
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls35_releves_nuisibles_insert" on public.releves_nuisibles;
  create policy "rls35_releves_nuisibles_insert" on public.releves_nuisibles
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls35_releves_nuisibles_update_manager" on public.releves_nuisibles;
  create policy "rls35_releves_nuisibles_update_manager" on public.releves_nuisibles
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  -- chef_bande UPDATE : only rows HE created TODAY (same-day
  -- self-correction window - see header for the UTC = farm-local note).
  -- The WITH CHECK freezes created_by / created_at against the stored
  -- row so the window cannot be extended nor ownership reassigned ; the
  -- OTHER columns stay editable on purpose (fixing a wrongly picked
  -- station or date is what the window is for). Subquery on the
  -- statement snapshot = pre-update tuple, visible via the SELECT policy
  -- above which holds no subquery itself - no policy recursion.
  drop policy if exists "rls35_releves_nuisibles_update_chef" on public.releves_nuisibles;
  create policy "rls35_releves_nuisibles_update_chef" on public.releves_nuisibles
    for update to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and created_by = auth.uid()
      and created_at::date = current_date
    )
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'chef_bande'
      and exists (
        select 1
        from public.releves_nuisibles prev
        where prev.id = releves_nuisibles.id
          and prev.created_by is not distinct from releves_nuisibles.created_by
          and prev.created_at = releves_nuisibles.created_at
      )
    );

  drop policy if exists "rls35_releves_nuisibles_delete" on public.releves_nuisibles;
  create policy "rls35_releves_nuisibles_delete" on public.releves_nuisibles
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Tables present :
--   select to_regclass('public.postes_appatage'), to_regclass('public.releves_nuisibles');
--   -- expected : both not null.
--
-- 2. Columns :
--   select table_name, column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public'
--      and table_name in ('postes_appatage','releves_nuisibles')
--    order by table_name, ordinal_position;
--   -- expected : postes_appatage 6 rows (id, created_at, numero,
--   -- localisation, type, actif), releves_nuisibles 13 rows (id,
--   -- created_at, created_by, poste_id, date_releve, constat, quantite,
--   -- appat_remplace, produit, numero_lot, action, releve_par,
--   -- observations).
--
-- 3. Unique constraints :
--   select conname from pg_constraint
--    where conrelid in ('public.postes_appatage'::regclass,
--                       'public.releves_nuisibles'::regclass)
--      and contype = 'u'
--    order by conname;
--   -- expected : postes_appatage_numero_uniq,
--   --            releves_nuisibles_poste_date_uniq.
--
-- 4. RLS enabled on both :
--   select relname, relrowsecurity from pg_class
--    where oid in ('public.postes_appatage'::regclass,
--                  'public.releves_nuisibles'::regclass);
--   -- expected : true, true.
--
-- 5. Policies (expected : exactly 7 rows, all rls35_*) :
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public'
--      and tablename in ('postes_appatage','releves_nuisibles')
--    order by tablename, policyname;
--   -- expected :
--   --   postes_appatage   | rls35_postes_appatage_select          | SELECT
--   --   postes_appatage   | rls35_postes_appatage_write           | ALL
--   --   releves_nuisibles | rls35_releves_nuisibles_delete        | DELETE
--   --   releves_nuisibles | rls35_releves_nuisibles_insert        | INSERT
--   --   releves_nuisibles | rls35_releves_nuisibles_select        | SELECT
--   --   releves_nuisibles | rls35_releves_nuisibles_update_chef   | UPDATE
--   --   releves_nuisibles | rls35_releves_nuisibles_update_manager| UPDATE
--
-- 6. anon has no access (expected : 0 rows) :
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema = 'public'
--      and table_name in ('postes_appatage','releves_nuisibles')
--      and grantee = 'anon';
--
-- 7. FK cascade + unique (compute-only check, rolled back) :
--   begin;
--   insert into public.postes_appatage (numero, localisation, type)
--   values ('TEST-0035', 'test', 'rongeurs');
--   insert into public.releves_nuisibles (poste_id, date_releve, constat)
--   select id, '2026-01-01', 'ras' from public.postes_appatage where numero = 'TEST-0035';
--   insert into public.releves_nuisibles (poste_id, date_releve, constat)
--   select id, '2026-01-01', 'ras' from public.postes_appatage where numero = 'TEST-0035';
--   -- expected : the SECOND insert fails (duplicate key
--   -- releves_nuisibles_poste_date_uniq) - then :
--   rollback;
--
-- 8. Functional test (chef_bande session, browser console - <P_ID> is a
--    station uuid created by the manager, <ID> a releve the chef created
--    TODAY) :
--   a) chef INSERTs a check (expected : accepted) :
--     sb.from('releves_nuisibles').insert([{poste_id:'<P_ID>', date_releve:'2026-07-12', constat:'ras'}])
--   b) chef UPDATEs his own row the same day (expected : accepted) :
--     sb.from('releves_nuisibles').update({constat:'traces'}).eq('id','<ID>').select()
--   c) chef UPDATEs a row created by the manager, or one of his own
--      rows on a LATER day (expected : 0 rows affected)
--   d) chef INSERTs a station (expected : RLS error) :
--     sb.from('postes_appatage').insert([{numero:'X', localisation:'x', type:'rongeurs'}])
--   e) chef DELETEs a check (expected : 0 rows affected)
--   f) the manager session inserts/updates/deletes freely on both tables.
-- ============================================================
