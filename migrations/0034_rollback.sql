-- ============================================================
-- Rollback 0034 - Tables equipements + etalonnages (calibration register)
-- ------------------------------------------------------------
-- Drops both tables, etalonnages first (FK to equipements). Indexes,
-- constraints and policies fall with the tables (cascade). No other
-- table references them. Idempotent (drop table if exists). ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- ============================================================

drop table if exists public.etalonnages cascade;
drop table if exists public.equipements cascade;
