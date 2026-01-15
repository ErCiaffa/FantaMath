classdef FantaManager
    methods(Static)
        function state = applyTransaction(state, tx)
            if ~isfield(tx, 'type')
                error('Transazione senza tipo.');
            end
            switch lower(tx.type)
                case 'svincolo'
                    state = FantaManager.applyRelease(state, tx);
                case 'bonus'
                    state = FantaManager.applyBonus(state, tx);
                otherwise
                    error('Tipo transazione non supportato: %s', tx.type);
            end
            state.markDirty({'teams', 'results'});
        end

        function state = recalcTeams(state)
            players = state.data.players;
            if isempty(players)
                state.teams.table = table();
                return;
            end
            teams = unique(players.FantaSquadra);
            teamTable = table('Size', [numel(teams), 5], ...
                'VariableTypes', {'string', 'double', 'double', 'double', 'double'}, ...
                'VariableNames', {'Team', 'Bank', 'RosterValue', 'ReleaseValue', 'BonusMalus'});

            for i = 1:numel(teams)
                team = teams(i);
                mask = players.FantaSquadra == team;
                rosterValue = sum(players.FVM(mask), 'omitnan');
                releaseValue = sum(players.Costo(mask), 'omitnan');
                teamTable.Team(i) = team;
                teamTable.Bank(i) = 0;
                teamTable.RosterValue(i) = rosterValue;
                teamTable.ReleaseValue(i) = releaseValue;
                teamTable.BonusMalus(i) = 0;
            end

            state.teams.table = teamTable;
        end
    end

    methods(Static, Access = private)
        function state = applyRelease(state, tx)
            if ~isfield(tx, 'playerId')
                error('Svincolo senza playerId.');
            end
            idx = state.data.players.ID == tx.playerId;
            if any(idx)
                state.data.players.FantaSquadra(idx) = "";
            end
        end

        function state = applyBonus(state, tx)
            if ~isfield(tx, 'team') || ~isfield(tx, 'amount')
                error('Bonus senza team/amount.');
            end
            if isempty(state.teams.table)
                return;
            end
            mask = state.teams.table.Team == string(tx.team);
            state.teams.table.BonusMalus(mask) = state.teams.table.BonusMalus(mask) + tx.amount;
        end
    end
end
