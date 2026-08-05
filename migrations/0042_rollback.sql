-- ============================================================
-- Rollback 0042 - Confiance & tracabilite
-- ------------------------------------------------------------
-- Retire les 6 colonnes additives, puis REJOUE le bloc de vues 0040
-- section 1 avec les listes d'exclusion D'ORIGINE (0040) pour
-- resynchroniser les 9 vues _ops sur le schema retabli (regle
-- CLAUDE.md : receptions est sous vue _ops). Ordre impose par la
-- dependance vue->colonne : receptions_ops est droppee AVANT le drop
-- de stock_mouvement_ref (sinon erreur de dependance), puis les 9
-- vues sont recreees en section 2.
-- Les valeurs saisies dans ces colonnes sont PERDUES (metadonnees de
-- tracabilite, pas de donnees metier premieres).
-- Idempotent : if exists partout. ASCII uniquement.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Drop des colonnes (receptions_ops depend de
--    stock_mouvement_ref : la vue est droppee d'abord, elle est
--    recreee en section 2)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.receptions') is not null then
    drop view if exists public.receptions_ops;
    alter table public.receptions drop column if exists prix_pose_par;
    alter table public.receptions drop column if exists prix_pose_le;
    alter table public.receptions drop column if exists stock_mouvement_ref;
    raise notice 'rollback 0042: colonnes receptions retirees.';
  end if;

  if to_regclass('public.stocks') is not null then
    alter table public.stocks drop column if exists dernier_mouvement_delta;
    alter table public.stocks drop column if exists dernier_mouvement_type;
    alter table public.stocks drop column if exists dernier_mouvement_date;
    raise notice 'rollback 0042: colonnes stocks retirees.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 2) Rejeu du bloc de vues avec les listes d'exclusion 0040
--    (etat pre-0042)
-- ------------------------------------------------------------
do $$
declare
  spec record;
  cols text;
  vue  text;
begin
  for spec in
    select * from (values
      ('bandes',          array['prix_poussin_unitaire','cout_aliment_kg','prix_vente_carcasse_kg']),
      ('intrants',        array['cout_total_fcfa']),
      ('receptions',      array['prix_unitaire_fcfa','cout_total_fcfa']),
      ('abattages',       array['cout_workers_fcfa','cout_transport_fcfa','cout_emballage_fcfa','cout_autres_fcfa']),
      ('aliments_phases', array['prix_unitaire','cout_total']),
      ('formulations_mp', array['prix_unitaire_fcfa','cout_total_fcfa']),
      ('commandes',       array['montant_total_fcfa','statut_paiement','date_paiement','mode_paiement']),
      ('lignes_commande', array['prix_kg_fcfa','montant_fcfa']),
      ('clients',         array['solde_fcfa','limite_credit_fcfa'])
    ) as t(tbl, excl)
  loop
    if to_regclass(format('public.%I', spec.tbl)) is null then
      continue;
    end if;

    select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
      into cols
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = spec.tbl
       and column_name <> all (spec.excl);

    vue := spec.tbl || '_ops';
    execute format('drop view if exists public.%I', vue);
    execute format(
      'create view public.%I as select %s from public.%I '
      'where (auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande'')',
      vue, cols, spec.tbl);
    execute format('revoke all on public.%I from anon', vue);
    execute format('grant select on public.%I to authenticated', vue);
    raise notice 'rollback 0042: vue % rejouee (listes 0040).', vue;
  end loop;
end $$;

-- ============================================================
-- VERIFICATION (lecture seule)
-- ------------------------------------------------------------
-- 1. Plus aucune des 6 colonnes (attendu : 0 ligne) :
--   select table_name, column_name from information_schema.columns
--    where table_schema = 'public'
--      and column_name in ('prix_pose_par','prix_pose_le',
--          'stock_mouvement_ref','dernier_mouvement_delta',
--          'dernier_mouvement_type','dernier_mouvement_date')
--      and table_name in ('receptions','stocks');
--
-- 2. Les 9 vues repondent (attendu : 9 lignes) :
--   select table_name from information_schema.views
--    where table_schema = 'public'
--      and table_name like '%\_ops' escape '\'
--    order by table_name;
-- ============================================================
