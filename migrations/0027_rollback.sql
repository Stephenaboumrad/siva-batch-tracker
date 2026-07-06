-- ============================================================
-- Rollback 0027 - POS / Caisse V1
-- ------------------------------------------------------------
-- Retour a l'etat 0002 (tables POS dormantes, policies permissives) :
--   - drop des policies rls27_* et RECREATION des policies permissives
--     0002 sur les 6 tables POS (etat anterieur fidele - ces tables
--     redeviennent dormantes et non exposees par l'app).
--   - drop de cloture_caisse (PERTE DE DONNEES : clotures effacees).
--   - drop de bandes_pos.
--   - v_client_soldes recreee dans sa definition 0002 d'origine (sans
--     ventes POS, sans gate de role).
--   - drop des colonnes 0027 (PERTE DE DONNEES : bande_id d'en-tete et
--     quantite/unite/prix_unitaire des lignes effaces).
-- La caisse (caisse.html) CESSE de fonctionner apres ce rollback.
-- Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.pos_transactions') is null then
    raise notice '0027 rollback: tables POS absentes - rien a faire.';
    return;
  end if;

  drop policy if exists "rls27_sites_manager" on public.sites;
  drop policy if exists "rls27_pdv_manager" on public.points_de_vente;
  drop policy if exists "rls27_pdv_vendeur_select" on public.points_de_vente;
  drop policy if exists "rls27_postx_manager" on public.pos_transactions;
  drop policy if exists "rls27_postx_vendeur_insert" on public.pos_transactions;
  drop policy if exists "rls27_postx_vendeur_select" on public.pos_transactions;
  drop policy if exists "rls27_lignestx_manager" on public.lignes_transaction;
  drop policy if exists "rls27_lignestx_vendeur_insert" on public.lignes_transaction;
  drop policy if exists "rls27_lignestx_vendeur_select" on public.lignes_transaction;
  drop policy if exists "rls27_paiements_manager" on public.paiements;
  drop policy if exists "rls27_paiements_vendeur_insert" on public.paiements;
  drop policy if exists "rls27_paiements_vendeur_select" on public.paiements;
  drop policy if exists "rls27_mvt_manager" on public.mouvements_stock;
  drop policy if exists "rls27_mvt_vendeur_insert" on public.mouvements_stock;
  drop policy if exists "rls27_mvt_vendeur_select" on public.mouvements_stock;

  create policy "Allow all select on sites" on public.sites for select using (true);
  create policy "Allow all insert on sites" on public.sites for insert with check (true);
  create policy "Allow all update on sites" on public.sites for update using (true) with check (true);
  create policy "Allow all delete on sites" on public.sites for delete using (true);

  create policy "Allow all select on points_de_vente" on public.points_de_vente for select using (true);
  create policy "Allow all insert on points_de_vente" on public.points_de_vente for insert with check (true);
  create policy "Allow all update on points_de_vente" on public.points_de_vente for update using (true) with check (true);
  create policy "Allow all delete on points_de_vente" on public.points_de_vente for delete using (true);

  create policy "Allow all select on pos_transactions" on public.pos_transactions for select using (true);
  create policy "Allow all insert on pos_transactions" on public.pos_transactions for insert with check (true);
  create policy "Allow all update on pos_transactions" on public.pos_transactions for update using (true) with check (true);
  create policy "Allow all delete on pos_transactions" on public.pos_transactions for delete using (true);

  create policy "Allow all select on lignes_transaction" on public.lignes_transaction for select using (true);
  create policy "Allow all insert on lignes_transaction" on public.lignes_transaction for insert with check (true);
  create policy "Allow all update on lignes_transaction" on public.lignes_transaction for update using (true) with check (true);
  create policy "Allow all delete on lignes_transaction" on public.lignes_transaction for delete using (true);

  create policy "Allow all select on mouvements_stock" on public.mouvements_stock for select using (true);
  create policy "Allow all insert on mouvements_stock" on public.mouvements_stock for insert with check (true);
  create policy "Allow all update on mouvements_stock" on public.mouvements_stock for update using (true) with check (true);
  create policy "Allow all delete on mouvements_stock" on public.mouvements_stock for delete using (true);

  create policy "Allow all select on paiements" on public.paiements for select using (true);
  create policy "Allow all insert on paiements" on public.paiements for insert with check (true);
  create policy "Allow all update on paiements" on public.paiements for update using (true) with check (true);
  create policy "Allow all delete on paiements" on public.paiements for delete using (true);
end $$;

do $$
begin
  if to_regclass('public.clients') is null then
    return;
  end if;
  drop policy if exists "rls27_clients_vendeur_select" on public.clients;
end $$;

drop view if exists public.bandes_pos;

drop table if exists public.cloture_caisse;

do $$
begin
  if to_regclass('public.clients') is null then
    raise notice '0027 rollback: clients absente - vue v_client_soldes non recreee.';
    return;
  end if;

  create or replace view public.v_client_soldes as
  select
    c.client_id,
    c.nom,
    coalesce(f.total_facture_fcfa, 0)                                   as total_facture_fcfa,
    coalesce(p.total_paye_fcfa, 0)                                      as total_paye_fcfa,
    coalesce(f.total_facture_fcfa, 0) - coalesce(p.total_paye_fcfa, 0)  as solde_fcfa
  from clients c
  left join (
    select client_id, sum(montant_total_fcfa) as total_facture_fcfa
    from commandes
    where statut = 'livree' and client_id is not null
    group by client_id
  ) f on f.client_id = c.client_id
  left join (
    select client_id, sum(montant_fcfa) as total_paye_fcfa
    from paiements
    where sens = 'encaissement' and statut = 'confirme' and client_id is not null
    group by client_id
  ) p on p.client_id = c.client_id;
end $$;

do $$
begin
  if to_regclass('public.pos_transactions') is null then
    return;
  end if;

  alter table public.pos_transactions drop column if exists bande_id;
  alter table public.lignes_transaction drop column if exists prix_unitaire_fcfa;
  alter table public.lignes_transaction drop column if exists unite;
  alter table public.lignes_transaction drop column if exists quantite;
end $$;
