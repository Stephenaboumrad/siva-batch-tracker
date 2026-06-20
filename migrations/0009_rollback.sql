-- ═══════════════════════════════════════════════════════════════════
-- Migration 0009 — ROLLBACK
-- ───────────────────────────────────────────────────────────────────
-- Annule 0009 : supprime la vue v_catalogue_client puis la table produits
-- (les policies rls9_produits_select / rls9_produits_write sont supprimées
-- automatiquement avec la table). Idempotent.
--
-- ⚠ `drop table ... cascade` n'est SÛR que TANT QUE PR-C n'est pas posée.
--   PR-C ajoutera `lignes_commande.produit_id text references produits(produit_id)`.
--   Si cette FK existe, le cascade SUPPRIMERAIT la contrainte (laissant la colonne
--   produit_id orpheline). Dans ce cas : retirer/gérer d'abord la FK, puis rollback.
--   En l'état (PR-A seule), produits n'a AUCUN dépendant hormis la vue.
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase).
-- ═══════════════════════════════════════════════════════════════════

drop view  if exists v_catalogue_client;
drop table if exists produits cascade;
