-- ============================================================
-- Migration 0027 - POS / Caisse V1 : role vendeur, RLS, extensions
-- ------------------------------------------------------------
-- Active les tables dormantes de la migration 0002 (sites,
-- points_de_vente, pos_transactions, lignes_transaction,
-- mouvements_stock, paiements, v_client_soldes) pour la caisse
-- caisse.html (nouveau role 'vendeur').
--
-- PREREQUIS : la migration 0002 doit avoir ete appliquee (les tables
-- ci-dessus existent). Chaque section est gardee par to_regclass et se
-- saute avec un notice si la table manque - rien ne casse, mais la
-- caisse ne fonctionnera pas tant que 0002 puis 0027 ne sont pas
-- appliquees toutes les deux.
--
-- MODELE DE ROLES : auth.jwt() -> 'app_metadata' ->> 'role' parmi
-- {manager, chef_bande, client, vendeur}. Le vendeur porte AUSSI
-- app_metadata.point_de_vente_id (pdv_id de son point de vente) : toutes
-- ses ecritures/lectures POS sont liees a CE pdv par les policies.
-- anon : aucune policy = aucun acces (convention 0007/0021).
--
-- CE QUE LE VENDEUR PEUT FAIRE (et rien d'autre) :
--   - INSERT pos_transactions / lignes_transaction / paiements /
--     mouvements_stock / cloture_caisse, lignes de SON pdv (WITH CHECK).
--   - SELECT ces memes tables, restreint a SON pdv (USING) - necessaire
--     au stock courant, au theorique de cloture et au recu. (La consigne
--     initiale ne listait que l'INSERT ; le SELECT lie au pdv est le
--     minimum pour que stock et cloture fonctionnent.)
--   - SELECT points_de_vente : SA ligne uniquement.
--   - SELECT produits publies : via la policy 0009 existante
--     (rls9_produits_select a une branche "disponible = true" qui
--     couvre tout role authentifie) et la vue v_catalogue_client.
--     AUCUNE nouvelle policy produits necessaire.
--   - SELECT clients (lecture pour la vente a credit) + v_client_soldes.
--   - SELECT bandes_pos : vue assainie 3 colonnes (bande_id, nom_bande,
--     statut) pour la tracabilite. Le vendeur n'a AUCUNE policy sur
--     bandes, saisies, paies, commandes, ni aucune table interne : les
--     policies 0021 ne nomment que manager/chef_bande, donc le vendeur
--     y est refuse par construction (verification en pied de fichier).
--
-- EXTENSIONS DE SCHEMA (0002 etendu, jamais re-signifie) :
--   - pos_transactions.bande_id : tracabilite au niveau en-tete (l'UI
--     impose une bande par vente ; les lignes la portent aussi, colonne
--     0002 existante).
--   - lignes_transaction.quantite / unite / prix_unitaire_fcfa : vente a
--     l'UNITE (poulet entier) - extension explicitement anticipee par la
--     note de la migration 0002 sur cette table.
--   - cloture_caisse : nouvelle table (cloture de caisse quotidienne).
--   - v_client_soldes : recreee pour integrer les ventes POS a credit au
--     "facture" (transaction finalisee portant un client_id), et gatee
--     aux roles manager/vendeur (la vue est en droits proprietaire - pas
--     de security_invoker, c'est la barriere d'acces ; personne ne la
--     consommait avant cette migration).
--   - bandes_pos : vue en droits proprietaire (PAS security_invoker, a
--     dessein : le vendeur n'a aucun droit sur bandes, la vue 3 colonnes
--     EST la frontiere, comme une fonction definer). Filtre archivee
--     construit dynamiquement (la colonne n'existe pas dans tous les
--     environnements).
--
-- IDEMPOTENCE DES VENTES : pos_transactions.transaction_id est deja
-- UNIQUE (0002) - la caisse genere un uuid cote client et le rejeu de la
-- file hors ligne tolere les doublons (violation d'unicite = deja passe).
-- Idem ligne_id / paiement_id / mouvement_id / cloture_id.
--
-- Idempotent : to_regclass + add column if not exists + drop policy if
-- exists + drop/create view. ASCII uniquement, pas de commentaire en fin
-- de ligne d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0027_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Extensions de colonnes (0002 anticipait la vente a l'unite)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.pos_transactions') is null then
    raise notice '0027: table pos_transactions absente (0002 non appliquee) - section 1 ignoree.';
    return;
  end if;

  alter table public.pos_transactions
    add column if not exists bande_id text references public.bandes(bande_id) on delete set null;

  alter table public.lignes_transaction
    add column if not exists quantite numeric;
  alter table public.lignes_transaction
    add column if not exists unite text;
  alter table public.lignes_transaction
    add column if not exists prix_unitaire_fcfa numeric;

  create index if not exists idx_pos_transactions_bande_id on public.pos_transactions(bande_id);
end $$;

-- ------------------------------------------------------------
-- 2) Table cloture_caisse (nouvelle)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.points_de_vente') is null then
    raise notice '0027: table points_de_vente absente (0002 non appliquee) - section 2 ignoree.';
    return;
  end if;

  create table if not exists public.cloture_caisse (
    id                uuid        primary key default gen_random_uuid(),
    created_at        timestamptz not null default now(),
    cloture_id        text        unique not null,
    pdv_id            text        references public.points_de_vente(pdv_id) on delete set null,
    date_cloture      timestamptz default now(),
    fond_caisse_fcfa  numeric     default 0,
    theorique_fcfa    numeric     default 0,
    compte_fcfa       numeric     default 0,
    ecart_fcfa        numeric     default 0,
    vendeur_id        text,
    note              text
  );

  create index if not exists idx_cloture_caisse_pdv_id on public.cloture_caisse(pdv_id);
  create index if not exists idx_cloture_caisse_date   on public.cloture_caisse(date_cloture);
end $$;

-- ------------------------------------------------------------
-- 3) RLS par verbe (style 0021) - remplace les policies permissives 0002
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.pos_transactions') is null then
    raise notice '0027: tables POS absentes - section 3 (RLS) ignoree.';
    return;
  end if;

  alter table public.sites              enable row level security;
  alter table public.points_de_vente    enable row level security;
  alter table public.pos_transactions   enable row level security;
  alter table public.lignes_transaction enable row level security;
  alter table public.mouvements_stock   enable row level security;
  alter table public.paiements          enable row level security;
  alter table public.cloture_caisse     enable row level security;

  revoke all on public.sites              from anon;
  revoke all on public.points_de_vente    from anon;
  revoke all on public.pos_transactions   from anon;
  revoke all on public.lignes_transaction from anon;
  revoke all on public.mouvements_stock   from anon;
  revoke all on public.paiements          from anon;
  revoke all on public.cloture_caisse     from anon;

  grant select, insert, update, delete on public.sites              to authenticated;
  grant select, insert, update, delete on public.points_de_vente    to authenticated;
  grant select, insert, update, delete on public.pos_transactions   to authenticated;
  grant select, insert, update, delete on public.lignes_transaction to authenticated;
  grant select, insert, update, delete on public.mouvements_stock   to authenticated;
  grant select, insert, update, delete on public.paiements          to authenticated;
  grant select, insert, update, delete on public.cloture_caisse     to authenticated;

  -- sites : manager uniquement
  drop policy if exists "Allow all select on sites" on public.sites;
  drop policy if exists "Allow all insert on sites" on public.sites;
  drop policy if exists "Allow all update on sites" on public.sites;
  drop policy if exists "Allow all delete on sites" on public.sites;
  drop policy if exists "rls27_sites_manager" on public.sites;
  create policy "rls27_sites_manager" on public.sites
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  -- points_de_vente : manager tout ; vendeur lit SA ligne
  drop policy if exists "Allow all select on points_de_vente" on public.points_de_vente;
  drop policy if exists "Allow all insert on points_de_vente" on public.points_de_vente;
  drop policy if exists "Allow all update on points_de_vente" on public.points_de_vente;
  drop policy if exists "Allow all delete on points_de_vente" on public.points_de_vente;
  drop policy if exists "rls27_pdv_manager" on public.points_de_vente;
  drop policy if exists "rls27_pdv_vendeur_select" on public.points_de_vente;
  create policy "rls27_pdv_manager" on public.points_de_vente
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
  create policy "rls27_pdv_vendeur_select" on public.points_de_vente
    for select to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );

  -- pos_transactions : manager tout ; vendeur INSERT + SELECT sur SON pdv
  drop policy if exists "Allow all select on pos_transactions" on public.pos_transactions;
  drop policy if exists "Allow all insert on pos_transactions" on public.pos_transactions;
  drop policy if exists "Allow all update on pos_transactions" on public.pos_transactions;
  drop policy if exists "Allow all delete on pos_transactions" on public.pos_transactions;
  drop policy if exists "rls27_postx_manager" on public.pos_transactions;
  drop policy if exists "rls27_postx_vendeur_insert" on public.pos_transactions;
  drop policy if exists "rls27_postx_vendeur_select" on public.pos_transactions;
  create policy "rls27_postx_manager" on public.pos_transactions
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
  create policy "rls27_postx_vendeur_insert" on public.pos_transactions
    for insert to authenticated
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );
  create policy "rls27_postx_vendeur_select" on public.pos_transactions
    for select to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );

  -- lignes_transaction : liaison au pdv via la transaction mere (la ligne
  -- ne porte pas de pdv_id - le EXISTS re-applique la RLS de
  -- pos_transactions pour le vendeur, donc son pdv uniquement).
  -- L'en-tete DOIT etre insere avant ses lignes (ordre du composite caisse).
  drop policy if exists "Allow all select on lignes_transaction" on public.lignes_transaction;
  drop policy if exists "Allow all insert on lignes_transaction" on public.lignes_transaction;
  drop policy if exists "Allow all update on lignes_transaction" on public.lignes_transaction;
  drop policy if exists "Allow all delete on lignes_transaction" on public.lignes_transaction;
  drop policy if exists "rls27_lignestx_manager" on public.lignes_transaction;
  drop policy if exists "rls27_lignestx_vendeur_insert" on public.lignes_transaction;
  drop policy if exists "rls27_lignestx_vendeur_select" on public.lignes_transaction;
  create policy "rls27_lignestx_manager" on public.lignes_transaction
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
  create policy "rls27_lignestx_vendeur_insert" on public.lignes_transaction
    for insert to authenticated
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and exists (
        select 1 from public.pos_transactions t
        where t.transaction_id = lignes_transaction.transaction_id
      )
    );
  create policy "rls27_lignestx_vendeur_select" on public.lignes_transaction
    for select to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and exists (
        select 1 from public.pos_transactions t
        where t.transaction_id = lignes_transaction.transaction_id
      )
    );

  -- paiements : manager tout ; vendeur INSERT + SELECT sur SON pdv
  drop policy if exists "Allow all select on paiements" on public.paiements;
  drop policy if exists "Allow all insert on paiements" on public.paiements;
  drop policy if exists "Allow all update on paiements" on public.paiements;
  drop policy if exists "Allow all delete on paiements" on public.paiements;
  drop policy if exists "rls27_paiements_manager" on public.paiements;
  drop policy if exists "rls27_paiements_vendeur_insert" on public.paiements;
  drop policy if exists "rls27_paiements_vendeur_select" on public.paiements;
  create policy "rls27_paiements_manager" on public.paiements
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
  create policy "rls27_paiements_vendeur_insert" on public.paiements
    for insert to authenticated
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );
  create policy "rls27_paiements_vendeur_select" on public.paiements
    for select to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );

  -- mouvements_stock : manager tout ; vendeur ecrit/lit les mouvements de
  -- SON pdv (aucun pdv etranger dans from/to ; au moins un cote = le sien)
  drop policy if exists "Allow all select on mouvements_stock" on public.mouvements_stock;
  drop policy if exists "Allow all insert on mouvements_stock" on public.mouvements_stock;
  drop policy if exists "Allow all update on mouvements_stock" on public.mouvements_stock;
  drop policy if exists "Allow all delete on mouvements_stock" on public.mouvements_stock;
  drop policy if exists "rls27_mvt_manager" on public.mouvements_stock;
  drop policy if exists "rls27_mvt_vendeur_insert" on public.mouvements_stock;
  drop policy if exists "rls27_mvt_vendeur_select" on public.mouvements_stock;
  create policy "rls27_mvt_manager" on public.mouvements_stock
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
  create policy "rls27_mvt_vendeur_insert" on public.mouvements_stock
    for insert to authenticated
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and (from_pdv_id is null or from_pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id'))
      and (to_pdv_id   is null or to_pdv_id   = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id'))
      and (from_pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
           or to_pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id'))
    );
  create policy "rls27_mvt_vendeur_select" on public.mouvements_stock
    for select to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and (from_pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
           or to_pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id'))
    );

  -- cloture_caisse : manager tout ; vendeur INSERT + SELECT sur SON pdv
  drop policy if exists "rls27_cloture_manager" on public.cloture_caisse;
  drop policy if exists "rls27_cloture_vendeur_insert" on public.cloture_caisse;
  drop policy if exists "rls27_cloture_vendeur_select" on public.cloture_caisse;
  create policy "rls27_cloture_manager" on public.cloture_caisse
    for all to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
  create policy "rls27_cloture_vendeur_insert" on public.cloture_caisse
    for insert to authenticated
    with check (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );
  create policy "rls27_cloture_vendeur_select" on public.cloture_caisse
    for select to authenticated
    using (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and pdv_id = (auth.jwt() -> 'app_metadata' ->> 'point_de_vente_id')
    );
end $$;

-- ------------------------------------------------------------
-- 4) Vendeur : lecture clients (vente a credit)
--    Policy ADDITIVE (les policies permissives s'additionnent) - ne
--    modifie aucune policy clients existante (0011/0013 portail).
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.clients') is null then
    raise notice '0027: table clients absente - section 4 ignoree.';
    return;
  end if;

  drop policy if exists "rls27_clients_vendeur_select" on public.clients;
  create policy "rls27_clients_vendeur_select" on public.clients
    for select to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur');
end $$;

-- ------------------------------------------------------------
-- 5) Vue bandes_pos - tracabilite assainie pour la caisse
--    DROITS PROPRIETAIRE a dessein (pas de security_invoker) : le
--    vendeur n'a AUCUNE policy sur bandes ; cette vue 3 colonnes est la
--    frontiere d'acces, comme une fonction security definer. Aucune
--    colonne financiere ni operationnelle au-dela du strict necessaire.
--    Filtre archivee construit dynamiquement (colonne hors schema de
--    base, presente en prod).
-- ------------------------------------------------------------
do $$
declare filtre text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0027: table bandes absente - section 5 ignoree.';
    return;
  end if;

  filtre := '';
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bandes' and column_name = 'archivee'
  ) then
    filtre := ' where coalesce(archivee, false) = false';
  end if;

  execute 'drop view if exists public.bandes_pos';
  execute 'create view public.bandes_pos as select bande_id, nom_bande, statut from public.bandes' || filtre;

  execute 'revoke all on public.bandes_pos from anon';
  execute 'grant select on public.bandes_pos to authenticated';
