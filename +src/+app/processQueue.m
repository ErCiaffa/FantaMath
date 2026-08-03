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
            state = src.state.LeagueState.recomputeScores(state);
            state.meta.lastCsvPath = string(entry.payload.csvPath);
            state.meta.lastCsvLoadedAt = datetime('now');

        case "setEpsilon"
            state = src.state.LeagueState.setEpsilon(state, entry.payload.epsilon);

        case "setBankOverride"
            state = src.state.LeagueState.setBankOverride(state, string(entry.payload.teamName), entry.payload.value);

        case "applyBonusMalus"
            state = src.state.LeagueState.applyBonusMalus(state, string(entry.payload.teamName), ...
                entry.payload.amount, string(entry.payload.motivo));

        case "setFormulaParams"
            state = src.state.LeagueState.setFormulaParams(state, entry.payload.phi, entry.payload.alphaF, ...
                entry.payload.alphaQ, entry.payload.pLow, entry.payload.pHigh);

        case "setRoleOverride"
            state = src.state.LeagueState.setRoleOverride(state, entry.payload.roleOverride);

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
