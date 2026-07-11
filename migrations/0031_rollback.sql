-- ============================================================
-- Rollback 0031 - Table vides_sanitaires (sanitary downtime register)
-- ------------------------------------------------------------
-- Drops the table. Indexes, constraints and policies fall with it
-- (cascade). The FKs point FROM vides_sanitaires TO bandes, so bandes
-- is untouched. Idempotent (drop table if exists). ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- ============================================================

drop table if exists public.vides_sanitaires cascade;
