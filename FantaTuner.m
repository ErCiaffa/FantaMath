function FantaTuner(csvFile)
% FantaTuner (MATLAB R2024a)
% Calcolo listone completo con parametri modificabili live (Mantra)

if nargin < 1
    files = dir('*.csv');
    if isempty(files), files = dir('*.xlsx'); end
    if ~isempty(files), csvFile = files(1).name; else, csvFile = "listone.csv"; end
end

%% ===== 1. LOAD DATA =====
try
    opts = detectImportOptions(csvFile);
    opts.VariableNamingRule = 'preserve';
    if any(strcmpi(opts.VariableNames, '#'))
        opts = setvartype(opts, '#', 'string');
    end
    T_full = readtable(csvFile, opts);
catch err
    uialert(uifigure, "Errore file: " + err.message, "Errore"); return;
end

cols = string(T_full.Properties.VariableNames);
findCol = @(pattern) find(contains(upper(cols), upper(pattern)), 1);

idx_ID   = findCol("#");
idx_Name = findCol("Nome");
idx_Out  = findCol("Fuori");
idx_FVM  = findCol("FVM");
idx_Quot = findCol("QUOT");
idx_Cost = findCol("Costo");
idx_Team = findCol("FantaSquadra");
idx_Age  = findCol("Under"); if isempty(idx_Age), idx_Age = findCol("Eta"); end
idx_R    = findCol("R.");
idx_RM   = findCol("MANTRA");

if isempty(idx_ID) || isempty(idx_Name) || isempty(idx_FVM) || isempty(idx_Quot) || isempty(idx_Team)
    error("Colonne mancanti. Serve: #, Nome, FVM, QUOT, FantaSquadra, Costo");
end

cleanNum = @(c) str2double(strrep(strrep(string(c), ',', '.'), ' ', ''));

id    = string(T_full{:, idx_ID});
name  = string(T_full{:, idx_Name});
fvm   = cleanNum(T_full{:, idx_FVM});
quot  = cleanNum(T_full{:, idx_Quot});
cost  = cleanNum(T_full{:, idx_Cost});
fantaTeam = string(T_full{:, idx_Team});

if isempty(idx_RM)
    rolesRaw = string(T_full{:, idx_R});
else
    rolesRaw = string(T_full{:, idx_RM});
end

if isempty(idx_Out)
    outRaw = strings(size(name));
else
    outRaw = string(T_full{:, idx_Out});
end

owned = fantaTeam ~= "" & ~ismissing(fantaTeam);

%% ===== 2. UI SETUP =====
fig = uifigure('Name', 'FantaMath - FantaTuner', 'Position', [100 100 1300 820]);

grid = uigridlayout(fig, [1 2]);
grid.ColumnWidth = {420, '1x'};

paramPanel = uipanel(grid, 'Title', 'Parametri (modificabili live)');
paramPanel.Layout.Row = 1; paramPanel.Layout.Column = 1;

paramGrid = uigridlayout(paramPanel, [32 2]);
paramGrid.RowHeight = repmat({22}, 1, 32);
paramGrid.ColumnWidth = {'1x', '1x'};

recLabel = uilabel(paramGrid, 'Text', 'Valori consigliati (solo avviso):');
recLabel.FontWeight = 'bold';
recLabel.Layout.Row = 1; recLabel.Layout.Column = [1 2];

recText = { ...
    'φ=0.60, α_F=0.02, F_ref=380, α_Q=0.15, Q_ref=35, γ=1.45', ...
    'μ=1.2, k=0.55, p=1', ...
    'η=1.0, ρ=0.7', ...
    'β=0.12, n_max=4', ...
    'T=10, C_start=500, ε=0.15, Cb=0, Cp=0', ...
    't_plus=0.25, t_gE=0.02, t_gV=0.20, f=2' ...
    };

recLabelDetails = uilabel(paramGrid, 'Text', sprintf('%s\n', recText{:}), 'FontAngle', 'italic', 'WordWrap', 'on');
recLabelDetails.Layout.Row = 2; recLabelDetails.Layout.Column = [1 2];

