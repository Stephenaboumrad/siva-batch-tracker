-- ============================================================
-- Rollback 0028 - supprime la table parametres et ses policies
-- ------------------------------------------------------------
-- ATTENTION : supprime le standard commun enregistre (seuils d'alerte
-- mortalite, reglages sanitaires partages). Le front retombe alors sur
-- ses defauts / cache localStorage par appareil, comme avant 0028.
-- Idempotent : to_regclass + drop policy if exists.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.parametres') is null then
    raise notice '0028 rollback: table parametres absente - rien a faire.';
    return;
  end if;

  drop policy if exists "rls28_parametres_select_auth"    on public.parametres;
  drop policy if exists "rls28_parametres_manager_insert" on public.parametres;
  drop policy if exists "rls28_parametres_manager_update" on public.parametres;
  drop policy if exists "rls28_parametres_manager_delete" on public.parametres;

  drop table public.parametres;
end $$;

-- VERIFICATION (attendu : null)
--   select to_regclass('public.parametres');
