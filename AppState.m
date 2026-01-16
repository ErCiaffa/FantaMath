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
            obj.data = struct('rawTable', table(), 'players', table(), 'meta', AppState.defaultMeta());
            obj.teams = struct('table', table());
            obj.params = AppState.defaultParams();
            obj.paramsLock = AppState.defaultParamLocks(obj.params);
            obj.results = struct('listone', table(), 'ranking', table(), 'kpi', struct());
            obj.ui = struct('selection', struct('viewId', 'Listone', 'filters', struct(), 'team', ""));
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

        function addLog(obj, message, level)
            if nargin < 3 || strlength(string(level)) == 0
                level = 'INFO';
            end
            ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            obj.log{end+1, 1} = sprintf('[%s] %s: %s', ts, upper(string(level)), string(message));
        end
    end

    methods(Static)
        function params = defaultParams()
            params = struct();
            params.Sq = 10;
            params.Cstr = 500;
            params.Cmax = 700;
            params.epsilon = 0.15;
            params.phi = 75;
            params.omega = 25;
            params.pLow_FVM = 0.10;
            params.pHigh_FVM = 0.94;
            params.pLow_QUOT = 0.10;
            params.pHigh_QUOT = 0.92;
            params.useExp_FVM = false;
            params.useExp_QUOT = false;
            params.exp_FVM = 1.00;
            params.exp_QUOT = 1.00;
            params.gamma = 2.40;
            params.mu = 0.20;
            params.k = 20.00;
            params.p = 2.00;
            params.lambda = 0.10;
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

        function meta = defaultMeta()
            meta = struct();
            meta.fileName = "";
            meta.filePath = "";
            meta.rowCount = 0;
            meta.columnsFound = strings(0, 1);
            meta.columnsMapped = strings(0, 1);
            meta.stats = struct('FVM', struct(), 'QUOT', struct(), 'nanPct', struct());
            meta.lastError = "";
        end
    end
end
