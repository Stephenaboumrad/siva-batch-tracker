-- ═══════════════════════════════════════════════════════════════════
-- COQORICO / SIVA — Supabase Setup v2 (additive migration)
-- Société Ivoirienne de Volaille et Assimilés
--
-- Adds three columns to the `saisies` table to capture environmental
-- data already collected by the field-entry form (eau, température,
-- humidité). These columns will also be populated by the upcoming IoT
-- pipeline (ESP32 sensors → Supabase).
--
-- IDEMPOTENT: safe to re-run. Uses ADD COLUMN IF NOT EXISTS, so running
-- this on a database where the columns already exist is a no-op.
-- Does NOT touch existing data or other tables.
-- ═══════════════════════════════════════════════════════════════════

alter table saisies add column if not exists eau_consommee_l numeric;
alter table saisies add column if not exists temperature_c   numeric;
alter table saisies add column if not exists humidite_pct    numeric;

-- ═══════════════════════════════════════════════════════════════════
-- Done. Columns added: 3 (all nullable, no constraints).
-- ═══════════════════════════════════════════════════════════════════
