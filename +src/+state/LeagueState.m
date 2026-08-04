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
            state.roleSuggestion = defaultRoleSuggestion();
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
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = recomputeScores(state)
            % FORM-01/FORM-02 (ported from FantaMath): F_score/Q_score/S computed over the
            % WHOLE players table (not just owned rows) -- the percentile cut is relative to
            % the entire listone pool, matching the source formula's design.
            n = height(state.players);
            if n == 0
                state.scores = emptyScoresTable();
                state.roleSuggestion = defaultRoleSuggestion();
                state = src.state.LeagueState.recomputeTeamValue(state);
                return
            end
            p = state.params;
            fScore = src.engine.normalizeScore(state.players.fvm, p.alphaF, p.pLow, p.pHigh);
            qScore = src.engine.normalizeScore(state.players.quot, p.alphaQ, p.pLow, p.pHigh);
            score = src.engine.mixScores(fScore, qScore, p.phi);

            roleParams = struct('qw', p.qw, 'mix_owned', p.mixOwned, 'eta', p.eta, ...
                'Sq', max(height(state.teams.table), 1), 'nmax', p.nmax, ...
                'duttilita2', p.duttilita2, 'duttilita3', p.duttilita3, ...
                'rho', p.rho, 'roleOverride', p.roleOverride);
            scarcity = src.engine.roleScarcity(state.players, score, roleParams);
            rf = src.engine.roleFactor(state.players.roleTokens, scarcity, roleParams);

            ageParams = struct('etaFloor', p.etaFloor, 'etaZero', p.etaZero, 'etaBonusMax', p.etaBonusMax);
            etaWeight = src.engine.ageWeight(state.players.age, ageParams);

            mod = src.engine.roleMod(state.players.roleTokens, p.roleOverride);
            duttilita = rf.Flex - 1.0;
            assembleWeight = src.engine.assembleWeight(score, mod, duttilita, etaWeight);

            totalBudget = sum(state.teams.table.creditiIniziali) * (1 + state.epsilon);
            taxParams = struct('taxEstero', p.taxEstero, 'taxDecisionale', p.taxDecisionale, ...
                'taxPlusvalenza', p.taxPlusvalenza, 'taxMinusvalenza', p.taxMinusvalenza, 'taxFee', p.taxFee);
            costo = state.players.costo;
            costo(isnan(costo)) = 0;
            owned = state.players.owned;

            if isfinite(totalBudget) && totalBudget > 0 && any(owned)
                shape = max(0, assembleWeight + p.auctionOffsetC) .^ p.auctionExpK;
                netSumFor = @(s) sum(arrayfun(@(i) src.engine.releaseTax( ...
                    max(p.auctionFloor, s*shape(i)), costo(i), false, taxParams).IncassoNetto, find(owned)));
                % Scale-factor tale che il NETTO (dopo tasse, motivo decisionale) sommi
                % esatto a totalBudget -- 2026-08-04, richiesta esplicita del proprietario:
                % "se tutti svincolano tutti abbiamo W*", non il lordo. Bisezione: netSumFor
                % e' monotona crescente in s (piu' lordo -> piu' netto), un solo giro basta.
                lo = 0; hi = 10;
                while netSumFor(hi) < totalBudget && hi < 1e6
                    hi = hi * 4;
                end
                for iter = 1:40
                    mid = (lo + hi) / 2;
                    if netSumFor(mid) < totalBudget
                        lo = mid;
                    else
                        hi = mid;
                    end
                end
                scaleFactor = (lo + hi) / 2;
                creditoStimato = max(p.auctionFloor, scaleFactor * shape);
            else
                creditoStimato = zeros(n, 1);
            end

            incassoNettoDecisionale = zeros(n, 1);
            for i = 1:n
                out = src.engine.releaseTax(creditoStimato(i), costo(i), false, taxParams);
                incassoNettoDecisionale(i) = out.IncassoNetto;
            end

            state.scores = table(state.players.id, fScore, qScore, score, rf.RoleFactor, rf.Flex, rf.PesoRuolo, ...
                etaWeight, mod, assembleWeight, creditoStimato, incassoNettoDecisionale, ...
                'VariableNames', {'id', 'fScore', 'qScore', 'score', 'roleFactor', 'flex', 'pesoRuolo', ...
                'etaWeight', 'mod', 'assembleWeight', 'creditoStimato', 'incassoNettoDecisionale'});
            state.roleSuggestion = computeRoleSuggestion(state.players, scarcity);
            % Valore squadra = somma del valore di svincolo netto (decisionale, dopo tasse) dei
            % giocatori posseduti, non il costo pagato in asta (2026-08-04, richiesta esplicita
            % del proprietario: "quanto vale la rosa oggi", non "quanto ho speso"). Deve girare
            % DOPO gli scores appena calcolati, da cui prende incassoNettoDecisionale.
            state = src.state.LeagueState.recomputeTeamValue(state);
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

        function state = setRoleParams(state, qw, mixOwned, eta, nmax, rho)
            arguments
                state struct
                qw (1,1) double {mustBeNonnegative}
                mixOwned (1,1) double {mustBeInRange(mixOwned, 0, 1)}
                eta (1,1) double {mustBePositive}
                nmax (1,1) double {mustBePositive, mustBeInteger}
                rho (1,1) double {mustBePositive}
            end
            state.params.qw = qw;
            state.params.mixOwned = mixOwned;
            state.params.eta = eta;
            state.params.nmax = nmax;
            state.params.rho = rho;
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = setDuttilita(state, duttilita2, duttilita3)
            % duttilita2/duttilita3: bonus (0-1, es. 0.03 = +3%) applicato a Flex per un
            % giocatore con esattamente 2 ruoli / con nmax o piu' ruoli (vedi roleFactor.m).
            % Parametri modificabili -- 2026-08-03: valori scelti dal proprietario lega
            % (3%/5%), non fissi, editabili se cambia idea.
            arguments
                state struct
                duttilita2 (1,1) double {mustBeNonnegative}
                duttilita3 (1,1) double {mustBeNonnegative}
            end
            state.params.duttilita2 = duttilita2;
            state.params.duttilita3 = duttilita3;
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = setAuctionParams(state, offsetC, expK, floorCredito)
            % Conversione finale assembleWeight -> crediti (2026-08-04, vedi auctionPrice.m):
            % offsetC (default 0.52), expK (default 4.5), floorCredito (default 1.0). Tarati
            % sui dati reali della lega per portare il top a 100-150 crediti senza schiacciare
            % meta' roster nella stessa fascia bassa (vedi docs/decisioni-e-logica.md).
            arguments
                state struct
                offsetC (1,1) double {mustBeNonnegative}
                expK (1,1) double {mustBePositive}
                floorCredito (1,1) double {mustBeNonnegative}
            end
            state.params.auctionOffsetC = offsetC;
            state.params.auctionExpK = expK;
            state.params.auctionFloor = floorCredito;
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = setTaxParams(state, taxEstero, taxDecisionale, taxPlusvalenza, taxMinusvalenza, taxFee)
            % Tassazione svincolo (2026-08-04, vedi releaseTax.m). Default: estero=0,
            % decisionale=0.15, plusvalenza=0.10, minusvalenza(recupero)=0.15, fee=0 --
            % valori scelti dal proprietario lega, non tarati sui dati, modificabili.
            arguments
                state struct
                taxEstero (1,1) double {mustBeNonnegative}
                taxDecisionale (1,1) double {mustBeNonnegative}
                taxPlusvalenza (1,1) double {mustBeNonnegative}
                taxMinusvalenza (1,1) double {mustBeNonnegative}
                taxFee (1,1) double {mustBeNonnegative}
            end
            state.params.taxEstero = taxEstero;
            state.params.taxDecisionale = taxDecisionale;
            state.params.taxPlusvalenza = taxPlusvalenza;
            state.params.taxMinusvalenza = taxMinusvalenza;
            state.params.taxFee = taxFee;
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = setEtaParams(state, etaFloor, etaZero, etaBonusMax)
            % Rampa lineare bonus giovani, nessun malus veterani (2026-08-03, sostituisce lo
            % schema a soglie 23/31 + step fissi): vedi ageWeight.m per la formula esatta.
            % etaFloor (default 15, eta' minima Serie A): bonus massimo per eta'<=etaFloor.
            % etaZero (default 38): eta' a cui il bonus arriva a 0 e ci resta (mai negativo).
            % etaBonusMax (default 0.10 = 10%): bonus a etaFloor, decresce linearmente fino
            % a 0 a etaZero.
            arguments
                state struct
                etaFloor (1,1) double {mustBePositive}
                etaZero (1,1) double {mustBePositive}
                etaBonusMax (1,1) double {mustBeNonnegative}
            end
            if etaFloor >= etaZero
                error('FantaManager:formula:invalidAgeThresholds', ...
                    'etaFloor (%.1f) deve essere minore di etaZero (%.1f).', etaFloor, etaZero);
            end
            state.params.etaFloor = etaFloor;
            state.params.etaZero = etaZero;
            state.params.etaBonusMax = etaBonusMax;
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = setRoleOverride(state, overrides)
            % overrides: struct with a field per Mantra role token (A, B, C, Dc, Dd, Ds, E,
            % M, Pc, Por, T, W), each a positive multiplier applied to that role's ScarNorm
            % before roleFactor's per-player MAX is taken (see roleFactor.m).
            arguments
                state struct
                overrides (1,1) struct
            end
            whitelist = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
            missing = whitelist(~isfield(overrides, cellstr(whitelist)));
            if ~isempty(missing)
                error('FantaManager:formula:missingRoleOverride', ...
                    'Modificatore ruolo mancante per: %s.', strjoin(missing, ', '));
            end
            for i = 1:numel(whitelist)
                tok = char(whitelist(i));
                val = overrides.(tok);
                if ~(isnumeric(val) && isscalar(val) && isfinite(val) && val > 0)
                    error('FantaManager:formula:invalidRoleOverride', ...
                        'Modificatore ruolo "%s" deve essere un numero positivo finito.', tok);
                end
                state.params.roleOverride.(tok) = double(val);
            end
            state = src.state.LeagueState.recomputeScores(state);
        end

        function state = recomputeTeamValue(state)
            % Somma, per squadra, il valore di svincolo netto (state.scores.incassoNettoDecisionale)
            % dei giocatori posseduti -- non il costo pagato in asta. state.scores e' allineato
            % riga-per-riga a state.players (stesso ordine, costruito da esso in recomputeScores),
            % quindi la stessa mask booleana funziona su entrambe le tabelle.
            n = height(state.teams.table);
            teamValue = zeros(n, 1);
            if height(state.scores) == height(state.players)
                valorePerGiocatore = state.scores.incassoNettoDecisionale;
            else
                valorePerGiocatore = zeros(height(state.players), 1);
            end
            for i = 1:n
                mask = state.players.owned & state.players.team == state.teams.table.name(i);
                teamValue(i) = sum(valorePerGiocatore(mask));
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
        'qw', 1, 'mixOwned', 1, 'eta', 1, 'nmax', 3, 'duttilita2', 0.03, 'duttilita3', 0.05, 'rho', 1, ...
        'etaFloor', 15, 'etaZero', 38, 'etaBonusMax', 0.10, ...
        'auctionOffsetC', 0.52, 'auctionExpK', 4.5, 'auctionFloor', 1.0, ...
        'taxEstero', 0, 'taxDecisionale', 0.15, 'taxPlusvalenza', 0.10, 'taxMinusvalenza', 0.15, 'taxFee', 0, ...
        'roleOverride', defaultRoleOverride());
