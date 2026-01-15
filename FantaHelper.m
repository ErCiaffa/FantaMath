classdef FantaHelper
    methods(Static)
        function state = recalcKPI(state)
            listone = state.results.listone;
            kpi = struct();
            if isempty(listone)
                kpi.CountPlayers = 0;
                kpi.AvgValue = 0;
                kpi.TopValue = 0;
            else
                kpi.CountPlayers = height(listone);
                kpi.AvgValue = mean(listone.ValueFinal, 'omitnan');
                kpi.TopValue = max(listone.ValueFinal, [], 'omitnan');
            end
            if ~isempty(state.teams.table)
                kpi.CountTeams = height(state.teams.table);
            else
                kpi.CountTeams = 0;
            end
            state.results.kpi = kpi;
        end

        function advice = getAdvice(state)
            kpi = state.results.kpi;
            if kpi.CountPlayers == 0
                advice = "Carica un listone per iniziare.";
            else
                advice = sprintf('Valore medio: %.1f. Considera di bloccare i parametri chiave.', kpi.AvgValue);
            end
        end
    end
end
