-- ============================================================
-- Migration 0028 - Table parametres : standard commun (cle/valeur)
-- ------------------------------------------------------------
-- Les seuils d'alerte mortalite et la config partagee vivaient dans le
-- localStorage (par appareil). Le travail standardise exige un standard
-- COMMUN, pas par appareil : cette table cle/valeur (jsonb) devient la
-- source de verite, lue par tous les utilisateurs authentifies, ecrite
-- par le manager seul. Le front (index.html) garde ses defauts
-- localStorage en repli tant que la table n'existe pas - rien ne casse
-- avant application, le localStorage n'est ensuite qu'un cache de
-- relecture.
--
-- MODELE DE ROLES : auth.jwt() -> 'app_metadata' ->> 'role' (convention
-- 0007/0021/0027). anon : aucune policy + revoke = aucun acces.
--
-- CLES UTILISEES PAR LE FRONT (extensible sans nouvelle migration) :
--   - 'vet_params' : objet jsonb {mortDaily, mortCumul, videSanitaire,
--     anticoccidien, vetNom, vetOnvci, vetStructure} - seuils d'alerte
--     mortalite et reglages sanitaires partages.
--
-- Idempotent : create table if not exists + to_regclass + drop policy
-- if exists. ASCII uniquement, pas de commentaire en fin de ligne
-- d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0028_rollback.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Table
-- ------------------------------------------------------------
create table if not exists public.parametres (
  key        text        primary key,
  value      jsonb,
  updated_at timestamptz default now(),
  updated_by uuid
);

-- ------------------------------------------------------------
-- 2) RLS par verbe (style 0021/0027) : lecture authentifiee,
--    ecriture manager uniquement
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.parametres') is null then
    raise notice '0028: table parametres absente - section 2 (RLS) ignoree.';
    return;
  end if;

  alter table public.parametres enable row level security;

  revoke all on public.parametres from anon;
  grant select, insert, update, delete on public.parametres to authenticated;

  drop policy if exists "rls28_parametres_select_auth" on public.parametres;
  create policy "rls28_parametres_select_auth" on public.parametres
    for select to authenticated
    using (true);

  drop policy if exists "rls28_parametres_manager_insert" on public.parametres;
  create policy "rls28_parametres_manager_insert" on public.parametres
    for insert to authenticated
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  drop policy if exists "rls28_parametres_manager_update" on public.parametres;
  create policy "rls28_parametres_manager_update" on public.parametres
    for update to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
    with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

  drop policy if exists "rls28_parametres_manager_delete" on public.parametres;
  create policy "rls28_parametres_manager_delete" on public.parametres
    for delete to authenticated
    using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Table presente :
--   select to_regclass('public.parametres');
--   -- attendu : public.parametres (non null).
--
-- 2. Colonnes :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public' and table_name = 'parametres'
--    order by ordinal_position;
--   -- attendu : key text, value jsonb, updated_at timestamptz, updated_by uuid.
--
-- 3. RLS activee :
--   select relrowsecurity from pg_class where oid = 'public.parametres'::regclass;
--   -- attendu : true.
--
-- 4. Policies (attendu : exactement 4 lignes, toutes rls28_*) :
--   select policyname, cmd, roles, qual, with_check from pg_policies
--    where schemaname = 'public' and tablename = 'parametres'
--    order by policyname;
--   -- attendu :
--   --   rls28_parametres_manager_delete | DELETE | {authenticated} | qual role manager
--   --   rls28_parametres_manager_insert | INSERT | {authenticated} | with_check role manager
--   --   rls28_parametres_manager_update | UPDATE | {authenticated} | qual + with_check role manager
--   --   rls28_parametres_select_auth    | SELECT | {authenticated} | qual true
--
-- 5. anon sans acces (attendu : 0 ligne) :
--   select grantee, privilege_type from information_schema.role_table_grants
--    where table_schema = 'public' and table_name = 'parametres' and grantee = 'anon';
-- ============================================================