% Editable parameters
paramDefaults = struct();
paramDefaults.phi = 0.60;
paramDefaults.alphaF = 0.02;
paramDefaults.Fref = 380;
paramDefaults.alphaQ = 0.15;
paramDefaults.Qref = 35;
paramDefaults.gamma = 1.45;
paramDefaults.mu = 1.2;
paramDefaults.k = 0.55;
paramDefaults.p = 1;
paramDefaults.eta = 1.0;
paramDefaults.rho = 0.7;
paramDefaults.beta = 0.12;
paramDefaults.nmax = 4;
paramDefaults.T = 10;
paramDefaults.Cstart = 500;
paramDefaults.eps = 0.15;
paramDefaults.Cb = 0;
paramDefaults.Cp = 0;
paramDefaults.Cashnow = 0;
paramDefaults.tplus = 0.25;
paramDefaults.tGE = 0.02;
paramDefaults.tGV = 0.20;
paramDefaults.fee = 2;

fieldInfo = {
    'φ (peso FVM)', 'phi';
    'α_F (log FVM)', 'alphaF';
    'F_ref', 'Fref';
    'α_Q (log QUOT)', 'alphaQ';
    'Q_ref', 'Qref';
    'γ (separazione top)', 'gamma';
    'μ (floor)', 'mu';
    'k (floor)', 'k';
    'p (floor)', 'p';
    'η (scarcity)', 'eta';
    'ρ (ruoli)', 'rho';
    'β (duttilità)', 'beta';
    'n_max', 'nmax';
    'T squadre', 'T';
    'C_start', 'Cstart';
    'ε crescita', 'eps';
    'Cb bonus', 'Cb';
    'Cp penalità', 'Cp';
    'Cash_now', 'Cashnow';
    't_plus', 'tplus';
    't_gE', 'tGE';
    't_gV', 'tGV';
    'f fee', 'fee' ...
    };

fieldControls = struct();
startRow = 3;
for i = 1:size(fieldInfo, 1)
    row = startRow + i - 1;
    lbl = uilabel(paramGrid, 'Text', fieldInfo{i, 1});
    lbl.Layout.Row = row; lbl.Layout.Column = 1;
    edit = uieditfield(paramGrid, 'numeric', 'Value', paramDefaults.(fieldInfo{i, 2}));
    edit.Layout.Row = row; edit.Layout.Column = 2;
    edit.ValueChangedFcn = @(~, ~) recalc();
    fieldControls.(fieldInfo{i, 2}) = edit;
end

rowAfterParams = startRow + size(fieldInfo, 1);

roleLabel = uilabel(paramGrid, 'Text', 'Domanda ruoli (D_r) - modificabile live');
roleLabel.FontWeight = 'bold';
roleLabel.Layout.Row = rowAfterParams; roleLabel.Layout.Column = [1 2];

roleNames = ["P","Dd","Ds","Dc","B","E","M","C","T","W","A","Pc"];
defaultDemand = defaultRoleDemand(roleNames, paramDefaults.T);
roleTable = uitable(paramGrid, 'Data', [roleNames', num2cell(defaultDemand')]);
roleTable.ColumnName = {'Ruolo', 'Domanda D_r'};
roleTable.ColumnEditable = [false true];
roleTable.Layout.Row = rowAfterParams + 1; roleTable.Layout.Column = [1 2];
roleTable.CellEditCallback = @(~, ~) recalc();

roleMethodLabel = uilabel(paramGrid, 'Text', 'RoleFactor');
roleMethodLabel.Layout.Row = rowAfterParams + 2; roleMethodLabel.Layout.Column = 1;
roleMethod = uidropdown(paramGrid, 'Items', {'MAX', 'MEDIA'}, 'Value', 'MAX');
roleMethod.Layout.Row = rowAfterParams + 2; roleMethod.Layout.Column = 2;
roleMethod.ValueChangedFcn = @(~, ~) recalc();

%% ===== 3. Output Panel =====
outputPanel = uipanel(grid, 'Title', 'Listone completo');
outputPanel.Layout.Row = 1; outputPanel.Layout.Column = 2;

outputGrid = uigridlayout(outputPanel, [3 1]);
outputGrid.RowHeight = {60, '1x', 40};

summaryLabel = uilabel(outputGrid, 'Text', '');
summaryLabel.FontWeight = 'bold';
summaryLabel.WordWrap = 'on';

listTable = uitable(outputGrid, 'Data', table());
listTable.ColumnSortable = true;

