-- ============================================================
-- Migration 0021 - Enforcement serveur : operations destructives sur les
--                  bandes + boucle de validation (audit C-F3, C-F4)
-- ------------------------------------------------------------
-- Avant 0021, la politique rls7_internal_all (0007) donnait FOR ALL a
-- manager ET chef_bande sur les tables operationnelles : toutes les gardes
-- (suppression de bande, boucle de validation intrants/receptions/abattages)
-- n'existaient que cote client (CSS manager-only, liste de matricules).
-- Un chef_bande pouvait, depuis la console, supprimer des bandes ou inserer
-- directement dans intrants/receptions/abattages en contournant la file de
-- validation. 0021 fait du serveur le controle.
--
-- DECISION (finale) : enforcement par ROLE (auth.jwt()->'app_metadata'->>'role'
-- = 'manager'), coherent avec 0007/0017/0018. Aucun matricule en dur.
--
-- Chemins d'ecriture VERIFIES dans index.html (etat au merge de #99) :
--   bandes          : ecritures manager uniquement (createBande / archivage /
--                     cloture / suppression - UI manager) ; le chef LIT via la
--                     vue bandes_ops (security_invoker -> il garde SELECT sur
--                     la table) et via le ping de sync.
--   saisies         : INSERT par les DEUX roles (saisie journaliere du chef =
--                     insertion directe + rejeu de la file hors ligne) ;
--                     aucun UPDATE en prod (action morte) ; DELETE = bouton
--                     manager-only (fiche) + cascade de suppression de bande.
--   intrants        : chef -> file notifications ; l'insertion reelle a lieu
--   receptions        dans la SESSION MANAGER a la validation
--   abattages         (performValidateNotif) ou en direct par le manager.
--                     UPDATE (validation d'abattage) et DELETE : manager.
--   aliments_phases : ajout/suppression gates par canEdit = isManager().
--   formulations_mp : AUCUNE ecriture applicative (table heritee) ; seule la
--                     cascade de suppression de bande (manager) la touche.
--   notifications   : NON TOUCHEE (le chef doit continuer a y inserer, le
--                     manager a y mettre a jour -> rls7_internal_all reste).
--
-- STRICTEMENT ADDITIF cote schema : aucune colonne/table modifiee ; seules
-- les politiques RLS des 7 tables ci-dessus sont remplacees (per-verbe,
-- style 0017/0018) + un trigger BEFORE DELETE sur bandes (ceinture ET
-- bretelles, modele du garde paiement 0014).
--
-- Idempotent : to_regclass + drop policy if exists avant chaque create,
-- create or replace pour la fonction, drop trigger if exists. ASCII
-- uniquement, pas de commentaire en fin de ligne d'instruction.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0021_rollback.sql.
-- ============================================================

-- PRE-CHECK (lecture seule, a lancer AVANT) : politiques actuelles des tables
-- concernees. Attendu : rls7_internal_all sur chacune des 7 tables.
--   select tablename, policyname, cmd
--     from pg_policies
--    where schemaname = 'public'
--      and tablename in ('bandes','saisies','intrants','receptions',
--                        'abattages','aliments_phases','formulations_mp')
--    order by tablename, policyname;

-- ── 1) bandes (C-F3) : SELECT roles internes ; ecritures manager ─────────
do $$
begin
  if to_regclass('public.bandes') is null then
    raise notice '0021: table bandes absente - section ignoree.';
    return;
  end if;

  alter table public.bandes enable row level security;

  drop policy if exists "rls7_internal_all"     on public.bandes;
  drop policy if exists "rls21_bandes_select"   on public.bandes;
  drop policy if exists "rls21_bandes_insert"   on public.bandes;
  drop policy if exists "rls21_bandes_update"   on public.bandes;
  drop policy if exists "rls21_bandes_delete"   on public.bandes;

  create policy "rls21_bandes_select" on public.bandes
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  create policy "rls21_bandes_insert" on public.bandes
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  create policy "rls21_bandes_update" on public.bandes
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  create policy "rls21_bandes_delete" on public.bandes
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ── 2) saisies : INSERT conserve pour le chef (saisie journaliere !) ;
--      UPDATE/DELETE manager ────────────────────────────────────────────
do $$
begin
  if to_regclass('public.saisies') is null then
    raise notice '0021: table saisies absente - section ignoree.';
    return;
  end if;

  alter table public.saisies enable row level security;

  drop policy if exists "rls7_internal_all"      on public.saisies;
  drop policy if exists "rls21_saisies_select"   on public.saisies;
  drop policy if exists "rls21_saisies_insert"   on public.saisies;
  drop policy if exists "rls21_saisies_update"   on public.saisies;
  drop policy if exists "rls21_saisies_delete"   on public.saisies;

  create policy "rls21_saisies_select" on public.saisies
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  create policy "rls21_saisies_insert" on public.saisies
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('manager','chef_bande'));

  create policy "rls21_saisies_update" on public.saisies
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  create policy "rls21_saisies_delete" on public.saisies
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ── 3) intrants / receptions / abattages (C-F4) : SELECT roles internes ;
--      TOUTES les ecritures manager (le chemin chef passe par notifications,
--      l'insertion reelle se fait dans la session manager a la validation) ──
do $$
declare
  t text;
begin
  foreach t in array array['intrants','receptions','abattages'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0021: table % absente - section ignoree.', t;
      continue;
    end if;

    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    execute format('drop policy if exists "rls21_%s_select" on public.%I', t, t);
    execute format('drop policy if exists "rls21_%s_write"  on public.%I', t, t);

    execute format(
      'create policy "rls21_%s_select" on public.%I for select to authenticated '
      'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t, t);

    execute format(
      'create policy "rls21_%s_write" on public.%I for all to authenticated '
      'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
      'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t, t);
  end loop;
end $$;

-- ── 4) aliments_phases / formulations_mp : SELECT roles internes ;
--      ecritures manager (UI deja gatee canEdit=isManager ; formulations_mp
--      n'a aucune ecriture applicative) ──────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['aliments_phases','formulations_mp'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0021: table % absente - section ignoree.', t;
      continue;
    end if;

    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    execute format('drop policy if exists "rls21_%s_select" on public.%I', t, t);
    execute format('drop policy if exists "rls21_%s_write"  on public.%I', t, t);

    execute format(
      'create policy "rls21_%s_select" on public.%I for select to authenticated '
      'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t, t);

    execute format(
      'create policy "rls21_%s_write" on public.%I for all to authenticated '
      'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
      'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t, t);
  end loop;
end $$;

-- ── 5) Ceinture + bretelles : trigger BEFORE DELETE sur bandes (modele du
--      garde paiement 0014). Un contexte SANS JWT (SQL Editor / service role)
--      reste autorise, comme dans 0014. ─────────────────────────────────
create or replace function public.trg_bandes_delete_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_role text;
begin
  v_role := auth.jwt() -> 'app_metadata' ->> 'role';
  if v_role is not null and v_role <> 'manager' then
    raise exception 'suppression de bande reservee au manager'
      using errcode = '42501';
  end if;
  return old;
end;
$$;

do $$
begin
  if to_regclass('public.bandes') is null then
    raise notice '0021: table bandes absente - trigger ignore.';
    return;
  end if;

  drop trigger if exists bandes_delete_guard on public.bandes;
  create trigger bandes_delete_guard
    before delete on public.bandes
    for each row
    execute function public.trg_bandes_delete_guard();
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule).
-- ------------------------------------------------------------
-- 1) Politiques : plus AUCUN rls7_internal_all sur les 7 tables ;
--    a la place les politiques rls21_* ci-dessous.
--   select tablename, policyname, cmd
--     from pg_policies
--    where schemaname = 'public'
--      and tablename in ('bandes','saisies','intrants','receptions',
--                        'abattages','aliments_phases','formulations_mp')
--    order by tablename, policyname;
--   -- attendu (18 lignes) :
--   --   abattages       | rls21_abattages_write        | ALL
--   --   abattages       | rls21_abattages_select       | SELECT
--   --   aliments_phases | rls21_aliments_phases_write  | ALL
--   --   aliments_phases | rls21_aliments_phases_select | SELECT
--   --   bandes          | rls21_bandes_delete          | DELETE
--   --   bandes          | rls21_bandes_insert          | INSERT
--   --   bandes          | rls21_bandes_select          | SELECT
--   --   bandes          | rls21_bandes_update          | UPDATE
--   --   formulations_mp | rls21_formulations_mp_write  | ALL
--   --   formulations_mp | rls21_formulations_mp_select | SELECT
--   --   intrants        | rls21_intrants_write         | ALL
--   --   intrants        | rls21_intrants_select        | SELECT
--   --   receptions      | rls21_receptions_write       | ALL
--   --   receptions      | rls21_receptions_select      | SELECT
--   --   saisies         | rls21_saisies_delete         | DELETE
--   --   saisies         | rls21_saisies_insert         | INSERT
--   --   saisies         | rls21_saisies_select         | SELECT
--   --   saisies         | rls21_saisies_update         | UPDATE
--
-- 2) Trigger :
--   select tgname from pg_trigger
--    where tgrelid = 'public.bandes'::regclass
--      and tgname = 'bandes_delete_guard';
--   -- attendu : 1 ligne
--
-- 3) Test fonctionnel (session chef_bande, ex. SIVA-003, console navigateur) :
--   sb.from('bandes').delete().neq('bande_id','')  -- attendu : 0 ligne affectee
--   sb.from('intrants').insert([{...}])            -- attendu : rejet RLS
--   (et la saisie journaliere du chef doit toujours passer)
-- ============================================================
