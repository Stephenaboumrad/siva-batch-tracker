-- ============================================================
-- Migration 0013 - Overlays RLS client (SELECT uniquement)
-- ------------------------------------------------------------
-- Trois policies PERMISSIVES en LECTURE SEULE qui s'ajoutent (combinaison OR)
-- a la baseline rls7. Elles ne matchent QUE role = 'client', donc elles
-- n'ouvrent rien aux roles internes ni a anon. Aucune policy d'ecriture pour
-- le client : le SEUL chemin d'ecriture sur les tables de commande reste la
-- RPC place_order (0012, SECURITY DEFINER).
--
--   - commandes        : un client voit SES commandes (client_id = claim).
--   - clients          : un client voit SA fiche (client_id = claim).
--   - lignes_commande  : pas de colonne client_id, donc EXISTS correle sur
--                        commandes (fail-closed : au pire moins de lignes,
--                        jamais plus). commande_id est unique et indexe.
--
-- Rappel RLS : les policies permissives se combinent en OR. rls7_internal_all
-- (manager, chef_bande) et rls7_manager_all restent inchanges. Le WITH CHECK
-- de rls7 exige un role interne, donc tout INSERT/UPDATE/DELETE d'un client est
-- refuse (aucune policy permissive ne matche).
--
-- Idempotent (drop policy if exists avant create), gardes to_regclass. ASCII
-- uniquement, pas de commentaire en fin de ligne d'instruction, pas de
-- point-virgule en commentaire. A EXECUTER MANUELLEMENT dans Supabase SQL
-- Editor. Rollback : 0013_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.commandes') is not null then
    alter table public.commandes enable row level security;
    drop policy if exists "rls_client_commandes_select" on public.commandes;
    create policy "rls_client_commandes_select" on public.commandes
      for select to authenticated
      using (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'client'
        and client_id = (auth.jwt() -> 'app_metadata' ->> 'client_id')
      );
  end if;

  if to_regclass('public.clients') is not null then
    alter table public.clients enable row level security;
    drop policy if exists "rls_client_clients_select" on public.clients;
    create policy "rls_client_clients_select" on public.clients
      for select to authenticated
      using (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'client'
        and client_id = (auth.jwt() -> 'app_metadata' ->> 'client_id')
      );
  end if;

  if to_regclass('public.lignes_commande') is not null then
    alter table public.lignes_commande enable row level security;
    drop policy if exists "rls_client_lignes_select" on public.lignes_commande;
    create policy "rls_client_lignes_select" on public.lignes_commande
      for select to authenticated
      using (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'client'
        and exists (
          select 1 from public.commandes c
          where c.commande_id = lignes_commande.commande_id
            and c.client_id = (auth.jwt() -> 'app_metadata' ->> 'client_id')
        )
      );
  end if;
end $$;
