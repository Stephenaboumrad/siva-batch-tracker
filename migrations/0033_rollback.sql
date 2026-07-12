-- ============================================================
-- Rollback 0033 - Table non_conformites (deviation register)
-- ------------------------------------------------------------
-- Drops the table. Indexes, constraints and policies fall with it
-- (cascade), including the chef UPDATE policy with the frozen
-- effectiveness-check columns. The FK points FROM non_conformites TO
-- bandes, so bandes is untouched. Idempotent (drop table if exists).
-- ASCII only.
-- TO BE RUN MANUALLY in the Supabase SQL Editor.
-- ============================================================

drop table if exists public.non_conformites cascade;
