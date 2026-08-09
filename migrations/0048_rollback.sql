-- ============================================================
-- Rollback 0048 - restaure le SELECT ouvert de 0028 sur parametres
-- ------------------------------------------------------------
-- DECONSEILLE : recree rls28_parametres_select_auth avec qual = true,
-- ce qui ROUVRE la lecture de parametres (vet_params, objectifs_bande)
-- aux roles employe et client. N'utiliser que pour revenir a l'etat
-- 0028 avant de rejouer un 0048 amende.
-- Les policies d'ecriture rls28 manager ne sont pas touchees.
-- DDL a plat (contrainte editeur 0043+). Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.parametres') is null then
    raise exception '0048_rollback: table parametres absente - rien a restaurer.';
  end if;
end $$;

drop policy if exists "rls48_parametres_select" on public.parametres;

drop policy if exists "rls28_parametres_select_auth" on public.parametres;

create policy "rls28_parametres_select_auth" on public.parametres
  for select to authenticated
  using (true);

-- ============================================================
-- VERIFICATION (executable - NOTICEs)
-- ------------------------------------------------------------
do $$
declare
  p record;
begin
  raise notice '0048_rollback verify: policies sur parametres (attendu : 4, SELECT = rls28_parametres_select_auth) :';
  for p in
    select policyname, cmd from pg_policies
     where schemaname = 'public' and tablename = 'parametres'
     order by policyname
  loop
    raise notice '0048_rollback verify:   % | %', p.policyname, p.cmd;
  end loop;
end $$;
