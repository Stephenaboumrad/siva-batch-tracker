-- ============================================================
-- Migration 0020 - Seed du programme previsionnel type "ferme" (Cobb 500)
-- ------------------------------------------------------------
-- Charge le programme reel transmis par le veterinaire (Dr Doua T. Privat
-- Camille, Complexe Veterinaire CI, N ONVCI 168, signe le 01/07/2026) :
--   - VACCINATIONS -> protocole_vaccinal (0017)
--   - TRAITEMENTS / actes de soutien -> protocole_traitements (0018)
-- Les deux restent des PLANS DE REFERENCE editables (le manager peut modifier /
-- desactiver chaque ligne dans l'app). Le seed ne fait qu'amorcer le contenu.
--
-- CONVENTION DE JOUR : l'app compte l'age avec J1 = mise en place (comme cycleDay,
-- date prevue = date_entree + jour_cible - 1). Le programme veto est ecrit en
-- J0 = mise en place. On TRADUIT donc chaque jour veto (+1) dans jour_cible pour
-- que les dates calculees soient exactes. Chaque ligne porte en note son jour
-- veto d'origine, pour relecture. Fenetre "J3-5" du veto : jour_cible = 4,
-- jour_max = 6 (bornes traduites de J3 et J5).
--
-- ACTES DE SOUTIEN vs VACCINS : les hepatoprotecteurs / vitamines / anticoccidiens
-- / diuretiques / acides organiques NE SONT PAS des vaccins -> ils vont dans
-- protocole_traitements, jamais dans le carnet de vaccination.
--
-- AUCUNE VALEUR MEDICALE FIGEE COTE APP : les delais d'attente ne sont PAS seedes
-- (ils dependent du produit reel et se saisissent A L'EXECUTION, par bande, dans
-- le registre traitements). L'anticoccidien Toltrazuril est une SUGGESTION
-- (modifiable), pas une obligation.
--
-- Idempotent : insert ... on conflict (id metier) do nothing -> rejouer le seed
-- ne cree aucun doublon et n'ecrase aucune modification manuelle. Garde de
-- dependance LOUD (raise) si 0017/0018/0019 non appliques, pour ne PAS rejouer le
-- silence de 0004. ASCII uniquement (apostrophes doublees), pas de commentaire en
-- fin de ligne d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0020_rollback.sql.
-- ============================================================

-- -- 0) Garde de dependance : tables + colonnes prerequises (echec explicite) --
do $$
begin
  if to_regclass('public.protocole_vaccinal') is null then
    raise exception '0020: protocole_vaccinal absente (executer 0017 d abord).';
  end if;
  if to_regclass('public.protocole_traitements') is null then
    raise exception '0020: protocole_traitements absente (executer 0018 d abord).';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'protocole_vaccinal'
      and column_name = 'jour_max'
  ) then
    raise exception '0020: colonne protocole_vaccinal.jour_max absente (executer 0019 d abord).';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'protocole_vaccinal'
      and column_name = 'origine'
  ) then
    raise exception '0020: colonne protocole_vaccinal.origine absente (executer 0019 d abord).';
  end if;
end $$;

-- -- 1) VACCINATIONS (programme ferme Cobb 500) -> protocole_vaccinal --
--    jour_cible = jour veto + 1 (J1 = mise en place). ordre par jour croissant.
insert into protocole_vaccinal (proto_id, nom_vaccin, jour_cible, jour_max, voie, note, ordre, actif, origine) values
  ('pv-ferme-j0-nd-h9',        'Vaccin inactive ND +/- H9',                1, null, 'SC (injection)',                'Vet J0 (mise en place). Rappel : non.',        10, true, 'ferme'),
  ('pv-ferme-j3-5-hb1-h120',   'HB1 + H120 (ou bivalent + IB variante)',   4, 6,    'Nebulisation ou eau de boisson', 'Vet J3-5 (fenetre). jour_cible=J4, jour_max=J6.', 20, true, 'ferme'),
  ('pv-ferme-j7-gumboro',      'Gumboro intermediaire',                    8, null, 'Eau de boisson',                'Vet J7.',                                      30, true, 'ferme'),
  ('pv-ferme-j12-lasota',      'La Sota',                                 13, null, 'Nebulisation ou eau de boisson', 'Vet J12.',                                    40, true, 'ferme'),
  ('pv-ferme-j14-gumboro-plus','Gumboro intermediaire plus',              15, null, 'Eau de boisson',                'Vet J14.',                                     50, true, 'ferme'),
  ('pv-ferme-j21-lasota',      'La Sota',                                 22, null, 'Nebulisation ou eau de boisson', 'Vet J21.',                                    60, true, 'ferme')
on conflict (proto_id) do nothing;

-- -- 2) TRAITEMENTS / actes de soutien -> protocole_traitements --
--    Aucun delai d'attente seede (a saisir a l'execution, par produit reel).
insert into protocole_traitements (proto_trait_id, nom_produit, molecule, type_acte, jour_cible, jour_max, voie, duree_jours, conditionnel, note, ordre, actif, origine) values
  ('pt-ferme-j0-hepato',       'Hepatoprotecteur ou Vitamine C', null,        'hepatoprotecteur',  1, null, 'Eau de boisson', 1,    false, 'Vet J0. NB veto : hepatoprotecteur a chaque transition alimentaire et apres chaque anticoccidien (rappel, non automatise).', 10, true, 'ferme'),
  ('pt-ferme-j1-vitamine',     'Vitamine',                       null,        'vitamine',          2, null, 'Eau de boisson', 3,    false, 'Vet J1.',                                                                          20, true, 'ferme'),
  ('pt-ferme-j18-anticoc',     'Anticoccidien (Toltrazuril)',    'Toltrazuril','anticoccidien',    19, null, 'Eau de boisson', 3,    true,  'Vet J18. A appliquer si pas deja present dans l''aliment. Toltrazuril = suggestion recommandee (modifiable).', 30, true, 'ferme'),
  ('pt-ferme-j21-diuretique',  'Diuretique',                     null,        'diuretique',       22, null, 'Eau de boisson', 5,    false, 'Vet J21.',                                                                         40, true, 'ferme'),
  ('pt-ferme-acide-organique', 'Acide organique',                null,        'acide_organique',   1, null, 'Eau de boisson', null, true,  'Conditionnel : appliquer si necessaire (aucun jour planifie).',                    50, true, 'ferme')
on conflict (proto_trait_id) do nothing;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) :
-- ------------------------------------------------------------
--   select proto_id, nom_vaccin, jour_cible, jour_max, voie, origine
--     from protocole_vaccinal where proto_id like 'pv-ferme-%' order by ordre;
--   -- attendu : 6 lignes (dont j3-5 avec jour_max = 6).
--
--   select proto_trait_id, nom_produit, type_acte, jour_cible, duree_jours, conditionnel
--     from protocole_traitements where proto_trait_id like 'pt-ferme-%' order by ordre;
--   -- attendu : 5 lignes (anticoccidien + acide organique en conditionnel = true).
-- ============================================================
