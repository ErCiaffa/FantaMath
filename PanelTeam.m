function panel = PanelTeam(parent, appState, controller)
    panel = uipanel(parent, 'Title', 'Squadre', 'FontWeight', 'bold');
    layout = uigridlayout(panel, [4 1]);
    layout.RowHeight = {120, 80, 220, '1x'};
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

    rosterPanel = uipanel(layout, 'Title', 'Roster Squadra');
    rosterGrid = uigridlayout(rosterPanel, [2 2]);
    rosterGrid.RowHeight = {32, '1x'};
    rosterGrid.ColumnWidth = {'1x', 140};
    teamDropdown = uidropdown(rosterGrid, 'Items', {''}, 'Value', '');
    releaseButton = uibutton(rosterGrid, 'Text', 'Simula svincolo');
    rosterTable = uitable(rosterGrid, 'RowStriping', true);
    rosterTable.Layout.Row = 2;
    rosterTable.Layout.Column = [1 2];

    teamTable = uitable(layout, 'ColumnEditable', [false true true true true], 'RowStriping', true);

    controller.onKpiUpdate = @(kpi) setKpi(lblPlayers, lblAvg, lblTop, lblTeams, kpi);
    controller.onAdviceUpdate = @(text) set(helperArea, 'Value', text);
    controller.onTeamsUpdate = @(data) set(teamTable, 'Data', data);
    controller.onRosterUpdate = @(data, teams, selectedTeam) updateRoster(teamDropdown, rosterTable, data, teams, selectedTeam);
    teamTable.CellEditCallback = @(src, evt) controller.onTeamEdit(evt);
    releaseButton.ButtonPushedFcn = @(~, ~) onReleaseSelected();
    teamDropdown.ValueChangedFcn = @(src, ~) controller.onTeamSelect(src.Value);

    selectedId = NaN;
    rosterTable.CellSelectionCallback = @(~, evt) onRosterSelect(evt);

    function onRosterSelect(evt)
        if isempty(evt.Indices)
            selectedId = NaN;
            return;
        end
        row = evt.Indices(1);
        data = rosterTable.Data;
        if isempty(data) || ~any(strcmp(data.Properties.VariableNames, 'ID'))
            selectedId = NaN;
            return;
        end
        selectedId = data.ID(row);
    end

    function onReleaseSelected()
        if isnan(selectedId)
            return;
        end
        controller.onReleasePlayer(selectedId);
    end
end

function setKpi(lblPlayers, lblAvg, lblTop, lblTeams, kpi)
    lblPlayers.Text = sprintf('Giocatori: %d', kpi.CountPlayers);
    lblAvg.Text = sprintf('Valore medio: %.1f', kpi.AvgValue);
    lblTop.Text = sprintf('Top: %.1f', kpi.TopValue);
    lblTeams.Text = sprintf('Squadre: %d', kpi.CountTeams);
end

function updateRoster(dropdown, tableHandle, data, teams, selectedTeam)
    if isempty(teams)
        dropdown.Items = {''};
        dropdown.Value = '';
        tableHandle.Data = table();
        return;
    end
    teamItems = cellstr(teams);
    dropdown.Items = teamItems;
    if strlength(string(selectedTeam)) == 0 || ~any(strcmp(teamItems, selectedTeam))
        dropdown.Value = teamItems{1};
    else
        dropdown.Value = selectedTeam;
    end
    tableHandle.Data = data;
end
