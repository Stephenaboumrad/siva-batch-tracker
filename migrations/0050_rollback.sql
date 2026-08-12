-- ============================================================
-- Rollback 0050 - retire les triggers de date systeme + la fonction
-- ------------------------------------------------------------
-- Retire aa_date_systeme des 7 tables et drop trg_date_systeme.
-- AUCUNE donnee touchee (les dates deja ecrites restent). Apres ce
-- rollback, les roles non-manager peuvent de nouveau poser une date
-- d'evenement arbitraire cote serveur.
-- DDL a plat + boucle do $$. Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'receptions', 'abattages', 'avances', 'cloture_caisse',
    'paiements', 'mouvements_stock', 'pos_transactions'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0050_rollback: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('drop trigger if exists aa_date_systeme on public.%I', t);
    raise notice '0050_rollback: trigger retire de % (si present).', t;
  end loop;
end $$;

drop function if exists public.trg_date_systeme();

-- ============================================================
-- VERIFICATION (executable - NOTICEs)
-- ------------------------------------------------------------
do $$
declare
  n integer;
begin
  select count(*) into n
    from pg_trigger where tgname = 'aa_date_systeme' and not tgisinternal;
  raise notice '0050_rollback verify: triggers aa_date_systeme restants = % (attendu 0).', n;
  raise notice '0050_rollback verify: fonction trg_date_systeme absente = %',
    (to_regprocedure('public.trg_date_systeme()') is null);
end $$;
