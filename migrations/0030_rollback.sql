-- ============================================================
-- Rollback 0030 - retire bandes.surface_m2 et rejoue la vue bandes_ops
-- ------------------------------------------------------------
-- ATTENTION : perd les surfaces deja saisies (la densite redevient non
-- calculable). Les bandes elles-memes ne sont PAS touchees.
-- La vue bandes_ops depend de la colonne : elle est supprimee AVANT le
-- drop column puis reconstruite (bloc 0008, liste dynamique excluant les
-- 3 colonnes financieres) - sinon le drop column echouerait.
-- Idempotent : to_regclass + drop column if exists + drop/create view.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
declare cols text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0030 rollback: table bandes absente - rien a faire.';
    return;
  end if;

  execute 'drop view if exists public.bandes_ops';

  alter table public.bandes
    drop column if exists surface_m2;

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
  from information_schema.columns
  where table_schema = 'public'
    and table_name   = 'bandes'
    and column_name not in ('prix_poussin_unitaire', 'cout_aliment_kg', 'prix_vente_carcasse_kg');

  execute 'create view public.bandes_ops with (security_invoker = true) as select '
          || cols || ' from public.bandes';

  execute 'revoke all on public.bandes_ops from anon';
  execute 'grant select on public.bandes_ops to authenticated';
end $$;

-- VERIFICATION (attendu : 0 ligne)
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'bandes'
--      and column_name = 'surface_m2';
