-- ============================================================
-- Migration 0031 - Table vides_sanitaires : sanitary downtime register
-- ------------------------------------------------------------
-- Records the cleaning / disinfection period between two batches in the
-- same building (vide sanitaire). Core biosecurity record and prerequisite
-- programme for future food-safety certification. One row per downtime:
--   - batiment           : building name (bandes.batiment, 0025, is free
--                          text - same convention here)
--   - bande_sortante_id  : outgoing batch (nullable - first cycle has none)
--   - bande_entrante_id  : next batch placed (nullable until known)
--   - date_sortie        : last bird out (starts the downtime)
--   - date_fin_nettoyage : cleaning / disinfection completed
--   - date_entree        : next placement (ends the downtime)
--   - duree_jours        : GENERATED (date_entree - date_sortie), stored -
--                          server-authoritative once both dates are known,
--                          null while the building is still empty. The
--                          front NEVER writes this column (Postgres would
--                          reject it) and computes the live value itself.
--   - produits           : jsonb array of products used, shape
--                          [{nom, dose, numero_lot, date_application}]
--   - operateur / controle_visuel / observations : execution trace
--   - created_by         : defaults to auth.uid() (null from SQL Editor)
--
-- FK to bandes(id) (uuid PK), NOT bandes(bande_id) : on delete set null on
-- BOTH sides - deleting a batch must never destroy a biosecurity record.
-- UNIQUE (batiment, date_sortie) : one downtime per building per exit date.
--
-- NO date-ordering check constraints ON PURPOSE : the recommended minimum
-- duration is a front-side WARNING only (never blocks saving) and field
-- data entry must always be recordable, then corrected by the manager.
--
-- NOTE numbering : the scoping note said 0028, but 0028 (parametres), 0029
-- and 0030 are already taken - this file is 0031, next free number.
--
-- ROLE MODEL : auth.jwt() -> 'app_metadata' ->> 'role' (convention
-- 0007/0021/0027/0028). chef_bande : SELECT + INSERT (field entry) ;
-- manager : full access ; anon : no policy + revoke = no access.
--
-- STRICTLY ADDITIVE : one new table only, no existing table/column/policy
-- touched. NO-OP for the app until the front reads/writes it (the front
-- treats the table as OPTIONAL and falls back to [] until this runs).
-- Idempotent : create table/index if not exists + to_regclass + drop
-- policy if exists. ASCII only, no comment at end of statement lines,
-- no semicolon inside comments.
-- TO BE RUN MANUALLY in the Supabase SQL Editor. Rollback : 0031_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 0) Dependency guard : bandes must exist (loud failure otherwise)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.bandes') is null then
    raise exception '0031: table bandes absente - migration interrompue (aucune table creee).';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Table
-- ------------------------------------------------------------
create table if not exists public.vides_sanitaires (
  id                 uuid        primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  created_by         uuid        default auth.uid(),
  batiment           text        not null,
  bande_sortante_id  uuid        references public.bandes(id) on delete set null,
  bande_entrante_id  uuid        references public.bandes(id) on delete set null,
  date_sortie        date        not null,
  date_fin_nettoyage date,
  date_entree        date,
  duree_jours        int         generated always as (date_entree - date_sortie) stored,
  produits           jsonb,
  operateur          text,
  controle_visuel    boolean     not null default false,
  observations       text,
  constraint vides_sanitaires_batiment_sortie_uniq unique (batiment, date_sortie)
);

create index if not exists idx_vides_sanitaires_batiment on public.vides_sanitaires(batiment);
create index if not exists idx_vides_sanitaires_sortante on public.vides_sanitaires(bande_sortante_id);
create index if not exists idx_vides_sanitaires_entrante on public.vides_sanitaires(bande_entrante_id);

-- ------------------------------------------------------------
-- 2) RLS per verb (style 0021/0028) : SELECT internal roles,
--    INSERT chef_bande + manager, UPDATE/DELETE manager only
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.vides_sanitaires') is null then
    raise notice '0031: table vides_sanitaires absente - section 2 (RLS) ignoree.';
    return;
  end if;

  alter table public.vides_sanitaires enable row level security;

  revoke all on public.vides_sanitaires from anon;
  grant select, insert, update, delete on public.vides_sanitaires to authenticated;

  drop policy if exists "rls31_vides_sanitaires_select" on public.vides_sanitaires;
  create policy "rls31_vides_sanitaires_select" on public.vides_sanitaires
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls31_vides_sanitaires_insert" on public.vides_sanitaires;
  create policy "rls31_vides_sanitaires_insert" on public.vides_sanitaires
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  drop policy if exists "rls31_vides_sanitaires_update" on public.vides_sanitaires;
  create policy "rls31_vides_sanitaires_update" on public.vides_sanitaires
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  drop policy if exists "rls31_vides_sanitaires_delete" on public.vides_sanitaires;
  create policy "rls31_vides_sanitaires_delete" on public.vides_sanitaires
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ============================================================
-- VERIFICATION (run AFTER, read-only)
-- ------------------------------------------------------------
-- 1. Table present :
--   select to_regclass('public.vides_sanitaires');
--   -- expected : public.vides_sanitaires (not null).
--
-- 2. Columns (duree_jours must be a stored generated column) :
--   select column_name, data_type, is_nullable, is_generated
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'vides_sanitaires'
--    order by ordinal_position;
--   -- expected : 14 rows, duree_jours integer with is_generated = ALWAYS.
--
-- 3. RLS enabled :
--   select relrowsecurity from pg_class
--    where oid = 'public.vides_sanitaires'::regclass;
--   -- expected : true.
--
-- 4. Policies (expected : exactly 4 rows, all rls31_*) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'vides_sanitaires'
--    order by policyname;
--   -- expected :
--   --   rls31_vides_sanitaires_delete | DELETE
--   --   rls31_vides_sanitaires_insert | INSERT
--   --   rls31_vides_sanitaires_select | SELECT
--   --   rls31_vides_sanitaires_update | UPDATE
--
-- 5. anon has no access (expected : 0 rows) :
--   select grantee, privilege_type from information_schema.role_table_grants
--    where table_schema = 'public' and table_name = 'vides_sanitaires'
--      and grantee = 'anon';
--
-- 6. Generated duration behaves (compute-only check, rolled back) :
--   begin;
--   insert into public.vides_sanitaires (batiment, date_sortie, date_entree)
--   values ('TEST-0031', '2026-01-01', '2026-01-15');
--   select duree_jours from public.vides_sanitaires where batiment = 'TEST-0031';
--   -- expected : 14
--   rollback;
--
-- 7. Functional test (chef_bande session, browser console) :
--   sb.from('vides_sanitaires').insert([{batiment:'T', date_sortie:'2026-01-01'}])
--   -- expected : accepted (then delete the row as manager)
--   sb.from('vides_sanitaires').delete().eq('batiment','T')
--   -- expected as chef_bande : 0 rows affected (DELETE is manager-only)
-- ============================================================
