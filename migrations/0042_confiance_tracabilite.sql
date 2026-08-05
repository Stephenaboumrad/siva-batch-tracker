-- ============================================================
-- Migration 0042 - Confiance & tracabilite (lot terrain 2026-08)
-- ------------------------------------------------------------
-- Trois anomalies terrain, un fil conducteur : l'app agissait sans
-- le montrer. Cote schema, deux tables recoivent des colonnes
-- ADDITIVES nullable :
--
-- 1) receptions (tracabilite du PRIX et du LIEN STOCK) :
--    prix_pose_par       text         matricule du manager qui a pose
--                                     le prix (a la validation, au
--                                     formulaire direct, ou plus tard)
--    prix_pose_le        timestamptz  horodatage de la pose du prix
--    stock_mouvement_ref text         reference de l'increment de stock
--                                     applique via le picker SC-1.3,
--                                     format 'stock_id|delta|unite'
--                                     (ex. 'stk-abc|500|kg') ; NULL =
--                                     aucun increment applique
--
--    CONVENTION PRIX (fin du zero silencieux) : prix_unitaire_fcfa
--    NULL = prix MANQUANT (badge ambre cote front) ; 0 = prix
--    explicitement pose a zero (don, echantillon). Les lignes
--    historiques a 0 restent a 0 (pas de backfill, pas de badge).
--
-- 2) stocks (dernier mouvement PERSISTE, affiche sur la carte) :
--    dernier_mouvement_delta numeric      delta signe (+500 / -20)
--    dernier_mouvement_type  text         'reception' | 'ajustement'
--    dernier_mouvement_date  timestamptz  date du mouvement
--
--    Mecanisme retenu : colonnes sur stocks, PAS de table journal.
--    Justification : le besoin est l'affichage du DERNIER mouvement
--    par carte ; le journal complet des mouvements ferme est le
--    territoire de SC-2.1 (reconciliation conso<->stock) - le
--    construire ici en ad hoc preempterait sa conception sans les
--    semantiques de reconciliation. Colonnes additives = reversibles.
--
-- REGLE CLAUDE.md (gotcha 0040) : receptions est dans les 9 tables
-- sous vue _ops -> le bloc de vues 0040 section 1 est REJOUE ici
-- (section 3), dans la MEME migration. stocks n'est PAS dans les 9
-- (aucune vue stocks_ops) : aucun rejeu requis pour elle.
--
-- DECISION D'EXCLUSION (vue receptions_ops, lue par le chef) :
--   prix_pose_par / prix_pose_le : EXCLUS. Ce sont des metadonnees,
--   pas des montants - mais elles revelent l'existence, l'auteur et
--   le moment de la pose d'un prix. Le principe verrouille en SC-1
--   (decision 3) est que le CYCLE DE VIE du prix est invisible au
--   chef, pas seulement son montant ; le chef n'a aucun cas d'usage
--   de ces colonnes. Les exclure ne coute rien fonctionnellement et
--   garde la barriere lisible (tout ce qui commence par prix_/cout_
--   est hors vue chef).
--   stock_mouvement_ref : INCLUS. Tracabilite operationnelle
--   (quel stock a bouge), aucune information financiere.
--
-- Les 8 autres tables gardent leur liste d'exclusion 0040 inchangee ;
-- le rejeu est idempotent et resynchronise au passage toute colonne
-- ajoutee par ailleurs. Les futures migrations doivent repartir de la
-- liste receptions de CE fichier (la plus recente), pas de celle de
-- 0040.
--
-- Idempotent : to_regclass + add column if not exists + drop view if
-- exists. ASCII uniquement, pas de commentaire en fin de ligne
-- d'instruction. A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Rollback : 0042_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) receptions : metadonnees de pose du prix + reference stock
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.receptions') is null then
    raise notice '0042: table receptions absente - section 1 ignoree.';
    return;
  end if;

  alter table public.receptions add column if not exists prix_pose_par       text;
  alter table public.receptions add column if not exists prix_pose_le        timestamptz;
  alter table public.receptions add column if not exists stock_mouvement_ref text;

  raise notice '0042: colonnes prix_pose_par / prix_pose_le / stock_mouvement_ref ajoutees a receptions.';