end $$;

-- ------------------------------------------------------------
-- 6) v_client_soldes v2 - integre les ventes POS a credit + gate de role
--    facture = commandes livrees + transactions POS finalisees portant un
--    client_id ; paye = paiements encaissement confirmes. Une vente POS
--    payee comptant avec client s'annule (facture et paye augmentent du
--    meme montant) ; la part credit reste en solde. Vue en droits
--    proprietaire : le WHERE gate aux roles manager/vendeur (personne ne
--    consommait cette vue avant 0027).
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.clients') is null or to_regclass('public.pos_transactions') is null then
    raise notice '0027: clients ou pos_transactions absente - section 6 ignoree.';
    return;
  end if;

  create or replace view public.v_client_soldes as
  select
    c.client_id,
    c.nom,
    coalesce(f.total_facture_fcfa, 0) + coalesce(x.total_pos_fcfa, 0)      as total_facture_fcfa,
    coalesce(p.total_paye_fcfa, 0)                                          as total_paye_fcfa,
    coalesce(f.total_facture_fcfa, 0) + coalesce(x.total_pos_fcfa, 0)
      - coalesce(p.total_paye_fcfa, 0)                                      as solde_fcfa
  from clients c
  left join (
    select client_id, sum(montant_total_fcfa) as total_facture_fcfa
    from commandes
    where statut = 'livree' and client_id is not null
    group by client_id
  ) f on f.client_id = c.client_id
  left join (
    select client_id, sum(montant_total_fcfa) as total_pos_fcfa
    from pos_transactions
    where statut = 'finalisee' and client_id is not null
    group by client_id
  ) x on x.client_id = c.client_id
  left join (
    select client_id, sum(montant_fcfa) as total_paye_fcfa
    from paiements
    where sens = 'encaissement' and statut = 'confirme' and client_id is not null
    group by client_id
  ) p on p.client_id = c.client_id
  where (auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'vendeur');

  revoke all on public.v_client_soldes from anon;
  grant select on public.v_client_soldes to authenticated;
