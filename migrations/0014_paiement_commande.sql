-- ============================================================
-- Migration 0014 - Suivi du paiement par commande (audit #4 / PR-A)
-- ------------------------------------------------------------
-- Modele : UN paiement par commande (pas de paiement partiel). On ajoute le
-- statut de paiement directement sur commandes (PAS la table paiements du POS
-- 0002, dormante / multi-paiements). STRICTEMENT ADDITIF : aucune colonne
-- existante supprimee ni renommee, place_order / montant_total_fcfa / calcul CA
-- tresorerie (#52) NON touches. Les commandes existantes prennent statut_paiement
-- 'impaye' par defaut.
--
-- Colonnes ajoutees a commandes :
--   statut_paiement text not null default 'impaye'  (valeurs : impaye | paye)
--   date_paiement   timestamptz null                (date d'encaissement si paye)
--   mode_paiement   text null                        (especes|mobile_money|virement|cheque|carte)
--
-- Ecriture du paiement = RPC mark_commande_paiement (SECURITY DEFINER), reservee
-- au role manager (controle app_metadata.role, comme place_order pour 'client').
--
-- GARDE-FOU DE NIVEAU BASE : aujourd'hui commandes est modifiable par manager ET
-- chef_bande via la policy rls7_internal_all. La RLS Postgres ne sait pas
-- restreindre l'ecriture d'UNE colonne par role (row-level, pas column-level ;
-- WITH CHECK ne compare pas OLD/NEW ; un GRANT colonne ne distingue pas manager
-- de chef_bande car les deux sont le meme role Postgres 'authenticated'). Sans
-- garde, un chef_bande pourrait contourner la RPC par un UPDATE direct via
-- l'API. On ajoute donc un trigger BEFORE UPDATE qui, UNIQUEMENT si une colonne
-- de paiement change, rejette tout role JWT != manager. Les autres updates
-- (ex: statut soumise->livree) ne sont pas impactes. Les contextes sans JWT
-- (migration, SQL Editor, service_role, cron) restent autorises.
--
-- Idempotent, to_regclass / IF NOT EXISTS / create or replace guarde. ASCII
-- uniquement, pas de commentaire en fin de ligne d'instruction, pas de
-- point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0014_rollback.sql.
-- ============================================================

-- 1) Colonnes de paiement sur commandes (additif, idempotent)
do $$
begin
  if to_regclass('public.commandes') is null then
    raise notice '0014: table commandes absente - migration ignoree.';
    return;
  end if;

  alter table public.commandes add column if not exists statut_paiement text not null default 'impaye';
  alter table public.commandes add column if not exists date_paiement   timestamptz;
  alter table public.commandes add column if not exists mode_paiement    text;

  if not exists (
    select 1 from pg_constraint
    where conname = 'commandes_statut_paiement_chk'
      and conrelid = 'public.commandes'::regclass
  ) then
    alter table public.commandes
      add constraint commandes_statut_paiement_chk
      check (statut_paiement in ('impaye','paye'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'commandes_mode_paiement_chk'
      and conrelid = 'public.commandes'::regclass
  ) then
    alter table public.commandes
      add constraint commandes_mode_paiement_chk
      check (mode_paiement is null or mode_paiement in ('especes','mobile_money','virement','cheque','carte'));
  end if;
end $$;

-- 2) RPC manager-only : marque (ou annule) le paiement d'une commande
create or replace function public.mark_commande_paiement(
  p_commande_id     text,
  p_statut_paiement text,
  p_date_paiement   timestamptz default null,
  p_mode_paiement   text        default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := auth.jwt() -> 'app_metadata' ->> 'role';
begin
  -- Autorisation : managers uniquement (defense en profondeur cote serveur)
  if v_role is distinct from 'manager' then
    raise exception 'mark_commande_paiement: acces reserve au manager' using errcode = '42501';
  end if;

  if p_statut_paiement not in ('impaye','paye') then
    raise exception 'mark_commande_paiement: statut_paiement invalide (impaye|paye)' using errcode = '22023';
  end if;

  if p_mode_paiement is not null
     and p_mode_paiement not in ('especes','mobile_money','virement','cheque','carte') then
    raise exception 'mark_commande_paiement: mode_paiement invalide' using errcode = '22023';
  end if;

  -- Normalisation : date et mode ne sont conserves que si paye
  update public.commandes
     set statut_paiement = p_statut_paiement,
         date_paiement   = case when p_statut_paiement = 'paye'
                                then coalesce(p_date_paiement, now()) else null end,
         mode_paiement   = case when p_statut_paiement = 'paye'
                                then p_mode_paiement else null end
   where commande_id = p_commande_id;

  if not found then
    raise exception 'mark_commande_paiement: commande introuvable : %', p_commande_id using errcode = 'P0002';
  end if;
end;
$$;

revoke all     on function public.mark_commande_paiement(text, text, timestamptz, text) from public;
revoke all     on function public.mark_commande_paiement(text, text, timestamptz, text) from anon;
grant  execute on function public.mark_commande_paiement(text, text, timestamptz, text) to authenticated;

-- 3) Garde-fou : seul un manager (ou un contexte sans JWT) peut modifier les
--    colonnes de paiement par un UPDATE direct (ferme le contournement de la RPC)
create or replace function public.trg_commandes_paiement_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_role text;
begin
  if (new.statut_paiement is distinct from old.statut_paiement)
     or (new.date_paiement is distinct from old.date_paiement)
     or (new.mode_paiement is distinct from old.mode_paiement) then
    v_role := auth.jwt() -> 'app_metadata' ->> 'role';
    if v_role is not null and v_role <> 'manager' then
      raise exception 'paiement reserve au manager (utiliser mark_commande_paiement)'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists commandes_paiement_guard on public.commandes;
create trigger commandes_paiement_guard
  before update on public.commandes
  for each row
  execute function public.trg_commandes_paiement_guard();
