-- ============================================================
-- Rollback 0025 - bandes : batiment + souche
-- ------------------------------------------------------------
-- Supprime les 2 colonnes puis recree la vue bandes_ops sans elles.
-- ORDRE IMPORTANT : la vue reference les colonnes - on la supprime
-- d'abord, on retire les colonnes, puis on la recree (liste dynamique
-- 0008, security_invoker, grants reappliques).
-- PERTE DE DONNEES : les valeurs batiment / souche deja saisies sont
-- perdues. Le front tolere l'absence des colonnes (replis 0025) et
-- retombe sur '-' au rendu : aucun deploiement n'est requis avant ce
-- rollback.
-- Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
declare cols text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0025 rollback: table bandes absente - rien a faire.';
    return;
  end if;

  execute 'drop view if exists public.bandes_ops';

  alter table public.bandes drop column if exists souche;
  alter table public.bandes drop column if exists batiment;

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
  from information_schema.columns
  where table_schema = 'public'
    and table_name   = 'bandes'
    and column_name not in ('prix_poussin_unitaire', 'cout_aliment_kg', 'prix_vente_carcasse_kg');

  execute 'create view public.bandes_ops with (security_invoker = true) as select '
          || cols || ' from public.bandes';

  execute 'revoke all on public.bandes_ops from anon';
  execute 'grant select on public.bandes_ops to authenticated';
end $$;
