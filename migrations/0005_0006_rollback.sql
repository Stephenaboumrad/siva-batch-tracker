-- ═══════════════════════════════════════════════════════════════════
-- Migration 0005+0006 — ROLLBACK (Security PR 3)
-- ───────────────────────────────────────────────────────────────────
-- Annule la vue assainie et rend aux tables POS finance l'accès « baseline »
-- (authenticated R/W, comme 0004b). NB : ne ré-expose PAS les colonnes
-- financières de bandes à chef_bande côté app — c'est le front (lecture
-- bandes_ops) qui décide ; ce rollback supprime juste la vue, donc l'app
-- chef retombera à vide pour les bandes tant que le front lit bandes_ops.
-- Si vous rollback, déployez aussi un front qui relit `bandes` pour chef.
--
-- Robuste (ignore les tables absentes), idempotent.
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase).
-- ═══════════════════════════════════════════════════════════════════

-- 1) Supprime la vue assainie.
drop view if exists public.bandes_ops;

-- 2) Tables POS finance → retour baseline (authenticated R/W).
do $$
declare
  t text;
  p record;
  finance text[] := array['pos_transactions','paiements','lignes_transaction'];
begin
  foreach t in array finance loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "rls2_auth_all" on public.%I for all to authenticated using (true) with check (true)', t);
    end if;
  end loop;
end $$;
