-- ============================================================
-- Migration 0040 - Barriere serveur sur les colonnes financieres
--                  (fix issue #142) : vues _ops + SELECT manager-only
-- ------------------------------------------------------------
-- AVANT : manager et chef_bande partagent le role Postgres
-- authenticated ; la RLS filtre des LIGNES, pas des colonnes -> les
-- colonnes de prix/cout etaient servies au chef_bande par l'API, le
-- masquage canSee('finance') du front etant la seule barriere (#142).
--
-- APRES, pour 9 tables porteuses de finance :
--   1) une vue <table>_ops en DROITS PROPRIETAIRE (PAS security_invoker
--      - motif bandes_pos 0027, la vue EST la frontiere d'acces),
--      exposant toutes les colonnes SAUF les financieres (construction
--      DYNAMIQUE, motif 0008), gardee par un WHERE sur le role JWT
--      (motif v_client_soldes 0027) : manager + chef_bande.
--   2) le SELECT du chef sur la TABLE est retire (policies rls40_*,
--      SELECT/ALL manager-only). Le chef lit la vue, le manager lit la
--      table complete. Le front route via dataSourceFor (PR appairee).
--
-- Tables et colonnes EXCLUES des vues :
--   bandes          : prix_poussin_unitaire, cout_aliment_kg,
--                     prix_vente_carcasse_kg
--   intrants        : cout_total_fcfa
--   receptions      : prix_unitaire_fcfa, cout_total_fcfa
--   abattages       : cout_workers_fcfa, cout_transport_fcfa,
--                     cout_emballage_fcfa, cout_autres_fcfa
--   aliments_phases : prix_unitaire, cout_total
--   formulations_mp : prix_unitaire_fcfa, cout_total_fcfa
--   commandes       : montant_total_fcfa, statut_paiement,
--                     date_paiement, mode_paiement
--   lignes_commande : prix_kg_fcfa, montant_fcfa
--   clients         : solde_fcfa, limite_credit_fcfa
--
-- bandes_ops : RECREEE ici en droits proprietaire (supersede la version
-- security_invoker de 0008 - meme nom, le front existant ne change pas).
-- En version invoker elle mourrait avec le retrait du SELECT chef sur
-- la table (elle applique la RLS de l'appelant).
--
-- bandes_pos : + WHERE role in (manager, vendeur) - ferme la lecture
-- des noms de bandes par un compte client (constat mineur de l'audit).
--
-- INTACTS : overlays client 0013 (le client lit les TABLES commandes /
-- lignes_commande / clients scoped a ses lignes par ses propres
-- policies), rls27_clients_vendeur_select (0027), trigger paiement 0014,
-- saisies / notifications / fournisseurs / inspections / stocks /
-- matieres (aucune colonne finance).
--
-- ECRITURES chef : aucune sur ces tables (verifie front : creation et
-- statuts de commande manager-only ; intrants/receptions/abattages via
-- la boucle notifications, insert reel en session manager - 0021).
--
-- GOTCHA DURABLE (motif 0008) : chaque vue fige ses colonnes a la
-- creation. Toute colonne ajoutee plus tard a une table ci-dessus exige
-- de REJOUER le bloc de vues (section 1) - sinon la colonne n'existe
-- pas pour le chef.
--
-- Idempotent : to_regclass + drop view if exists + drop policy if
-- exists. ASCII uniquement, pas de commentaire en fin de ligne
-- d'instruction. DEPENDANCE : executer 0039 AVANT (nettoyage derive).
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Rollback : 0040_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Les 9 vues _ops (droits proprietaire + WHERE role JWT)
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
      raise notice '0040: table % absente - vue ignoree.', spec.tbl;
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
    raise notice '0040: vue % creee.', vue;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) SELECT manager-only sur les 6 tables a policies per-verbe 0021
--    (les ecritures rls21_* restaient deja manager-only : intactes)
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['bandes','intrants','receptions','abattages',
                           'aliments_phases','formulations_mp'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0040: table % absente - section 2 ignoree.', t;
      continue;
    end if;
    execute format('drop policy if exists "rls21_%s_select" on public.%I', t, t);
    execute format('drop policy if exists "rls40_%s_select" on public.%I', t, t);
    execute format(
      'create policy "rls40_%s_select" on public.%I for select to authenticated '
      'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t, t);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 3) commandes / lignes_commande / clients : rls7_internal_all ->
--    rls40_<t>_all (FOR ALL manager). Les overlays client 0013 et la
--    policy vendeur 0027 sur clients sont des policies DISTINCTES :
--    non touchees.
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['commandes','lignes_commande','clients'] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice '0040: table % absente - section 3 ignoree.', t;
      continue;
    end if;
    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    execute format('drop policy if exists "rls40_%s_all" on public.%I', t, t);
    execute format(
      'create policy "rls40_%s_all" on public.%I for all to authenticated '
      'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'') '
      'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') = ''manager'')', t, t);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 4) bandes_pos : + gate de role (manager, vendeur) - reprend la
--    construction 0027 section 5 (filtre archivee dynamique)
-- ------------------------------------------------------------
do $$
declare filtre text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0040: table bandes absente - section 4 ignoree.';
    return;
  end if;

  filtre := ' where (auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''vendeur'')';
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bandes' and column_name = 'archivee'
  ) then
    filtre := filtre || ' and coalesce(archivee, false) = false';
  end if;

  execute 'drop view if exists public.bandes_pos';
  execute 'create view public.bandes_pos as select bande_id, nom_bande, statut from public.bandes' || filtre;
  execute 'revoke all on public.bandes_pos from anon';
  execute 'grant select on public.bandes_pos to authenticated';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Les 9 vues existent (attendu : 9 lignes) :
--   select table_name from information_schema.views
--    where table_schema = 'public'
--      and table_name in ('bandes_ops','intrants_ops','receptions_ops',
--          'abattages_ops','aliments_phases_ops','formulations_mp_ops',
--          'commandes_ops','lignes_commande_ops','clients_ops')
--    order by table_name;
--
-- 2. AUCUNE colonne financiere dans AUCUNE vue (attendu : 0 ligne) :
--   select table_name, column_name from information_schema.columns
--    where table_schema = 'public'
--      and table_name in ('bandes_ops','intrants_ops','receptions_ops',
--          'abattages_ops','aliments_phases_ops','formulations_mp_ops',
--          'commandes_ops','lignes_commande_ops','clients_ops')
--      and column_name in ('prix_poussin_unitaire','cout_aliment_kg',
--          'prix_vente_carcasse_kg','cout_total_fcfa','prix_unitaire_fcfa',
--          'cout_workers_fcfa','cout_transport_fcfa','cout_emballage_fcfa',
--          'cout_autres_fcfa','prix_unitaire','cout_total',
--          'montant_total_fcfa','statut_paiement','date_paiement',
--          'mode_paiement','prix_kg_fcfa','montant_fcfa','solde_fcfa',
--          'limite_credit_fcfa');
--
-- 3. Carte des policies attendue sur les 9 tables :
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public'
--      and tablename in ('bandes','intrants','receptions','abattages',
--          'aliments_phases','formulations_mp','commandes',
--          'lignes_commande','clients')
--    order by tablename, policyname;
--   -- attendu : rls40_<t>_select (6 tables) + leurs rls21_*_write /
--   -- rls21_bandes_insert/update/delete intacts ; rls40_<t>_all sur
--   -- commandes / lignes_commande / clients ; overlays client
--   -- rls_client_* et rls27_clients_vendeur_select INTACTS ;
--   -- plus AUCUN rls21_<t>_select ni rls7_internal_all.
--
-- 4. Simulation JWT chef_bande (le coeur du fix) :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--     select count(*) from public.intrants;
--     select count(*) from public.intrants_ops;
--     select count(*) from public.bandes;
--     select count(*) from public.bandes_ops;
--     select count(*) from public.commandes;
--     select count(*) from public.commandes_ops;
--   rollback;
--   -- attendu : tables = 0 partout ; vues > 0 (si donnees presentes)
--
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"chef_bande"}}';
--     select cout_total_fcfa from public.intrants_ops limit 1;
--   rollback;
--   -- attendu : ERREUR "column ... does not exist" (LE test colonne)
--
-- 5. Simulation manager : les tables completes repondent :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"manager"}}';
--     select count(*) from public.bandes;
--     select montant_total_fcfa from public.commandes limit 1;
--   rollback;
--
-- 6. Simulation client (overlays intacts, vues fermees) :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"client","client_id":"cli-001"}}';
--     select count(*) from public.commandes;
--     select count(*) from public.commandes_ops;
--     select count(*) from public.bandes_pos;
--   rollback;
--   -- attendu : ses commandes ; 0 ; 0
--
-- 7. API REELLE (deux vrais JWT - a lancer depuis un terminal, token =
--    access_token de la session ; URL/cle = celles du front) :
--   curl -s "https://wlcvapssgxqptmeulqdc.supabase.co/rest/v1/intrants?select=cout_total_fcfa" \
--     -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <JWT_CHEF>"
--   -- attendu : []
--   curl -s "https://wlcvapssgxqptmeulqdc.supabase.co/rest/v1/intrants_ops?select=cout_total_fcfa" \
--     -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <JWT_CHEF>"
--   -- attendu : erreur 400 (colonne inconnue)
--   curl -s "https://wlcvapssgxqptmeulqdc.supabase.co/rest/v1/intrants_ops?select=*&limit=1" \
--     -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <JWT_CHEF>"
--   -- attendu : 1 ligne SANS colonne de cout
--   curl -s "https://wlcvapssgxqptmeulqdc.supabase.co/rest/v1/intrants?select=cout_total_fcfa&limit=1" \
--     -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <JWT_MANAGER>"
--   -- attendu : 1 ligne AVEC cout_total_fcfa
--   Console navigateur (session chef, l'app ouverte) :
--     sb.from('commandes').select('montant_total_fcfa')  -- attendu : []
--
-- 8. Fonctionnel chef (apres deploiement du front appaire) : saisie du
--    jour OK ; page veto affiche les intrants ; KPI delai d'attente
--    intact ; page Commandes en kg intacte ; caisse vendeur inchangee.
-- ============================================================
