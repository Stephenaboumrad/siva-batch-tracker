# CLAUDE.md — SIVA Batch Tracker

Broiler poultry farm management app (brand: Coqorico), Azaguié, Côte d'Ivoire.
Single-file vanilla JS surfaces + Supabase (PostgreSQL). These are the standing
working rules for every task in this repository.

## Hard rules

- **NEVER merge a PR.** Merging is done by Stephen alone, in the GitHub UI.
  A numbered plan, a checklist, or a suggested order of steps is NOT an
  instruction to merge.
- **NEVER execute SQL.** Migrations are delivered as files only; Stephen runs
  them manually in the Supabase SQL Editor.
- **NEVER commit directly to main.** Always a branch + a PR.
- **A migration that has been EXECUTED is immutable** — ship a new additive
  one. A migration that is merged but NOT yet executed may still be amended
  in place. Merge status and execution status are different things.
- **Before writing a migration, list `migrations/` and use the next free
  number.** Never assume the number (scoping notes can be stale).
- **NEVER execute `scripts/reset_transactional_data.sql` after J0** (first
  real batch placed). It wipes every transactional table. There is exactly
  ONE legitimate final run, right before J0, with the GO-LIVE guard at the
  top of the script ARMED (set the `go_live` constant to the real placement
  date — an armed guard aborts the whole transaction if any bande has
  `date_entree >= go_live`). Revision 3 (2026-08-11) folds in Stephen's
  arbitration — these four decisions are FINAL, do not reopen them:
  (1) `clients` KEPT as reference (real B2B fiches survive; revision 1
  wiped the table); (2) `clients.solde_fcfa` zeroing is MANDATORY in the
  standard flow, with a per-client NOTICE audit trail of old balances;
  (3) `stocks` and `intrants` are FULLY PURGED (no quantite=0 variant) —
  `aliments_phases`/`formulations_mp` purged too (per-bande); (4) the
  test fiches employes `SIVA-010` and clients `CLI-TEST-001` are deleted
  as part of the standard flow. Scope: 28 transactional tables wiped
  (children before parents, DELETE only, never TRUNCATE CASCADE), 13
  reference tables kept. The pre-J0 procedure includes an "inventaire
  d'ouverture" step: right after the reset and before the chicks arrive,
  the real physical stock (feed, vet products, consumables) is counted
  and entered FRESH so cycle 1 starts on true dated stock rows.
  `auth.users` cannot be touched by SQL: the test accounts
  (siva-010@coqorico.internal, the CLI-TEST-001 client account) are
  deleted MANUALLY in the Supabase dashboard after the run.

## Migration conventions

- Guards throughout: `to_regclass`, `if not exists`, `drop policy if exists`.
  A migration must never half-apply: a guarded section that references a
  missing table skips itself cleanly, and a hard prerequisite aborts before
  anything is created.
- Every migration ships a matching `_rollback.sql` and ends with a read-only
  `VERIFICATION` block (expected policy count + functional probes).
- No date-ordering CHECK constraints. Saving must never be blocked by the DB;
  thresholds are UI-level and non-blocking.
- RLS is the real barrier; the UI is defence in depth, never the only guard.
- When a policy must freeze columns against the stored row, use the
  EXISTS-on-stored-row correlation, and use `is not distinct from` for
  nullable columns — a plain `=` evaluates to NULL on `(null, null)` and
  silently rejects every legitimate update.

## Architecture

- Three separate surfaces, **no shared code, no build step**:
  - `index.html` — staff app (manager, chef_bande)
  - `caisse.html` — POS (vendeur role, per-PDV)
  - `portail.html` — B2B client portal (client role)

  Consequence: brand tokens, auth conventions, helpers and offline-queue
  logic are DUPLICATED across the three files. Any change to branding, auth
  or queue behaviour must be applied to all three by hand.
- Supabase (PostgreSQL) backend; Railway auto-deploys on every merge to main.
  The front can therefore ship BEFORE its SQL has been run.