end $$;

-- ------------------------------------------------------------
-- 2) stocks : dernier mouvement persiste
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.stocks') is null then
    raise notice '0042: table stocks absente - section 2 ignoree.';
    return;
  end if;

  alter table public.stocks add column if not exists dernier_mouvement_delta numeric;
  alter table public.stocks add column if not exists dernier_mouvement_type  text;
  alter table public.stocks add column if not exists dernier_mouvement_date  timestamptz;

  raise notice '0042: colonnes dernier_mouvement_* ajoutees a stocks.';
end $$;

-- ------------------------------------------------------------
-- 3) REJEU du bloc de vues 0040 section 1 (regle CLAUDE.md :
--    colonne ajoutee a une table sous vue _ops => rejouer le bloc
--    DANS la meme migration). Seule la liste receptions change :
--    + prix_pose_par, prix_pose_le (metadonnees prix, hors vue chef).
--    stock_mouvement_ref n'est PAS exclu (il entre dans la vue).
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
      ('receptions',      array['prix_unitaire_fcfa','cout_total_fcfa','prix_pose_par','prix_pose_le']),
      ('abattages',       array['cout_workers_fcfa','cout_transport_fcfa','cout_emballage_fcfa','cout_autres_fcfa']),
      ('aliments_phases', array['prix_unitaire','cout_total']),
      ('formulations_mp', array['prix_unitaire_fcfa','cout_total_fcfa']),
      ('commandes',       array['montant_total_fcfa','statut_paiement','date_paiement','mode_paiement']),
      ('lignes_commande', array['prix_kg_fcfa','montant_fcfa']),
      ('clients',         array['solde_fcfa','limite_credit_fcfa'])
    ) as t(tbl, excl)
  loop
    if to_regclass(format('public.%I', spec.tbl)) is null then
      raise notice '0042: table % absente - vue ignoree.', spec.tbl;
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
    raise notice '0042: vue % rejouee.', vue;
  end loop;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Les 6 nouvelles colonnes existent (attendu : 6 lignes) :
--   select table_name, column_name, data_type
--     from information_schema.columns
--    where table_schema = 'public'
--      and ((table_name = 'receptions' and column_name in
--              ('prix_pose_par','prix_pose_le','stock_mouvement_ref'))
--        or (table_name = 'stocks' and column_name in
--              ('dernier_mouvement_delta','dernier_mouvement_type',
--               'dernier_mouvement_date')))
--    order by table_name, column_name;
--
-- 2. receptions_ops : stock_mouvement_ref DEDANS, metadonnees prix
--    DEHORS (attendu : 1 seule ligne, stock_mouvement_ref) :
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'receptions_ops'
--      and column_name in ('stock_mouvement_ref','prix_pose_par',
--          'prix_pose_le','prix_unitaire_fcfa','cout_total_fcfa');
--
-- 3. Les 9 vues repondent toujours (attendu : 9 lignes) :
--   select table_name from information_schema.views
--    where table_schema = 'public'
--      and table_name in ('bandes_ops','intrants_ops','receptions_ops',
--          'abattages_ops','aliments_phases_ops','formulations_mp_ops',
--          'commandes_ops','lignes_commande_ops','clients_ops')
--    order by table_name;
--
-- 4. Simulation JWT chef : la vue s'ouvre, les metadonnees prix non :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--     select count(*) from public.receptions_ops;
--   rollback;
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--     select prix_pose_par from public.receptions_ops limit 1;
--   rollback;
--   -- attendu : count OK ; puis ERREUR "column ... does not exist"
--
-- 5. Simulation manager : la table complete repond :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"manager"}}';
--     select prix_pose_par, prix_pose_le, stock_mouvement_ref
--       from public.receptions limit 1;
--     select dernier_mouvement_delta, dernier_mouvement_type,
--            dernier_mouvement_date
--       from public.stocks limit 1;
--   rollback;
-- ============================================================
