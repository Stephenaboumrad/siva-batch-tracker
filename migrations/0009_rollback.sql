-- ============================================================
-- Migration 0009 - ROLLBACK (version durcie)
-- ------------------------------------------------------------
-- Supprime la vue v_catalogue_client puis la table produits.
-- Les policies rls9_produits_select / rls9_produits_write sont supprimees
-- automatiquement avec la table. Idempotent.
--
-- ATTENTION : le cascade n'est SUR que TANT QUE PR-C n'est pas posee.
-- PR-C ajoutera lignes_commande.produit_id en FK vers produits. Si cette FK
-- existe, retirer/gerer d'abord la contrainte avant ce rollback. En l'etat
-- (PR-A seule), produits n'a aucun dependant hormis la vue.
--
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Meme hygiene que 0009_catalog.sql : ASCII, pas de commentaire en fin de
-- ligne d'instruction, pas de point-virgule dans un commentaire.
-- ============================================================

drop view if exists v_catalogue_client;
drop table if exists produits cascade;
