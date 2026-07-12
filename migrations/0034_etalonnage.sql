-- ============================================================
-- Migration 0034 - Tables equipements + etalonnages : calibration register
-- ------------------------------------------------------------
-- The app records temperatures (temperature_observee_c, 0024) and weights
-- (poids_vif_moyen_g) but nothing records WHICH instrument produced them,
-- when it was last calibrated, or by whom. An uncalibrated thermometer
-- makes every temperature record unusable in an audit. Two tables :
--
--   1) equipements : the instrument inventory (one row per device).
--      - nom / type ('thermometre' | 'balance' | 'autre') / numero_serie
--        / localisation : identification
--      - frequence_etalonnage_mois : calibration interval (default 12) -
--        the front computes "next due" = last calibration + interval and
--        flags it ETALONNAGE_ALERTE_JOURS days ahead (front constant)
--      - actif : soft retirement - equipment is DEACTIVATED, not deleted,
--        so its calibration history survives (no delete in the UI)
--
--   2) etalonnages : the calibration log (one row per calibration act).
--      - realise_par : internal name or external body
--      - methode / ecart_constate : free text ON PURPOSE - the observed
--        deviation is NOT forced numeric (a reference-thermometer check
--        and a test-weight check express results differently)
--      - conforme : the verdict (default true)
--      - created_by : defaults to auth.uid() (null from SQL Editor)
--
-- REGISTER ONLY : saisies is NOT touched - linking a saisie to an
-- instrument (equipement_id) is a separate decision.
--
-- ROLE MODEL : auth.jwt() -> 'app_metadata' ->> 'role' (convention
-- 0021/0031/0033). manager : full access on both tables. chef_bande :
-- SELECT on both + INSERT on etalonnages only (he performs the periodic
-- checks in the buildings ; the inventory itself is manager-curated).
-- anon : no policy + revoke = no access.
--
-- STRICTLY ADDITIVE : two new tables only, no existing table/column/
-- policy touched. NO-OP for the app until the front reads/writes them
-- (the front treats both as OPTIONAL and falls back to [] until this
-- runs). No dependency on bandes. NO date CHECK constraints : field
-- entry must always be recordable, then corrected by the manager.
-- Idempotent : create table/index if not exists + to_regclass + drop
-- policy if exists. ASCII only, no comment at end of statement lines,
-- no semicolon inside comments.
-- TO BE RUN MANUALLY in the Supabase SQL Editor. Rollback : 0034_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Tables (equipements first : etalonnages references it)
-- ------------------------------------------------------------
create table if not exists public.equipements (
  id                         uuid        primary key default gen_random_uuid(),
  created_at                 timestamptz not null default now(),
  nom                        text        not null,
  type                       text        not null,
  numero_serie               text,
  localisation               text,
  frequence_etalonnage_mois  int         default 12,
  actif                      boolean     not null default true,
  constraint equipements_type_chk
    check (type in ('thermometre','balance','autre')),
  constraint equipements_frequence_chk
    check (frequence_etalonnage_mois is null or frequence_etalonnage_mois > 0)
);

create table if not exists public.etalonnages (
  id               uuid        primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  created_by       uuid        default auth.uid(),
  equipement_id    uuid        not null references public.equipements(id) on delete cascade,
  date_etalonnage  date        not null,
  realise_par      text,
  methode          text,
  ecart_constate   text,
  conforme         boolean     not null default true,
  observations     text
);

create index if not exists idx_equipements_actif      on public.equipements(actif);
create index if not exists idx_etalonnages_equipement on public.etalonnages(equipement_id);
create index if not exists idx_etalonnages_date       on public.etalonnages(date_etalonnage);

