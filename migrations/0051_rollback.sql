-- ============================================================
-- Rollback 0051 - retire la policy d'edition chef sur saisies
-- ------------------------------------------------------------
-- Drop rls51_saisies_update_chef. Les colonnes created_by / created_at
-- sont CONSERVEES (inoffensives, potentiellement heritees avant 0051 -
-- les dropper risquerait de retirer une colonne du schema d'origine).
-- rls21_saisies_update (manager) n'est pas touchee.
-- DDL a plat. Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.saisies') is null then
    raise notice '0051_rollback: table saisies absente - rien a retirer.';
  end if;
end $$;

drop policy if exists "rls51_saisies_update_chef" on public.saisies;

-- ============================================================
-- VERIFICATION (executable - NOTICEs)
-- ------------------------------------------------------------
do $$
begin
  raise notice '0051_rollback verify: rls51_saisies_update_chef absente = % ; rls21_saisies_update presente = %',
    not exists (select 1 from pg_policies where schemaname='public' and tablename='saisies'
                 and policyname='rls51_saisies_update_chef'),
    exists (select 1 from pg_policies where schemaname='public' and tablename='saisies'
             and policyname='rls21_saisies_update');
end $$;
