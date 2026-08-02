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
