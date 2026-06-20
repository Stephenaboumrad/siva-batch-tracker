-- ═══════════════════════════════════════════════════════════════════
-- Migration 0007 — ROLLBACK
-- ───────────────────────────────────────────────────────────────────
-- Annule 0007_rls_hardening.sql en restaurant l'ÉTAT « 0004b PROPRE » VÉRIFIÉ
-- avant exécution (dump pg_policies), NOMS DE POLITIQUES D'ORIGINE INCLUS :
--
--   • 21 tables → rls2_auth_all  : `for all to authenticated using(true) with check(true)`
--       les 18 opérationnelles + paiements + pos_transactions + lignes_transaction
--   • 3 tables  → rls2_manager_all : `for all to authenticated`, role='manager'
--       employes, paies, depenses_rh
--   • profiles  → rls2_profiles_select : `for select to authenticated using(true)`
--
-- NB : ce rollback REDONNE l'accès baseline `using(true)` à TOUT utilisateur
-- authentifié (état d'avant 0007). Il ne recrée PAS d'éventuelles politiques
-- permissives « Allow all% » résiduelles : le dump vérifié n'en contenait
-- aucune (état propre). S'il en existait, restaurer cet état propre est le
-- comportement voulu (ne pas réintroduire de fuite).
--
-- ROBUSTE (to_regclass, drop-all-then-recreate par table), IDEMPOTENT.
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase, rôle propriétaire).
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  t text;
  p record;
  -- 21 tables qui étaient en rls2_auth_all / using(true) (état 0004b vérifié) :
  baseline text[] := array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications','sites','points_de_vente','mouvements_stock',
    'paiements','pos_transactions','lignes_transaction'
  ];
  -- 3 tables RH manager-only :
  managers text[] := array['employes','paies','depenses_rh'];
begin
  -- ── BASELINE → rls2_auth_all (authenticated, using(true)) ────────────
  foreach t in array baseline loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "rls2_auth_all" on public.%I for all to authenticated using (true) with check (true)', t);
    end if;
  end loop;

  -- ── MANAGER-ONLY (RH) → rls2_manager_all ─────────────────────────────
  foreach t in array managers loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "rls2_manager_all" on public.%I for all to authenticated '
        'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
        'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t);
    end if;
  end loop;

  -- ── profiles → rls2_profiles_select (select, using(true)) ────────────
  if to_regclass('public.profiles') is not null then
    execute 'alter table public.profiles enable row level security';
    for p in select policyname from pg_policies where schemaname='public' and tablename='profiles' loop
      execute format('drop policy if exists %I on public.profiles', p.policyname);
    end loop;
    execute 'create policy "rls2_profiles_select" on public.profiles for select to authenticated using (true)';
  end if;
end $$;
