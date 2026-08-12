-- ============================================================
-- Rollback 0049 - retire les triggers d'audit, la fonction et le
-- journal
-- ------------------------------------------------------------
-- ATTENTION : drop table audit_log = PERTE DEFINITIVE de tout le
-- journal d'audit accumule. Exporter en CSV avant si l'historique doit
-- survivre. Les 21 triggers zz_audit_log et la fonction trg_audit_log
-- sont retires ; AUCUNE table metier n'est touchee.
-- DDL a plat + boucles do $$ (drop trigger dynamique - seul create
-- policy est rejete par l'editeur). Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'saisies', 'receptions', 'pointages', 'absences', 'avances',
    'paies', 'commandes', 'lignes_commande', 'pos_transactions',
    'lignes_transaction', 'paiements', 'cloture_caisse',
    'mouvements_stock', 'produits', 'employes', 'clients',
    'parametres', 'traitements', 'vaccinations', 'bandes',
    'notifications'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0049_rollback: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('drop trigger if exists zz_audit_log on public.%I', t);
    raise notice '0049_rollback: trigger retire de % (si present).', t;
  end loop;
end $$;

drop function if exists public.trg_audit_log();

drop table if exists public.audit_log;

-- ============================================================
-- VERIFICATION (executable - NOTICEs)
-- ------------------------------------------------------------
do $$
declare
  n integer;
begin
  select count(*) into n
    from pg_trigger where tgname = 'zz_audit_log' and not tgisinternal;
  raise notice '0049_rollback verify: triggers zz_audit_log restants = % (attendu 0).', n;
  raise notice '0049_rollback verify: table audit_log absente = % ; fonction absente = %',
    (to_regclass('public.audit_log') is null),
    (to_regprocedure('public.trg_audit_log()') is null);
end $$;
