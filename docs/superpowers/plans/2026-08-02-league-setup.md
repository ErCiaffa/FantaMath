# League Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working vertical slice of FantaManager's League Setup page: MATLAB owns league state (players, teams, credits, banks, bonus/malus), a FastAPI bridge exposes it as JSON and accepts write requests through a file-based queue, and a real HTML/CSS/JS frontend (matching the approved mockup) lets the user load a CSV, set credits/epsilon, and manage the dashboard.

**Architecture:** MATLAB (`+src/+state/LeagueState.m`, `+src/+io/*.m`) is the single source of truth, persisted to `config/lega.mat` and auto-exported to `config/lega.json`. A polling script (`watchLeague.m`) applies pending entries from `config/queue.json` via `src.app.processQueue`. FastAPI (`server/main.py`) serves `lega.json` read-only, accepts new queue entries, and serves the static frontend. The frontend never touches MATLAB directly — it only calls the FastAPI JSON API.

**Tech Stack:** MATLAB (namespace classes/functions, `matlab.unittest.TestCase` tests), Python 3 + FastAPI + Uvicorn (`pytest` + `fastapi.testclient`), vanilla HTML/CSS/JS (no build step).

## Global Constraints

- CSV parsing/validation reuses FantaMath's `loadListone.m` behavior verbatim — no silent fallback on missing columns, unrecognized role tokens, or missing Costo for an owned player (spec: "Error Handling").
- Player merge on CSV update is keyed by `nome` (string), not by numeric id (spec: "CSV Loading & Merge" — user confirmed id stability is not guaranteed).
- Bonus/malus requires a non-empty `motivo`, validated in MATLAB even though the frontend also validates client-side (spec: "Error Handling" — never trust the caller).
- Epsilon is set once at first setup and never re-asked on CSV update (spec: "Data Model").
- Writes from the web layer never touch `lega.mat`/`lega.json` directly; they go through `config/queue.json` and are applied by MATLAB (spec: "Architecture").
- MATLAB error identifiers use the `FantaManager:<area>:<reason>` convention (mirrors FantaMath's `FantaMath:*` convention).

---

### Task 1: LeagueState core — empty state, save/load round-trip

**Files:**
- Create: `+src/+state/LeagueState.m`
- Test: `tests/tLeagueStateTest.m`

**Interfaces:**
- Produces: `src.state.LeagueState.empty()` → struct with fields `meta` (`schemaVersion` double, `lastCsvPath` string, `lastCsvLoadedAt` datetime), `epsilon` (double), `players` (table, 12 columns: `id,nome,roleClassic,roleMantra,roleTokens,fvm,quot,age,team,costo,owned,fuoriLista`), `teams.table` (table: `name,creditiIniziali,bankOverride,teamValue`), `teams.transactions` (table: `Timestamp,PlayerId,PlayerName,Team,Type,Mandatory,Amount,Motivo`), `teams.released` (double column vector).
- Produces: `src.state.LeagueState.saveState(state, matPath)`, `src.state.LeagueState.loadState(matPath)` → round-trips the struct through a `.mat` file.

- [ ] **Step 1: Write the failing test**

```matlab
% tests/tLeagueStateTest.m
classdef tLeagueStateTest < matlab.unittest.TestCase
    methods (Test)
        function emptyStateHasZeroRowsEverywhere(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyEqual(height(state.players), 0);
            testCase.verifyEqual(height(state.teams.table), 0);
            testCase.verifyEqual(height(state.teams.transactions), 0);
            testCase.verifyEqual(state.teams.released, zeros(0, 1));
            testCase.verifyTrue(isnan(state.epsilon));
        end

        function saveAndLoadRoundTripsState(testCase)
            state = src.state.LeagueState.empty();
            state.epsilon = 0.05;
            tmpFile = fullfile(tempdir, "tLeagueStateTest_roundtrip.mat");
            testCase.addTeardown(@() delete(tmpFile));

            src.state.LeagueState.saveState(state, string(tmpFile));
            loaded = src.state.LeagueState.loadState(string(tmpFile));

            testCase.verifyEqual(loaded.epsilon, 0.05);
            testCase.verifyEqual(height(loaded.players), 0);
        end

        function loadStateThrowsWhenFileMissing(testCase)
            missingPath = fullfile(tempdir, "tLeagueStateTest_does_not_exist.mat");
            testCase.verifyError(@() src.state.LeagueState.loadState(string(missingPath)), ...
                'FantaManager:state:notFound');
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `FantaManager/`): `matlab -batch "runtests('tests/tLeagueStateTest.m')"`
Expected: FAIL — `src.state.LeagueState` does not exist (undefined function/class).

- [ ] **Step 3: Write minimal implementation**

```matlab
% +src/+state/LeagueState.m
classdef LeagueState
    methods (Static)
        function state = empty()
            state = struct();
            state.meta = struct('schemaVersion', 1, 'lastCsvPath', "", 'lastCsvLoadedAt', NaT);
            state.epsilon = NaN;
            state.players = emptyPlayersTable();
            state.teams = struct();
            state.teams.table = emptyTeamsTable();
            state.teams.transactions = emptyTransactionTable();
            state.teams.released = zeros(0, 1);
        end

        function saveState(state, matPath)
            arguments
                state struct
                matPath (1,1) string {mustBeNonzeroLengthText}
            end
            [folder, ~, ~] = fileparts(matPath);
            if strlength(folder) > 0 && ~isfolder(folder)
                mkdir(folder);
            end
            save(matPath, 'state');
        end

        function state = loadState(matPath)
            arguments
                matPath (1,1) string {mustBeNonzeroLengthText}
            end
            if ~isfile(matPath)
                error('FantaManager:state:notFound', 'Nessun file di stato trovato in "%s".', matPath);
            end
            data = load(matPath, 'state');
            state = data.state;
        end
    end
end

function t = emptyPlayersTable()
    t = table('Size', [0 12], ...
        'VariableTypes', {'double','string','string','string','cell','double','double','double','string','double','logical','logical'}, ...
        'VariableNames', {'id','nome','roleClassic','roleMantra','roleTokens','fvm','quot','age','team','costo','owned','fuoriLista'});
end

function t = emptyTeamsTable()
    t = table(strings(0,1), zeros(0,1), nan(0,1), zeros(0,1), ...
        'VariableNames', {'name', 'creditiIniziali', 'bankOverride', 'teamValue'});
end

function t = emptyTransactionTable()
    t = table('Size', [0 8], ...
        'VariableTypes', {'datetime','double','string','string','string','logical','double','string'}, ...
        'VariableNames', {'Timestamp','PlayerId','PlayerName','Team','Type','Mandatory','Amount','Motivo'});
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests/tLeagueStateTest.m')"`
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add +src/+state/LeagueState.m tests/tLeagueStateTest.m
git commit -m "feat: LeagueState core with empty state and save/load round-trip"
```

---

### Task 2: Port `loadListone.m` from FantaMath

**Files:**
- Create: `+src/+io/loadListone.m`
- Create: `tests/fixtures/listone_min.csv`
- Test: `tests/tLoadListoneTest.m`

**Interfaces:**
- Produces: `src.io.loadListone(csvFile)` → table with columns `id,nome,roleClassic,roleMantra,roleTokens,fvm,quot,age,team,costo,owned,fuoriLista` (same shape `LeagueState.empty().players` expects). Throws `FantaMath:csv:missingColumns`, `FantaMath:data:unrecognizedRole`, `FantaMath:data:missingCost` on invalid input (identifiers kept as-is from the ported source so any future cross-project tooling stays consistent).

- [ ] **Step 1: Write the failing test fixture and test**

```
# tests/fixtures/listone_min.csv
#;Nome;Fuori lista;Sq.;Under;R.;R.MANTRA;PGv;MV;FM;FVM/1000;QUOT.;FantaSquadra;Costo
1;Martinez L.;;Inter;28;A;Pc;18;6,36;8,19;353;34;LAMINCHIADURA;149
2;Pulisic;;Milan;27;C;T/A;12;6,75;8,67;277;32;Eintracht Piangoforte;104
3;Carlos Augusto;;Inter;26;D;B/Ds/E;20;6,10;6,50;120;12;LAMINCHIADURA;18
4;Riserva Senza Squadra;;Roma;23;C;C;0;0;0;80;9;;
```

```matlab
% tests/tLoadListoneTest.m
classdef tLoadListoneTest < matlab.unittest.TestCase
    methods (Test)
        function loadsAllRowsFromMinimalFixture(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            players = src.io.loadListone(string(csvFile));
            testCase.verifyEqual(height(players), 4);
            testCase.verifyEqual(players.nome(1), "Martinez L.");
            testCase.verifyEqual(players.costo(1), 149);
            testCase.verifyTrue(players.owned(1));
            testCase.verifyFalse(players.owned(4));
            testCase.verifyEqual(players.roleTokens{3}, ["B", "Ds", "E"]);
        end

        function missingCostoOnOwnedRowThrows(testCase)
            csvFile = fullfile(tempdir, "tLoadListoneTest_missingcost.csv");
            fid = fopen(csvFile, 'w');
            fprintf(fid, '%s\n', '#;Nome;Fuori lista;Sq.;Under;R.;R.MANTRA;PGv;MV;FM;FVM/1000;QUOT.;FantaSquadra;Costo');
            fprintf(fid, '%s\n', '1;Senza Costo;;Inter;28;A;Pc;18;6,36;8,19;353;34;LAMINCHIADURA;');
            fclose(fid);
            testCase.addTeardown(@() delete(csvFile));
            testCase.verifyError(@() src.io.loadListone(string(csvFile)), 'FantaMath:data:missingCost');
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "runtests('tests/tLoadListoneTest.m')"`
Expected: FAIL — `src.io.loadListone` does not exist.

- [ ] **Step 3: Port the implementation**

```bash
mkdir -p +src/+io
cp "../raw_data/FantaMath/+src/+io/loadListone.m" "+src/+io/loadListone.m"
```

Open `+src/+io/loadListone.m` and confirm it has no dependency on any other FantaMath namespace (it doesn't — it's fully self-contained: `resolveColumns`, `buildAliasSpec`, `normalizeHeaders`, `mantraRoleWhitelist` are all local functions in the same file). No edits needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests/tLoadListoneTest.m')"`
Expected: PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add +src/+io/loadListone.m tests/fixtures/listone_min.csv tests/tLoadListoneTest.m
git commit -m "feat: port loadListone CSV parser from FantaMath"
```

---

### Task 3: `LeagueState.createFromCsv` and `recomputeTeamValue`

**Files:**
- Modify: `+src/+state/LeagueState.m`
- Test: `tests/tLeagueStateCsvTest.m`

**Interfaces:**
- Consumes: `src.io.loadListone(csvFile)` (Task 2).
- Produces: `src.state.LeagueState.createFromCsv(csvFile, creditiMap, epsilonValue)` where `creditiMap` is a `containers.Map('KeyType','char','ValueType','double')` keyed by exact team name → state with `players`, `teams.table` (one row per team, `teamValue` = sum of `costo` for that team's owned players), `epsilon` set, `meta.lastCsvPath`/`lastCsvLoadedAt` set. Throws `FantaManager:setup:missingCredits` listing any team present in the CSV without a matching map entry.
- Produces: `src.state.LeagueState.recomputeTeamValue(state)` → state with `teams.table.teamValue` recalculated from the current `players` table (used again by the merge flow in Task 5).
- Produces: `src.state.LeagueState.addTeam(state, teamName, creditiIniziali)` → state with one new row appended to `teams.table` (`bankOverride=NaN`, `teamValue=0`, recomputed separately). Throws `FantaManager:state:teamAlreadyExists` if the name is already present.

- [ ] **Step 1: Write the failing test**

```matlab
% tests/tLeagueStateCsvTest.m
classdef tLeagueStateCsvTest < matlab.unittest.TestCase
    methods (Test)
        function createFromCsvBuildsTeamsWithValueAndCredits(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});

            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyEqual(height(state.players), 4);
            testCase.verifyEqual(state.epsilon, 0.05);
            testCase.verifyEqual(height(state.teams.table), 2);

            idxLam = find(state.teams.table.name == "LAMINCHIADURA", 1);
            testCase.verifyEqual(state.teams.table.creditiIniziali(idxLam), 500);
            testCase.verifyEqual(state.teams.table.teamValue(idxLam), 149 + 18);
        end

        function createFromCsvThrowsWhenATeamHasNoCredits(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA'}, {500});
            testCase.verifyError(@() src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05), ...
                'FantaManager:setup:missingCredits');
        end

        function addTeamAppendsRowThenThrowsOnDuplicate(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Nuova Squadra", 500);
            testCase.verifyEqual(height(state.teams.table), 1);
            testCase.verifyEqual(state.teams.table.creditiIniziali(1), 500);
            testCase.verifyTrue(isnan(state.teams.table.bankOverride(1)));

            testCase.verifyError(@() src.state.LeagueState.addTeam(state, "Nuova Squadra", 100), ...
                'FantaManager:state:teamAlreadyExists');
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "runtests('tests/tLeagueStateCsvTest.m')"`
Expected: FAIL — `createFromCsv`/`addTeam` are not methods of `LeagueState`.

- [ ] **Step 3: Extend the implementation**

Replace the full contents of `+src/+state/LeagueState.m` with:

```matlab
classdef LeagueState
    methods (Static)
        function state = empty()
            state = struct();
            state.meta = struct('schemaVersion', 1, 'lastCsvPath', "", 'lastCsvLoadedAt', NaT);
            state.epsilon = NaN;
            state.players = emptyPlayersTable();
            state.teams = struct();
            state.teams.table = emptyTeamsTable();
            state.teams.transactions = emptyTransactionTable();
            state.teams.released = zeros(0, 1);
        end

        function state = createFromCsv(csvFile, creditiMap, epsilonValue)
            arguments
                csvFile (1,1) string {mustBeNonzeroLengthText}
                creditiMap containers.Map
                epsilonValue (1,1) double {mustBeFinite}
            end
            players = src.io.loadListone(csvFile);
            teamNames = unique(players.team(players.owned & strlength(players.team) > 0));
            n = numel(teamNames);

            missing = strings(0, 1);
            for i = 1:n
                if ~isKey(creditiMap, char(teamNames(i)))
                    missing(end+1, 1) = teamNames(i); %#ok<AGROW>
                end
            end
            if ~isempty(missing)
                error('FantaManager:setup:missingCredits', ...
                    'Crediti iniziali mancanti per le squadre: %s.', strjoin(missing, ', '));
            end

            creditiIniziali = zeros(n, 1);
            for i = 1:n
                creditiIniziali(i) = creditiMap(char(teamNames(i)));
            end

            state = src.state.LeagueState.empty();
            state.players = players;
            state.epsilon = epsilonValue;
            state.meta.lastCsvPath = csvFile;
            state.meta.lastCsvLoadedAt = datetime('now');
            state.teams.table = table(teamNames, creditiIniziali, nan(n, 1), zeros(n, 1), ...
                'VariableNames', {'name', 'creditiIniziali', 'bankOverride', 'teamValue'});
            state = src.state.LeagueState.recomputeTeamValue(state);
        end

        function state = recomputeTeamValue(state)
            n = height(state.teams.table);
            teamValue = zeros(n, 1);
            for i = 1:n
                mask = state.players.owned & state.players.team == state.teams.table.name(i);
                teamValue(i) = sum(state.players.costo(mask));
            end
            state.teams.table.teamValue = teamValue;
        end

        function state = addTeam(state, teamName, creditiIniziali)
            arguments
                state struct
                teamName (1,1) string
                creditiIniziali (1,1) double {mustBeFinite}
            end
            if any(state.teams.table.name == teamName)
                error('FantaManager:state:teamAlreadyExists', ...
                    'La squadra "%s" esiste gia'' nello stato corrente.', teamName);
            end
            newRow = table(teamName, creditiIniziali, NaN, 0, ...
                'VariableNames', {'name', 'creditiIniziali', 'bankOverride', 'teamValue'});
            state.teams.table = [state.teams.table; newRow];
        end

        function saveState(state, matPath)
            arguments
                state struct
                matPath (1,1) string {mustBeNonzeroLengthText}
            end
            [folder, ~, ~] = fileparts(matPath);
            if strlength(folder) > 0 && ~isfolder(folder)
                mkdir(folder);
            end
            save(matPath, 'state');
        end

        function state = loadState(matPath)
            arguments
                matPath (1,1) string {mustBeNonzeroLengthText}
            end
            if ~isfile(matPath)
                error('FantaManager:state:notFound', 'Nessun file di stato trovato in "%s".', matPath);
            end
            data = load(matPath, 'state');
            state = data.state;
        end
    end
end

function t = emptyPlayersTable()
    t = table('Size', [0 12], ...
        'VariableTypes', {'double','string','string','string','cell','double','double','double','string','double','logical','logical'}, ...
        'VariableNames', {'id','nome','roleClassic','roleMantra','roleTokens','fvm','quot','age','team','costo','owned','fuoriLista'});
end

function t = emptyTeamsTable()
    t = table(strings(0,1), zeros(0,1), nan(0,1), zeros(0,1), ...
        'VariableNames', {'name', 'creditiIniziali', 'bankOverride', 'teamValue'});
end

function t = emptyTransactionTable()
    t = table('Size', [0 8], ...
        'VariableTypes', {'datetime','double','string','string','string','logical','double','string'}, ...
        'VariableNames', {'Timestamp','PlayerId','PlayerName','Team','Type','Mandatory','Amount','Motivo'});
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests/tLeagueStateCsvTest.m')"` and `matlab -batch "runtests('tests/tLeagueStateTest.m')"`
Expected: both PASS (Task 1's tests must still pass unchanged).

- [ ] **Step 5: Commit**

```bash
git add +src/+state/LeagueState.m tests/tLeagueStateCsvTest.m
git commit -m "feat: LeagueState.createFromCsv, recomputeTeamValue, addTeam"
```

---

### Task 4: `LeagueState` bank and bonus/malus methods

**Files:**
- Modify: `+src/+state/LeagueState.m`
- Test: `tests/tLeagueStateBankTest.m`

**Interfaces:**
- Produces: `src.state.LeagueState.setBankOverride(state, teamName, value)` → state with that team's `teams.table.bankOverride` set. Throws `FantaManager:transaction:unknownTeam`.
- Produces: `src.state.LeagueState.bankResiduoVector(state)` → column vector, one entry per `teams.table` row: `bankOverride` if finite, else `creditiIniziali + sum(transactions.Amount for that team)`.
- Produces: `src.state.LeagueState.applyBonusMalus(state, teamName, amount, motivo)` → state with one row appended to `teams.transactions` (`Type="bonus"`, `Amount=amount` signed). Throws `FantaManager:transaction:unknownTeam` / `FantaManager:transaction:missingMotivo`.

- [ ] **Step 1: Write the failing test**

```matlab
% tests/tLeagueStateBankTest.m
classdef tLeagueStateBankTest < matlab.unittest.TestCase
    methods (Test)
        function bankResiduoDefaultsToCreditiIniziali(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            bank = src.state.LeagueState.bankResiduoVector(state);
            testCase.verifyEqual(bank, 500);
        end

        function setBankOverrideWinsOverComputedValue(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            state = src.state.LeagueState.setBankOverride(state, "Squadra A", 340);
            bank = src.state.LeagueState.bankResiduoVector(state);
            testCase.verifyEqual(bank, 340);
        end

        function setBankOverrideOnUnknownTeamThrows(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyError(@() src.state.LeagueState.setBankOverride(state, "Fantasma", 10), ...
                'FantaManager:transaction:unknownTeam');
        end

        function applyBonusMalusAddsSignedTransactionAndShiftsBank(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            state = src.state.LeagueState.applyBonusMalus(state, "Squadra A", 20, "Premio classifica");
            state = src.state.LeagueState.applyBonusMalus(state, "Squadra A", -5, "Penalita disciplinare");

            testCase.verifyEqual(height(state.teams.transactions), 2);
            bank = src.state.LeagueState.bankResiduoVector(state);
            testCase.verifyEqual(bank, 515);
        end

        function applyBonusMalusRejectsEmptyMotivo(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            testCase.verifyError(@() src.state.LeagueState.applyBonusMalus(state, "Squadra A", 20, "   "), ...
                'FantaManager:transaction:missingMotivo');
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "runtests('tests/tLeagueStateBankTest.m')"`
Expected: FAIL — `setBankOverride`/`bankResiduoVector`/`applyBonusMalus` are not methods of `LeagueState`.

- [ ] **Step 3: Extend the implementation**

Insert these three methods into `+src/+state/LeagueState.m`, inside the existing `methods (Static)` block, right after `addTeam` (before `saveState`):

```matlab
        function state = setBankOverride(state, teamName, value)
            arguments
                state struct
                teamName (1,1) string
                value (1,1) double
            end
            idx = find(state.teams.table.name == teamName, 1);
            if isempty(idx)
                error('FantaManager:transaction:unknownTeam', ...
                    'Squadra "%s" non trovata.', teamName);
            end
            state.teams.table.bankOverride(idx) = value;
        end

        function bank = bankResiduoVector(state)
            n = height(state.teams.table);
            bank = zeros(n, 1);
            for i = 1:n
                if isfinite(state.teams.table.bankOverride(i))
                    bank(i) = state.teams.table.bankOverride(i);
                    continue
                end
                mask = state.teams.transactions.Team == state.teams.table.name(i);
                bank(i) = state.teams.table.creditiIniziali(i) + sum(state.teams.transactions.Amount(mask));
            end
        end

        function state = applyBonusMalus(state, teamName, amount, motivo)
            arguments
                state struct
                teamName (1,1) string
                amount (1,1) double {mustBeFinite}
                motivo (1,1) string
            end
            if ~any(state.teams.table.name == teamName)
                error('FantaManager:transaction:unknownTeam', ...
                    'Squadra "%s" non trovata nello stato corrente.', teamName);
            end
            if strlength(strtrim(motivo)) == 0
                error('FantaManager:transaction:missingMotivo', ...
                    'Il bonus o malus richiede una motivazione non vuota.');
            end
            newRow = table(datetime('now'), NaN, "", teamName, "bonus", false, amount, motivo, ...
                'VariableNames', {'Timestamp', 'PlayerId', 'PlayerName', 'Team', 'Type', 'Mandatory', 'Amount', 'Motivo'});
            state.teams.transactions = [state.teams.transactions; newRow];
        end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests', 'IncludeSubfolders', true)"`
Expected: all `tLeagueState*` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add +src/+state/LeagueState.m tests/tLeagueStateBankTest.m
git commit -m "feat: LeagueState bank override and bonus/malus ledger"
```

---

### Task 5: `mergePlayers` — CSV update merge keyed by nome

**Files:**
- Create: `+src/+io/mergePlayers.m`
- Create: `tests/fixtures/listone_merge_old.csv`
- Create: `tests/fixtures/listone_merge_new.csv`
- Test: `tests/tMergePlayersTest.m`

**Interfaces:**
- Consumes: `src.io.loadListone` output shape (Task 2).
- Produces: `src.io.mergePlayers(oldPlayers, newPlayers)` → merged table, same 12-column shape. New-only rows inserted as-is; old-only rows kept with `fuoriLista=true`; matched rows take every new-CSV field except `costo` (new if present & different, kept if new is blank, either way new-vs-same-value is a no-op).

- [ ] **Step 1: Write the failing fixtures and test**

```
# tests/fixtures/listone_merge_old.csv
#;Nome;Fuori lista;Sq.;Under;R.;R.MANTRA;PGv;MV;FM;FVM/1000;QUOT.;FantaSquadra;Costo
1;Martinez L.;;Inter;28;A;Pc;18;6,36;8,19;353;34;LAMINCHIADURA;149
2;Chiesa;;Roma;27;A;A;10;6,20;7,00;180;20;LAMINCHIADURA;18
3;Pulisic;;Milan;27;C;T/A;12;6,75;8,67;277;32;Eintracht Piangoforte;104
4;McTominay;;Napoli;28;C;M/C;9;6,00;6,10;200;15;;
```

```
# tests/fixtures/listone_merge_new.csv
#;Nome;Fuori lista;Sq.;Under;R.;R.MANTRA;PGv;MV;FM;FVM/1000;QUOT.;FantaSquadra;Costo
1;Martinez L.;;Inter;28;A;Pc;20;6,50;8,40;360;35;LAMINCHIADURA;149
3;Pulisic;;Milan;27;C;T/A;14;6,80;8,70;280;33;Eintracht Piangoforte;112
4;McTominay;;Napoli;28;C;M/C;11;6,10;6,20;210;16;LAMINCHIADURA;76
5;Yildiz;;Juventus;20;A;A/W;16;6,90;8,50;300;28;Eintracht Piangoforte;22
```

Fixture design covers all four merge cases: `Chiesa` (id 2) is old-only → must become `fuoriLista=true`; `Yildiz` (id 5) is new-only → inserted as-is; `Martinez L.` costo is unchanged (149→149, no-op); `Pulisic` costo changed (104→112, new wins); `McTominay` costo was blank and is now present (blank→76, new wins since old was blank, not the "keep old" branch — old had no value to keep).

```matlab
% tests/tMergePlayersTest.m
classdef tMergePlayersTest < matlab.unittest.TestCase
    methods (Test)
        function mergeAppliesAllFourOutcomes(testCase)
            fixturesDir = fullfile(fileparts(mfilename('fullpath')), 'fixtures');
            oldPlayers = src.io.loadListone(string(fullfile(fixturesDir, 'listone_merge_old.csv')));
            newPlayers = src.io.loadListone(string(fullfile(fixturesDir, 'listone_merge_new.csv')));

            merged = src.io.mergePlayers(oldPlayers, newPlayers);

            testCase.verifyEqual(height(merged), 5);

            idxChiesa = find(merged.nome == "Chiesa", 1);
            testCase.verifyTrue(merged.fuoriLista(idxChiesa));
            testCase.verifyEqual(merged.costo(idxChiesa), 18);

            idxYildiz = find(merged.nome == "Yildiz", 1);
            testCase.verifyFalse(isempty(idxYildiz));
            testCase.verifyEqual(merged.costo(idxYildiz), 22);

            idxMartinez = find(merged.nome == "Martinez L.", 1);
            testCase.verifyEqual(merged.costo(idxMartinez), 149);
            testCase.verifyEqual(merged.fvm(idxMartinez), 360);

            idxPulisic = find(merged.nome == "Pulisic", 1);
            testCase.verifyEqual(merged.costo(idxPulisic), 112);

            idxMcTominay = find(merged.nome == "McTominay", 1);
            testCase.verifyEqual(merged.costo(idxMcTominay), 76);
            testCase.verifyEqual(merged.team(idxMcTominay), "LAMINCHIADURA");
        end

        function mergeAgainstEmptyOldReturnsNewUnchanged(testCase)
            fixturesDir = fullfile(fileparts(mfilename('fullpath')), 'fixtures');
            newPlayers = src.io.loadListone(string(fullfile(fixturesDir, 'listone_merge_new.csv')));
            emptyOld = newPlayers([], :);

            merged = src.io.mergePlayers(emptyOld, newPlayers);

            testCase.verifyEqual(height(merged), height(newPlayers));
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "runtests('tests/tMergePlayersTest.m')"`
Expected: FAIL — `src.io.mergePlayers` does not exist.

- [ ] **Step 3: Write the implementation**

```matlab
% +src/+io/mergePlayers.m
function merged = mergePlayers(oldPlayers, newPlayers)
%MERGEPLAYERS Merge a re-loaded listone against the previously stored players table, keyed
% by nome (id stability across exports is not guaranteed, per project decision).
%
% Only-in-new rows are inserted as-is. Only-in-old rows are kept with fuoriLista forced to
% true, every other field untouched. Rows in both take every new-CSV field as-is EXCEPT
% costo: the new value wins only when present and different from the old one; a blank new
% costo keeps the old value.
    arguments
        oldPlayers table
        newPlayers table
    end

    if height(oldPlayers) == 0
        merged = newPlayers;
        return
    end

    merged = newPlayers;
    for i = 1:height(merged)
        idxOld = find(oldPlayers.nome == merged.nome(i), 1);
        if ~isempty(idxOld) && isnan(merged.costo(i))
            merged.costo(i) = oldPlayers.costo(idxOld);
        end
    end

    oldOnlyMask = ~ismember(oldPlayers.nome, newPlayers.nome);
    oldOnly = oldPlayers(oldOnlyMask, :);
    oldOnly.fuoriLista(:) = true;

    merged = [merged; oldOnly];
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests/tMergePlayersTest.m')"`
Expected: PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add +src/+io/mergePlayers.m tests/fixtures/listone_merge_old.csv tests/fixtures/listone_merge_new.csv tests/tMergePlayersTest.m
git commit -m "feat: mergePlayers CSV update merge keyed by nome"
```

---

### Task 6: `exportLegaJson` — JSON snapshot export

**Files:**
- Create: `+src/+io/exportLegaJson.m`
- Test: `tests/tExportLegaJsonTest.m`

**Interfaces:**
- Consumes: a `LeagueState`-shaped struct (Tasks 1/3/4).
- Produces: `src.io.exportLegaJson(state, jsonPath)` → writes `jsonPath` with keys `meta`, `epsilon`, `players` (array), `teams.table` (array), `teams.transactions` (array), `teams.released` (array). `NaN`/`NaT` are encoded by MATLAB's default `jsonencode` as the quoted strings `"NaN"`/`"NaT"` — the frontend (Task 9) treats any non-numeric `bankOverride` as "no override".

- [ ] **Step 1: Write the failing test**

```matlab
% tests/tExportLegaJsonTest.m
classdef tExportLegaJsonTest < matlab.unittest.TestCase
    methods (Test)
        function exportsReadableJsonWithExpectedShape(testCase)
            state = src.state.LeagueState.empty();
            state.epsilon = 0.05;
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            state = src.state.LeagueState.applyBonusMalus(state, "Squadra A", 20, "Premio classifica");

            jsonFile = fullfile(tempdir, "tExportLegaJsonTest_export.json");
            testCase.addTeardown(@() delete(jsonFile));

            src.io.exportLegaJson(state, string(jsonFile));

            testCase.verifyTrue(isfile(jsonFile));
            decoded = jsondecode(fileread(jsonFile));

            testCase.verifyEqual(decoded.epsilon, 0.05);
            testCase.verifyEqual(numel(decoded.teams.table), 1);
            testCase.verifyEqual(decoded.teams.table.name, "Squadra A");
            testCase.verifyEqual(numel(decoded.teams.transactions), 1);
            testCase.verifyEqual(decoded.teams.transactions.Motivo, "Premio classifica");
        end

        function exportsEmptyArraysForEmptyState(testCase)
            state = src.state.LeagueState.empty();
            jsonFile = fullfile(tempdir, "tExportLegaJsonTest_empty.json");
            testCase.addTeardown(@() delete(jsonFile));

            src.io.exportLegaJson(state, string(jsonFile));
            decoded = jsondecode(fileread(jsonFile));

            testCase.verifyEqual(decoded.players, []);
            testCase.verifyEqual(decoded.teams.table, []);
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "runtests('tests/tExportLegaJsonTest.m')"`
Expected: FAIL — `src.io.exportLegaJson` does not exist.

- [ ] **Step 3: Write the implementation**

```matlab
% +src/+io/exportLegaJson.m
function exportLegaJson(state, jsonPath)
%EXPORTLEGAJSON Flatten a LeagueState struct to a JSON file readable by the FastAPI bridge.
% MATLAB tables become JSON arrays via table2struct; datetime columns are stringified first
% since jsonencode cannot serialize datetime directly.
    arguments
        state struct
        jsonPath (1,1) string {mustBeNonzeroLengthText}
    end

    out = struct();
    out.meta = struct('schemaVersion', state.meta.schemaVersion, ...
        'lastCsvPath', state.meta.lastCsvPath, ...
        'lastCsvLoadedAt', encodeDatetime(state.meta.lastCsvLoadedAt));
    out.epsilon = state.epsilon;
    out.players = table2struct(state.players);

    out.teams = struct();
    out.teams.table = table2struct(state.teams.table);

    txTable = state.teams.transactions;
    txTable.Timestamp = string(txTable.Timestamp);
    out.teams.transactions = table2struct(txTable);
    out.teams.released = state.teams.released;

    [folder, ~, ~] = fileparts(jsonPath);
    if strlength(folder) > 0 && ~isfolder(folder)
        mkdir(folder);
    end

    fid = fopen(jsonPath, 'w');
    if fid == -1
        error('FantaManager:export:cannotWrite', 'Impossibile scrivere "%s".', jsonPath);
    end
    fwrite(fid, jsonencode(out), 'char');
    fclose(fid);
end

function s = encodeDatetime(dt)
    if isnat(dt)
        s = "";
    else
        s = string(dt);
    end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests/tExportLegaJsonTest.m')"`
Expected: PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add +src/+io/exportLegaJson.m tests/tExportLegaJsonTest.m
git commit -m "feat: exportLegaJson JSON snapshot for the FastAPI bridge"
```

---

### Task 7: `processQueue` — apply write-queue entries, plus `watchLeague.m` runner

**Files:**
- Create: `+src/+app/processQueue.m`
- Create: `watchLeague.m`
- Test: `tests/tProcessQueueTest.m`

**Interfaces:**
- Consumes: `src.state.LeagueState.*` (Tasks 1/3/4), `src.io.loadListone`/`mergePlayers`/`exportLegaJson` (Tasks 2/5/6).
- Produces: `src.app.processQueue(queuePath, statePath, jsonPath)` — reads `queuePath` (JSON array of `{id,type,payload,status,createdAt,appliedAt,error}`), applies every `status=="pending"` entry, sets `status` to `"applied"` or `"failed"` (with `error` message on failure), re-writes `queuePath` (entries kept, not deleted, so a poller can read their final status), then saves `statePath` and exports `jsonPath`. Supported `type` values: `"createLeague"` (`payload: {csvPath, epsilon, credits:[{teamName,value}]}`), `"mergeCsv"` (`payload: {csvPath, newTeamCredits:[{teamName,value}]}`), `"setBankOverride"` (`payload: {teamName, value}`), `"applyBonusMalus"` (`payload: {teamName, amount, motivo}`).

- [ ] **Step 1: Write the failing test**

```matlab
% tests/tProcessQueueTest.m
classdef tProcessQueueTest < matlab.unittest.TestCase
    methods (Test)
        function createLeagueEntryAppliesAndExportsJson(testCase)
            work = testCase.createWorkDir();
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');

            queue = {struct('id', "a1", 'type', "createLeague", 'status', "pending", ...
                'payload', struct('csvPath', string(csvFile), 'epsilon', 0.05, ...
                    'credits', [struct('teamName', "LAMINCHIADURA", 'value', 500); ...
                                struct('teamName', "Eintracht Piangoforte", 'value', 480)]))};
            testCase.writeQueue(work.queuePath, queue);

            src.app.processQueue(work.queuePath, work.statePath, work.jsonPath);

            testCase.verifyTrue(isfile(work.statePath));
            testCase.verifyTrue(isfile(work.jsonPath));

            resultQueue = jsondecode(fileread(work.queuePath));
            testCase.verifyEqual(string(resultQueue.status), "applied");

            state = src.state.LeagueState.loadState(work.statePath);
            testCase.verifyEqual(height(state.teams.table), 2);
        end

        function unknownTeamBonusMalusEntryIsMarkedFailed(testCase)
            work = testCase.createWorkDir();
            state = src.state.LeagueState.empty();
            src.state.LeagueState.saveState(state, work.statePath);
            src.io.exportLegaJson(state, work.jsonPath);

            queue = {struct('id', "b1", 'type', "applyBonusMalus", 'status', "pending", ...
                'payload', struct('teamName', "Fantasma", 'amount', 10, 'motivo', "test"))};
            testCase.writeQueue(work.queuePath, queue);

            src.app.processQueue(work.queuePath, work.statePath, work.jsonPath);

            resultQueue = jsondecode(fileread(work.queuePath));
            testCase.verifyEqual(string(resultQueue.status), "failed");
            testCase.verifyNotEmpty(char(resultQueue.error));
        end

        function missingQueueFileStillExportsCurrentState(testCase)
            work = testCase.createWorkDir();
            src.app.processQueue(work.queuePath, work.statePath, work.jsonPath);
            testCase.verifyTrue(isfile(work.statePath));
            testCase.verifyTrue(isfile(work.jsonPath));
        end
    end

    methods
        function work = createWorkDir(testCase)
            folder = string(fullfile(tempdir, "tProcessQueueTest_" + char(matlab.lang.makeValidName(datestr(now, 30)))));
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            work = struct('queuePath', fullfile(folder, "queue.json"), ...
                'statePath', fullfile(folder, "lega.mat"), ...
                'jsonPath', fullfile(folder, "lega.json"));
        end

        function writeQueue(~, queuePath, entries)
            fid = fopen(queuePath, 'w');
            fwrite(fid, jsonencode(entries), 'char');
            fclose(fid);
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "runtests('tests/tProcessQueueTest.m')"`
Expected: FAIL — `src.app.processQueue` does not exist.

- [ ] **Step 3: Write the implementation**

```matlab
% +src/+app/processQueue.m
function processQueue(queuePath, statePath, jsonPath)
%PROCESSQUEUE Apply every pending entry in queuePath against the LeagueState at statePath,
% then persist the updated state and re-export jsonPath. Entries are never deleted -- their
% status transitions from "pending" to "applied"/"failed" so a caller polling by id can read
% the final outcome.
    arguments
        queuePath (1,1) string {mustBeNonzeroLengthText}
        statePath (1,1) string {mustBeNonzeroLengthText}
        jsonPath (1,1) string {mustBeNonzeroLengthText}
    end

    if isfile(statePath)
        state = src.state.LeagueState.loadState(statePath);
    else
        state = src.state.LeagueState.empty();
    end

    entries = readQueue(queuePath);
    for i = 1:numel(entries)
        if entries(i).status ~= "pending"
            continue
        end
        try
            state = applyEntry(state, entries(i));
            entries(i).status = "applied";
        catch ME
            entries(i).status = "failed";
            entries(i).error = string(ME.message);
        end
        entries(i).appliedAt = string(datetime('now'));
    end

    src.state.LeagueState.saveState(state, statePath);
    src.io.exportLegaJson(state, jsonPath);
    writeQueue(queuePath, entries);
end

function entries = readQueue(queuePath)
    template = struct('id', {}, 'type', {}, 'payload', {}, 'status', {}, ...
        'createdAt', {}, 'appliedAt', {}, 'error', {});
    if ~isfile(queuePath)
        entries = template;
        return
    end
    raw = strtrim(string(fileread(queuePath)));
    if strlength(raw) == 0
        entries = template;
        return
    end
    decoded = jsondecode(char(raw));
    entries = decoded(:);
    for i = 1:numel(entries)
        entries(i).status = string(entries(i).status);
        entries(i).type = string(entries(i).type);
        if ~isfield(entries(i), 'error') || isempty(entries(i).error)
            entries(i).error = "";
        end
        if ~isfield(entries(i), 'appliedAt') || isempty(entries(i).appliedAt)
            entries(i).appliedAt = "";
        end
    end
end

function writeQueue(queuePath, entries)
    fid = fopen(queuePath, 'w');
    fwrite(fid, jsonencode(entries), 'char');
    fclose(fid);
end

function state = applyEntry(state, entry)
    switch entry.type
        case "createLeague"
            if height(state.players) > 0
                error('FantaManager:queue:leagueAlreadyExists', 'Una lega e'' gia'' configurata.');
            end
            creditiMap = creditsToMap(entry.payload.credits);
            state = src.state.LeagueState.createFromCsv(string(entry.payload.csvPath), creditiMap, entry.payload.epsilon);

        case "mergeCsv"
            newPlayers = src.io.loadListone(string(entry.payload.csvPath));
            state.players = src.io.mergePlayers(state.players, newPlayers);

            newTeamCredits = containers.Map('KeyType', 'char', 'ValueType', 'double');
            if isfield(entry.payload, 'newTeamCredits')
                newTeamCredits = creditsToMap(entry.payload.newTeamCredits);
            end

            teamNames = unique(state.players.team(state.players.owned & strlength(state.players.team) > 0));
            for i = 1:numel(teamNames)
                if any(state.teams.table.name == teamNames(i))
                    continue
                end
                if ~isKey(newTeamCredits, char(teamNames(i)))
                    error('FantaManager:queue:missingCredits', ...
                        'Crediti iniziali mancanti per la nuova squadra "%s".', teamNames(i));
                end
                state = src.state.LeagueState.addTeam(state, teamNames(i), newTeamCredits(char(teamNames(i))));
            end

            state = src.state.LeagueState.recomputeTeamValue(state);
            state.meta.lastCsvPath = string(entry.payload.csvPath);
            state.meta.lastCsvLoadedAt = datetime('now');

        case "setBankOverride"
            state = src.state.LeagueState.setBankOverride(state, string(entry.payload.teamName), entry.payload.value);

        case "applyBonusMalus"
            state = src.state.LeagueState.applyBonusMalus(state, string(entry.payload.teamName), ...
                entry.payload.amount, string(entry.payload.motivo));

        otherwise
            error('FantaManager:queue:unknownType', 'Tipo azione sconosciuto: "%s".', entry.type);
    end
end

function creditiMap = creditsToMap(credits)
    creditiMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
    if isempty(credits)
        return
    end
    credits = credits(:);
    for i = 1:numel(credits)
        creditiMap(char(string(credits(i).teamName))) = double(credits(i).value);
    end
end
```

```matlab
% watchLeague.m
% Polls config/queue.json and keeps config/lega.mat + config/lega.json in sync.
% Run from the FantaManager root: matlab -batch "watchLeague" (or run interactively).
configDir = fullfile(fileparts(mfilename('fullpath')), 'config');
queuePath = string(fullfile(configDir, 'queue.json'));
statePath = string(fullfile(configDir, 'lega.mat'));
jsonPath = string(fullfile(configDir, 'lega.json'));

fprintf('FantaManager: watching %s (Ctrl+C per fermare)\n', queuePath);
while true
    src.app.processQueue(queuePath, statePath, jsonPath);
    pause(2);
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "runtests('tests/tProcessQueueTest.m')"`
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add +src/+app/processQueue.m watchLeague.m tests/tProcessQueueTest.m
git commit -m "feat: processQueue write-action application and watchLeague poller"
```

---

### Task 8: FastAPI bridge — state, actions, upload endpoints

**Files:**
- Create: `server/main.py`
- Create: `server/requirements.txt`
- Test: `server/tests/test_api.py`

**Interfaces:**
- Produces: `GET /api/state` → the parsed contents of `config/lega.json` (or an empty-shaped default if the file doesn't exist yet).
- Produces: `POST /api/actions` (`{"type": str, "payload": dict}`) → appends a `pending` entry to `config/queue.json`, returns `{"id": str}`.
- Produces: `GET /api/actions/{action_id}` → the matching queue entry (404 if not found).
- Produces: `POST /api/upload-csv` (multipart file) → saves under `config/uploads/`, returns `{"path": str}`.
- Serves the `frontend/` directory as static files at `/` (built in Task 9).

- [ ] **Step 1: Write the failing test**

```python
# server/tests/test_api.py
import json
import os
import shutil
import tempfile

import pytest


@pytest.fixture()
def client(monkeypatch):
    work_dir = tempfile.mkdtemp()
    monkeypatch.setenv("FANTAMANAGER_CONFIG_DIR", os.path.join(work_dir, "config"))
    monkeypatch.setenv("FANTAMANAGER_FRONTEND_DIR", os.path.join(work_dir, "frontend"))
    os.makedirs(os.path.join(work_dir, "frontend"), exist_ok=True)
    with open(os.path.join(work_dir, "frontend", "index.html"), "w") as f:
        f.write("<html><body>ok</body></html>")

    import importlib
    import server.main as main_module
    importlib.reload(main_module)
    from fastapi.testclient import TestClient

    with TestClient(main_module.app) as test_client:
        yield test_client

    shutil.rmtree(work_dir, ignore_errors=True)


def test_get_state_returns_default_shape_when_no_snapshot_yet(client):
    response = client.get("/api/state")
    assert response.status_code == 200
    body = response.json()
    assert body["players"] == []
    assert body["teams"]["table"] == []


def test_create_action_appends_pending_entry_to_queue(client):
    response = client.post("/api/actions", json={"type": "setBankOverride", "payload": {"teamName": "A", "value": 10}})
    assert response.status_code == 200
    action_id = response.json()["id"]
    assert action_id

    status_response = client.get(f"/api/actions/{action_id}")
    assert status_response.status_code == 200
    entry = status_response.json()
    assert entry["status"] == "pending"
    assert entry["type"] == "setBankOverride"


def test_get_unknown_action_returns_404(client):
    response = client.get("/api/actions/does-not-exist")
    assert response.status_code == 404


def test_upload_csv_saves_file_and_returns_path(client):
    response = client.post(
        "/api/upload-csv",
        files={"file": ("listone.csv", b"#;Nome\n1;Test\n", "text/csv")},
    )
    assert response.status_code == 200
    saved_path = response.json()["path"]
    assert os.path.isfile(saved_path)
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `FantaManager/`): `pip install -r server/requirements.txt && pip install pytest && python -m pytest server/tests/test_api.py -v`
Expected: FAIL — `server.main` module does not exist.

- [ ] **Step 3: Write the implementation**

```python
# server/main.py
import json
import os
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = Path(os.environ.get("FANTAMANAGER_CONFIG_DIR", str(BASE_DIR / "config")))
FRONTEND_DIR = Path(os.environ.get("FANTAMANAGER_FRONTEND_DIR", str(BASE_DIR / "frontend")))
UPLOADS_DIR = CONFIG_DIR / "uploads"
STATE_JSON = CONFIG_DIR / "lega.json"
QUEUE_JSON = CONFIG_DIR / "queue.json"

CONFIG_DIR.mkdir(parents=True, exist_ok=True)
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

EMPTY_STATE = {
    "meta": None,
    "epsilon": None,
    "players": [],
    "teams": {"table": [], "transactions": [], "released": []},
}

app = FastAPI(title="FantaManager")


def _read_queue():
    if not QUEUE_JSON.exists():
        return []
    text = QUEUE_JSON.read_text(encoding="utf-8").strip()
    if not text:
        return []
    data = json.loads(text)
    return data if isinstance(data, list) else [data]


def _write_queue(entries):
    QUEUE_JSON.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")


@app.get("/api/state")
def get_state():
    if not STATE_JSON.exists():
        return JSONResponse(EMPTY_STATE)
    return JSONResponse(json.loads(STATE_JSON.read_text(encoding="utf-8")))


@app.post("/api/actions")
def create_action(body: dict):
    if "type" not in body or "payload" not in body:
        raise HTTPException(status_code=400, detail="Richiesta azione priva di 'type' o 'payload'.")
    entries = _read_queue()
    entry = {
        "id": uuid.uuid4().hex,
        "type": body["type"],
        "payload": body["payload"],
        "status": "pending",
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "appliedAt": "",
        "error": "",
    }
    entries.append(entry)
    _write_queue(entries)
    return {"id": entry["id"]}


@app.get("/api/actions/{action_id}")
def get_action(action_id: str):
    for entry in _read_queue():
        if entry["id"] == action_id:
            return entry
    raise HTTPException(status_code=404, detail="Azione non trovata.")


@app.post("/api/upload-csv")
async def upload_csv(file: UploadFile = File(...)):
    dest = UPLOADS_DIR / f"{int(time.time())}_{file.filename}"
    contents = await file.read()
    dest.write_bytes(contents)
    return {"path": str(dest)}


app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
```

```
# server/requirements.txt
fastapi
uvicorn[standard]
python-multipart
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest server/tests/test_api.py -v`
Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
git add server/main.py server/requirements.txt server/tests/test_api.py
git commit -m "feat: FastAPI bridge serving state/actions/upload endpoints"
```

---

### Task 9: Frontend — wire the approved mockup to the real API

**Files:**
- Create: `frontend/index.html`
- Create: `frontend/styles.css`
- Create: `frontend/app.js`

**Interfaces:**
- Consumes: `GET /api/state`, `POST /api/actions`, `GET /api/actions/{id}`, `POST /api/upload-csv` (Task 8).

**Scope note:** this task delivers the first-setup flow and the dashboard (bank edit, bonus/malus) end to end. The rich per-player merge-diff table from the approved mockup's third screen is deferred — "Carica nuovo CSV (aggiorna)" queues a `mergeCsv` action and shows a pending/applied/failed status, without the row-by-row preview. That preview is a follow-up enhancement, not required for this vertical slice to be genuinely usable.

- [ ] **Step 1: Build `frontend/styles.css`**

Reuse the token system and component styles already validated in the approved mockup (dark/light theme via `:root` custom properties, `.window`/`.panel`/`.table-wrap`/`.stat-grid`/`.pill`/`.bank-cell` etc.). Copy the `<style>` block contents from the mockup file verbatim into `frontend/styles.css` (drop the `.mockup-tabs`/`.theme-toggle` rules — those were mockup-navigation-only; keep the theme tokens and every component class listed above, since Task 9's `app.js` renders into the same DOM structure).

- [ ] **Step 2: Build `frontend/index.html`**

```html
<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>FantaManager — Setup Lega</title>
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <div class="window" id="app-window">
    <div class="titlebar">
      <div class="dots"><span class="dot"></span><span class="dot"></span><span class="dot"></span></div>
      <div class="name"><b>FantaManager</b> — Setup Lega</div>
    </div>
    <div class="app-body" id="app-body">
      <p class="sub">Caricamento…</p>
    </div>
  </div>
  <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 3: Build `frontend/app.js`**

```javascript
const appBody = document.getElementById("app-body");

async function fetchState() {
  const response = await fetch("/api/state");
  return response.json();
}

async function postAction(type, payload) {
  const response = await fetch("/api/actions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ type, payload }),
  });
  const { id } = await response.json();
  return pollAction(id);
}

async function pollAction(id) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const response = await fetch(`/api/actions/${id}`);
    const entry = await response.json();
    if (entry.status === "applied") return entry;
    if (entry.status === "failed") throw new Error(entry.error || "Azione fallita.");
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error("Timeout in attesa che MATLAB applicasse l'azione.");
}

function isOverrideSet(bankOverride) {
  return typeof bankOverride === "number" && !Number.isNaN(bankOverride);
}

function parseCsvTeams(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return [];
  const header = lines[0].split(";").map((h) => h.trim().toLowerCase());
  const teamCol = header.indexOf("fantasquadra");
  if (teamCol === -1) return [];
  const teams = new Set();
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(";");
    const team = (cols[teamCol] || "").trim();
    if (team.length > 0) teams.add(team);
  }
  return Array.from(teams);
}

function renderNewLeagueScreen(csvPath, teamNames) {
  appBody.innerHTML = `
    <div>
      <div class="eyebrow">Primo avvio</div>
      <h1>Configura la tua lega</h1>
      <p class="sub">${teamNames.length} squadre rilevate nel CSV caricato.</p>
    </div>
    <div class="panel">
      <div class="panel-head"><h2>Parametro di lega</h2></div>
      <div class="field-row">
        <div class="field" style="max-width:260px;">
          <label for="eps">Epsilon</label>
          <input class="input mono" id="eps" value="0.05" />
        </div>
      </div>
    </div>
    <div class="panel">
      <div class="panel-head"><h2>Crediti iniziali per squadra</h2></div>
      <div class="table-wrap"><table>
        <thead><tr><th>Squadra</th><th class="num">Crediti iniziali</th></tr></thead>
        <tbody>${teamNames
          .map((name) => `<tr><td>${name}</td><td class="num"><input class="cell-input mono" data-team="${name}" value="500" /></td></tr>`)
          .join("")}</tbody>
      </table></div>
    </div>
    <div class="footer-bar">
      <div></div>
      <div class="footer-actions"><button class="btn btn-primary" id="confirm-btn">Conferma e crea lega →</button></div>
    </div>
  `;

  document.getElementById("confirm-btn").addEventListener("click", async () => {
    const epsilon = parseFloat(document.getElementById("eps").value);
    const credits = teamNames.map((name) => ({
      teamName: name,
      value: parseFloat(document.querySelector(`[data-team="${CSS.escape(name)}"]`).value),
    }));
    await postAction("createLeague", { csvPath, epsilon, credits });
    await loadAndRender();
  });
}

function renderUploadScreen() {
  appBody.innerHTML = `
    <div>
      <div class="eyebrow">Primo avvio</div>
      <h1>Configura la tua lega</h1>
      <p class="sub">Nessuna lega salvata trovata. Carica il listone per iniziare.</p>
    </div>
    <div class="panel">
      <div class="dropzone">
        <div class="icon">CSV</div>
        <div class="title">Trascina qui il listone, o scegli un file</div>
        <input type="file" id="csv-input" accept=".csv" style="margin-top:8px;" />
      </div>
    </div>
  `;

  document.getElementById("csv-input").addEventListener("change", async (event) => {
    const file = event.target.files[0];
    if (!file) return;
    const text = await file.text();
    const teamNames = parseCsvTeams(text);

    const formData = new FormData();
    formData.append("file", file);
    const uploadResponse = await fetch("/api/upload-csv", { method: "POST", body: formData });
    const { path } = await uploadResponse.json();

    renderNewLeagueScreen(path, teamNames);
  });
}

function renderDashboard(state) {
  const teams = state.teams.table;
  const totalCredits = teams.reduce((sum, t) => sum + t.creditiIniziali, 0);
  const totalBank = teams.reduce((sum, t) => sum + (isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali), 0);

  appBody.innerHTML = `
    <div class="toolbar">
      <div class="left">
        <div class="eyebrow">Lega caricata</div>
        <h1 style="font-size:22px;">Dashboard</h1>
      </div>
      <div class="right">
        <button class="btn btn-ghost btn-sm" id="update-csv-btn">↻ Carica nuovo CSV (aggiorna)</button>
      </div>
    </div>
    <div class="stat-grid">
      <div class="stat"><span class="k">Squadre</span><span class="v">${teams.length}</span></div>
      <div class="stat"><span class="k">Epsilon</span><span class="v gold">${state.epsilon}</span></div>
      <div class="stat"><span class="k">Crediti in circolazione</span><span class="v">${totalCredits}</span></div>
      <div class="stat"><span class="k">Banche residue totali</span><span class="v accent">${totalBank}</span></div>
    </div>
    <div class="panel" style="padding:0; overflow:hidden;">
      <div class="table-wrap" style="border:none; border-radius:0;"><table>
        <thead><tr><th>Squadra</th><th class="num">Crediti iniziali</th><th class="num">Valore squadra</th><th class="num">Banca residua</th><th></th></tr></thead>
        <tbody>${teams
          .map((t) => {
            const bank = isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali;
            return `<tr>
              <td class="team-name">${t.name}</td>
              <td class="num mono">${t.creditiIniziali}</td>
              <td class="num mono">${t.teamValue}</td>
              <td class="num"><span class="bank-value ${bank >= 0 ? "pos" : "neg"}" data-bank-for="${t.name}">${bank}</span>
                <span class="edit-icon" data-edit-for="${t.name}">✎</span></td>
              <td class="num"><button class="bm-btn" data-bonus-for="${t.name}">± B/M</button></td>
            </tr>`;
          })
          .join("")}</tbody>
      </table></div>
    </div>
  `;

  teams.forEach((t) => {
    document.querySelector(`[data-edit-for="${CSS.escape(t.name)}"]`).addEventListener("click", async () => {
      const value = parseFloat(window.prompt(`Nuova banca residua per ${t.name}:`));
      if (Number.isNaN(value)) return;
      await postAction("setBankOverride", { teamName: t.name, value });
      await loadAndRender();
    });
    document.querySelector(`[data-bonus-for="${CSS.escape(t.name)}"]`).addEventListener("click", async () => {
      const amount = parseFloat(window.prompt(`Importo (positivo=bonus, negativo=malus) per ${t.name}:`));
      if (Number.isNaN(amount)) return;
      const motivo = window.prompt("Motivo (obbligatorio):");
      if (!motivo || motivo.trim().length === 0) {
        window.alert("Il motivo e' obbligatorio.");
        return;
      }
      await postAction("applyBonusMalus", { teamName: t.name, amount, motivo });
      await loadAndRender();
    });
  });

  document.getElementById("update-csv-btn").addEventListener("click", () => {
    renderUploadForUpdate(state);
  });
}

function renderUploadForUpdate(state) {
  appBody.innerHTML = `
    <div>
      <div class="eyebrow">Aggiornamento</div>
      <h1>Carica nuovo listone</h1>
    </div>
    <div class="panel">
      <div class="dropzone">
        <div class="icon">CSV</div>
        <div class="title">Scegli il file CSV aggiornato</div>
        <input type="file" id="csv-input" accept=".csv" style="margin-top:8px;" />
      </div>
    </div>
    <p class="sub" id="update-status"></p>
  `;

  document.getElementById("csv-input").addEventListener("change", async (event) => {
    const file = event.target.files[0];
    if (!file) return;
    const statusEl = document.getElementById("update-status");
    statusEl.textContent = "Caricamento in corso…";

    const formData = new FormData();
    formData.append("file", file);
    const uploadResponse = await fetch("/api/upload-csv", { method: "POST", body: formData });
    const { path } = await uploadResponse.json();

    try {
      statusEl.textContent = "MATLAB sta applicando l'aggiornamento…";
      await postAction("mergeCsv", { csvPath: path, newTeamCredits: [] });
      await loadAndRender();
    } catch (err) {
      statusEl.textContent = `Errore: ${err.message}. Se il messaggio indica squadre nuove senza crediti, contatta lo sviluppo per il flusso "nuove squadre" (non ancora nella UI).`;
    }
  });
}

async function loadAndRender() {
  const state = await fetchState();
  if (!state.teams || state.teams.table.length === 0) {
    renderUploadScreen();
  } else {
    renderDashboard(state);
  }
}

loadAndRender();
