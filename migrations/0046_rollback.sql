-- ============================================================
-- Rollback 0046 - retire absences/avances, les colonnes ajoutees et
-- restaure les policies pointages employe de 0045
-- ------------------------------------------------------------
-- ATTENTION : DETRUIT les donnees absences/avances, la valeur des
-- colonnes employes.matricule / employes.numero_cnps et la trace
-- pointages.corrige_par / corrige_le.
-- Restaure rls45_pointages_insert_employe / rls45_pointages_update_
-- employe EXACTEMENT comme 0045 les ecrivait (le drop des colonnes de
-- trace rendrait les versions rls46_* invalides).
-- DDL a plat (contrainte editeur 0043+). Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.pointages') is null then
    raise exception '0046_rollback: table pointages absente - incoherent, abort.';
  end if;
  raise notice '0046_rollback: suppression absences/avances + colonnes 0046.';
end $$;

-- 1) Tables du lot (policies et contraintes tombent avec)
drop table if exists public.absences;

drop table if exists public.avances;

-- 2) pointages : retour aux policies 0045 PUIS drop des colonnes de
--    trace (ordre impose : les policies rls46_* referencent ces
--    colonnes ; un drop column d'abord echouerait sur la dependance)
drop policy if exists "rls46_pointages_insert_employe" on public.pointages;

drop policy if exists "rls45_pointages_insert_employe" on public.pointages;

create policy "rls45_pointages_insert_employe" on public.pointages
  for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
    and date_pointage = current_date
    and employe_matricule = upper(coalesce(auth.jwt() -> 'app_metadata' ->> 'matricule', ''))
    and heure_arrivee is not null
    and heure_depart is null
  );

drop policy if exists "rls46_pointages_update_employe" on public.pointages;

drop policy if exists "rls45_pointages_update_employe" on public.pointages;

create policy "rls45_pointages_update_employe" on public.pointages
  for update to authenticated
  using (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and created_by = auth.uid()
    and date_pointage = current_date
  )
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'employe'
    and heure_depart is not null
    and exists (
      select 1
      from public.pointages prev
      where prev.id = pointages.id
        and prev.employe_matricule is not distinct from pointages.employe_matricule
        and prev.employe_nom       is not distinct from pointages.employe_nom
        and prev.date_pointage     is not distinct from pointages.date_pointage
        and prev.heure_arrivee     is not distinct from pointages.heure_arrivee
        and prev.created_by        is not distinct from pointages.created_by
        and prev.created_at        is not distinct from pointages.created_at
        and prev.heure_depart is null
    )
  );

alter table public.pointages drop column if exists corrige_par;

alter table public.pointages drop column if exists corrige_le;

-- 3) employes : retrait des ajouts 0046
drop index if exists public.employes_matricule_uniq;

alter table public.employes drop column if exists matricule;

alter table public.employes drop column if exists numero_cnps;

-- ============================================================
-- VERIFICATION (executable - NOTICEs)
-- ------------------------------------------------------------
do $$
declare
  p record;
begin
  raise notice '0046_rollback verify: absences absente = % ; avances absente = %',
    (to_regclass('public.absences') is null),
    (to_regclass('public.avances') is null);
  raise notice '0046_rollback verify: employes.matricule absente = % ; pointages.corrige_par absente = %',
    not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='employes' and column_name='matricule'),
    not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='pointages' and column_name='corrige_par');
  raise notice '0046_rollback verify: policies pointages (attendu : 7, toutes rls45_*) :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'pointages'
     order by policyname
  loop
    raise notice '0046_rollback verify:   % | %', p.policyname, p.cmd;
  end loop;
end $$;