- Roles (in `auth.jwt() -> 'app_metadata' ->> 'role'`): `manager`,
  `chef_bande`, `vendeur`, `client`, `employe`.
  `employe` (RH-1, 0045) has DELIBERATELY EMPTY default access: no nav page,
  no section in `ROLE_VISIBILITY`, no RLS policy on any table except
  `pointages` (own rows). Its only surface is the dedicated time-clock
  screen in `index.html` (`enterSession` short-circuits before `init()`).
  Accounts are created manually in Supabase Auth with app_metadata
  `{role:'employe', matricule, name}`.
- `pointages` (0045, RH-1): one time-clock row per (employe_matricule, day).
  Arrival/departure times are rewritten to `now()` by a BEFORE trigger for
  employe writes — client clock values are never trusted; manager and
  SQL-editor writes keep explicit values (correction path). 0046 added
  `corrige_par uuid` + `corrige_le timestamptz` (manager correction trace;
  frozen for the employe role by the rls46_* insert/update policies that
  superseded the two rls45_* employe policies).
- HR module (RH-2/RH-3, 0046/0047): top-level `rh` page (manager-only) with
  Équipe / Pointages / Absences & Avances / Paie tabs. The `rh` page OWNS
  payroll management (generation, validation, bulletins); Trésorerie →
  RH & Paie is the EXPENSE VIEW only (read-only monthly charges + Dépenses
  RH) and must never regrow management UI. The SINGLE employee fiche editor
  is RH → Équipe (the legacy Trésorerie fiche was removed in RH-3).
  Pay period is the calendar month (`paies.mois` YYYY-MM, unique
  (employe_id, mois) — 0022). Pay bases: journalier = days with a pointage
  carrying heure_arrivee × `taux_journalier_fcfa` (a missing départ flags
  but does not void the day); permanent = `salaire_base_fcfa` + CNPS
  (pointages are presence control only); prestataire = never generated
  (legacy behaviour). The derivation is written into `paies.note`.
  Unjustified absences are surfaced, never auto-deducted. Avances deducted
  on pay validation write `rembourse=true` + trace `rembourse_le` /
  `rembourse_paie_ref` (0047; front retries without the trace columns and
  warns if 0047 is not yet applied). `absences`/`avances` are manager-only
  (rls46 FOR ALL); the employe role has no access. `avances.mode_paiement
  'wave'` carries a manual `reference_wave` (no Wave API).
- Trésorerie page = three tabs: **Vue d'ensemble** (4 KPIs Encaissé/Décaissé/
  Net/Position de caisse + symmetric Encaissements/Décaissements cards +
  historical blocks in collapsed accordions), **Mouvements** (unified
  read-only financial journal over existing tables — B2B paid orders, POS
  payments aggregated per day/PDV, paies of the month at full charge incl.
  CNPS, dépenses RH with their CRUD, réceptions+intrants, clôture écarts
  listed but excluded from totals), **Caisse PDV**. The old "RH & Paie" tab
  is REMOVED (RH-3bis): payroll MANAGEMENT lives in the RH page; payroll
  charges are a TREASURY CATEGORY here. Journal footer totals must always
  reconcile with the Vue d'ensemble KPIs (same formulas by construction) —
  every figure move is presentation-only, never a computation change.
- **`employes` column aliasing (0046 — do NOT add duplicate columns):**
  the canonical columns are the ORIGINAL ones, read by the payroll code:
  `type` (permanent|journalier|prestataire) NOT type_contrat,
  `statut` ('actif'|'inactif') NOT an `actif` boolean,
  `salaire_base_fcfa` NOT salaire_mensuel,
  `taux_journalier_fcfa` NOT taux_journalier,
  `note` NOT notes. 0046 added only `matricule` (nullable, partial unique
  index; THE join key to pointages/absences/avances and to auth accounts'
  `app_metadata.matricule` — never join HR data on `employe_id`) and
  `numero_cnps` (CNPS registration number; `cnps_patronal_pct` is a rate,
  a different thing).
