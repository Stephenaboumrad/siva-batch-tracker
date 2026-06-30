-- ============================================================
-- Rollback 0017 - Carnet de vaccination
-- ------------------------------------------------------------
-- Supprime les deux tables (vaccinations d'abord : FK vers protocole_vaccinal).
-- Les index, contraintes et policies tombent avec les tables (cascade).
-- Idempotent (drop table if exists). ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

drop table if exists vaccinations       cascade;
drop table if exists protocole_vaccinal  cascade;
