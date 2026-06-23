-- ============================================================
-- Migration 0012 - ROLLBACK
-- ------------------------------------------------------------
-- Supprime la fonction place_order. N'affecte aucune commande deja creee :
-- les lignes restent en base avec leur snapshot. Apres ce rollback, le portail
-- ne peut plus creer de commande tant que 0012 n'est pas re-applique.
-- Idempotent. La signature exacte est requise pour cibler la bonne surcharge.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

drop function if exists public.place_order(jsonb, timestamptz, text);
