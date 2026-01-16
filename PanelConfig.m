function panel = PanelConfig(parent, appState, controller)
    panel = uipanel(parent, 'Title', 'Parametri', 'FontWeight', 'bold');
    layout = uigridlayout(panel, [4 1]);
    layout.RowHeight = {'1x', 140, 160, 140};
    layout.Padding = [10 10 10 10];

    tabGroup = uitabgroup(layout);
    tabGroup.Layout.Row = 1;

    tabLeague = uitab(tabGroup, 'Title', 'Lega');
    leagueGrid = uigridlayout(tabLeague, [4 4]);
    leagueGrid.ColumnWidth = {180, 120, 70, 60};
    leagueGrid.RowHeight = {32, 32, 32, 32};
    createParamRow(leagueGrid, 1, 'Sq', 'Squadre (Sq)', appState, controller, [4 20], ...
        'Numero di squadre della lega.');
    createParamRow(leagueGrid, 2, 'Cstr', 'Crediti iniziali (Cstr)', appState, controller, [100 1000], ...
        'Crediti iniziali per squadra.');
    createParamRow(leagueGrid, 3, 'Cmax', 'Cap liquidità (Cmax)', appState, controller, [100 2000], ...
        'Cap assoluto liquidità lega.');
    createParamRow(leagueGrid, 4, 'epsilon', 'Margine crescita (ε)', appState, controller, [0 0.5], ...
        'Margine crescita capitale consentita.');

    tabWeights = uitab(tabGroup, 'Title', 'Pesi');
    weightGrid = uigridlayout(tabWeights, [2 4]);
    weightGrid.ColumnWidth = {180, 120, 70, 60};
    weightGrid.RowHeight = {32, 32};
    createParamRow(weightGrid, 1, 'phi', 'Peso FVM (φ)', appState, controller, [0 100], ...
        'Peso FVM (0-100).');
    createParamRow(weightGrid, 2, 'omega', 'Peso QUOT (ω)', appState, controller, [0 100], ...
        'Peso QUOT (0-100).');

    tabPercentiles = uitab(tabGroup, 'Title', 'Percentili');
    pctGrid = uigridlayout(tabPercentiles, [4 4]);
    pctGrid.ColumnWidth = {180, 120, 70, 60};
    pctGrid.RowHeight = {32, 32, 32, 32};
    createParamRow(pctGrid, 1, 'pLow_FVM', 'pLow FVM', appState, controller, [0 1], ...
        'Percentile basso FVM.');
    createParamRow(pctGrid, 2, 'pHigh_FVM', 'pHigh FVM', appState, controller, [0 1], ...
        'Percentile alto FVM.');
    createParamRow(pctGrid, 3, 'pLow_QUOT', 'pLow QUOT', appState, controller, [0 1], ...
        'Percentile basso QUOT.');
    createParamRow(pctGrid, 4, 'pHigh_QUOT', 'pHigh QUOT', appState, controller, [0 1], ...
        'Percentile alto QUOT.');

    tabTransforms = uitab(tabGroup, 'Title', 'Trasf.');
    transGrid = uigridlayout(tabTransforms, [4 4]);
    transGrid.ColumnWidth = {180, 120, 70, 60};
    transGrid.RowHeight = {32, 32, 32, 32};
    createCheckRow(transGrid, 1, 'useExp_FVM', 'Abilita exp FVM', appState, controller, ...
        'Abilita trasformazione esponenziale FVM.');
    createParamRow(transGrid, 2, 'exp_FVM', 'Esponente FVM', appState, controller, [0.5 5], ...
        'Esponente/curva FVM.');
    createCheckRow(transGrid, 3, 'useExp_QUOT', 'Abilita exp QUOT', appState, controller, ...
        'Abilita trasformazione esponenziale QUOT.');
    createParamRow(transGrid, 4, 'exp_QUOT', 'Esponente QUOT', appState, controller, [0.5 5], ...
        'Esponente/curva QUOT.');

    tabBoost = uitab(tabGroup, 'Title', 'Boost');
    boostGrid = uigridlayout(tabBoost, [5 4]);
    boostGrid.ColumnWidth = {180, 120, 70, 60};
    boostGrid.RowHeight = {32, 32, 32, 32, 32};
    createParamRow(boostGrid, 1, 'gamma', 'Esponente concentrazione (γ)', appState, controller, [0.5 5], ...
        'Esponente concentrazione.');
    createParamRow(boostGrid, 2, 'mu', 'Anti-1 boost (μ)', appState, controller, [0 1], ...
        'Boost anti-1.');
    createParamRow(boostGrid, 3, 'k', 'Boost scale (k)', appState, controller, [0 100], ...
        'Scala boost.');
    createParamRow(boostGrid, 4, 'p', 'Boost curve (p)', appState, controller, [0.5 5], ...
        'Curva boost.');
    createParamRow(boostGrid, 5, 'lambda', 'Peso boost (λ)', appState, controller, [0 1], ...
        'Peso boost nella distribuzione.');

    tabRoles = uitab(tabGroup, 'Title', 'Ruoli');
    roleGrid = uigridlayout(tabRoles, [4 4]);
    roleGrid.ColumnWidth = {180, 120, 70, 60};
    roleGrid.RowHeight = {32, 32, 32, 32};
    createParamRow(roleGrid, 1, 'wr_P', 'Peso Portieri (P)', appState, controller, [0.5 2], ...
        'Moltiplicatore per portieri.');
    createParamRow(roleGrid, 2, 'wr_D', 'Peso Difensori (D)', appState, controller, [0.5 2], ...
        'Moltiplicatore per difensori.');
    createParamRow(roleGrid, 3, 'wr_C', 'Peso Centroc. (C)', appState, controller, [0.5 2], ...
        'Moltiplicatore per centrocampisti.');
    createParamRow(roleGrid, 4, 'wr_A', 'Peso Attaccanti (A)', appState, controller, [0.5 2], ...
        'Moltiplicatore per attaccanti.');

    metaPanel = uipanel(layout, 'Title', 'Dati CSV');
    metaPanel.Layout.Row = 2;
    metaGrid = uigridlayout(metaPanel, [5 2]);
    metaGrid.ColumnWidth = {120, '1x'};
    metaGrid.RowHeight = {28, 28, 28, 28, '1x'};

    uilabel(metaGrid, 'Text', 'File');
    fileField = uieditfield(metaGrid, 'text', 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Righe');
    rowsField = uieditfield(metaGrid, 'text', 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Colonne');
    colsArea = uitextarea(metaGrid, 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Stats FVM');
    fvmField = uieditfield(metaGrid, 'text', 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Stats QUOT');
    quotField = uieditfield(metaGrid, 'text', 'Editable', 'off');

    colsArea.Layout.Row = 3;
    colsArea.Layout.Column = 2;

    tunerPanel = uipanel(layout, 'Title', 'Tuner Guidato');
    tunerPanel.Layout.Row = 3;
    tunerGrid = uigridlayout(tunerPanel, [3 2]);
    tunerGrid.RowHeight = {30, 30, 30};
    tunerGrid.ColumnWidth = {'1x', '1x'};
    uidropdown(tunerGrid, 'Items', {'Suggerito', 'Manuale', 'Ottimizza'}, 'Value', 'Suggerito', ...
        'ValueChangedFcn', @(src, ~) controller.onTunerMode(src.Value));
    uidropdown(tunerGrid, 'Items', {'avg', 'var', 'top'}, 'Value', 'avg', ...
        'ValueChangedFcn', @(src, ~) controller.onTunerTarget(src.Value));
    uibutton(tunerGrid, 'Text', 'Applica', 'ButtonPushedFcn', @(~, ~) controller.onTune());

    metaPanel = uipanel(layout, 'Title', 'Dati CSV');
    metaPanel.Layout.Row = 3;
    metaGrid = uigridlayout(metaPanel, [5 2]);
    metaGrid.ColumnWidth = {120, '1x'};
    metaGrid.RowHeight = {28, 28, 28, 28, '1x'};

    uilabel(metaGrid, 'Text', 'File');
    fileField = uieditfield(metaGrid, 'text', 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Righe');
    rowsField = uieditfield(metaGrid, 'text', 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Colonne');
    colsArea = uitextarea(metaGrid, 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Stats FVM');
    fvmField = uieditfield(metaGrid, 'text', 'Editable', 'off');
    uilabel(metaGrid, 'Text', 'Stats QUOT');
    quotField = uieditfield(metaGrid, 'text', 'Editable', 'off');

    colsArea.Layout.Row = 3;
    colsArea.Layout.Column = 2;

    logPanel = uipanel(layout, 'Title', 'Log');
    logPanel.Layout.Row = 4;
    logGrid = uigridlayout(logPanel, [1 1]);
    logArea = uitextarea(logGrid, 'Editable', 'off');
    logArea.Layout.Row = 1;
    logArea.Layout.Column = 1;
    controller.onLogUpdate = @(lines) set(logArea, 'Value', lines);
    controller.onMetaUpdate = @(meta) updateMeta(fileField, rowsField, colsArea, fvmField, quotField, meta);
end

function createParamRow(grid, row, name, label, appState, controller, range, tooltip)
    labelControl = uilabel(grid, 'Text', label, 'FontWeight', 'bold');
    labelControl.Layout.Row = row;
    labelControl.Layout.Column = 1;
    labelControl.WordWrap = 'on';
    labelControl.HorizontalAlignment = 'left';
    if nargin >= 8 && strlength(string(tooltip)) > 0
        labelControl.Tooltip = tooltip;
    end
    slider = uislider(grid, 'Limits', range, 'Value', appState.params.(name));
    slider.Layout.Row = row;
    slider.Layout.Column = 2;
    editField = uieditfield(grid, 'numeric', 'Value', appState.params.(name));
    editField.Layout.Row = row;
    editField.Layout.Column = 3;
    if nargin >= 8 && strlength(string(tooltip)) > 0
        slider.Tooltip = tooltip;
        editField.Tooltip = tooltip;
    end

    slider.ValueChangedFcn = @(src, ~) controller.onParamChange(name, src.Value, range);
    editField.ValueChangedFcn = @(src, ~) controller.onParamChange(name, src.Value, range);

    lock = uicheckbox(grid, 'Text', 'Lock', 'Value', appState.paramsLock.(name));
    lock.Layout.Row = row;
    lock.Layout.Column = 4;
    lock.ValueChangedFcn = @(src, ~) controller.onLockChange(name, src.Value);
end

function createCheckRow(grid, row, name, label, appState, controller, tooltip)
    labelControl = uilabel(grid, 'Text', label, 'FontWeight', 'bold');
    labelControl.Layout.Row = row;
    labelControl.Layout.Column = 1;
    checkbox = uicheckbox(grid, 'Text', '', 'Value', appState.params.(name));
    checkbox.Layout.Row = row;
    checkbox.Layout.Column = 2;
    checkbox.ValueChangedFcn = @(src, ~) controller.onParamChange(name, src.Value, []);
    if nargin >= 7 && strlength(string(tooltip)) > 0
        checkbox.Tooltip = tooltip;
        labelControl.Tooltip = tooltip;
    end
    lock = uicheckbox(grid, 'Text', 'Lock', 'Value', appState.paramsLock.(name));
    lock.Layout.Row = row;
    lock.Layout.Column = 4;
    lock.ValueChangedFcn = @(src, ~) controller.onLockChange(name, src.Value);
end

function updateMeta(fileField, rowsField, colsArea, fvmField, quotField, meta)
    if isempty(meta)
        return;
    end
    fileField.Value = string(meta.fileName);
    rowsField.Value = sprintf('%d', meta.rowCount);
    colsArea.Value = string(meta.columnsMapped);
    fvmField.Value = formatStats(meta.stats, 'FVM');
    quotField.Value = formatStats(meta.stats, 'QUOT');
end

function text = formatStats(stats, key)
    if ~isfield(stats, key)
        text = '';
        return;
    end
    block = stats.(key);
    if ~isfield(block, 'min') || ~isfield(stats, 'nanPct') || ~isfield(stats.nanPct, key)
        text = '';
        return;
    end
    nanPct = stats.nanPct.(key);
    text = sprintf('min %.2f | max %.2f | mean %.2f | NaN %.1f%%', ...
        block.min, block.max, block.mean, nanPct);
end
