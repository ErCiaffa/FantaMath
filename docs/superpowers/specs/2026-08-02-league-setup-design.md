# League Setup — Design Spec

Date: 2026-08-02
Status: Approved by user, ready for implementation planning.

## Purpose

FantaManager is a new project (sibling to FantaMath, itself a from-scratch rebuild). Its
first screen is "Setup Lega": load the league's player CSV, detect teams, set starting
credits and the epsilon margin, then present a dashboard of team credits/banks that can be
edited (bank overrides, bonus/malus) and re-synced against a newer CSV export over time.

This spec covers ONLY the setup + dashboard page. Formula engine, scarcity, auction/release
value calculation are out of scope (they live in the FantaMath project and may be ported
into FantaManager in a later phase).

## Platform & Architecture

- **Engine**: MATLAB (university license, no MATLAB Compiler / Web App Server needed).
  Business logic and validation live in MATLAB, mirroring FantaMath's proven
  `+src/+state`/`+src/+io` namespace-class pattern (state as plain structs, methods as
  `methods(Static)` classes, no hidden handle-object state).
- **Frontend**: real HTML/CSS/JS web page (not MATLAB App Designer/uifigure — evaluated and
  rejected: uifigure cannot deliver the approved visual design, no border-radius/shadows/
  hover transitions/custom type scale).
- **Bridge**: small Python FastAPI server (same pattern as FantaMath's existing
  `companion/` read-only viewer, extended here to also accept writes).
- **Why not MATLAB Engine API for Python**: rejected in favor of a file-based action queue
  (see below) — no live MATLAB session dependency, no extra install, matches the existing
  companion convention already validated in FantaMath.

### Data flow

```
                 ┌─────────────────────┐
   MATLAB app -> │ config/lega.mat      │  <- source of truth, written by MATLAB only
   (LeagueState) │ config/lega.json      │  <- auto-exported snapshot, read-only for Python
                 │ config/queue.json     │  <- write requests appended by the web UI
                 └─────────────────────┘
                       ^            |
                       | reads      | serves
                       |            v
                 FastAPI (companion) --- HTTP/JSON ---> Web frontend (browser)
```

- MATLAB owns `lega.mat` and is the only writer of `lega.json` (exported after every mutating
  action).
- The web UI never writes `lega.mat`/`lega.json` directly. A user action in the browser
  (edit bank, apply bonus/malus, confirm CSV merge) POSTs to FastAPI, which appends a
  request row to `config/queue.json`.
- The MATLAB app polls `queue.json` (on a timer, and on any user interaction with the setup
  page) and applies pending requests through `LeagueState` methods — same validation path as
  a MATLAB-side edit — then clears the applied entries and re-exports `lega.json`.
- This means a web edit is not instantaneous; it completes on MATLAB's next poll tick. The
  UI shows a pending/applied state per request (see Error Handling).

## Data Model — `LeagueState`

Namespaced `+src/+state/LeagueState.m`, `methods(Static)`, ported from FantaMath's
`TeamsState.m` pattern (transaction ledger, `bankOverride`, `applyBonusMalus` with mandatory
motivo — reused near-verbatim).

```
LeagueState
├── meta
│   ├── schemaVersion   (double)
│   ├── lastCsvPath     (string)
│   └── lastCsvLoadedAt (datetime)
├── epsilon             (double) — set once at first setup, edited only via an explicit
│                                   future "modifica epsilon" action, never re-asked on CSV
│                                   update
├── players             (table)  — full merged roster, same column shape as FantaMath's
│                                   loadListone output (id, nome, roleClassic, roleMantra,
│                                   roleTokens, fvm, quot, age, team, costo, owned,
│                                   fuoriLista), persisted so the NEXT csv load has something
│                                   to merge against
├── teams.table          (table) — name, creditiIniziali, bankOverride (NaN = unset),
│                                   teamValue (sum of players.costo for that team, recomputed
│                                   after every load/merge)
├── teams.transactions   (table) — Timestamp, PlayerId, PlayerName, Team, Type
│                                   ("bonus"/"malus"), Mandatory, Amount (signed), Motivo —
│                                   identical shape to FantaMath's TeamsState ledger
└── teams.released       (double vector) — carried over from FantaMath's shape, unused by
                                            this phase but kept for schema compatibility with
                                            a possible later roster/release phase
```

`lega.json` is a flattened export of the same shape (tables become arrays of objects,
`datetime`/`NaN` become ISO strings/`null`) — read-only for the web layer.

## CSV Loading & Merge

Reuses FantaMath's `+src/+io/loadListone.m` almost verbatim (semicolon CSV, synonym column
resolution, blocking validation on unrecognized role tokens / missing Costo for owned
players — no silent fallback, consistent with the project's data-integrity rule).

