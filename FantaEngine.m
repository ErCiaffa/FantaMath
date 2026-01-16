classdef FantaEngine
    methods(Static)
        function state = recalcListone(state)
            players = state.data.players;
            if isempty(players)
                state.results.listone = table();
                return;
            end

            params = state.params;
            fvmNorm = FantaEngine.normalize(players.FVM, params.pLow_FVM, params.pHigh_FVM);
            quotNorm = FantaEngine.normalize(players.QUOT, params.pLow_QUOT, params.pHigh_QUOT);

            if params.useExp_FVM
                fvmNorm = fvmNorm .^ params.exp_FVM;
            end
            if params.useExp_QUOT
                quotNorm = quotNorm .^ params.exp_QUOT;
            end

            totalWeight = params.phi + params.omega;
            if totalWeight == 0
                weightFvm = 0.5;
                weightQuot = 0.5;
            else
                weightFvm = params.phi / totalWeight;
                weightQuot = params.omega / totalWeight;
            end

            valueFinal = params.Cstr .* (weightFvm * fvmNorm + weightQuot * quotNorm);
            valueFinal = valueFinal .* params.gamma;
            roleWeights = FantaEngine.roleWeights(players.Role, params);
            valueFinal = valueFinal .* roleWeights;

            listone = players;
            listone.ValueFinal = valueFinal;
            listone = sortrows(listone, 'ValueFinal', 'descend');

            state.results.listone = listone;
            state.markDirty({'results'});
        end
    end

    methods(Static, Access = private)
        function weights = roleWeights(roles, params)
            roles = upper(string(roles));
            weights = ones(size(roles));
            weights(startsWith(roles, "P")) = params.wr_P;
            weights(startsWith(roles, "D")) = params.wr_D;
            weights(startsWith(roles, "C")) = params.wr_C;
            weights(startsWith(roles, "A")) = params.wr_A;
        end

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
