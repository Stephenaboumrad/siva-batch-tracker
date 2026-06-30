-- ============================================================
-- Rollback 0016 - Trace override delai d'attente sur abattages
-- ------------------------------------------------------------
-- Retire les 4 colonnes ajoutees par 0016. Idempotent (drop column if exists).
-- ASCII uniquement. A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

alter table public.abattages drop column if exists delai_attente_override;
alter table public.abattages drop column if exists delai_attente_override_par;
alter table public.abattages drop column if exists delai_attente_override_at;
alter table public.abattages drop column if exists delai_attente_override_motif;
