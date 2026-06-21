-- ============================================================
-- Migration 0012 - RPC place_order (coeur d'integrite des prix)
-- ------------------------------------------------------------
-- Fonction SECURITY DEFINER, CLIENT UNIQUEMENT. Le portail B2B appelle cette
-- RPC pour creer une commande. Le client ne fournit QUE des lignes
-- { produit_id, quantite_kg }. Il ne fournit NI prix NI client_id.
--
-- Garanties :
--   - client_id derive du JWT (app_metadata.client_id), JAMAIS d'un parametre,
--     donc un client ne peut pas creer la commande d'un autre client.
--   - prix LU COTE SERVEUR depuis produits (disponible vrai). Le client ne peut
--     pas fixer ni influencer le prix. Produit inconnu ou indisponible declenche
--     une exception et annule toute la commande.
--   - nom et prix figes par ligne (snapshot dans description et prix_kg_fcfa).
--   - montant et montant_total recalcules cote serveur.
--   - en-tete ecrite en statut 'soumise', source 'portail_client'.
--   - atomique : une seule transaction, toute exception annule l'ordre entier.
--   - search_path epingle (public, pg_temp) contre le detournement de resolution.
--   - execution refusee a public et anon, accordee a authenticated. Le garde
--     interne role = 'client' restreint l'usage effectif.
--
-- PREREQUIS (verifies avant execution) : tables clients, produits, commandes,
-- lignes_commande presentes (Supabase valide le corps a la creation). Colonne
-- commandes.source presente (migration 0011). Les comptes clients portent
-- app_metadata.role = 'client' et app_metadata.client_id = clients.client_id.
--
-- Idempotent (create or replace). ASCII uniquement, pas de commentaire en fin
-- de ligne d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0012_rollback.sql.
-- ============================================================

create or replace function public.place_order(
  p_items                    jsonb,
  p_date_livraison_souhaitee timestamptz default null,
  p_note                     text        default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role        text := auth.jwt() -> 'app_metadata' ->> 'role';
  v_client_id   text := auth.jwt() -> 'app_metadata' ->> 'client_id';
  v_commande_id text;
  v_total       numeric := 0;
  v_count       int;
  v_item        jsonb;
  v_produit_id  text;
  v_qte         numeric;
  v_nom         text;
  v_prix        numeric;
  v_montant     numeric;
begin
  -- 1) Autorisation : comptes 'client' uniquement, claim client_id obligatoire
  if v_role is distinct from 'client' or v_client_id is null then
    raise exception 'place_order: acces reserve aux comptes client' using errcode = '42501';
  end if;

  -- 2) Le client doit exister et etre actif (defense en profondeur)
  perform 1 from clients where client_id = v_client_id and statut = 'actif';
  if not found then
    raise exception 'place_order: client introuvable ou inactif' using errcode = '42501';
  end if;

  -- 3) Validation de la charge utile
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'place_order: items doit etre un tableau JSON';
  end if;
  v_count := jsonb_array_length(p_items);
  if v_count < 1 or v_count > 100 then
    raise exception 'place_order: nombre de lignes invalide (1 a 100)';
  end if;

  -- 4) En-tete : client_id vient du claim, statut soumise, source portail
  v_commande_id := 'cmd-' || replace(gen_random_uuid()::text, '-', '');
  insert into commandes (commande_id, client_id, date_commande,
                         date_livraison_souhaitee, statut, source, note, montant_total_fcfa)
  values (v_commande_id, v_client_id, now(),
          p_date_livraison_souhaitee, 'soumise', 'portail_client', p_note, 0);

  -- 5) Lignes : prix lu serveur depuis produits, snapshot nom et prix
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_produit_id := v_item ->> 'produit_id';
    if v_produit_id is null then
      raise exception 'place_order: produit_id manquant';
    end if;

    begin
      v_qte := (v_item ->> 'quantite_kg')::numeric;
    exception when others then
      raise exception 'place_order: quantite_kg invalide pour %', v_produit_id;
    end;
    if v_qte is null or v_qte <= 0 or v_qte > 100000 then
      raise exception 'place_order: quantite_kg hors bornes pour %', v_produit_id;
    end if;

    select nom, prix_base_kg_fcfa into v_nom, v_prix
      from produits
     where produit_id = v_produit_id and disponible = true;
    if not found then
      raise exception 'place_order: produit indisponible ou inconnu : %', v_produit_id;
    end if;

    v_montant := round(v_qte * v_prix);
    v_total   := v_total + v_montant;

    insert into lignes_commande (ligne_id, commande_id, produit_id, produit,
                                 description, quantite_kg, prix_kg_fcfa, montant_fcfa)
    values ('lig-' || replace(gen_random_uuid()::text, '-', ''),
            v_commande_id, v_produit_id, null,
            v_nom, v_qte, v_prix, v_montant);
  end loop;

  -- 6) Total recalcule serveur
  update commandes set montant_total_fcfa = v_total where commande_id = v_commande_id;

  return v_commande_id;
end;
$$;

revoke all     on function public.place_order(jsonb, timestamptz, text) from public;
revoke all     on function public.place_order(jsonb, timestamptz, text) from anon;
grant  execute on function public.place_order(jsonb, timestamptz, text) to authenticated;
