-- ============================================================
-- Migration 0047 - RH lot 3 : trace de remboursement des avances
-- ------------------------------------------------------------
-- SCOPE (lot RH-3, paie) : quand une paie est validee, le manager peut
-- marquer des avances comme retenues sur cette paie. Le drapeau
-- rembourse (0046) existe deja ; il lui manque la TRACE :
--   - rembourse_le       timestamptz : quand le remboursement a ete
--                        enregistre.
--   - rembourse_paie_ref text : la fiche de paie porteuse de la
--                        retenue. Reference le paie_id de public.paies
--                        (identifiant texte genere cote client
--                        'paie-<uuid>' - c'est l'idField du front).
--                        Colonne texte SANS contrainte FK, a dessein :
--                        une paie supprimee ne doit pas casser
--                        l'historique de l'avance - reference souple,
--                        meme motif que pointages.employe_matricule.
--
-- RLS : AUCUN changement. rls46_avances_manager_all (FOR ALL manager)
-- couvre automatiquement les nouvelles colonnes - la RLS filtre des
-- lignes, pas des colonnes. paies / employes restent manager-only
-- (rls7_manager_all, 0007) ; avances manager-only (0046). Rien n'est
-- affaibli ni ajoute.
--
-- _ops NOTE (dit explicitement) : avances n'est PAS une table _ops de
-- 0040 section 1 - aucun rejeu de vues n'est requis.
--
-- PREREQUIS DUR : public.avances doit exister (0046 executee). Abort
-- bruyant sinon.
--
-- FRONT : le front retente sans les colonnes de trace si cette
-- migration n'est pas encore appliquee (toast explicite) - deploiement
-- Railway avant SQL = degradation propre, sans perte du drapeau
-- rembourse.
--
-- FORM : DDL a plat (precedent 0043+). Idempotent : add column if not
-- exists. ASCII uniquement. A EXECUTER MANUELLEMENT dans le SQL Editor.
-- Rollback : 0047_rollback.sql (perd la trace, pas le drapeau).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Prerequis dur
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.avances') is null then
    raise exception '0047: table avances absente (0046 non executee ?) - abort.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Colonnes de trace
-- ------------------------------------------------------------
alter table public.avances add column if not exists rembourse_le timestamptz;

alter table public.avances add column if not exists rembourse_paie_ref text;

-- ============================================================
-- VERIFICATION (executable - NOTICEs, catalogues en lecture seule)
-- ------------------------------------------------------------
do $$
declare
  p record;
  n integer := 0;
begin
  raise notice '0047 verify: avances.rembourse_le = % ; avances.rembourse_paie_ref = %',
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='avances' and column_name='rembourse_le'),
    exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='avances' and column_name='rembourse_paie_ref');
  raise notice '0047 verify: policies avances (attendu : 1 seule, rls46_avances_manager_all | ALL) :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'avances'
     order by policyname
  loop
    n := n + 1;
    raise notice '0047 verify:   % | %', p.policyname, p.cmd;
  end loop;
  if n = 0 then
    raise notice '0047 verify:   ATTENTION - aucune policy sur avances.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Sonde fonctionnelle (console, session MANAGER certifiee getSession) :
--   sb.from('avances').update({rembourse:true,
--     rembourse_le:new Date().toISOString(),
--     rembourse_paie_ref:'paie-test-0047'}).eq('id','<ID>').select()
--   -- attendu : 1 ligne avec les trois champs poses.
--   Puis remettre : sb.from('avances').update({rembourse:false,
--     rembourse_le:null, rembourse_paie_ref:null}).eq('id','<ID>').select()
-- Session employe : sb.from('avances').select('*') -- attendu : 0 ligne.
-- ============================================================
