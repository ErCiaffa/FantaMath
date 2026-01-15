function panel = PanelConfig(parent, appState, controller)
    panel = uipanel(parent, 'Title', 'Parametri', 'FontWeight', 'bold');
    layout = uigridlayout(panel, [3 1]);
    layout.RowHeight = {260, 220, '1x'};
    layout.Padding = [10 10 10 10];

    tabGroup = uitabgroup(layout);
    tabGroup.Layout.Row = 1;

    tabVal = uitab(tabGroup, 'Title', 'Valutazione');
    valGrid = uigridlayout(tabVal, [4 4]);
    valGrid.ColumnWidth = {'1x', 120, 70, 60};
    valGrid.RowHeight = {32, 32, 32, 32};
    createParamRow(valGrid, 1, 'phi', 'Peso FVM', appState, controller, [0 100]);
    createParamRow(valGrid, 2, 'gamma', 'Gamma', appState, controller, [0.5 3]);
    createParamRow(valGrid, 3, 'Wstar', 'Pool', appState, controller, [500 2000]);

    tabSoglie = uitab(tabGroup, 'Title', 'Soglie');
    soglieGrid = uigridlayout(tabSoglie, [3 4]);
    soglieGrid.ColumnWidth = {'1x', 120, 70, 60};
    soglieGrid.RowHeight = {32, 32, 32};
    createParamRow(soglieGrid, 1, 'pLowF', 'pLow FVM', appState, controller, [0 0.5]);
    createParamRow(soglieGrid, 2, 'pHighF', 'pHigh FVM', appState, controller, [0.8 1]);

    tunerPanel = uipanel(layout, 'Title', 'Tuner Guidato');
    tunerPanel.Layout.Row = 2;
    tunerGrid = uigridlayout(tunerPanel, [3 2]);
    tunerGrid.RowHeight = {30, 30, 30};
    tunerGrid.ColumnWidth = {'1x', '1x'};
    uidropdown(tunerGrid, 'Items', {'Suggerito', 'Manuale', 'Ottimizza'}, 'Value', 'Suggerito', ...
        'ValueChangedFcn', @(src, ~) controller.onTunerMode(src.Value));
    uidropdown(tunerGrid, 'Items', {'avg', 'var', 'top'}, 'Value', 'avg', ...
        'ValueChangedFcn', @(src, ~) controller.onTunerTarget(src.Value));
    uibutton(tunerGrid, 'Text', 'Applica', 'ButtonPushedFcn', @(~, ~) controller.onTune());

    logPanel = uipanel(layout, 'Title', 'Log');
    logPanel.Layout.Row = 3;
    logArea = uitextarea(logPanel, 'Editable', 'off');
    logArea.Layout.Row = 1;
    controller.onLogUpdate = @(lines) set(logArea, 'Value', lines);
end

function createParamRow(grid, row, name, label, appState, controller, range)
    labelControl = uilabel(grid, 'Text', label, 'FontWeight', 'bold');
    labelControl.Layout.Row = row;
    labelControl.Layout.Column = 1;
    slider = uislider(grid, 'Limits', range, 'Value', appState.params.(name));
    slider.Layout.Row = row;
    slider.Layout.Column = 2;
    editField = uieditfield(grid, 'numeric', 'Value', appState.params.(name));
    editField.Layout.Row = row;
    editField.Layout.Column = 3;

    slider.ValueChangedFcn = @(src, ~) controller.onParamChange(name, src.Value);
    editField.ValueChangedFcn = @(src, ~) controller.onParamChange(name, src.Value);

    lock = uicheckbox(grid, 'Text', 'Lock', 'Value', appState.paramsLock.(name));
    lock.Layout.Row = row;
    lock.Layout.Column = 4;
    lock.ValueChangedFcn = @(src, ~) controller.onLockChange(name, src.Value);
end
