function FantaMain()
    appState = AppState();
    appState = FantaIO.loadCSV(appState, '');

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
    end

    function onParamChange(name, value)
        appState.params.(name) = value;
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
            return;
        end
        FantaIO.exportExcel(appState, fullfile(path, file));
        appState.log{end+1, 1} = 'Export Excel completato.';
        updateApp();
    end

    function onLoadCSV()
        [file, path] = uigetfile({'*.csv;*.xlsx', 'CSV or Excel'});
        if isequal(file, 0)
            return;
        end
        appState = FantaIO.loadCSV(appState, fullfile(path, file));
        updateApp();
    end

    function onSaveConfig()
        [file, path] = uiputfile('*.json', 'Salva Config');
        if isequal(file, 0)
            return;
        end
        FantaIO.saveConfig(appState, fullfile(path, file));
        appState.log{end+1, 1} = 'Config salvata.';
        updateApp();
    end

    function onLoadConfig()
        [file, path] = uigetfile('*.json', 'Carica Config');
        if isequal(file, 0)
            return;
        end
        appState = FantaIO.loadConfig(appState, fullfile(path, file));
        updateApp();
    end

    function onResetDefaults()
        appState.params = AppState.defaultParams();
        appState.paramsLock = AppState.defaultParamLocks(appState.params);
        appState.markDirty({'params', 'results', 'ui'});
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
    end
end

function listone = applySearch(listone, selection)
    if isempty(listone)
        return;
    end
    if isfield(selection, 'filters') && isfield(selection.filters, 'search')
        query = string(selection.filters.search);
        if strlength(query) > 0
            mask = contains(lower(listone.Nome), lower(query));
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
            viewModel.c = listone.Quot;
            viewModel.xLabel = 'FVM';
            viewModel.yLabel = 'Valore Finale';
        case 'Istogramma'
            viewModel.values = listone.ValueFinal;
            viewModel.xLabel = 'Valore Finale';
        case 'Heatmap'
            roles = string(listone.Ruolo);
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
    teams = unique(data.FantaSquadra);
    ranking = table('Size', [numel(teams), 2], 'VariableTypes', {'string', 'double'}, ...
        'VariableNames', {'Team', 'TotalValue'});
    for i = 1:numel(teams)
        team = teams(i);
        mask = data.FantaSquadra == team;
        ranking.Team(i) = team;
        ranking.TotalValue(i) = sum(data.ValueFinal(mask), 'omitnan');
    end
    ranking = sortrows(ranking, 'TotalValue', 'descend');
    state.results.ranking = ranking;
end
