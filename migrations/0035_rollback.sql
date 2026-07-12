-- ============================================================
-- Rollback 0035 - Tables postes_appatage + releves_nuisibles (pest control)
-- ------------------------------------------------------------
-- Drops both tables, releves_nuisibles first (FK to postes_appatage).
-- Indexes, constraints and policies fall with the tables (cascade). No
-- other table references them. Idempotent (drop table if exists).
-- ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- ============================================================

drop table if exists public.releves_nuisibles cascade;
drop table if exists public.postes_appatage cascade;