**First setup** (no `lega.mat` found):
1. User picks a CSV. `loadListone` parses and validates it.
2. Distinct team names are extracted from `players.team` (non-empty, i.e. owned players).
3. UI shows one row per team with a `Crediti Iniziali` input (no default assumed — user
   fills every row) and each team's `teamValue` (sum of `costo`) for reference.
4. UI asks for a single `epsilon` value (league-wide, not per team).
5. On confirm: build `teams.table`, `players` = the loaded table as-is, save `lega.mat`,
   export `lega.json`.

**Subsequent loads** (`lega.mat` exists):
- Default action: load `lega.mat` directly, go straight to the dashboard. No CSV needed.
- Secondary action "Carica nuovo CSV (aggiorna)": re-run `loadListone` on a new file, then
  merge against the stored `players` table **keyed by `nome`** (not `id` — the user
  confirmed team-name/player-id stability across exports is not guaranteed, name is the
  reliable key):
  - Player only in the new CSV → inserted as a new row, as-is.
  - Player only in the stored table → kept, `fuoriLista` forced to `true`, every other field
    left untouched (no new data exists for them).
  - Player in both → `fuoriLista`, `Sq.` (team/roleClassic column), `Under`, `R.`,
    `R.MANTRA`, `PGv`, `MV`, `FM`, `FVM/1000`, `QUOT.`, `FantaSquadra` are always overwritten
    with the new CSV's values. `Costo` is special: new value used only if present AND
    different from stored; if new is blank, the stored value is kept; if new equals stored,
    unchanged.
  - After merging, `teamValue` is recomputed per team from the merged `players.costo`.
  - Any team name appearing in the merged players but absent from `teams.table` triggers the
    same "set Crediti Iniziali" prompt as first setup, scoped to just the new teams.
  - The UI shows a merge preview (new / fuori lista / updated counts and a per-player diff
    table) before the user confirms and it's applied — mirrors the approved mockup's screen
    3.

## Dashboard

- Header stats: team count, epsilon, total credits in circulation (`sum(creditiIniziali)`),
  total bank residuals (`sum(bankResiduoVector)`, reusing FantaMath's derivation: bank =
  creditiIniziali + sum of that team's transaction amounts, unless a `bankOverride` is set).
- Team table: Squadra, Crediti Iniziali, Valore Squadra, Banca Residua (inline-editable —
  double-click/edit icon queues a `setBankOverride` request), a per-row Bonus/Malus button
  (opens a small form: importo + motivo, motivo mandatory — mirrors
  `TeamsState.applyBonusMalus`'s blocking validation, enforced again in MATLAB even though
  the web form also validates client-side).
- "Carica nuovo CSV (aggiorna)" button re-enters the merge flow above.

## Error Handling

- CSV structurally invalid (missing required columns, unrecognized role token, missing
  Costo for an owned player) → blocking error surfaced verbatim from `loadListone`'s
  existing error identifiers/messages, nothing partially applied.
- Bonus/malus with empty motivo → rejected both client-side (button stays disabled) and
  server-side in `LeagueState`/`TeamsState`-style validation (`FantaMath:transaction:
  missingMotivo`-equivalent) — the queue consumer must not trust the web layer blindly.
- Queue entries referencing an unknown team name → rejected, logged, surfaced back to the
  web UI as a failed/needs-attention state on next poll (never silently dropped).
- Because writes are polled, not instant: each queued action gets a UI state (`pending` →
  `applied`/`failed`) so the user isn't left wondering whether an edit "took".

## Testing

Ported/adapted from FantaMath's existing test conventions (`tests/t*.m`, MATLAB unit test
framework):
- `tLeagueStateTest`: empty state shape, `applyBonusMalus` (mandatory motivo, ledger
  append), `setBankOverride`/`bankResiduoVector` derivation — all direct ports of
  `TeamsState`'s already-covered behavior.
- `tCsvMergeTest`: the three merge outcomes (new/fuori-lista/updated) including the Costo
  tri-state rule (present+different / present+same / blank), keyed by `nome`.
- `tLeagueStatePersistenceTest`: `.mat` save/load round-trip; `.json` export shape
  (flattening of tables, `NaN`/`datetime` encoding).
- Queue processing: applying a valid request updates state and clears the queue entry;
  applying an invalid request (bad team name, empty motivo) leaves state untouched and
  marks the entry failed.

## Explicitly Out of Scope (this spec)

- Formula engine / scarcity / auction-release value calculation (FantaMath territory, not
  ported here yet).
- Roster/`released` player management (schema field kept for compatibility, no UI yet).
- Epsilon edit-after-setup UI (data model supports it; no dedicated screen designed yet).
- Removing a team that disappears from a new CSV entirely (no players owned by them
  anymore) — no deletion flow, out of scope for now, flagged for a future decision.