footerLabel = uilabel(outputGrid, 'Text', '');
footerLabel.WordWrap = 'on';

%% ===== 4. Compute initial =====
recalc();

    function recalc()
        params = structfun(@(c) c.Value, fieldControls, 'UniformOutput', false);
        params = struct2scalar(params, paramDefaults);

        roleData = roleTable.Data;
        D_r = zeros(1, numel(roleNames));
        for ii = 1:numel(roleNames)
            val = roleData{ii, 2};
            if isnumeric(val)
                D_r(ii) = val;
            else
                D_r(ii) = str2double(string(val));
            end
        end

        [resultTable, summaryText, footerText] = computeListone(...
            id, name, fvm, quot, cost, fantaTeam, rolesRaw, outRaw, owned, ...
            roleNames, D_r, roleMethod.Value, params);

        listTable.Data = resultTable;
        listTable.ColumnName = resultTable.Properties.VariableNames;
        summaryLabel.Text = summaryText;
        footerLabel.Text = footerText;
    end
end

function params = struct2scalar(params, defaults)
fields = fieldnames(defaults);
for i = 1:numel(fields)
    key = fields{i};
    val = params.(key);
    if iscell(val)
        val = val{1};
    end
    if ~isfinite(val)
        val = defaults.(key);
    end
    params.(key) = val;
end
end

function [resultTable, summaryText, footerText] = computeListone(...
    id, name, fvm, quot, cost, fantaTeam, rolesRaw, outRaw, owned, ...
    roleNames, D_r, roleMethod, params)

rolesPerPlayer = parseRoles(rolesRaw);

F_comp = log(1 + params.alphaF .* fvm);
F_scale = log(1 + params.alphaF .* params.Fref);
F_score = min(1, F_comp ./ max(F_scale, eps));

Q_comp = log(1 + params.alphaQ .* quot);
Q_scale = log(1 + params.alphaQ .* params.Qref);
Q_score = min(1, Q_comp ./ max(Q_scale, eps));

S = params.phi .* F_score + (1 - params.phi) .* Q_score;
S_pow = S .^ params.gamma;

% Floor
D_quality = F_score + Q_score;
Floor = 1 + params.mu .* (D_quality .^ params.p ./ (D_quality .^ params.p + params.k));

% Role scarcity
S_r = zeros(1, numel(roleNames));
for r = 1:numel(roleNames)
    role = roleNames(r);
    count = 0;
    for i = 1:numel(rolesPerPlayer)
        if owned(i) && any(strcmpi(rolesPerPlayer{i}, role))
            count = count + 1;
        end
    end
    S_r(r) = count;
end

Scar_r = (D_r ./ max(1, S_r)) .^ params.eta;
medScar = median(Scar_r);
if medScar <= 0
    medScar = 1;
end
Scar_norm = Scar_r ./ medScar;

RoleFactor = ones(size(fvm));
for i = 1:numel(rolesPerPlayer)
    roles = rolesPerPlayer{i};
    if isempty(roles)
        RoleFactor(i) = 1;
        continue;
    end
    roleVals = ones(1, numel(roles));
    for j = 1:numel(roles)
        idx = find(strcmpi(roleNames, roles{j}), 1);
        if ~isempty(idx)
            roleVals(j) = Scar_norm(idx);
        end
    end
    if strcmpi(roleMethod, 'MAX')
        RoleFactor(i) = max(roleVals);
    else
        RoleFactor(i) = mean(roleVals);
    end
end

n_i = cellfun(@numel, rolesPerPlayer);
Flex = 1 + params.beta .* (log(1 + n_i) ./ log(1 + max(params.nmax, 1)));

Weight = S_pow .* (RoleFactor .^ params.rho) .* Flex;

% Economy
Money0 = params.T * params.Cstart;
MoneyTarget = Money0 * (1 + params.eps);
CashNet = params.Cashnow + (params.Cb - params.Cp);
Wstar = max(0, MoneyTarget - CashNet);

ownedIdx = find(owned);
B = sum(Floor(ownedIdx));
R = max(0, Wstar - B);
WeightSum = sum(Weight(ownedIdx));
V_raw = zeros(size(fvm));
if WeightSum > 0
    V_raw(ownedIdx) = Floor(ownedIdx) + R * Weight(ownedIdx) ./ WeightSum;
