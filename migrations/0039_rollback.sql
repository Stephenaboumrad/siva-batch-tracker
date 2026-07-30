-- ============================================================
-- Rollback 0039 - restaure rls7_internal_all sur sites /
--                 points_de_vente / mouvements_stock
-- ------------------------------------------------------------
-- ATTENTION : ceci restaure l'etat DERIVE (chef_bande retrouve un CRUD
-- complet sur les 3 tables, colonnes de cout comprises). A n'executer
-- que si le nettoyage 0039 casse un flux imprevu, le temps du
-- diagnostic. Idempotent : drop puis create.
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array['sites', 'points_de_vente', 'mouvements_stock'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0039 rollback: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    execute format(
      'create policy "rls7_internal_all" on public.%I for all to authenticated '
      'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande'')) '
      'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t);
  end loop;
end $$;

-- VERIFICATION (attendu : 3 lignes rls7_internal_all) :
--   select tablename, policyname from pg_policies
--    where schemaname = 'public'
--      and tablename in ('sites', 'points_de_vente', 'mouvements_stock')
--      and policyname = 'rls7_internal_all';
