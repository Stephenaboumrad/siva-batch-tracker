-- ============================================================
-- Rollback 0021 - Restaure l'etat pre-0021 (rls7_internal_all de 0007)
-- ------------------------------------------------------------
-- Supprime les politiques per-verbe rls21_* et le trigger de garde, puis
-- recree la politique rls7_internal_all (manager + chef_bande, FOR ALL)
-- sur les 7 tables touchees - texte identique a 0007.
-- ATTENTION : revenir en arriere rouvre les contournements identifies par
-- l'audit (C-F3 suppression de bande cote chef, C-F4 bypass de la boucle
-- de validation) ; seules les gardes client subsistent alors.
-- Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
declare
  t text;
  p record;
begin
  foreach t in array array['bandes','saisies','intrants','receptions',
                           'abattages','aliments_phases','formulations_mp'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0021 rollback: table % absente - ignoree.', t;
      continue;
    end if;

    for p in select policyname from pg_policies
              where schemaname = 'public' and tablename = t
                and policyname like 'rls21_%' loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;

    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    execute format(
      'create policy "rls7_internal_all" on public.%I for all to authenticated '
      'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande'')) '
      'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t);
  end loop;
end $$;

do $$
begin
  if to_regclass('public.bandes') is not null then
    drop trigger if exists bandes_delete_guard on public.bandes;
  end if;
end $$;

drop function if exists public.trg_bandes_delete_guard();

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) :
--   select tablename, policyname from pg_policies
--    where schemaname = 'public'
--      and tablename in ('bandes','saisies','intrants','receptions',
--                        'abattages','aliments_phases','formulations_mp')
--    order by tablename;
--   -- attendu : exactement 1 ligne par table = rls7_internal_all
--   select tgname from pg_trigger
--    where tgrelid = 'public.bandes'::regclass
--      and tgname = 'bandes_delete_guard';
--   -- attendu : 0 ligne
-- ============================================================
