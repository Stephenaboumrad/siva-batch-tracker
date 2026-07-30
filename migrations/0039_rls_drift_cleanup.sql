-- ============================================================
-- Migration 0039 - Nettoyage de la derive RLS rls7_internal_all
--                  sur sites / points_de_vente / mouvements_stock
-- ------------------------------------------------------------
-- CONSTAT (audit 2026-07-30, issue #142 constat lie) : 0027 a remplace
-- les policies "Allow all" par les policies rls27_* sur les tables POS,
-- mais n'a PAS droppe rls7_internal_all (0007) sur sites,
-- points_de_vente et mouvements_stock - 0021 ne l'avait droppee que sur
-- ses 7 tables. Les policies permissives se combinant en OR, un
-- chef_bande garde donc un CRUD COMPLET sur ces 3 tables, dont les
-- colonnes cout_unitaire_fcfa / cout_total_fcfa de mouvements_stock.
-- Le bloc VERIFICATION de 0027 ("uniquement des rls27_*") etait
-- incoherent avec ce que la migration faisait reellement.
--
-- FIX : 3 drop policy. Apres quoi l'acces est exactement celui que
-- 0027 voulait : manager tout (rls27_*_manager), vendeur limite a SON
-- pdv (rls27_*_vendeur_*), chef_bande AUCUN acces. Aucun site de
-- lecture chef n'existe dans le front pour ces tables (verifie).
--
-- Idempotent : to_regclass + drop policy if exists (deja absente =
-- no-op propre). ASCII uniquement, pas de commentaire en fin de ligne
-- d'instruction. A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Rollback : 0039_rollback.sql (restaure l'etat DERIVE - deconseille).
-- ============================================================

-- PRE-CHECK (lecture seule, a lancer AVANT) : la derive est-elle bien
-- presente ? Attendu : une ligne rls7_internal_all par table (3 au
-- total) + les policies rls27_*. Si rls7_internal_all est deja absente,
-- la migration est un no-op propre.
--   select tablename, policyname, cmd
--     from pg_policies
--    where schemaname = 'public'
--      and tablename in ('sites', 'points_de_vente', 'mouvements_stock')
--    order by tablename, policyname;

do $$
declare
  t text;
begin
  foreach t in array array['sites', 'points_de_vente', 'mouvements_stock'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0039: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    raise notice '0039: rls7_internal_all retiree de % (si presente).', t;
  end loop;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Plus aucune rls7_internal_all sur les 3 tables (attendu : 0 ligne) :
--   select tablename, policyname from pg_policies
--    where schemaname = 'public'
--      and tablename in ('sites', 'points_de_vente', 'mouvements_stock')
--      and policyname = 'rls7_internal_all';
--
-- 2. Les policies rls27_* restent seules en place :
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public'
--      and tablename in ('sites', 'points_de_vente', 'mouvements_stock')
--    order by tablename, policyname;
--
-- 3. Test DENY chef_bande (simulation JWT, aucun compte requis) :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--     select count(*) from public.sites;
--     select count(*) from public.points_de_vente;
--     select count(*) from public.mouvements_stock;
--   rollback;
--   -- attendu : 0 / 0 / 0
--
-- 4. Test ALLOW vendeur (son pdv passe toujours - remplacer le pdv_id
--    par un reel) :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"vendeur","point_de_vente_id":"pdv-bingerville"}}';
--     select count(*) from public.points_de_vente;
--     select count(*) from public.mouvements_stock;
--   rollback;
--   -- attendu : >= 1 (sa ligne pdv) / >= 0 sans erreur
--
-- 5. Test ALLOW manager :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"manager"}}';
--     select count(*) from public.mouvements_stock;
--   rollback;
--   -- attendu : total reel de la table
-- ============================================================
