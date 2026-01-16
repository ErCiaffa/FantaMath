classdef FantaIO
    methods(Static)
        function state = loadCSV(state, csvFile)
            if nargin < 2 || strlength(string(csvFile)) == 0
                error('File CSV non specificato.');
            end

            [rawTable, usedDelimiter] = FantaIO.readTableWithFallback(csvFile);
            if isempty(rawTable) || height(rawTable) == 0
                error('CSV letto ma vuoto: %s', csvFile);
            end
            state.data.rawTable = rawTable;

            [players, meta, logLines] = FantaIO.mapColumns(rawTable, csvFile);
            state.data.players = players;
            state.data.meta = meta;

            if usedDelimiter ~= ""
                logLines = [logLines; {sprintf('Delimiter rilevato: %s', usedDelimiter)}];
            end
            for i = 1:numel(logLines)
                state.addLog(logLines{i});
            end
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
        function [players, meta, logLines] = mapColumns(T_in, csvFile)
            logLines = {};
            meta = AppState.defaultMeta();
            [~, baseName, ext] = fileparts(csvFile);
            meta.fileName = string(strcat(baseName, ext));
            meta.filePath = string(which(csvFile));
            if meta.filePath == ""
                meta.filePath = string(csvFile);
            end
            meta.rowCount = height(T_in);

            [canonicalMap, synonyms] = FantaIO.buildSynonymMap();
            originalCols = string(T_in.Properties.VariableNames);
            normalizedCols = FantaIO.normalizeColumnNames(originalCols);
            meta.columnsFound = originalCols(:);

            resolved = struct();
            for i = 1:numel(originalCols)
                colKey = normalizedCols(i);
                if strlength(colKey) == 0
                    continue;
                end
                if isfield(canonicalMap, colKey)
                    canonical = canonicalMap.(colKey);
                    if ~isfield(resolved, canonical)
                        resolved.(canonical) = i;
                    end
                end
            end

            required = {'name', 'fvm', 'quot'};
            missing = required(~isfield(resolved, required));
            if ~isempty(missing)
                foundList = strjoin(originalCols, ', ');
                supportedList = FantaIO.describeSynonyms(synonyms);
                error(['Colonne obbligatorie mancanti: %s.\n' ...
                    'Colonne trovate: %s.\n' ...
                    'Sinonimi supportati: %s.'], strjoin(missing, ', '), foundList, supportedList);
            end

            optionalFields = {'team', 'role', 'rolemantra', 'cost', 'owned', 'age', 'out', 'id'};
            for i = 1:numel(optionalFields)
                if ~isfield(resolved, optionalFields{i})
                    logLines{end+1, 1} = sprintf('Warning: colonna opzionale non trovata: %s (verrà riempita con NaN o vuoto).', optionalFields{i});
                end
            end

            players = table();
            players.ID = FantaIO.getNumericColumn(T_in, resolved, 'id', NaN);
            players.Name = FantaIO.getTextColumn(T_in, resolved, 'name');
            players.Team = FantaIO.getTextColumn(T_in, resolved, 'team');
            players.Role = FantaIO.getTextColumn(T_in, resolved, 'role');
            players.RoleMantra = FantaIO.getTextColumn(T_in, resolved, 'rolemantra');
            players.FVM = FantaIO.getNumericColumn(T_in, resolved, 'fvm', NaN);
            players.QUOT = FantaIO.getNumericColumn(T_in, resolved, 'quot', NaN);
            players.Cost = FantaIO.getNumericColumn(T_in, resolved, 'cost', NaN);
            players.Owned = FantaIO.getTextColumn(T_in, resolved, 'owned');
            if all(strlength(strtrim(players.Owned)) == 0) && isfield(resolved, 'team')
                players.Owned = players.Team;
            end
            players.Age = FantaIO.getNumericColumn(T_in, resolved, 'age', NaN);
            players.Out = FantaIO.getTextColumn(T_in, resolved, 'out');
            players.OutList = contains(players.Out, "*");

            nanFvm = sum(isnan(players.FVM));
            nanQuot = sum(isnan(players.QUOT));
            nanCost = sum(isnan(players.Cost));
            if nanFvm > 0
                logLines{end+1, 1} = sprintf('Warning: %d valori FVM non numerici convertiti in NaN.', nanFvm);
            end
            if nanQuot > 0
                logLines{end+1, 1} = sprintf('Warning: %d valori QUOT non numerici convertiti in NaN.', nanQuot);
            end
            if nanCost > 0
                logLines{end+1, 1} = sprintf('Warning: %d valori Cost non numerici convertiti in NaN.', nanCost);
            end

            meta.columnsMapped = string(fieldnames(resolved));
            meta.stats = FantaIO.buildStats(players);

            maskValid = strlength(strtrim(players.Name)) > 0;
            maskValid = maskValid & ~isnan(players.FVM) & ~isnan(players.QUOT);
            players = players(maskValid, :);

            if height(players) == 0
                error('CSV letto ma nessun giocatore valido dopo il parsing.');
            end

            logLines{end+1, 1} = sprintf('Caricati %d giocatori.', height(players));
            logLines{end+1, 1} = sprintf('Colonne canoniche: %s', strjoin(meta.columnsMapped, ', '));
            logLines{end+1, 1} = sprintf('Righe CSV: %d', meta.rowCount);
            logLines{end+1, 1} = sprintf('Path file: %s', meta.filePath);
        end

        function out = cleanNum(c)
            if iscell(c)
                c = string(c);
            end
            out = str2double(strrep(strrep(string(c), ',', '.'), ' ', ''));
        end

        function out = getNumericColumn(T_in, resolved, fieldName, defaultValue)
            if nargin < 4
                defaultValue = NaN;
            end
            if isfield(resolved, fieldName)
                out = FantaIO.cleanNum(T_in{:, resolved.(fieldName)});
            else
                out = defaultValue .* ones(height(T_in), 1);
            end
        end

        function out = getTextColumn(T_in, resolved, fieldName)
            if isfield(resolved, fieldName)
                out = string(T_in{:, resolved.(fieldName)});
            else
                out = strings(height(T_in), 1);
            end
        end

        function [tableOut, usedDelimiter] = readTableWithFallback(filePath)
            usedDelimiter = "";
            [~, ~, ext] = fileparts(filePath);
            if any(strcmpi(ext, {'.xlsx', '.xls'}))
                opts = detectImportOptions(filePath, 'VariableNamingRule', 'preserve');
                tableOut = readtable(filePath, opts);
                return;
            end
            delimiters = [";", ",", "\t", "|"];
            lastError = [];
            for i = 1:numel(delimiters)
                try
                    opts = detectImportOptions(filePath, 'Delimiter', delimiters(i), 'VariableNamingRule', 'preserve');
                    tableOut = readtable(filePath, opts);
                    if width(tableOut) > 1
                        usedDelimiter = delimiters(i);
                        return;
                    end
                catch ME
                    lastError = ME;
                end
            end
            if ~isempty(lastError)
                rethrow(lastError);
            end
            tableOut = table();
        end

        function normalized = normalizeColumnNames(cols)
            normalized = lower(strtrim(cols));
            normalized = regexprep(normalized, '[^a-z0-9]', '');
        end

        function [canonicalMap, synonyms] = buildSynonymMap()
            synonyms = struct();
            synonyms.id = ["#", "id", "playerid"];
            synonyms.name = ["nome", "name", "giocatore", "player"];
            synonyms.team = ["fantasquadra", "squadra", "team", "sq"];
            synonyms.owned = ["owned", "owner", "posseduto", "fantasquadra"];
            synonyms.role = ["r", "ruolo", "role", "pos", "posizione"];
            synonyms.rolemantra = ["rm", "ruolomantra", "mantra"];
            synonyms.fvm = ["fvm", "fvm1000", "quotazione", "fvmk", "valore"];
            synonyms.quot = ["quot", "q", "quotazioneuff", "quotuff", "quotazioneufficiale"];
            synonyms.cost = ["costo", "prezzo", "pagato", "cost", "price"];
            synonyms.age = ["eta", "age", "under"];
            synonyms.out = ["fuori", "fuorilista", "out", "fuorilista"];

            canonicalMap = struct();
            fields = fieldnames(synonyms);
            for i = 1:numel(fields)
                key = fields{i};
                values = synonyms.(key);
                for j = 1:numel(values)
                    normalized = regexprep(lower(strtrim(values(j))), '[^a-z0-9]', '');
                    if strlength(normalized) == 0
                        continue;
                    end
                    canonicalMap.(normalized) = key;
                end
            end
        end

        function text = describeSynonyms(synonyms)
            fields = fieldnames(synonyms);
            parts = strings(1, numel(fields));
            for i = 1:numel(fields)
                key = fields{i};
                parts(i) = sprintf('%s=[%s]', key, strjoin(synonyms.(key), '|'));
            end
            text = strjoin(parts, '; ');
        end

        function stats = buildStats(players)
            stats = struct();
            stats.FVM = FantaIO.basicStats(players.FVM);
            stats.QUOT = FantaIO.basicStats(players.QUOT);
            stats.nanPct = struct();
            stats.nanPct.FVM = FantaIO.nanPct(players.FVM);
            stats.nanPct.QUOT = FantaIO.nanPct(players.QUOT);
        end

        function out = basicStats(values)
            out = struct('min', NaN, 'max', NaN, 'mean', NaN);
            if isempty(values)
                return;
            end
            out.min = min(values, [], 'omitnan');
            out.max = max(values, [], 'omitnan');
            out.mean = mean(values, 'omitnan');
        end

        function pct = nanPct(values)
            if isempty(values)
                pct = 0;
                return;
            end
            pct = 100 * sum(isnan(values)) / numel(values);
        end
    end
end
