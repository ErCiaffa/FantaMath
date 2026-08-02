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