-- ------------------------------------------------------------
-- 2) RLS equipements : SELECT internal roles, writes manager only
--    (style 0018/0021 select + write pair)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.equipements') is null then
    raise notice '0034: table equipements absente - section 2 (RLS) ignoree.';
    return;
  end if;

  alter table public.equipements enable row level security;

  revoke all on public.equipements from anon;
  grant select, insert, update, delete on public.equipements to authenticated;

  drop policy if exists "rls34_equipements_select" on public.equipements;
  create policy "rls34_equipements_select" on public.equipements
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls34_equipements_write" on public.equipements;
  create policy "rls34_equipements_write" on public.equipements
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ------------------------------------------------------------
-- 3) RLS etalonnages : SELECT internal roles, INSERT chef_bande +
--    manager, UPDATE/DELETE manager only (style 0031)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.etalonnages') is null then
    raise notice '0034: table etalonnages absente - section 3 (RLS) ignoree.';
    return;
  end if;

  alter table public.etalonnages enable row level security;

  revoke all on public.etalonnages from anon;
  grant select, insert, update, delete on public.etalonnages to authenticated;

  drop policy if exists "rls34_etalonnages_select" on public.etalonnages;
  create policy "rls34_etalonnages_select" on public.etalonnages
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls34_etalonnages_insert" on public.etalonnages;
  create policy "rls34_etalonnages_insert" on public.etalonnages
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls34_etalonnages_update" on public.etalonnages;
  create policy "rls34_etalonnages_update" on public.etalonnages
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  drop policy if exists "rls34_etalonnages_delete" on public.etalonnages;
  create policy "rls34_etalonnages_delete" on public.etalonnages
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Tables present :
--   select to_regclass('public.equipements'), to_regclass('public.etalonnages');
--   -- expected : both not null.
--
-- 2. Columns :
--   select table_name, column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public'
--      and table_name in ('equipements','etalonnages')
--    order by table_name, ordinal_position;
--   -- expected : equipements 8 rows (id, created_at, nom, type,
--   -- numero_serie, localisation, frequence_etalonnage_mois, actif),
--   -- etalonnages 10 rows (id, created_at, created_by, equipement_id,
--   -- date_etalonnage, realise_par, methode, ecart_constate, conforme,
--   -- observations).
--
-- 3. RLS enabled on both :
--   select relname, relrowsecurity from pg_class
--    where oid in ('public.equipements'::regclass, 'public.etalonnages'::regclass);
--   -- expected : true, true.
--
-- 4. Policies (expected : exactly 6 rows, all rls34_*) :
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public'
--      and tablename in ('equipements','etalonnages')
--    order by tablename, policyname;
--   -- expected :
--   --   equipements | rls34_equipements_select  | SELECT
--   --   equipements | rls34_equipements_write   | ALL
--   --   etalonnages | rls34_etalonnages_delete  | DELETE
--   --   etalonnages | rls34_etalonnages_insert  | INSERT
--   --   etalonnages | rls34_etalonnages_select  | SELECT
--   --   etalonnages | rls34_etalonnages_update  | UPDATE
--
-- 5. anon has no access (expected : 0 rows) :
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema = 'public'
--      and table_name in ('equipements','etalonnages')
--      and grantee = 'anon';
--
-- 6. FK cascade (compute-only check, rolled back) :
--   begin;
--   insert into public.equipements (nom, type) values ('TEST-0034', 'thermometre');
--   insert into public.etalonnages (equipement_id, date_etalonnage)
--   select id, '2026-01-01' from public.equipements where nom = 'TEST-0034';
--   delete from public.equipements where nom = 'TEST-0034';
--   select count(*) from public.etalonnages
--    where equipement_id not in (select id from public.equipements);
--   -- expected : 0 (the calibration row followed the cascade)
--   rollback;
--
-- 7. Functional test (chef_bande session, browser console - <EQ_ID> is
--    an equipment uuid created by the manager) :
--   a) chef INSERTs a calibration (expected : accepted) :
--     sb.from('etalonnages').insert([{equipement_id:'<EQ_ID>', date_etalonnage:'2026-07-12'}])
--   b) chef INSERTs an equipment (expected : RLS error) :
--     sb.from('equipements').insert([{nom:'X', type:'autre'}])
--   c) chef UPDATEs / DELETEs a calibration (expected : 0 rows affected) :
--     sb.from('etalonnages').update({conforme:false}).eq('equipement_id','<EQ_ID>').select()
--     sb.from('etalonnages').delete().eq('equipement_id','<EQ_ID>').select()
--   d) the manager session inserts/updates/deletes freely on both tables.
-- ============================================================