else
    V_raw(ownedIdx) = Floor(ownedIdx);
end

V = max(1, round(V_raw));
V(~owned) = 0;

% CashOut
g_i = outRaw ~= "" & outRaw ~= "0" & ~ismissing(outRaw);
Pi = max(0, V - cost);
roleTax = params.tGV * ones(size(V));
roleTax(g_i) = params.tGE;
CashOut = max(0, V - roleTax .* V - params.tplus .* Pi - params.fee);
CashOut(~owned) = 0;

summaryText = sprintf([
    "W* = %.2f | MoneyTarget = %.2f | CashNet = %.2f | Owned = %d | Totale V = %.2f"], ...
    Wstar, MoneyTarget, CashNet, sum(owned), sum(V(ownedIdx)));

footerText = sprintf("Nota: i valori consigliati sono solo un avviso, i campi sopra sono effettivi e modificabili live.");

resultTable = table(
    id, name, fantaTeam, rolesRaw, fvm, quot, cost, owned, V, CashOut, ...
    RoleFactor, Flex, S_pow, ...
    'VariableNames', {'ID', 'Nome', 'FantaSquadra', 'Ruoli', 'FVM', 'QUOT', 'Costo', 'Owned', 'V', 'CashOut', 'RoleFactor', 'Flex', 'S_pow'});

resultTable = sortrows(resultTable, 'V', 'descend');
end

function rolesPerPlayer = parseRoles(rolesRaw)
rolesPerPlayer = cell(numel(rolesRaw), 1);
for i = 1:numel(rolesRaw)
    raw = strtrim(string(rolesRaw(i)));
    if raw == "" || ismissing(raw)
        rolesPerPlayer{i} = {};
        continue;
    end
    parts = regexp(raw, '[^/\\, ]+', 'match');
    rolesPerPlayer{i} = parts;
end
end

function demand = defaultRoleDemand(roleNames, T)
% Default modules/slots (semplificato) per domanda ruoli
modules = {
    '3-4-1-2', {
        {'P'}; {'Dc','B'}; {'Dc','B'}; {'Dc','B'}; ...
        {'E','M','C'}; {'E','M','C'}; {'M','C'}; {'E','M','C'}; ...
        {'T','W'}; {'A','Pc'}; {'A','Pc'}
    };
    '3-4-2-1', {
        {'P'}; {'Dc','B'}; {'Dc','B'}; {'Dc','B'}; ...
        {'E','M','C'}; {'E','M','C'}; {'M','C'}; {'E','M','C'}; ...
        {'T','W'}; {'T','W'}; {'A','Pc'}
    };
    '4-3-3', {
        {'P'}; {'Dd','Ds','E'}; {'Dc','B'}; {'Dc','B'}; {'Dd','Ds','E'}; ...
        {'M','C'}; {'M','C'}; {'M','C'}; ...
        {'W','A'}; {'W','A'}; {'Pc','A'}
    };
    '4-4-2', {
        {'P'}; {'Dd','Ds','E'}; {'Dc','B'}; {'Dc','B'}; {'Dd','Ds','E'}; ...
        {'E','M','C'}; {'M','C'}; {'M','C'}; {'E','M','C'}; ...
        {'A','Pc'}; {'A','Pc'}
    };
    '4-2-3-1', {
        {'P'}; {'Dd','Ds','E'}; {'Dc','B'}; {'Dc','B'}; {'Dd','Ds','E'}; ...
        {'M','C'}; {'M','C'}; ...
        {'T','W'}; {'T','W'}; {'T','W'}; ...
        {'A','Pc'}
    };
};

roleIndex = containers.Map();
for i = 1:numel(roleNames)
    roleIndex(roleNames(i)) = i;
end

D = zeros(1, numel(roleNames));
for m = 1:size(modules, 1)
    slots = modules{m, 2};
    for s = 1:numel(slots)
        slotRoles = slots{s};
        for r = 1:numel(slotRoles)
            role = slotRoles{r};
            if isKey(roleIndex, role)
                D(roleIndex(role)) = D(roleIndex(role)) + 1 / numel(slotRoles);
            end
        end
    end
end

D = D / size(modules, 1);
D = T * D;

% Keep order
demand = D;
end
