function players = loadListone(csvFile)
%LOADLISTONE Load a listone CSV (listone.csv or example_listone.csv schema) into a validated table.
%
% players = loadListone(csvFile) reads the semicolon-delimited, comma-decimal CSV at csvFile,
% resolves its columns via a synonym map covering both known real-world schemas, and returns a
% table with columns id, nome, roleClassic, roleMantra, roleTokens, fvm, quot, age, team, costo,
% owned, fuoriLista.
%
% Blocking validation (FORM-10) runs over the ENTIRE file before any row is returned: an
% unrecognized role token throws FantaMath:data:unrecognizedRole; a missing Costo on an owned
% (posseduto) row throws FantaMath:data:missingCost. There is no partially-valid-listone state.
    arguments
        csvFile (1,1) string {mustBeNonzeroLengthText}
    end

    opts = detectImportOptions(csvFile, 'Delimiter', ';', 'VariableNamingRule', 'preserve');
    raw = readtable(csvFile, opts);

    originalCols = string(raw.Properties.VariableNames);
    resolved = resolveColumns(originalCols);

    requiredSimple = ["nome", "fvm", "quot", "team"];
    missingList = strings(0, 1);
    for k = 1:numel(requiredSimple)
        if ~isfield(resolved, requiredSimple(k))
            missingList(end+1, 1) = requiredSimple(k); %#ok<AGROW>
        end
    end

    hasMantraColumn = isfield(resolved, 'roleMantra');
    if ~hasMantraColumn && isfield(resolved, 'roleClassic')
        % Assumption A1 (LOCK): R.MANTRA is the operative role column. When a file has no
        % dedicated Mantra column (example_listone.csv schema), fall back to the classic
        % Ruolo column as the roleMantra source so the same downstream parsing/validation
        % path handles both schemas.
        resolved.roleMantra = resolved.roleClassic;
    end
    if ~isfield(resolved, 'roleMantra')
        missingList(end+1, 1) = "ruolo";
    end

    if ~isempty(missingList)
        error('FantaMath:csv:missingColumns', ...
            ['Colonne obbligatorie mancanti: %s.\n' ...
             'Colonne trovate: %s.\n' ...
             'Sinonimi supportati: %s.'], ...
            strjoin(missingList, ', '), strjoin(originalCols, ', '), describeAliasSpec());
    end

    n = height(raw);

    id = numericColumn(raw, optIndex(resolved, 'id'), n);
    nome = textColumn(raw, resolved.nome, n);
    roleClassic = textColumn(raw, optIndex(resolved, 'roleClassic'), n);
    roleMantraRaw = textColumn(raw, resolved.roleMantra, n);
    fvm = numericColumn(raw, resolved.fvm, n);
    quot = numericColumn(raw, resolved.quot, n);
    age = numericColumn(raw, optIndex(resolved, 'age'), n);
    team = textColumn(raw, resolved.team, n);
    costo = numericColumn(raw, optIndex(resolved, 'costo'), n);
    fuoriListaRaw = textColumn(raw, optIndex(resolved, 'fuoriLista'), n);

    owned = strlength(strtrim(team)) > 0;
    fuoriLista = strtrim(fuoriListaRaw) == "*";

    roleTokens = cell(n, 1);
    for i = 1:n
        roleTokens{i} = strtrim(split(roleMantraRaw(i), "/"));
    end

    whitelist = mantraRoleWhitelist();
    if ~hasMantraColumn
        % Deviation (Rule 1 - auto-fixed bug): Assumption A3 locks the whitelist to exactly
        % the 12 Mantra tokens, but example_listone.csv (D-01's second required schema) has no
        % Mantra column and uses classic single-letter roles (e.g. "D") that are not in that
        % 12-token set. Strictly applying A3 here would reject a valid, expected file and
        % break the acceptance criteria requiring example_listone.csv to load all 4 rows
        % without loss. When there is no genuine Mantra column, accept the classic role
        % tokens ("P","D") in addition to the Mantra whitelist (A and C already overlap).
        % Real listone.csv (which does have a Mantra column) is unaffected and keeps the
        % strict 12-token whitelist exactly as locked.
        whitelist = [whitelist, "P", "D"];
    end

    unrecognizedMask = false(n, 1);
    for i = 1:n
        tokens = roleTokens{i};
        tokens = tokens(strlength(tokens) > 0);
        if ~all(ismember(tokens, whitelist))
            unrecognizedMask(i) = true;
        end
    end
    if any(unrecognizedMask)
        idxBad = find(unrecognizedMask);
        parts = strings(numel(idxBad), 1);
        for k = 1:numel(idxBad)
            r = idxBad(k);
            parts(k) = sprintf('%s (%s)', nome(r), roleMantraRaw(r));
        end
        error('FantaMath:data:unrecognizedRole', ...
            'Ruolo non riconosciuto per %d giocatori: %s. Correggi il listone CSV e ricarica.', ...
            numel(idxBad), strjoin(parts, ', '));
    end

    missingCostMask = owned & isnan(costo);
    if any(missingCostMask)
        idxBad = find(missingCostMask);
        error('FantaMath:data:missingCost', ...
            'Costo acquisto mancante per %d giocatori posseduti: %s. Correggi il listone CSV e ricarica.', ...
            numel(idxBad), strjoin(nome(idxBad), ', '));
    end

    players = table(id, nome, roleClassic, roleMantraRaw, roleTokens, fvm, quot, age, team, costo, owned, fuoriLista, ...
        'VariableNames', {'id', 'nome', 'roleClassic', 'roleMantra', 'roleTokens', 'fvm', 'quot', 'age', 'team', 'costo', 'owned', 'fuoriLista'});
end

function resolved = resolveColumns(colNames)
    rawTrimmed = strtrim(regexprep(string(colNames), '^\x{FEFF}', ''));
    cleaned = normalizeHeaders(colNames);

    colIndexByName = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for i = 1:numel(cleaned)
        if strlength(cleaned(i)) == 0
            continue
        end
        key = char(cleaned(i));
        if ~isKey(colIndexByName, key)
            colIndexByName(key) = i;
        end
    end

    resolved = struct();

    idIdx = find(rawTrimmed == "#", 1);
    if ~isempty(idIdx)
        resolved.id = idIdx;
    end

    aliasSpec = buildAliasSpec();
    canonicalFields = fieldnames(aliasSpec);
    for i = 1:numel(canonicalFields)
        f = canonicalFields{i};
        aliases = aliasSpec.(f);
        for j = 1:numel(aliases)
            key = char(aliases(j));
            if isKey(colIndexByName, key)
                resolved.(f) = colIndexByName(key);
                break
            end
        end
    end
end

function aliasSpec = buildAliasSpec()
    aliasSpec = struct();
    aliasSpec.nome = "nome";
    aliasSpec.roleClassic = ["r", "ruolo", "role"];
    aliasSpec.roleMantra = ["rmantra", "ruolomantra", "mantra"];
    aliasSpec.fvm = ["fvm1000", "fvm", "quotazione"];
    aliasSpec.quot = ["quot", "quotazione"];
    aliasSpec.age = ["under", "eta", "age"];
    aliasSpec.team = "fantasquadra";
    aliasSpec.costo = "costo";
    aliasSpec.fuoriLista = "fuorilista";
end

function text = describeAliasSpec()
    aliasSpec = buildAliasSpec();
    fields = fieldnames(aliasSpec);
    parts = strings(1, numel(fields));
    for i = 1:numel(fields)
        key = fields{i};
        parts(i) = sprintf('%s=[%s]', key, strjoin(aliasSpec.(key), '|'));
    end
    parts(end+1) = "id=[#]";
    text = strjoin(parts, '; ');
end

function normalized = normalizeHeaders(names)
    normalized = string(names);
    normalized = regexprep(normalized, '^\x{FEFF}', '');
    normalized = lower(strtrim(normalized));
    normalized = regexprep(normalized, '[^a-z0-9]', '');
end

function w = mantraRoleWhitelist()
    w = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
end

function idx = optIndex(resolved, name)
    if isfield(resolved, name)
        idx = resolved.(name);
    else
        idx = [];
    end
end

function out = numericColumn(T, idx, n)
    if isempty(idx)
        out = nan(n, 1);
        return
    end
    out = cleanNumeric(T{:, idx});
end

function out = cleanNumeric(raw)
    out = str2double(strrep(strrep(string(raw), ',', '.'), ' ', ''));
end

function out = textColumn(T, idx, n)
    if isempty(idx)
        out = strings(n, 1);
        return
    end
    out = string(T{:, idx});
    out(ismissing(out)) = "";
end
