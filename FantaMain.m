function FantaMain()
    appState = AppState();
    appState.addLog('Nessun CSV caricato. Usa "Carica CSV" per iniziare.');

    fig = uifigure('Name', 'FantaTuner Pro', 'Position', [50 50 1500 900]);
    fig.WindowState = 'maximized';

    root = uigridlayout(fig, [2 1]);
    root.RowHeight = {45, '1x'};
    root.Padding = [10 10 10 10];

    controller = buildController(appState);

    topbar = uigridlayout(root, [1 6]);
    topbar.ColumnWidth = {120, 120, 120, 120, 120, '1x'};
    uibutton(topbar, 'Text', 'Carica CSV', 'ButtonPushedFcn', @(~, ~) controller.onLoadCSV());
    uibutton(topbar, 'Text', 'Salva Config', 'ButtonPushedFcn', @(~, ~) controller.onSaveConfig());
    uibutton(topbar, 'Text', 'Carica Config', 'ButtonPushedFcn', @(~, ~) controller.onLoadConfig());
    uibutton(topbar, 'Text', 'Esporta Excel', 'ButtonPushedFcn', @(~, ~) controller.onExport());
    uibutton(topbar, 'Text', 'Reset Defaults', 'ButtonPushedFcn', @(~, ~) controller.onResetDefaults());

    main = uigridlayout(root, [1 3]);
    main.Layout.Row = 2;
    main.ColumnWidth = {360, '1x', 360};
    main.ColumnSpacing = 10;
    panelConfig = PanelConfig(main, appState, controller);
    panelConfig.Layout.Column = 1;
    panelAnalytics = PanelAnalytics(main, appState, controller);
    panelAnalytics.Layout.Column = 2;
    panelTeams = PanelTeam(main, appState, controller);
    panelTeams.Layout.Column = 3;

    updateApp();

    function controller = buildController(state)
        controller = struct();
        controller.tunerMode = 'Suggerito';
        controller.tunerTarget = 'avg';
        controller.onParamChange = @onParamChange;
        controller.onLockChange = @onLockChange;
        controller.onViewChange = @onViewChange;
        controller.onTeamEdit = @onTeamEdit;
        controller.onExport = @onExport;
        controller.onLoadCSV = @onLoadCSV;
        controller.onSaveConfig = @onSaveConfig;
        controller.onLoadConfig = @onLoadConfig;
        controller.onResetDefaults = @onResetDefaults;
        controller.onSearch = @onSearch;
        controller.onTunerMode = @onTunerMode;
        controller.onTunerTarget = @onTunerTarget;
        controller.onTune = @onTune;
        controller.onLogUpdate = [];
        controller.onListoneUpdate = [];
        controller.onChartUpdate = [];
        controller.onKpiUpdate = [];
        controller.onAdviceUpdate = [];
        controller.onTeamsUpdate = [];
        controller.onMetaUpdate = [];
    end

    function onParamChange(name, value, range)
        if isfield(appState.paramsLock, name) && appState.paramsLock.(name)
            appState.addLog(sprintf('Parametro %s bloccato, modifica ignorata.', name), 'WARN');
            updateApp();
            return;
        end
        correctedValue = value;
        if nargin >= 3 && ~isempty(range)
            minVal = range(1);
            maxVal = range(2);
            if correctedValue < minVal || correctedValue > maxVal
                correctedValue = min(max(correctedValue, minVal), maxVal);
                appState.addLog(sprintf('Parametro %s fuori range, corretto a %.4g.', name, correctedValue), 'WARN');
            end
        end
        appState.params.(name) = correctedValue;
        appState.markDirty({'params', 'results'});
        updateApp();
    end

    function onLockChange(name, isLocked)
        appState.paramsLock.(name) = isLocked;
        appState.markDirty({'params'});
        updateApp();
    end

    function onViewChange(viewId)
        appState.ui.selection.viewId = viewId;
        appState.markDirty({'ui'});
        updateApp();
    end

    function onSearch(text)
        appState.ui.selection.filters.search = text;
        appState.markDirty({'ui'});
        updateApp();
    end

    function onTeamEdit(evt)
        if isempty(appState.teams.table)
            return;
        end
        row = evt.Indices(1);
        colName = appState.teams.table.Properties.VariableNames{evt.Indices(2)};
        appState.teams.table.(colName)(row) = evt.NewData;
        appState.markDirty({'teams'});
        updateApp();
    end

    function onExport()
        [file, path] = uiputfile('*.xlsx', 'Export Excel');
        if isequal(file, 0)
            appState.addLog('Export Excel annullato.');
            updateApp();
            return;
        end
        FantaIO.exportExcel(appState, fullfile(path, file));
        appState.addLog('Export Excel completato.');
        updateApp();
    end

    function onLoadCSV()
        [file, path] = uigetfile({'*.csv;*.xlsx', 'CSV or Excel'});
        if isequal(file, 0)
            appState.addLog('Caricamento annullato.');
            updateApp();
            return;
        end
        try
            filePath = fullfile(path, file);
            appState.addLog(sprintf('Caricamento CSV: %s', filePath));
            appState = FantaIO.loadCSV(appState, filePath);
            appState.dirty.data = true;
            appState.dirty.results = true;
            updateApp();
        catch ME
            appState.addLog(ME.message, 'ERROR');
            stackLines = arrayfun(@(s) sprintf('%s:%d', s.file, s.line), ME.stack, 'UniformOutput', false);
            for i = 1:numel(stackLines)
                appState.addLog(stackLines{i}, 'ERROR');
            end
            uialert(fig, ME.message, 'Errore caricamento CSV');
            updateApp();
        end
    end

    function onSaveConfig()
        [file, path] = uiputfile('*.json', 'Salva Config');
        if isequal(file, 0)
            appState.addLog('Salvataggio config annullato.');
            updateApp();
            return;
        end
        FantaIO.saveConfig(appState, fullfile(path, file));
        appState.addLog('Config salvata.');
        updateApp();
    end

    function onLoadConfig()
        [file, path] = uigetfile('*.json', 'Carica Config');
        if isequal(file, 0)
            appState.addLog('Caricamento config annullato.');
            updateApp();
            return;
        end
        try
            appState = FantaIO.loadConfig(appState, fullfile(path, file));
            appState.addLog('Config caricata.');
            updateApp();
        catch ME
            appState.addLog(ME.message, 'ERROR');
            stackLines = arrayfun(@(s) sprintf('%s:%d', s.file, s.line), ME.stack, 'UniformOutput', false);
            for i = 1:numel(stackLines)
                appState.addLog(stackLines{i}, 'ERROR');
            end
            uialert(fig, ME.message, 'Errore caricamento config');
            updateApp();
        end
    end

    function onResetDefaults()
        appState.params = AppState.defaultParams();
        appState.paramsLock = AppState.defaultParamLocks(appState.params);
        appState.markDirty({'params', 'results', 'ui'});
        appState.addLog('Parametri ripristinati ai valori di default.');
        updateApp();
    end

    function onTunerMode(mode)
        controller.tunerMode = mode;
    end

    function onTunerTarget(target)
        controller.tunerTarget = target;
    end

    function onTune()
        appState = FantaTuner.tuneParams(appState, controller.tunerMode, controller.tunerTarget);
        updateApp();
    end

    function updateApp()
        if appState.dirty.data || appState.dirty.params
            appState = FantaEngine.recalcListone(appState);
            appState = FantaManager.recalcTeams(appState);
            appState = recalcRanking(appState);
            appState = FantaHelper.recalcKPI(appState);
            if isempty(appState.results.listone)
                appState.addLog('Listone vuoto: verifica colonne CSV o parametri.', 'WARN');
            end
            appState.clearDirty({'data', 'params'});
        end

        if appState.dirty.teams
            appState = FantaHelper.recalcKPI(appState);
            appState.clearDirty({'teams'});
        end

        updatePanels();
    end

    function updatePanels()
        if ~isempty(controller.onLogUpdate)
            controller.onLogUpdate(string(appState.log));
        end

        viewId = appState.ui.selection.viewId;
        listone = applySearch(appState.results.listone, appState.ui.selection);
        if strcmp(viewId, 'Listone')
            if ~isempty(controller.onListoneUpdate)
                controller.onListoneUpdate(listone);
            end
        end

        if ~isempty(controller.onKpiUpdate)
            controller.onKpiUpdate(appState.results.kpi);
        end

        if ~isempty(controller.onAdviceUpdate)
            controller.onAdviceUpdate(FantaHelper.getAdvice(appState));
        end

        if ~isempty(controller.onTeamsUpdate)
            controller.onTeamsUpdate(appState.teams.table);
        end

        if ~isempty(controller.onChartUpdate) && ~strcmp(viewId, 'Listone')
            viewModel = buildViewModel(appState, viewId);
            controller.onChartUpdate(viewModel, viewId);
        end

        if ~isempty(controller.onMetaUpdate)
            controller.onMetaUpdate(appState.data.meta);
        end
    end