- New tables go into `ALL_TABLES` **and** `OPTIONAL_TABLES` in `index.html`,
  so a front deploy before the SQL is run degrades cleanly (empty lists,
  clean write errors) instead of breaking the whole app.
- Financial columns: use the `canSeeFinance()` / `canSee()` helper pattern
  for any surface that shows money. Revenue figures have leaked into
  unexpected surfaces repeatedly.
- Audit & validation (0049) — TWO separate concepts, never merge them:
  `audit_log` is the APPEND-ONLY audit journal, populated EXCLUSIVELY by the
  SECURITY DEFINER trigger `trg_audit_log` (name `zz_audit_log` so it fires
  LAST, after business triggers) attached to 21 tables. Actor comes from the
  session JWT server-side (console writes of an authenticated session are
  captured identically; no-JWT contexts — SQL editor/service — are logged
  with `acteur_role='sans_jwt'` and NULL `acteur_id`, a deliberate deviation
  so manual ops never crash on audit). UPDATEs store only the changed-column
  diff (`{col:{old,new}}`), no-op updates are skipped; INSERT/DELETE store
  the full snapshot. A deny-list masks password/token-like column values —
  none exist in the schema today, the mechanism is a forward guard.
  SELECT is manager-only; NO write path for any role (no insert/update/
  delete policies + revoked grants — append-only by construction). Pure
  trigger additions change no columns, so the nine 0040 `_ops` views need
  NO replay. Retention: none yet (a pruning migration may come later).
  The VALIDATION QUEUE remains `notifications` (0044) with its server-
  enforced statut flow; its scope is chef_bande declarations ONLY —
  pointage corrections and avances are manager-only (rls45/rls46) hence
  JOURNAL-ONLY: never build approval flows for actions only the manager
  can perform. The bell badge counts pending validations only, never the
  journal; the manager's Historique tab reads `audit_log` (paginated 50,
  period filter server-side — never the full log), the chef's Historique
  keeps his declaration outcomes.

## Conventions

- French UI labels, English code and comments.
- Reuse existing design tokens. No new colours, no new fonts.
- Mascot rule: in-app surfaces are SIVA wordmark ONLY — the mascot never
  appears in the app, with ONE exception (decided 2026-08-09): the employee
  clock-in screen banner (RH-1) MAY carry the mascot with its orange
  pastille, that screen being a formal register surface. Everywhere else
  in-app stays wordmark-only.
- Commercial & Ventes OWNS catalog management (the Catalogue tab, manager-
  only): ONE `produits` catalog feeds BOTH the B2C caisse and the B2B portal
  through `v_catalogue_client` (server-side `disponible = true` filter — do
  not duplicate that filter in any front). The edit modal exposes `unite`
  ("au kg pesé" / "à la pièce") and its price label follows it; the modal
  carries the standing caution (price/unite changes hit both surfaces
  immediately; never rename a product sold in PDV — stock history is
  aggregated by name). Columns deliberately not editable: `id`, `created_at`
  (technical), `produit_id` (generated at creation, immutable join key).
