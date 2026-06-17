-- ═══════════════════════════════════════════════════════════════════
-- Migration 0005 — Security PR 3 (1/2) : tables de caisse/finance → manager only
-- ───────────────────────────────────────────────────────────────────
-- Le module Trésorerie n'a PAS de table dédiée (recettes/dépenses/solde sont
-- CALCULÉS côté app à partir de commandes + économie des bandes + paies +
-- depenses_rh). Les tables paies/depenses_rh/employes sont déjà manager-only
-- (0004b). Les seules autres tables de caisse/finance sont les tables POS de la
-- migration 0002 : on les restreint ici à role='manager' (cohérent), pour le
-- jour où le module POS sera utilisé. chef_bande & anon : aucun accès.
--
-- Rôle lu dans le JWT : auth.jwt() -> 'app_metadata' ->> 'role' (cf. PR 1).
-- ROBUSTE : ignore les tables absentes (to_regclass) — ces tables POS peuvent
-- ne pas exister dans cette base ; aucune annulation globale. Idempotent.
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase). Rollback : 0005_0006_rollback.sql.
-- ═══════════════════════════════════════════════════════════════════

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
        'create policy "rls3_manager_all" on public.%I for all to authenticated '
        'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
        'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t);
    end if;
  end loop;
end $$;

-- Vérification (après) :
--   select tablename, policyname, roles, qual from pg_policies
--    where tablename in ('pos_transactions','paiements','lignes_transaction');
--   → uniquement rls3_manager_all (authenticated, role='manager') sur les tables présentes.
