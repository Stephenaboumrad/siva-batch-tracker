-- ============================================================
-- Rollback 0041 - retire les colonnes de resolution d'ecart
-- ------------------------------------------------------------
-- DESTRUCTIF pour les resolutions deja saisies (note + horodatage +
-- matricule) : exporter cloture_caisse en CSV avant si des ecarts ont
-- ete marques resolus. Les agregats front retomberont sur « tout ecart
-- non nul = non resolu ». Idempotent : drop column if exists.
-- ============================================================

do $$
begin
  if to_regclass('public.cloture_caisse') is null then
    raise notice '0041 rollback: table cloture_caisse absente - rien a faire.';
    return;
  end if;

  alter table public.cloture_caisse drop column if exists ecart_resolu_note;
  alter table public.cloture_caisse drop column if exists ecart_resolu_at;
  alter table public.cloture_caisse drop column if exists ecart_resolu_par;

  raise notice '0041 rollback: colonnes de resolution retirees.';
end $$;

-- VERIFICATION (attendu : 0 ligne) :
--   select column_name from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'cloture_caisse'
--      and column_name in ('ecart_resolu_note', 'ecart_resolu_at', 'ecart_resolu_par');
