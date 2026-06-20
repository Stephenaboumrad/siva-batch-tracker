-- ═══════════════════════════════════════════════════════════════════
-- Migration 0008 — ROLLBACK
-- ───────────────────────────────────────────────────────────────────
-- Supprime la vue assainie bandes_ops. Ne touche AUCUNE politique RLS (0008
-- n'en créait aucune — la vue héritait de la RLS de `bandes` via security_invoker).
--
-- ⚠ Si vous rollback la DB SANS revenir aussi sur le front de cette PR, le
--   chargement chef_bande des bandes retombe sur [] (repli .catch(()=>[]) du
--   front) → dashboard/fiche dégradés pour chef_bande (pas de crash). Pour un
--   rollback complet, revenir aussi le front (chef relit `bandes`).
--
-- Idempotent. À EXÉCUTER MANUELLEMENT (SQL Editor Supabase).
-- ═══════════════════════════════════════════════════════════════════

drop view if exists public.bandes_ops;