end $$;

-- ------------------------------------------------------------
-- 7) SEED optionnel (COMMENTE - a adapter puis executer a la main) :
--    un point de vente d'exemple rattache au site existant.
-- ------------------------------------------------------------
--   insert into points_de_vente (pdv_id, nom, site_id, type, ville, statut)
--   values ('pdv-bingerville', 'Bingerville', 'site-azaguie', 'boutique', 'Bingerville', 'actif')
--   on conflict (pdv_id) do nothing;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Policies POS en place (attendu : uniquement des rls27_* sur ces tables) :
--   select tablename, policyname from pg_policies
--    where tablename in ('sites','points_de_vente','pos_transactions',
--          'lignes_transaction','mouvements_stock','paiements','cloture_caisse')
--    order by tablename, policyname;
--   -- attendu : 17 lignes, toutes rls27_*, AUCUNE "Allow all".
--
-- 2. Le vendeur n'a acces a AUCUNE table interne (attendu : 0 ligne) :
--   select tablename, policyname from pg_policies
--    where (qual like '%vendeur%' or with_check like '%vendeur%')
--      and tablename in ('bandes','saisies','paies','depenses_rh','commandes',
--          'lignes_commande','intrants','abattages','receptions','employes');
--
-- 3. Colonnes etendues :
--   select column_name from information_schema.columns
--    where table_name = 'pos_transactions' and column_name = 'bande_id';
--   -- attendu : 1 ligne.
--   select column_name from information_schema.columns
--    where table_name = 'lignes_transaction'
--      and column_name in ('quantite','unite','prix_unitaire_fcfa');
--   -- attendu : 3 lignes.
--
-- 4. Vues :
--   select table_name from information_schema.views
--    where table_name in ('bandes_pos','v_client_soldes');
--   -- attendu : 2 lignes.
--   select column_name from information_schema.columns
--    where table_name = 'bandes_pos';
--   -- attendu : exactement bande_id, nom_bande, statut.
--
-- 5. cloture_caisse :
--   select to_regclass('public.cloture_caisse');
--   -- attendu : non null.
-- ============================================================
