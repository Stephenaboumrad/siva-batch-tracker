-- ============================================================
-- Rollback 0018 - Registre des traitements medicamenteux
-- ------------------------------------------------------------
-- Supprime les deux tables (traitements d'abord : FK vers protocole_traitements).
-- Les index, contraintes et policies tombent avec les tables (cascade).
-- Idempotent (drop table if exists). ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

drop table if exists traitements          cascade;
drop table if exists protocole_traitements cascade;
