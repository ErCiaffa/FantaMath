classdef LeagueState
    methods (Static)
        function state = empty()
            state = struct();
            state.meta = struct('schemaVersion', 1, 'lastCsvPath', "", 'lastCsvLoadedAt', NaT);
            state.epsilon = NaN;
            state.players = emptyPlayersTable();
            state.params = defaultFormulaParams();
            state.scores = emptyScoresTable();
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
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = recomputeScores(state)
            % FORM-01/FORM-02 (ported from FantaMath): F_score/Q_score/S computed over the
            % WHOLE players table (not just owned rows) -- the percentile cut is relative to
            % the entire listone pool, matching the source formula's design.
            n = height(state.players);
            if n == 0
                state.scores = emptyScoresTable();
                return
            end
            p = state.params;
            fScore = src.engine.normalizeScore(state.players.fvm, p.alphaF, p.pLow, p.pHigh);
            qScore = src.engine.normalizeScore(state.players.quot, p.alphaQ, p.pLow, p.pHigh);
            score = src.engine.mixScores(fScore, qScore, p.phi);

            roleParams = struct('qw', p.qw, 'mix_owned', p.mixOwned, 'eta', p.eta, ...
                'Sq', max(height(state.teams.table), 1), 'nmax', p.nmax, 'beta', p.beta, ...
                'rho', p.rho, 'roleOverride', p.roleOverride);
            scarcity = src.engine.roleScarcity(state.players, score, roleParams);
            rf = src.engine.roleFactor(state.players.roleTokens, scarcity, roleParams);

            state.scores = table(state.players.id, fScore, qScore, score, rf.RoleFactor, rf.Flex, rf.PesoRuolo, ...
                'VariableNames', {'id', 'fScore', 'qScore', 'score', 'roleFactor', 'flex', 'pesoRuolo'});
        end

        function state = setFormulaParams(state, phi, alphaF, alphaQ, pLow, pHigh)
            arguments
                state struct
                phi (1,1) double {mustBeInRange(phi, 0, 1)}
                alphaF (1,1) double {mustBePositive}
                alphaQ (1,1) double {mustBePositive}
                pLow (1,1) double {mustBeInRange(pLow, 0, 1)}
                pHigh (1,1) double {mustBeInRange(pHigh, 0, 1)}
            end
            if pLow >= pHigh
                error('FantaManager:formula:invalidPercentileRange', ...
                    'pLow (%.4f) deve essere minore di pHigh (%.4f).', pLow, pHigh);
            end
            state.params.phi = phi;
            state.params.alphaF = alphaF;
            state.params.alphaQ = alphaQ;
            state.params.pLow = pLow;
            state.params.pHigh = pHigh;
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = setRoleParams(state, qw, mixOwned, eta, nmax, beta, rho)
            arguments
                state struct
                qw (1,1) double {mustBeNonnegative}
                mixOwned (1,1) double {mustBeInRange(mixOwned, 0, 1)}
                eta (1,1) double {mustBePositive}
                nmax (1,1) double {mustBePositive, mustBeInteger}
                beta (1,1) double {mustBeNonnegative}
                rho (1,1) double {mustBePositive}
            end
            state.params.qw = qw;
            state.params.mixOwned = mixOwned;
            state.params.eta = eta;
            state.params.nmax = nmax;
            state.params.beta = beta;
            state.params.rho = rho;
            state = src.state.LeagueState.recomputeScores(state);
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

        function state = setEpsilon(state, epsilonValue)
            arguments
                state struct
                epsilonValue (1,1) double {mustBeFinite}
            end
            state.epsilon = epsilonValue;
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

function p = defaultFormulaParams()
    p = struct('phi', 0.5, 'alphaF', 0.0005, 'alphaQ', 0.0005, 'pLow', 0, 'pHigh', 1, ...
        'qw', 1, 'mixOwned', 1, 'eta', 1, 'nmax', 3, 'beta', 0.2, 'rho', 1, 'roleOverride', struct());
end

function t = emptyScoresTable()
    t = table('Size', [0 7], ...
        'VariableTypes', {'double','double','double','double','double','double','double'}, ...
        'VariableNames', {'id', 'fScore', 'qScore', 'score', 'roleFactor', 'flex', 'pesoRuolo'});
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