- CANONICAL CROSS-SURFACE PALETTE (index.html tokens, reused verbatim by
  portail.html and caisse.html — "warm cream" does not exist as a token;
  the real shared background IS #F4F6F8): bg `#F4F6F8`, surface `#FFFFFF`,
  borders `#D4DBE2` / subtle `#E6EBEF`, text `#0F1822` / secondary `#4A5663`
  / muted `#8A95A1`, orange ramp 600 `#E2640F` (accent) / 700 `#B84E0A`
  (buttons, AA on white) / 800 `#8F3D08` (hover), success `#0E7C4A`, danger
  `#C8332B`, radii 3/4/6/8px, fonts Inter + JetBrains Mono (+ Orbitron for
  the wordmark). LIGHT CHROME everywhere: white header bars with
  `border-subtle` + shadow `0 2px 12px rgba(11,17,22,0.06)` — the portal's
  dark `#1E2A36` bar is gone; the only remaining dark surfaces are the login
  backdrops (identical on both surfaces by design).
- Portal (portail.html) shell follows the SIVA conventions: header = SIVA
  wordmark (Orbitron 900) + "Portail client B2B" + client name; the mascot
  (orange pastille) appears ONLY on the login lockup and as the default
  product-image placeholder (commercial-brand contexts). Pricing LABEL rule:
  the computation is always qty × price (identical to caisse and the
  place_order RPC) and the label follows `produits.unite` — never display
  "/kg" for a per-piece product. Weight-bracket pricing ("grille tarifaire
  par tranches de poids") is NOT modeled anywhere — flagged for a dedicated
  lot; do not fake it in labels. The short order ref (CMD-XXXXXXXX) is
  DISPLAY-ONLY — stored `commande_id` never changes.
- Verify lucide icon names exist in the pinned bundle (`lucide@1.21.0`)
  before using them — an unknown name renders as an empty box.
- PDV stock is aggregated by `type_produit` (the product NAME) in
  `mouvements_stock`: renaming a product in the catalogue splits its stock
  history in two. Do not rename; create a new product and deactivate the
  old one instead.
- Farm→PDV stock transfers (future SC-2.5) must NOT write
  `cout_unitaire_fcfa` / `cout_total_fcfa` on `mouvements_stock` rows a
  vendeur can read — RLS 0027 serves a PDV's rows to its vendeur, and RLS
  cannot mask columns. If transfer costing is ever needed, create a
  vendeur-facing sanitized view at that point (`bandes_pos` pattern).
- Any migration that adds a column to one of the 9 tables behind an
  `_ops` view (`bandes`, `intrants`, `receptions`, `abattages`,
  `aliments_phases`, `formulations_mp`, `commandes`, `lignes_commande`,
  `clients`) MUST replay the 0040 §1 view block in the same migration —
  the views freeze their column list at creation, so without the replay
  the new column is invisible to chef_bande (reads go through the views;
  QUEUE_COLUMN_FALLBACKS cannot help, it is the READ that is missing).
  Start every replay from the MOST RECENT replay's exclusion lists, not
  from 0040's: 0042 extended `receptions` with `prix_pose_par` /
  `prix_pose_le` (price-lifecycle metadata stays out of the chef view) —
  replaying 0040's original lists would resurrect them for the chef.
- Temperature: the daily series is `saisies.temperature_c` (building ambient
  — norms, alerts and charts read ONLY this column); `temperature_observee_c`
  (0024) is a clinical observation on the birds, optional, never a series.
- Day counter: J1 = placement day (matches the vaccination seed 0017/0019/
  0020). `computeJourBande(bande, date)` is the single source — never compute
  a J inline and never trust a stored `jour_bande` over it for display.
- Flag any deviation from the brief in the PR body rather than silently
  adopting it.

## Observed patterns (unconfirmed)

Habits observed in the repository, not stated as rules — follow them unless
told otherwise, but do not treat them as law:

- PRs are squash-merged (one commit per PR, `(#N)` suffix on main); merged
  branches are kept on the remote.
- Commit messages and PR bodies are written in French, conventional-commit
  style (`feat(scope): …`, `fix(scope): …`).
- Migration files: ASCII-only SQL, no comment at the end of statement lines,
  per-verb policy names `rls<NN>_<table>_<verb>`.
- Register tables use uuid primary keys generated CLIENT-SIDE (`uuidv4()`)
  so offline-queue replays stay idempotent (duplicate key = already applied).
- Business thresholds live as single named constants at the top of
  `index.html`'s config block (e.g. `VIDE_SANITAIRE_MIN_JOURS`,
  `ETALONNAGE_ALERTE_JOURS`, `NUISIBLES_INTERVALLE_JOURS`), earmarked for a
  later move to the `parametres` table (0028).
- Equipment-like inventories are deactivated (`actif` flag), not deleted, so
  their history survives; delete buttons are deliberately absent from those
  UIs.
