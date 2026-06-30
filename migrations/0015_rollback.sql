-- ============================================================
-- Rollback 0015 - Delai d'attente avant abattage
-- ------------------------------------------------------------
-- Retire la colonne ajoutee par 0015. La contrainte CHECK
-- intrants_delai_attente_jours_chk tombe automatiquement avec la colonne.
-- Idempotent (drop column if exists). ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

alter table public.intrants drop column if exists delai_attente_jours;
