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
