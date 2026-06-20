-- ═══════════════════════════════════════════════════════════════════
-- Migration 0008 — Vue assainie bandes_ops (masquage finance pour chef_bande)
-- ───────────────────────────────────────────────────────────────────
-- PR APPAIRÉE DB + FRONT. chef_bande DOIT lire les bandes (sélection de bande
-- pour la saisie, fiches, dashboard) mais ne doit JAMAIS voir les champs
-- financiers. On expose une vue `bandes_ops` = toutes les colonnes de `bandes`
-- SAUF les 3 entrées de coût/prix d'où dérivent coût de revient / marge / P&L :
--     prix_poussin_unitaire, cout_aliment_kg, prix_vente_carcasse_kg
-- Le front (index.html, dataSourceFor) lit `bandes_ops` pour chef_bande et la
-- table `bandes` pour les managers.
--
-- POURQUOI une vue + un redirect front (et pas RLS seule) : manager et
-- chef_bande partagent le rôle Postgres `authenticated` et doivent TOUS DEUX
-- lire les LIGNES de `bandes` (0007 = internal-roles). La RLS ne peut donc pas
-- masquer une COLONNE par rôle → le masquage colonne se fait par vue restreinte
-- + lecture de cette vue côté app.
--
-- security_invoker = true (PostgreSQL 15+ ; Supabase l'est) → la vue s'exécute
-- avec les droits de l'APPELANT : la RLS de `bandes` (0007) s'applique. anon
-- n'accède pas (aucune politique anon) ; chef_bande (internal-role) voit les
-- lignes. Sans security_invoker, la vue lirait via son propriétaire → fuite anon.
--
-- DÉPENDANCE : appliquer APRÈS 0007 (bandes en internal-roles). La vue n'ajoute
-- aucune politique RLS : elle hérite de celle de `bandes`.
--
-- ROBUSTE : ne fait rien si `bandes` n'existe pas. Construction DYNAMIQUE des
-- colonnes → inclut automatiquement les colonnes additionnelles (ex. site_id de
-- 0002) en n'excluant QUE les 3 financières. IDEMPOTENT (drop view + create).
--
-- ⚠ À DÉPLOYER AVEC le front de cette PR. Si la vue est créée mais le front
--   non déployé → aucun effet (managers et chef lisent `bandes`). Si le front
--   est déployé mais la vue absente → le chargement chef_bande des bandes
--   retombe silencieusement sur [] (repli .catch(()=>[]) — dégradé, pas de crash).
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase). Rollback : 0008_rollback.sql.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare cols text;
begin
  if to_regclass('public.bandes') is null then
    raise notice 'Table public.bandes absente — vue bandes_ops non créée.';
    return;
  end if;

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
  from information_schema.columns
  where table_schema = 'public'
    and table_name   = 'bandes'
    and column_name not in ('prix_poussin_unitaire', 'cout_aliment_kg', 'prix_vente_carcasse_kg');

  execute 'drop view if exists public.bandes_ops';
  execute 'create view public.bandes_ops with (security_invoker = true) as select '
          || cols || ' from public.bandes';

  -- anon : aucun accès à la vue ; authenticated : lecture seule.
  execute 'revoke all on public.bandes_ops from anon';
  execute 'grant select on public.bandes_ops to authenticated';
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- VÉRIFICATION (à lancer APRÈS)
-- ───────────────────────────────────────────────────────────────────
-- 1) La vue n'expose AUCUNE colonne financière → 0 ligne :
--      select column_name from information_schema.columns
--       where table_schema='public' and table_name='bandes_ops'
--         and column_name in ('prix_poussin_unitaire','cout_aliment_kg','prix_vente_carcasse_kg');
-- 2) security_invoker actif :
--      select relname, reloptions from pg_class where relname='bandes_ops';
--      → reloptions contient security_invoker=true.
-- 3) chef_bande voit des lignes via la vue (simulation JWT) :
--      begin;
--        set local role authenticated;
--        set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--        select count(*) from public.bandes_ops;   -- attendu > 0
--      rollback;
-- ═══════════════════════════════════════════════════════════════════
