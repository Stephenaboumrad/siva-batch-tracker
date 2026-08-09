-- ============================================================
-- Migration 0045 - RH lot 1 : table pointages (time clock) + role
--                  employe (foundation only)
-- ------------------------------------------------------------
-- SCOPE (lot RH-1) : a new auth role 'employe' (accounts created
-- MANUALLY by Stephen in Supabase Auth, app_metadata
-- {role:'employe', matricule, name}) clocks in/out on a dedicated
-- single-screen surface in index.html. No manager HR page in this lot.
-- employes / paies / depenses_rh are NOT touched.
--
-- TABLE : public.pointages - one row per (employe_matricule, day).
--   'Arrivee' INSERTs the row (heure_arrivee), 'Depart' UPDATEs the
--   same row (heure_depart). Unique (employe_matricule, date_pointage)
--   makes a double clock-in a loud duplicate-key error.
--
-- ACCESS MODEL :
--   SELECT : manager all ; employe only his own rows
--            (created_by = auth.uid()).
--   INSERT : manager free (manual corrections) ; employe only his own
--            row, born TODAY, arrival set, no departure, and
--            employe_matricule pinned to the JWT matricule.
--   UPDATE : manager free ; employe only his own row of TODAY and only
--            the null -> value fill of heure_depart - every other
--            column is frozen by the EXISTS-on-stored-row correlation
--            (rls35_releves_nuisibles_update_chef pattern ; the employe
--            SELECT policy holds no subquery, so the correlated
--            subquery reads the statement snapshot without policy
--            recursion - 0035 precedent).
--   DELETE : manager only.
--
-- SERVER TIME IS AUTHORITATIVE : a BEFORE trigger rewrites
-- heure_arrivee (INSERT) and heure_depart (UPDATE) to now() whenever
-- the writer's JWT role is 'employe' - client-supplied clock values
-- are never trusted from the phone. Manager sessions and no-JWT
-- contexts (SQL editor, service role) keep their explicit values :
-- manual corrections NEED arbitrary times.
--
-- TIMEZONE : Cote d'Ivoire is UTC (GMT+0) year-round, so current_date
-- and now() in UTC are exactly farm-local (same note as 0035).
--
-- _ops NOTE (stated on purpose) : pointages is NOT one of the nine
-- _ops tables of 0040 section 1 (bandes, intrants, receptions,
-- abattages, aliments_phases, formulations_mp, commandes,
-- lignes_commande, clients) - no 0040 view replay is needed here.
--
-- MANUAL SEED CAVEAT : created_by defaults to auth.uid(), which is
-- NULL in the SQL editor - a manual INSERT there must supply
-- created_by explicitly or it fails on NOT NULL (loud, intended).
--
-- FORM : flat top-level DDL (0043/0044 precedent - the Supabase SQL
-- editor rejects create policy inside do $$). One paste = one implicit
-- transaction ; the section 0 diagnostic aborts nothing (creation
-- migration), it only reports the pre-state.
--
-- Idempotent : create table if not exists + drop policy/trigger if
-- exists + create or replace function. ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- Rollback : 0045_rollback.sql (DROPS THE TABLE - destroys pointage
-- data).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Pre-state diagnostic (read-only NOTICEs, no abort)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.pointages') is null then
    raise notice '0045 pre-state: table pointages absente - creation.';
  else
    raise notice '0045 pre-state: table pointages deja presente - reprise idempotente.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Table
-- ------------------------------------------------------------
create table if not exists public.pointages (
  id uuid primary key default gen_random_uuid(),
  employe_matricule text not null,
  employe_nom text not null,
  date_pointage date not null default current_date,
  heure_arrivee timestamptz,
  heure_depart timestamptz,
  created_by uuid not null default auth.uid(),
  created_at timestamptz default now(),
  constraint pointages_matricule_jour_uniq unique (employe_matricule, date_pointage)
);

-- ------------------------------------------------------------
-- 2) Grants + RLS (0035 pattern : anon = no grant + no policy)
-- ------------------------------------------------------------
revoke all on public.pointages from anon;

grant select, insert, update, delete on public.pointages to authenticated;

alter table public.pointages enable row level security;

-- ------------------------------------------------------------
-- 3) Server-time trigger (employe writes only - see header)
-- ------------------------------------------------------------
create or replace function public.trg_pointages_horodatage()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_role text;
begin
  v_role := auth.jwt() -> 'app_metadata' ->> 'role';
  if v_role = 'employe' then
    if tg_op = 'INSERT' then
      if new.heure_arrivee is not null then
        new.heure_arrivee := now();
      end if;
      new.created_at := now();
    else
      if new.heure_depart is distinct from old.heure_depart then
        new.heure_depart := now();
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pointages_horodatage on public.pointages;

create trigger pointages_horodatage
  before insert or update on public.pointages
  for each row
  execute function public.trg_pointages_horodatage();

-- ------------------------------------------------------------
-- 4) Policies (per verb, rls45_* - 0044 naming style)
-- ------------------------------------------------------------

drop policy if exists "rls45_pointages_select_manager" on public.pointages;

create policy "rls45_pointages_select_manager" on public.pointages
  for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls45_pointages_select_employe" on public.pointages;

create policy "rls45_pointages_select_employe" on public.pointages
  for select to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
  );

