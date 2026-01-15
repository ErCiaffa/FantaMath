classdef FantaTuner
    methods(Static)
        function state = tuneParams(state, mode, target)
            if nargin < 3
                target = 'avg';
            end
            params = state.params;
            locks = state.paramsLock;

            adjustable = fieldnames(params);
            for i = 1:numel(adjustable)
                name = adjustable{i};
                if isfield(locks, name) && locks.(name)
                    continue;
                end
                params.(name) = FantaTuner.adjustValue(params.(name), mode, target);
            end
            state.params = params;
            state.markDirty({'params', 'results'});
        end
    end

    methods(Static, Access = private)
        function value = adjustValue(value, mode, target)
            switch lower(mode)
                case 'manual'
                    value = value;
                case 'ottimizza'
                    value = FantaTuner.applyTarget(value, target, 0.05);
                otherwise
                    value = FantaTuner.applyTarget(value, target, 0.02);
            end
        end

        function value = applyTarget(value, target, step)
            switch lower(target)
                case 'avg'
                    value = value * (1 + step);
                case 'var'
                    value = value * (1 - step);
                case 'top'
                    value = value * (1 + 2 * step);
                otherwise
                    value = value;
            end
        end
    end
end
