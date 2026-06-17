-- ═══════════════════════════════════════════════════════════════════
-- Migration 0004b — CORRECTIF : supprime les politiques permissives résiduelles
--                    et (re)pose les politiques restrictives. Self-contained.
-- ───────────────────────────────────────────────────────────────────
-- Pourquoi : après 0004_rls_restrictive.sql, des politiques permissives
-- d'origine « Allow all select/insert/update/delete on <table> » (using(true),
-- rôle public → inclut anon) subsistent sur certaines tables. Les politiques
-- permissives étant ADDITIVES (combinées en OR), une seule « Allow all » suffit
-- à tout ré-exposer → le verrouillage n'est PAS effectif.
--
-- Cause racine probable : 0004 commençait par un ALTER TABLE ... ENABLE RLS sur
-- les 24 tables + profiles ; si UNE table n'existe pas dans la base (p. ex. les
-- 6 tables POS de 0002 jamais exécutée ici), ce premier ordre échoue et ANNULE
-- toute la migration AVANT les DROP → rien n'est supprimé ni recréé.
--
-- Ce correctif est ROBUSTE :
--   • ignore les tables absentes (to_regclass) → aucune annulation globale ;
--   • pour CHAQUE table présente : active RLS, DROP de TOUTES ses politiques
--     (donc « Allow all … » ET d'éventuelles rls2_* partielles), puis CREATE de
--     la bonne politique restrictive ;
--   • idempotent : ré-exécutable sans erreur, même si 0004 a tourné en partie.
--
-- État final visé :
--   • anon (non authentifié)               → AUCUN accès (0 ligne / 0 écriture)
--   • authenticated (manager + chef_bande) → R/W sur les tables opérationnelles
--   • employes / paies / depenses_rh       → manager UNIQUEMENT (lecture+écriture)
--   • profiles                             → lecture seule pour authenticated
--
-- DÉPENDANCE (PR 1) : le rôle vient du JWT, claim
--   auth.jwt() -> 'app_metadata' ->> 'role'  (= 'manager' | 'chef_bande').
--   Vérifier AVANT :
--     select email, raw_app_meta_data ->> 'role' from auth.users
--      where email like '%@coqorico.internal';
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase, rôle propriétaire). Idempotent.
-- Rollback : 0004b_rollback.sql.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  t  text;
  p  record;
  -- Tables à accès « baseline » (tout utilisateur interne authentifié, R/W) :
  baseline text[] := array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications',
    'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements'
  ];
  -- Tables sensibles → manager uniquement :
  managers text[] := array['employes','paies','depenses_rh'];
begin
  -- ── BASELINE ──────────────────────────────────────────────────────
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

  -- ── MANAGER ONLY (paie / finance / personnel) ────────────────────
  foreach t in array managers loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "rls2_manager_all" on public.%I for all to authenticated '
        'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
        'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t);
    end if;
  end loop;

  -- ── profiles (lecture seule, authenticated) ──────────────────────
  if to_regclass('public.profiles') is not null then
    execute 'alter table public.profiles enable row level security';
    for p in select policyname from pg_policies where schemaname='public' and tablename='profiles' loop
      execute format('drop policy if exists %I on public.profiles', p.policyname);
    end loop;
    execute 'create policy "rls2_profiles_select" on public.profiles for select to authenticated using (true)';
  end if;
end $$;

-- ── VÉRIFICATION (à lancer après) ────────────────────────────────────
-- 1) paies ne doit montrer QUE la politique manager (aucune « Allow all »/true) :
--     select tablename, policyname, cmd, roles, qual
--       from pg_policies where tablename = 'paies';
--    → 1 ligne : rls2_manager_all | ALL | {authenticated}
--                | ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
--
-- 2) AUCUNE politique permissive « Allow all… » résiduelle nulle part :
--     select tablename, policyname from pg_policies where policyname ilike 'Allow all%';
--    → 0 ligne.
--
-- 3) AUCUNE politique ne s'applique encore à anon/public (verrou anon) :
--     select tablename, policyname, roles from pg_policies
--      where schemaname='public'
--        and (roles @> array['public']::name[] or roles @> array['anon']::name[])
--        and tablename = any (array[
--          'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
--          'fournisseurs','receptions','inspections','stocks','clients','commandes',
--          'lignes_commande','abattages','notifications','employes','paies','depenses_rh',
--          'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements','profiles']);
--    → 0 ligne.