end

function o = defaultRoleOverride()
    tokens = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
    o = struct();
    for i = 1:numel(tokens)
        o.(char(tokens(i))) = 1.0;
    end
end

function s = defaultRoleSuggestion()
    % Neutral suggestion (no scarcity data yet, e.g. before a listone is loaded): every field
    % zeroed/neutral, recommended override=1.0 (no nudge).
    tokens = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
    s = struct();
    for i = 1:numel(tokens)
        s.(char(tokens(i))) = struct('scarNorm', 1.0, 'nOwned', 0, 'nFree', 0, ...
            'fvmOwned', 0, 'fvmFree', 0, 'gapPct', 0, 'recommended', 1.0);
    end
end

function s = computeRoleSuggestion(players, scarcity)
    % "Consigliato" reference column for the Ruoli UI page (2026-08-03 decision, see
    % docs/decisioni-e-logica.md). Superseded the original ScarNorm+offensive-bump heuristic:
    % the league owner pointed out that headcount-based ScarNorm doesn't capture "how much
    % worse are the free agents left, if I have to replace this player" -- the actual
    % svincolo-relevant question. Measured directly instead: for each role, the gap between
    % the average FVM of OWNED players and of FREE AGENTS still available (fuoriLista
    % excluded from both). A role where free agents are much weaker than what's owned (e.g.
    % Pc, Por -- see the "0 free goalkeepers above FVM 20" finding logged in this session) is
    % expensive to lose and hard to replace, regardless of what a headcount ratio says.
    %
    % gapPct = (fvmOwned - fvmFree) / fvmOwned * 100 -- normalized to each role's own FVM
    % scale so goalkeepers (low absolute FVM) aren't unfairly discounted next to forwards
    % (high absolute FVM). recommended is a plain min-max of gapPct across all 12 roles onto
    % [1.00, 1.20] (the owner's explicit cap) -- the role with the smallest gap (easiest to
    % replace) lands at 1.00, the role with the largest gap (hardest to replace) at 1.20,
    % every other role its own value in between (2026-08-03: "ogni ruolo proprio mod", no
    % more shared tiers).
    tokens = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
    n = numel(tokens);

    included = ~players.fuoriLista;
    nOwned = zeros(1, n);
    nFree = zeros(1, n);
    fvmOwnedSum = zeros(1, n);
    fvmFreeSum = zeros(1, n);

    idxOf = containers.Map(cellstr(tokens), num2cell(1:n));
    rows = find(included)';
    for g = rows
        rowTokens = string(players.roleTokens{g});
        rowTokens = rowTokens(strlength(rowTokens) > 0);
        for t = 1:numel(rowTokens)
            tok = char(rowTokens(t));
            if ~isKey(idxOf, tok)
                continue
            end
            idx = idxOf(tok);
            if players.owned(g)
                nOwned(idx) = nOwned(idx) + 1;
                fvmOwnedSum(idx) = fvmOwnedSum(idx) + players.fvm(g);
            else
                nFree(idx) = nFree(idx) + 1;
                fvmFreeSum(idx) = fvmFreeSum(idx) + players.fvm(g);
            end
        end
    end

    fvmOwnedAvg = fvmOwnedSum ./ max(1, nOwned);
    fvmFreeAvg = fvmFreeSum ./ max(1, nFree);
    gapPct = zeros(1, n);
    validMask = fvmOwnedAvg > 0;
    gapPct(validMask) = (fvmOwnedAvg(validMask) - fvmFreeAvg(validMask)) ./ fvmOwnedAvg(validMask) * 100;

    minGap = min(gapPct);
    range = max(max(gapPct) - minGap, 1e-9);
    recommended = 1.0 + 0.20 * (gapPct - minGap) / range;

    s = struct();
    for i = 1:n
        tok = char(tokens(i));
        s.(tok) = struct('scarNorm', scarcity.ScarNorm(tok), 'nOwned', nOwned(i), 'nFree', nFree(i), ...
            'fvmOwned', fvmOwnedAvg(i), 'fvmFree', fvmFreeAvg(i), 'gapPct', gapPct(i), ...
            'recommended', recommended(i));
    end
end

function t = emptyScoresTable()
    t = table('Size', [0 12], ...
        'VariableTypes', repmat({'double'}, 1, 12), ...
        'VariableNames', {'id', 'fScore', 'qScore', 'score', 'roleFactor', 'flex', 'pesoRuolo', ...
            'etaWeight', 'mod', 'assembleWeight', 'creditoStimato', 'incassoNettoDecisionale'});
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
