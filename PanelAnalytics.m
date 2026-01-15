function panel = PanelAnalytics(parent, appState, controller)
    panel = uipanel(parent, 'Title', 'Analytics', 'FontWeight', 'bold');
    layout = uigridlayout(panel, [2 1]);
    layout.RowHeight = {40, '1x'};
    layout.Padding = [10 10 10 10];

    header = uigridlayout(layout, [1 2]);
    header.ColumnWidth = {'1x', 140};
    dropdown = uidropdown(header, 'Items', {'Listone', 'Scatter', 'Istogramma', 'Heatmap'}, ...
        'Value', appState.ui.selection.viewId, 'ValueChangedFcn', @(src, ~) controller.onViewChange(src.Value));
    searchField = uieditfield(header, 'text', 'Placeholder', 'Cerca');
    searchField.ValueChangedFcn = @(src, ~) controller.onSearch(src.Value);

    content = uigridlayout(layout, [1 1]);
    content.Layout.Row = 2;

    table = uitable(content, 'ColumnSortable', true, 'RowStriping', true);
    table.Layout.Row = 1;
    table.Layout.Column = 1;

    axesPanel = uiaxes(content, 'Visible', 'off');
    axesPanel.Layout.Row = 1;
    axesPanel.Layout.Column = 1;

    controller.onListoneUpdate = @(data) updateTable(table, axesPanel, data);
    controller.onChartUpdate = @(viewModel, mode) updateChart(axesPanel, table, viewModel, mode);
end

function updateTable(tableHandle, axesHandle, data)
    tableHandle.Visible = 'on';
    if isempty(data)
        tableHandle.Data = buildPlaceholderTable('Nessun CSV caricato.');
    else
        tableHandle.Data = data;
    end
    axesHandle.Visible = 'off';
end

function updateChart(ax, tableHandle, viewModel, mode)
    cla(ax);
    ax.Visible = 'on';
    tableHandle.Visible = 'off';
    if isempty(viewModel) || (~isfield(viewModel, 'x') && ~isfield(viewModel, 'values'))
        showEmptyChart(ax, 'Carica CSV per vedere i grafici.');
        return;
    end
    if isfield(viewModel, 'x') && isempty(viewModel.x) && isfield(viewModel, 'values') && isempty(viewModel.values)
        showEmptyChart(ax, 'Carica CSV per vedere i grafici.');
        return;
    end
    if isfield(viewModel, 'matrix') && isempty(viewModel.matrix)
        showEmptyChart(ax, 'Carica CSV per vedere i grafici.');
        return;
    end
    switch mode
        case 'Scatter'
            FantaGraph.drawScatter(ax, viewModel, struct('title', 'Scatter'));
        case 'Istogramma'
            FantaGraph.drawHist(ax, viewModel, struct('title', 'Distribuzione'));
        case 'Heatmap'
            FantaGraph.drawHeatmap(ax, viewModel, struct('title', 'Heatmap'));
        otherwise
            ax.Visible = 'off';
    end
end

function placeholder = buildPlaceholderTable(text)
    placeholder = table(string(text), 'VariableNames', {'Messaggio'});
end

function showEmptyChart(ax, textValue)
    ax.Visible = 'on';
    ax.XTick = [];
    ax.YTick = [];
    text(ax, 0.5, 0.5, textValue, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
