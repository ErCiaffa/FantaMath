classdef FantaIO
    methods(Static)
        function state = loadCSV(state, csvFile)
            if nargin < 2 || strlength(string(csvFile)) == 0
                files = dir('*.csv');
                if ~isempty(files)
                    csvFile = files(1).name;
                else
                    error('Nessun CSV trovato.');
                end
            end

            opts = detectImportOptions(csvFile, 'VariableNamingRule', 'preserve');
            rawTable = readtable(csvFile, opts);
            state.data.rawTable = rawTable;

            [players, logLines] = FantaIO.mapColumns(rawTable);
            state.data.players = players;
            state.log = [state.log; logLines];
            state.markDirty({'data', 'results', 'teams', 'ui'});
        end

        function saveConfig(state, filePath)
            if nargin < 2 || strlength(string(filePath)) == 0
                filePath = 'fantatuner_config.json';
            end
            payload = struct('params', state.params, 'paramsLock', state.paramsLock);
            json = jsonencode(payload, 'PrettyPrint', true);
            fid = fopen(filePath, 'w');
            if fid < 0
                error('Impossibile scrivere il file di configurazione.');
            end
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, json, 'char');
        end

        function state = loadConfig(state, filePath)
            if nargin < 2 || strlength(string(filePath)) == 0
                filePath = 'fantatuner_config.json';
            end
            if ~isfile(filePath)
                error('Config non trovata: %s', filePath);
            end
            txt = fileread(filePath);
            payload = jsondecode(txt);
            if isfield(payload, 'params')
                state.params = payload.params;
            end
            if isfield(payload, 'paramsLock')
                state.paramsLock = payload.paramsLock;
            end
            state.markDirty({'params', 'results', 'ui'});
        end

        function exportExcel(state, filePath)
            if nargin < 2 || strlength(string(filePath)) == 0
                filePath = 'fantatuner_export.xlsx';
            end

            if ~isempty(state.results.listone)
                writetable(state.results.listone, filePath, 'Sheet', 'Listone');
            else
                writetable(table(), filePath, 'Sheet', 'Listone');
            end

            if ~isempty(state.results.ranking)
                writetable(state.results.ranking, filePath, 'Sheet', 'Ranking');
            else
                writetable(table(), filePath, 'Sheet', 'Ranking');
            end

            if ~isempty(state.teams.table)
                writetable(state.teams.table, filePath, 'Sheet', 'Teams');
            else
                writetable(table(), filePath, 'Sheet', 'Teams');
            end

            paramTable = struct2table(state.params, 'AsArray', true);
            writetable(paramTable, filePath, 'Sheet', 'Params');

            kpiTable = struct2table(state.results.kpi, 'AsArray', true);
            writetable(kpiTable, filePath, 'Sheet', 'KPI');

            logTable = table(string(state.log), 'VariableNames', {'Log'});
            writetable(logTable, filePath, 'Sheet', 'Log');
        end
    end

    methods(Static, Access = private)
        function [players, logLines] = mapColumns(T_in)
            logLines = {};
            map = struct();
            map.ID = ["#", "ID", "Id"];
            map.Nome = ["Nome", "Name", "Giocatore"];
            map.FantaSquadra = ["FantaSquadra", "Squadra", "Team", "Sq."];
            map.Ruolo = ["R.", "Ruolo", "R", "Role"];
            map.RuoloMantra = ["MANTRA", "RM", "RuoloMantra"];
            map.FVM = ["FVM", "Quotazione", "Quot", "Fvm", "FVM/1000"];
            map.Quot = ["QUOT", "Q", "Quot."];
            map.Costo = ["Costo", "Prezzo", "Pagato"];
            map.Eta = ["Eta", "Age", "Under"];
            map.Fuori = ["Fuori", "Fuori lista", "Out"];

            cols = string(T_in.Properties.VariableNames);
            canonical = struct();
            fields = fieldnames(map);
            for i = 1:numel(fields)
                field = fields{i};
                canonical.(field) = FantaIO.findColumn(cols, map.(field));
            end

            required = {'ID', 'Nome', 'FantaSquadra', 'FVM', 'Quot'};
            for i = 1:numel(required)
                if isempty(canonical.(required{i}))
                    error('Colonna obbligatoria mancante: %s', required{i});
                end
            end

            players = table();
            players.ID = FantaIO.cleanNum(T_in{:, canonical.ID});
            players.Nome = string(T_in{:, canonical.Nome});
            players.FantaSquadra = string(T_in{:, canonical.FantaSquadra});
            players.Ruolo = FantaIO.getTextColumn(T_in, canonical.Ruolo);
            players.RuoloMantra = FantaIO.getTextColumn(T_in, canonical.RuoloMantra);
            players.FVM = FantaIO.cleanNum(T_in{:, canonical.FVM});
            players.Quot = FantaIO.cleanNum(T_in{:, canonical.Quot});
            players.Costo = FantaIO.getNumericColumn(T_in, canonical.Costo);
            players.Eta = FantaIO.getNumericColumn(T_in, canonical.Eta, 99);
            players.Fuori = FantaIO.getTextColumn(T_in, canonical.Fuori);

            players.FuoriLista = contains(players.Fuori, "*");

            maskValid = ~ismissing(players.FantaSquadra) & strlength(strtrim(players.FantaSquadra)) > 0;
            maskValid = maskValid & ~isnan(players.FVM) & ~isnan(players.Quot);
            players = players(maskValid, :);

            logLines{end+1, 1} = sprintf('Caricati %d giocatori.', height(players));
        end

        function idx = findColumn(cols, candidates)
            idx = [];
            for i = 1:numel(candidates)
                match = find(strcmpi(cols, candidates(i)), 1);
                if ~isempty(match)
                    idx = match;
                    return;
                end
            end
            for i = 1:numel(candidates)
                match = find(contains(lower(cols), lower(candidates(i))), 1);
                if ~isempty(match)
                    idx = match;
                    return;
                end
            end
        end

        function out = cleanNum(c)
            if iscell(c)
                c = string(c);
            end
            out = str2double(strrep(strrep(string(c), ',', '.'), ' ', ''));
        end

        function out = getNumericColumn(T_in, idx, defaultValue)
            if nargin < 3
                defaultValue = 0;
            end
            if isempty(idx)
                out = defaultValue .* ones(height(T_in), 1);
            else
                out = FantaIO.cleanNum(T_in{:, idx});
                out(isnan(out)) = defaultValue;
            end
        end

        function out = getTextColumn(T_in, idx)
            if isempty(idx)
                out = strings(height(T_in), 1);
            else
                out = string(T_in{:, idx});
            end
        end
    end
end