drop policy if exists "rls45_pointages_insert_manager" on public.pointages;

create policy "rls45_pointages_insert_manager" on public.pointages
  for insert to authenticated
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls45_pointages_insert_employe" on public.pointages;

create policy "rls45_pointages_insert_employe" on public.pointages
  for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
    and date_pointage = current_date
    and employe_matricule = upper(coalesce(auth.jwt() -> 'app_metadata' ->> 'matricule', ''))
    and heure_arrivee is not null
    and heure_depart is null
  );

drop policy if exists "rls45_pointages_update_manager" on public.pointages;

create policy "rls45_pointages_update_manager" on public.pointages
  for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "rls45_pointages_update_employe" on public.pointages;

create policy "rls45_pointages_update_employe" on public.pointages
  for update to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
    and date_pointage = current_date
  )
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and heure_depart is not null
    and exists (
      select 1
      from public.pointages prev
      where prev.id = pointages.id
        and prev.employe_matricule is not distinct from pointages.employe_matricule
        and prev.employe_nom       is not distinct from pointages.employe_nom
        and prev.date_pointage     is not distinct from pointages.date_pointage
        and prev.heure_arrivee     is not distinct from pointages.heure_arrivee
        and prev.created_by        is not distinct from pointages.created_by
        and prev.created_at        is not distinct from pointages.created_at
        and prev.heure_depart is null
    )
  );

drop policy if exists "rls45_pointages_delete_manager" on public.pointages;

create policy "rls45_pointages_delete_manager" on public.pointages
  for delete to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- ============================================================
-- VERIFICATION (executable - RAISEs NOTICEs, reads catalogs only)
-- ------------------------------------------------------------
do $$
declare
  p record;
  n integer := 0;
  bad integer := 0;
  v_rls boolean;
  v_trg integer;
  v_uniq integer;
begin
  if to_regclass('public.pointages') is null then
    raise notice '0045 verify: ATTENTION - table pointages ABSENTE.';
    return;
  end if;

  select relrowsecurity into v_rls
    from pg_class where oid = 'public.pointages'::regclass;
  raise notice '0045 verify: row level security enabled = %', v_rls;

  select count(*) into v_trg
    from pg_trigger
   where tgrelid = 'public.pointages'::regclass
     and tgname = 'pointages_horodatage';
  raise notice '0045 verify: trigger pointages_horodatage present = %', (v_trg = 1);

  select count(*) into v_uniq
    from pg_constraint
   where conrelid = 'public.pointages'::regclass
     and conname = 'pointages_matricule_jour_uniq';
  raise notice '0045 verify: unique (matricule, jour) present = %', (v_uniq = 1);

  raise notice '0045 verify: policies on public.pointages :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'pointages'
     order by policyname
  loop
    n := n + 1;
    if left(p.policyname, 6) <> 'rls45_' then
      bad := bad + 1;
    end if;
    raise notice '0045 verify:   % | %', p.policyname, p.cmd;
  end loop;

  if n = 7 and bad = 0 and v_rls and v_trg = 1 and v_uniq = 1 then
    raise notice '0045 verify: OK - 7 policies rls45_*, RLS + trigger + unique en place.';
  else
    raise notice '0045 verify: ATTENTION - etat inattendu (% policies, % non-rls45, rls=%, trigger=%, unique=%). Relire la liste ci-dessus.',
      n, bad, v_rls, (v_trg = 1), (v_uniq = 1);
  end if;
end $$;

-- ------------------------------------------------------------
-- Functional probes (browser console, per the RLS test discipline :
-- certify the session identity FIRST, one role per Chrome profile or
-- incognito window, and confirm the target row exists before reading
-- anything into a 0-row result) :
--   const s = await sb.auth.getSession();
--   console.log(s.data.session.user.email, s.data.session.user.app_metadata);
--
-- employe session :
--   a) clock in (expected : 1 row, heure_arrivee = SERVER time even if
--      the payload lies) :
--     sb.from('pointages').insert({employe_matricule:'<HIS-MATRICULE>',
--       employe_nom:'<Nom>', heure_arrivee:'2020-01-01T00:00:00Z'}).select()
--   b) double clock-in (expected : duplicate key
--      pointages_matricule_jour_uniq) : re-run (a).
--   c) clock in for a COLLEAGUE (expected : RLS error "new row violates
--      row-level security policy") : (a) with another matricule.
--   d) clock out (expected : 1 row, heure_depart = server time) :
--     sb.from('pointages').update({heure_depart:'2020-01-01T00:00:00Z'})
--       .eq('id','<ID-FROM-A>').select()
--   e) rewrite arrival (expected : RLS error - column frozen) :
--     sb.from('pointages').update({heure_arrivee:'2020-01-01T00:00:00Z'})
--       .eq('id','<ID-FROM-A>').select()
--   f) clock out twice (expected : RLS error - heure_depart already
--      filled) : re-run (d).
--   g) delete own row (expected : 0 rows) :
--     sb.from('pointages').delete().eq('id','<ID-FROM-A>').select()
--
-- manager session :
--   h) reads all rows ; may insert/update/delete freely with explicit
--      times (correction path - trigger does not rewrite manager
--      values). Clean up the probe row here.
-- ============================================================
