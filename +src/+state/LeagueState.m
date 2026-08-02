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

        function sums = bonusMalusSumVector(state)
            n = height(state.teams.table);
            sums = zeros(n, 1);
            for i = 1:n
                mask = state.teams.transactions.Team == state.teams.table.name(i);
                sums(i) = sum(state.teams.transactions.Amount(mask));
            end
        end

        function bank = bankResiduoVector(state)
            % Residuo = banca base (bankOverride if set, else creditiIniziali) + the full
            % bonus/malus ledger sum, ALWAYS additive -- an edited banca never hides the
            % bonus/malus history (2026-08-02 correction: the previous "override replaces
            % everything" behavior was confusing in the UI).
            n = height(state.teams.table);
            base = state.teams.table.creditiIniziali;
            overrideMask = isfinite(state.teams.table.bankOverride);
            base(overrideMask) = state.teams.table.bankOverride(overrideMask);
            bank = base + src.state.LeagueState.bonusMalusSumVector(state);
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
