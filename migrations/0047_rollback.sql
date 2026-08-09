-- ============================================================
-- Rollback 0047 - retire la trace de remboursement des avances
-- ------------------------------------------------------------
-- ATTENTION : perd la valeur de rembourse_le / rembourse_paie_ref sur
-- toutes les lignes. Le drapeau rembourse (0046) est conserve.
-- DDL a plat. Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.avances') is null then
    raise notice '0047_rollback: table avances absente - rien a retirer.';
  end if;
end $$;

alter table public.avances drop column if exists rembourse_le;

alter table public.avances drop column if exists rembourse_paie_ref;

-- ============================================================
-- VERIFICATION (executable - NOTICEs)
-- ------------------------------------------------------------
do $$
begin
  raise notice '0047_rollback verify: rembourse_le absente = % ; rembourse_paie_ref absente = %',
    not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='avances' and column_name='rembourse_le'),
    not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='avances' and column_name='rembourse_paie_ref');
end $$;
