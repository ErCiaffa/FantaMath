function panel = PanelTeam(parent, appState, controller)
    panel = uipanel(parent, 'Title', 'Squadre', 'FontWeight', 'bold');
    layout = uigridlayout(panel, [3 1]);
    layout.RowHeight = {120, 80, '1x'};
    layout.Padding = [10 10 10 10];

    kpiPanel = uipanel(layout, 'Title', 'KPI');
    kpiGrid = uigridlayout(kpiPanel, [2 2]);
    kpiGrid.RowHeight = {30, 30};
    kpiGrid.ColumnWidth = {'1x', '1x'};
    lblPlayers = uilabel(kpiGrid, 'Text', 'Giocatori: 0', 'FontWeight', 'bold');
    lblAvg = uilabel(kpiGrid, 'Text', 'Valore medio: 0', 'FontWeight', 'bold');
    lblTop = uilabel(kpiGrid, 'Text', 'Top: 0', 'FontWeight', 'bold');
    lblTeams = uilabel(kpiGrid, 'Text', 'Squadre: 0', 'FontWeight', 'bold');

    helperPanel = uipanel(layout, 'Title', 'Helper');
    helperArea = uitextarea(helperPanel, 'Editable', 'off');

    teamTable = uitable(layout, 'ColumnEditable', [false true true true true], 'RowStriping', true);

    controller.onKpiUpdate = @(kpi) setKpi(lblPlayers, lblAvg, lblTop, lblTeams, kpi);
    controller.onAdviceUpdate = @(text) set(helperArea, 'Value', text);
    controller.onTeamsUpdate = @(data) set(teamTable, 'Data', data);
    teamTable.CellEditCallback = @(src, evt) controller.onTeamEdit(evt);
end

function setKpi(lblPlayers, lblAvg, lblTop, lblTeams, kpi)
    lblPlayers.Text = sprintf('Giocatori: %d', kpi.CountPlayers);
    lblAvg.Text = sprintf('Valore medio: %.1f', kpi.AvgValue);
    lblTop.Text = sprintf('Top: %.1f', kpi.TopValue);
    lblTeams.Text = sprintf('Squadre: %d', kpi.CountTeams);
end
