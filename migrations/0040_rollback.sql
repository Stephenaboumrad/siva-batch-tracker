-- ============================================================
-- Rollback 0040 - restaure l'etat pre-barriere (chef relit les tables,
--                 colonnes financieres comprises)
-- ------------------------------------------------------------
-- ATTENTION : ceci ROUVRE la fuite #142 (les colonnes de prix/cout
-- redeviennent servies au chef_bande par l'API). A n'executer que si
-- la barriere casse un flux imprevu, le temps du diagnostic.
--
-- Restaure : SELECT roles internes sur les 6 tables 0021 ;
-- rls7_internal_all sur commandes / lignes_commande / clients ;
-- bandes_ops en version security_invoker (0008) ; bandes_pos sans gate
-- de role (0027 section 5) ; droppe les 8 autres vues _ops.
-- Idempotent.
-- ============================================================

-- 1) Drop des vues _ops (bandes_ops traitee en 3)
do $$
declare
  t text;
begin
  foreach t in array array['intrants','receptions','abattages','aliments_phases',
                           'formulations_mp','commandes','lignes_commande','clients'] loop
    execute format('drop view if exists public.%I', t || '_ops');
  end loop;
end $$;

-- 2) Policies : retour a l'etat 0021 / 0007
do $$
declare
  t text;
begin
  foreach t in array array['bandes','intrants','receptions','abattages',
                           'aliments_phases','formulations_mp'] loop
    if to_regclass(format('public.%I', t)) is null then
      continue;
    end if;
    execute format('drop policy if exists "rls40_%s_select" on public.%I', t, t);
    execute format('drop policy if exists "rls21_%s_select" on public.%I', t, t);
    execute format(
      'create policy "rls21_%s_select" on public.%I for select to authenticated '
      'using ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t, t);
  end loop;

  foreach t in array array['commandes','lignes_commande','clients'] loop
    if to_regclass(format('public.%I', t)) is null then
      continue;
    end if;
    execute format('drop policy if exists "rls40_%s_all" on public.%I', t, t);
    execute format('drop policy if exists "rls7_internal_all" on public.%I', t);
    execute format(
      'create policy "rls7_internal_all" on public.%I for all to authenticated '
      'using      ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande'')) '
      'with check ((auth.jwt() -> ''app_metadata'' ->> ''role'') in (''manager'',''chef_bande''))', t, t);
  end loop;
end $$;

-- 3) bandes_ops : retour a la version security_invoker (copie 0008)
do $$
declare cols text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0040 rollback: table bandes absente - bandes_ops non recreee.';
    return;
  end if;

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
  from information_schema.columns
  where table_schema = 'public'
    and table_name   = 'bandes'
    and column_name not in ('prix_poussin_unitaire', 'cout_aliment_kg', 'prix_vente_carcasse_kg');

  execute 'drop view if exists public.bandes_ops';
  execute 'create view public.bandes_ops with (security_invoker = true) as select '
          || cols || ' from public.bandes';
  execute 'revoke all on public.bandes_ops from anon';
  execute 'grant select on public.bandes_ops to authenticated';
end $$;

-- 4) bandes_pos : retour a la version 0027 (sans gate de role)
do $$
declare filtre text;
begin
  if to_regclass('public.bandes') is null then
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

-- VERIFICATION (attendu) :
-- 1. Vues _ops restantes : uniquement bandes_ops (invoker) :
--   select table_name from information_schema.views
--    where table_schema = 'public' and table_name like '%\_ops' escape '\';
-- 2. Simulation chef : select count(*) from bandes / intrants / commandes
--    repond a nouveau (> 0 si donnees).
-- ============================================================
