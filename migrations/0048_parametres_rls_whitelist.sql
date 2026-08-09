-- ============================================================
-- Migration 0048 - parametres : whitelist de roles sur le SELECT
-- ------------------------------------------------------------
-- CONSTAT (audits RH + B2B) : rls28_parametres_select_auth a qual = true
-- - TOUT role authentifie lit parametres, y compris employe (RH-1) et
-- client (portail B2B). Contenu expose : vet_params (coordonnees du
-- veterinaire, seuils de mortalite, protocole anticoccidien) et
-- objectifs_bande (cibles de production) - donnees INTERNES.
--
-- SONDE (chemins de lecture reels, verifies dans les trois surfaces) :
--   index.html   : getAll -> select parametres (sessions manager et
--                  chef_bande uniquement - employe court-circuite avant
--                  init(), vendeur est redirige vers caisse.html,
--                  client n'entre jamais dans index.html) ; lectures
--                  d'affichage via STATE (vet_params, objectifs_bande,
--                  rccm/ncc factures) pour manager ET chef_bande.
--   caisse.html  : select parametres WHERE key in ('rccm','ncc') -
--                  identite legale du pied de recu, SESSION VENDEUR.
--   portail.html : AUCUNE lecture de parametres.
--   ecran employe (index.html) : AUCUNE lecture (pointages + employes
--                  .poste seulement).
--
-- LISTE FINALE (justifiee par la sonde) :
--   - manager     : plein SELECT (source de verite des standards).
--   - chef_bande  : plein SELECT (seuils vet/mortalite et objectifs
--                   affiches sur ses ecrans ; repli localStorage sinon).
--   - vendeur     : SELECT restreint aux cles 'rccm' et 'ncc' (pied de
--                   recu) - moindre privilege : un vendeur n'a aucune
--                   raison de lire vet_params/objectifs_bande. Toute
--                   FUTURE cle de recu (mentions legales etc.) devra
--                   etre AJOUTEE a cette liste de cles - sinon le recu
--                   la verra vide (comportement deja tolere par la
--                   caisse : cles absentes = champs vides).
--   - employe, client : EXCLUS - aucun chemin de lecture, aucune
--                   scission de table necessaire.
--
-- Ecritures : rls28_parametres_manager_insert / _update / _delete
-- INTOUCHEES (manager-only depuis 0028).
--
-- _ops NOTE (dit explicitement) : parametres n'est PAS une table _ops
-- de 0040 section 1 - aucun rejeu de vues n'est requis.
--
-- PREREQUIS DUR : public.parametres doit exister (0028 executee -
-- confirme par le constat lui-meme : la policy 0028 est en base).
--
-- FORM : DDL a plat (precedent 0043+ - l'editeur SQL Supabase rejette
-- create policy dans do $$). Un collage = une transaction implicite ;
-- l'abort de la section 0 saute tout.
--
-- Idempotent : drop policy if exists + create. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- Rollback : 0048_rollback.sql (restaure le SELECT qual = true de 0028
-- - DECONSEILLE, il rouvre la lecture a employe/client).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Prerequis dur + etat AVANT (NOTICEs)
-- ------------------------------------------------------------
do $$
declare
  p record;
begin
  if to_regclass('public.parametres') is null then
    raise exception '0048: table parametres absente (0028 non executee ?) - abort.';
  end if;
  raise notice '0048 pre-state: policies actuelles sur public.parametres :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'parametres'
     order by policyname
  loop
    raise notice '0048 pre-state:   % | %', p.policyname, p.cmd;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 1) Remplacement du SELECT ouvert par la whitelist
-- ------------------------------------------------------------
drop policy if exists "rls28_parametres_select_auth" on public.parametres;

drop policy if exists "rls48_parametres_select" on public.parametres;

create policy "rls48_parametres_select" on public.parametres
  for select to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'chef_bande')
    or (
      (auth.jwt() -> 'app_metadata' ->> 'role') = 'vendeur'
      and key in ('rccm', 'ncc')
    )
  );

-- ============================================================
-- VERIFICATION (executable - NOTICEs, catalogues en lecture seule)
-- ------------------------------------------------------------
do $$
declare
  p record;
  n integer := 0;
  v_sel integer := 0;
begin
  raise notice '0048 verify: policies resultantes sur public.parametres :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'parametres'
     order by policyname
  loop
    n := n + 1;
    if p.cmd = 'SELECT' then v_sel := v_sel + 1; end if;
    raise notice '0048 verify:   % | %', p.policyname, p.cmd;
  end loop;
  if n = 4 and v_sel = 1
     and exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'parametres'
                    and policyname = 'rls48_parametres_select') then
    raise notice '0048 verify: OK - 1 SELECT rls48 + 3 ecritures rls28 manager.';
  else
    raise notice '0048 verify: ATTENTION - etat inattendu (% policies, % SELECT). Relire la liste.', n, v_sel;
  end if;
end $$;

-- ------------------------------------------------------------
-- Sondes fonctionnelles (console - discipline RLS : certifier
-- l'identite de session AVANT, un role par profil Chrome/incognito ;
-- cible confirmee : la table contient des lignes, verifiable en manager) :
--   const s = await sb.auth.getSession();
--   console.log(s.data.session.user.email, s.data.session.user.app_metadata);
--
-- Acceptation (tests annonces par Stephen) :
--   a) session employe (SIVA-010) :
--     sb.from('parametres').select('*')
--     -- attendu : data [] (0 ligne, sans erreur - le grant SELECT reste,
--     -- c'est la policy qui filtre)
--   b) session client (client-test) :
--     sb.from('parametres').select('*')
--     -- attendu : data []
--   c) session vendeur (caisse) :
--     sb.from('parametres').select('key, value')
--     -- attendu : UNIQUEMENT rccm et ncc (le pied de recu continue de
--     -- fonctionner) ; vet_params/objectifs_bande ABSENTS
--   d) sessions manager et chef_bande : ecrans lisant les standards
--      (Parametres, seuils vet, objectifs DMAICS, alertes mortalite)
--      inchanges - select complet.
-- ============================================================
