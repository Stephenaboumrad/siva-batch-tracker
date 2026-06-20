-- ═══════════════════════════════════════════════════════════════════
-- Migration 0007 — RLS HARDENING (consolidée — REMPLACE / SUPERSEDE 0005)
-- ───────────────────────────────────────────────────────────────────
-- Verrouille l'accès PAR CLASSE DE RÔLE sur les 25 tables, en remplaçant les
-- politiques permissives héritées (rls2_auth_all : `for all to authenticated
-- using(true)`, donc TOUT utilisateur authentifié) par des prédicats lus dans
-- le JWT (claim posé par Security PR1 : auth.jwt() -> 'app_metadata' ->> 'role') :
--
--   • MANAGER-ONLY  (role = 'manager')                       → 6 tables
--       RH/paie : employes, paies, depenses_rh
--       caisse/finance : paiements, pos_transactions, lignes_transaction
--   • INTERNAL-ROLES (role in ('manager','chef_bande'))      → 18 tables opér.
--       bandes, saisies, intrants, aliments_phases, matieres, formulations_mp,
--       fournisseurs, receptions, inspections, stocks, clients, commandes,
--       lignes_commande, abattages, notifications, sites, points_de_vente,
--       mouvements_stock
--   • profiles                                               → SELECT, internal-roles
--
-- POURQUOI CONSOLIDÉE : le dump pg_policies de prod (vérifié) montre l'état
-- « 0004b propre » — 0005 et 0006 n'ont JAMAIS été appliqués :
--   - paiements / pos_transactions / lignes_transaction sont ENCORE en
--     rls2_auth_all / qual=true (et non rls3_manager_all) ;
--   - seules employes / paies / depenses_rh sont manager-only ;
--   - profiles = rls2_profiles_select / using(true) ;
--   - aucune politique « Allow all% » résiduelle, aucun rôle public/anon ;
--   - la vue bandes_ops est absente.
-- 0007 reprend l'intention de 0005 (caisse/finance → manager) et décrit TOUTE
-- la posture RLS en UNE migration, diffable 1:1 contre pg_policies. Elle rend
-- 0005 inutile (ne pas l'exécuter).
--
-- HORS PÉRIMÈTRE (volontaire) : 0006 (vue assainie bandes_ops masquant les 3
-- colonnes financières de `bandes` pour chef_bande) n'est PAS ici. Le masquage
-- colonne exige la vue ET sa lecture côté front (chef_bande lit bandes_ops, pas
-- `bandes`) — RLS seule ne peut pas masquer une colonne car manager et
-- chef_bande partagent le rôle Postgres `authenticated` et doivent tous deux
-- lire les LIGNES de `bandes`. C'est donc une PR appairée (DB+front) distincte.
-- Ici, `bandes` reste INTERNAL-ROLES : chef_bande voit encore les colonnes
-- financières via la table tant que la PR de masquage n'est pas livrée.
--
-- DÉPENDANCE (Security PR1) — VÉRIFIÉE AVANT EXÉCUTION : chaque compte interne
-- porte app_metadata.role ∈ {manager, chef_bande} (3 comptes : manager / manager
-- / chef_bande). Sinon les utilisateurs internes se verrouillent eux-mêmes hors
-- des 24 tables internes/manager.
--   Re-vérifier au besoin :
--     select email, raw_app_meta_data ->> 'role' from auth.users
--      where email like '%@coqorico.internal';
--
-- PROPRIÉTÉS :
--   • ROBUSTE  : to_regclass → ignore les tables absentes (aucune annulation
--     globale) ; pour CHAQUE table : enable RLS, DROP de TOUTES ses politiques
--     AVANT le create (leçon 0004b : une seule politique permissive résiduelle
--     ré-ouvre la table car les permissives se combinent en OR).
--   • IDEMPOTENT : ré-exécutable sans erreur.
--   • anon : AUCUNE politique → refus total partout (inchangé depuis 0004b).
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase, rôle propriétaire → contourne
-- RLS). Rollback : 0007_rollback.sql (restaure l'état 0004b vérifié, noms inclus).
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  t text;
  p record;
  -- 18 tables opérationnelles → internal-roles (manager + chef_bande), R/W complet
  internal text[] := array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications','sites','points_de_vente','mouvements_stock'
  ];
  -- 6 tables RH + caisse/finance → manager UNIQUEMENT
  managers text[] := array[
    'employes','paies','depenses_rh','paiements','pos_transactions','lignes_transaction'
  ];
begin
  -- ── INTERNAL-ROLES (manager + chef_bande) ───────────────────────────
  foreach t in array internal loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "rls7_internal_all" on public.%I for all to authenticated '
        'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande'')) '
        'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t);
    end if;
  end loop;

  -- ── MANAGER-ONLY (RH + caisse/finance). chef_bande & anon : aucun accès ──
  foreach t in array managers loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "rls7_manager_all" on public.%I for all to authenticated '
        'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
        'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t);
    end if;
  end loop;

  -- ── profiles : SELECT pour internal-roles (résolution rôle/nom au login) ──
  --    Aucune politique d'écriture → écritures refusées (l'app n'écrit jamais
  --    profiles). anon EXCLU.
  if to_regclass('public.profiles') is not null then
    execute 'alter table public.profiles enable row level security';
    for p in select policyname from pg_policies where schemaname='public' and tablename='profiles' loop
      execute format('drop policy if exists %I on public.profiles', p.policyname);
    end loop;
    execute 'create policy "rls7_profiles_select" on public.profiles for select to authenticated '
            'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- VÉRIFICATION (à lancer APRÈS — voir aussi la description de la PR)
-- ───────────────────────────────────────────────────────────────────
-- 1) Carte des politiques : 18× rls7_internal_all, 6× rls7_manager_all,
--    1× rls7_profiles_select. AUCUN using(true) résiduel, AUCUN « Allow all% »,
--    AUCUN rôle public/anon.
--      select tablename, policyname, cmd, roles, qual
--        from pg_policies where schemaname='public' order by tablename, policyname;
--
-- 2) Test DENY client (aucun compte requis — simulation du JWT) :
--      begin;
--        set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"client"}}';
--        select count(*) from public.bandes;     -- attendu 0
--        select count(*) from public.commandes;  -- attendu 0
--        select count(*) from public.clients;    -- attendu 0
--        select count(*) from public.paiements;  -- attendu 0
--      rollback;
--
-- 3) Test ALLOW manager :
--      begin;
--        set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"manager"}}';
--        select count(*) from public.bandes;     -- attendu > 0 (prod a des données)
--        select count(*) from public.paies;      -- attendu > 0 (manager voit la paie)
--      rollback;
--
-- 4) Test ALLOW chef_bande (opérationnel oui, RH/caisse non) :
--      begin;
--        set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--        select count(*) from public.bandes;     -- attendu > 0
--        select count(*) from public.commandes;  -- attendu > 0
--        select count(*) from public.paies;            -- attendu 0 (manager-only)
--        select count(*) from public.paiements;        -- attendu 0 (manager-only)
--        select count(*) from public.pos_transactions; -- attendu 0 (manager-only)
--      rollback;
-- ═══════════════════════════════════════════════════════════════════
