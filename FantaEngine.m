classdef FantaEngine
    methods(Static)
        function state = recalcListone(state)
            players = state.data.players;
            if isempty(players)
                state.results.listone = table();
                return;
            end

            params = state.params;
            fvmNorm = FantaEngine.normalize(players.FVM, params.pLowF, params.pHighF);
            quotNorm = FantaEngine.normalize(players.Quot, params.pLowF, params.pHighF);
            weightFvm = params.phi / 100;
            weightQuot = 1 - weightFvm;

            valueFvm = fvmNorm * params.gamma;
            valueQuot = quotNorm;
            valueFinal = params.Wstar .* (weightFvm * valueFvm + weightQuot * valueQuot);

            listone = players;
            listone.ValueFvm = valueFvm;
            listone.ValueQuot = valueQuot;
            listone.ValueFinal = valueFinal;
            listone = sortrows(listone, 'ValueFinal', 'descend');

            state.results.listone = listone;
            state.markDirty({'results'});
        end
    end

    methods(Static, Access = private)
        function normVal = normalize(values, pLow, pHigh)
            values = double(values);
            normVal = zeros(size(values));
            validValues = values(~isnan(values));
            if isempty(validValues)
                return;
            end

            pLow = max(0, min(1, pLow));
            pHigh = max(0, min(1, pHigh));
            if pHigh <= pLow
                pHigh = min(1, pLow + 0.01);
            end

            lo = quantile(validValues, pLow);
            hi = quantile(validValues, pHigh);
            if hi == lo
                return;
            end

            normVal = (values - lo) / (hi - lo);
            normVal = max(0, min(1, normVal));
        end
    end
end