end

function listone = applySearch(listone, selection)
    if isempty(listone)
        return;
    end
    if isfield(selection, 'filters') && isfield(selection.filters, 'search')
        query = string(selection.filters.search);
        if strlength(query) > 0
            mask = contains(lower(listone.Name), lower(query));
            listone = listone(mask, :);
        end
    end
end

function viewModel = buildViewModel(state, viewId)
    listone = state.results.listone;
    viewModel = struct();
    if isempty(listone)
        viewModel.values = [];
        viewModel.x = [];
        viewModel.y = [];
        viewModel.c = [];
        viewModel.matrix = [];
        viewModel.xLabel = '';
        viewModel.yLabel = '';
        return;
    end

    switch viewId
        case 'Scatter'
            viewModel.x = listone.FVM;
            viewModel.y = listone.ValueFinal;
            viewModel.c = listone.QUOT;
            viewModel.xLabel = 'FVM';
            viewModel.yLabel = 'Valore Finale';
        case 'Istogramma'
            viewModel.values = listone.ValueFinal;
            viewModel.xLabel = 'Valore Finale';
        case 'Heatmap'
            roles = string(listone.Role);
            uniqueRoles = unique(roles);
            counts = zeros(numel(uniqueRoles));
            for i = 1:numel(uniqueRoles)
                for j = 1:numel(uniqueRoles)
                    mask = roles == uniqueRoles(i);
                    counts(i, j) = mean(listone.ValueFinal(mask), 'omitnan');
                end
            end
            viewModel.matrix = counts;
            viewModel.xTick = 1:numel(uniqueRoles);
            viewModel.xTickLabel = uniqueRoles;
            viewModel.yTick = 1:numel(uniqueRoles);
            viewModel.yTickLabel = uniqueRoles;
        otherwise
            viewModel = struct();
    end
end

function state = recalcRanking(state)
    if isempty(state.results.listone)
        state.results.ranking = table();
        return;
    end
    data = state.results.listone;
    teams = unique(data.Team);
    ranking = table('Size', [numel(teams), 2], 'VariableTypes', {'string', 'double'}, ...
        'VariableNames', {'Team', 'TotalValue'});
    for i = 1:numel(teams)
        team = teams(i);
        mask = data.Team == team;
        ranking.Team(i) = team;
        ranking.TotalValue(i) = sum(data.ValueFinal(mask), 'omitnan');
    end
    ranking = sortrows(ranking, 'TotalValue', 'descend');
    state.results.ranking = ranking;
end
