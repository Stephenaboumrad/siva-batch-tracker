-- ═══════════════════════════════════════════════════════════════════
-- Migration 0004 — RLS RESTRICTIVE : verrouillage anon + paie/finance manager-only
-- ───────────────────────────────────────────────────────────────────
-- Security PR 2. Remplace les politiques PERMISSIVES (using(true) pour TOUS les
-- rôles, y compris anon) par des politiques RESTRICTIVES :
--   • anon (clé publishable, NON authentifié)  → AUCUN accès (0 ligne, 0 écriture)
--   • authenticated (manager + chef_bande)      → R/W sur les tables opérationnelles
--   • employes / paies / depenses_rh            → manager UNIQUEMENT (R + W)
--
-- DÉPENDANCE (Security PR 1) : le rôle est lu dans le JWT à
--   auth.jwt() -> 'app_metadata' ->> 'role'   (= 'manager' | 'chef_bande')
-- → app_metadata.role DOIT être positionné sur les 3 comptes (étape 3b de la
--   PR 1). Vérifier AVANT d'appliquer :
--     select email, raw_app_meta_data ->> 'role' from auth.users
--      where email like '%@coqorico.internal';
--   (attendu : siva-001/002 = manager, siva-003 = chef_bande). Si role est NULL,
--   les managers eux-mêmes seront bloqués sur paies/employes/depenses_rh.
--
-- NON couvert ici (volontaire) :
--   • Masquage colonne-par-colonne des champs coût/marge de `bandes` pour
--     chef_bande : impossible en RLS seule (manager et chef_bande partagent le
--     rôle Postgres `authenticated`, et chef_bande DOIT lire `bandes` pour la
--     saisie). Cela nécessite une VUE assainie + bascule de l'app dessus → relève
--     de la PR 3 (refonte getAll / modèle de données). `bandes` reste donc en
--     baseline ici.
--   • Scoping par client / par site (aucun client externe encore) → PR ultérieure.
--
-- À EXÉCUTER MANUELLEMENT dans le SQL Editor Supabase (rôle propriétaire →
-- contourne RLS). Idempotent : ré-exécutable. Rollback : 0004_rls_rollback.sql.
-- ═══════════════════════════════════════════════════════════════════

-- 1) RLS activée sur toutes les tables ciblées (déjà le cas ; sécurité idempotente)
do $$
declare t text;
begin
  foreach t in array array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications','employes','paies','depenses_rh',
    'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements',
    'profiles'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- 2) Suppression de TOUTES les politiques existantes sur ces tables
--    (robuste : indépendant des noms « Allow all … » d'origine).
do $$
declare r record;
begin
  for r in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename = any (array[
      'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
      'fournisseurs','receptions','inspections','stocks','clients','commandes',
      'lignes_commande','abattages','notifications','employes','paies','depenses_rh',
      'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements',
      'profiles'
    ])
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- 3) BASELINE — utilisateurs internes authentifiés (manager + chef_bande) :
--    R/W complet, comme aujourd'hui. anon EXCLU (aucune politique anon → refus).
--    `for all` couvre SELECT/INSERT/UPDATE/DELETE.
do $$
declare t text;
begin
  foreach t in array array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications',
    'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements'
  ] loop
    execute format(
      'create policy "rls2_auth_all" on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- 4) MANAGER ONLY — paie / finance / personnel. chef_bande & anon : aucun accès.
--    Rôle lu dans le JWT (claim posé par la PR 1).
create policy "rls2_manager_all" on public.employes
  for all to authenticated
  using      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

create policy "rls2_manager_all" on public.paies
  for all to authenticated
  using      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

create policy "rls2_manager_all" on public.depenses_rh
  for all to authenticated
  using      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- 5) profiles — lecture seule pour les authentifiés (résolution du rôle au login).
--    Aucune politique d'écriture → écritures refusées. anon EXCLU.
create policy "rls2_profiles_select" on public.profiles
  for select to authenticated using (true);

-- Résultat :
--   • anon → 0 ligne / 0 écriture partout (REST publishable sans session = rien).
--   • chef_bande → app fonctionnelle ; employes/paies/depenses_rh renvoient [] (pas
--     d'erreur → getAll ne casse pas).
--   • manager → accès complet, paie/finance comprises.
