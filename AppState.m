classdef AppState < handle
    properties
        data struct
        teams struct
        params struct
        paramsLock struct
        results struct
        ui struct
        log cell
        dirty struct
    end

    methods
        function obj = AppState()
            obj.data = struct('rawTable', table(), 'players', table());
            obj.teams = struct('table', table());
            obj.params = AppState.defaultParams();
            obj.paramsLock = AppState.defaultParamLocks(obj.params);
            obj.results = struct('listone', table(), 'ranking', table(), 'kpi', struct());
            obj.ui = struct('selection', struct('viewId', 'Listone', 'filters', struct()));
            obj.log = {};
            obj.dirty = struct('data', true, 'params', true, 'teams', true, 'results', true, 'ui', true);
        end

        function markDirty(obj, fields)
            for i = 1:numel(fields)
                field = fields{i};
                if isfield(obj.dirty, field)
                    obj.dirty.(field) = true;
                end
            end
        end

        function clearDirty(obj, fields)
            for i = 1:numel(fields)
                field = fields{i};
                if isfield(obj.dirty, field)
                    obj.dirty.(field) = false;
                end
            end
        end
    end

    methods(Static)
        function params = defaultParams()
            params = struct();
            params.C_max = 500;
            params.epsilon = 0.15;
            params.Wstar = 1000;
            params.phi = 75;
            params.gamma = 1.00;
            params.mu = 3.00;
            params.k = 0.90;
            params.boostP = 1.10;
            params.alphaF = 0.02;
            params.pLowF = 0.15;
            params.pHighF = 0.995;
            params.GrossDec = 0.30;
            params.GrossOb = 0.05;
            params.PlusTax = 0.00;
            params.wr_P = 1.10;
            params.wr_D = 1.00;
            params.wr_C = 1.00;
            params.wr_A = 1.40;
        end

        function locks = defaultParamLocks(params)
            fields = fieldnames(params);
            locks = struct();
            for i = 1:numel(fields)
                locks.(fields{i}) = false;
            end
        end
    end
end
