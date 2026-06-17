-- ═══════════════════════════════════════════════════════════════════
-- Migration 0006 — Security PR 3 (2/2) : vue assainie bandes_ops (sans finance)
-- ───────────────────────────────────────────────────────────────────
-- chef_bande DOIT lire les bandes (sélection de bande pour la saisie, fiches,
-- dashboard) mais ne doit JAMAIS voir les champs financiers. On expose donc une
-- vue `bandes_ops` = toutes les colonnes de `bandes` SAUF :
--     prix_poussin_unitaire, cout_aliment_kg, prix_vente_carcasse_kg
-- (les 3 entrées de coût/prix d'où dérivent coût de revient / marge / P&L).
-- L'app lit bandes_ops pour chef_bande et la table `bandes` pour les managers.
--
-- security_invoker = true (PostgreSQL 15+ ; Supabase l'est) → la vue s'exécute
-- avec les droits de l'APPELANT, donc la RLS de `bandes` s'applique : anon n'y
-- accède pas (RLS anon = refus), authenticated voit les lignes (baseline). Sans
-- security_invoker, anon pourrait lire la vue via le propriétaire → fuite.
--
-- Construction DYNAMIQUE des colonnes : inclut automatiquement les colonnes
-- additionnelles éventuelles (p. ex. batiment / site_id de 0002) en excluant
-- seulement les 3 colonnes financières. ROBUSTE : ne fait rien si `bandes`
-- n'existe pas. Idempotent (drop view if exists + create).
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase). Rollback : 0005_0006_rollback.sql.
-- ⚠ Exécuter AVANT/AVEC le déploiement du front : sans cette vue, le chargement
--   chef_bande retombe à vide pour les bandes (dégradé, pas de crash).
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

-- Vérification (après) :
--   1) la vue n'expose AUCUNE colonne financière :
--      select column_name from information_schema.columns
--       where table_schema='public' and table_name='bandes_ops'
--         and column_name in ('prix_poussin_unitaire','cout_aliment_kg','prix_vente_carcasse_kg');
--      → 0 ligne.
--   2) security_invoker actif :
--      select relname, reloptions from pg_class where relname='bandes_ops';
--      → reloptions contient security_invoker=true.
