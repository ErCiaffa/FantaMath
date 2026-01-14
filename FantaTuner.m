function FantaTuner(csvFile)
% FantaTuner (MATLAB R2024a) - ALL PARAMETERS EDITION
% Espone TUTTI i parametri del modello organizzati in TAB per controllo totale.

if nargin < 1
    files = dir('*.csv');
    if isempty(files), files = dir('*.xlsx'); end
    if ~isempty(files), csvFile = files(1).name; else, csvFile = "listone.csv"; end
end

%% ===== 1. LOAD DATA =====
try
    opts = detectImportOptions(csvFile);
    opts.VariableNamingRule = 'preserve';
    T_full = readtable(csvFile, opts);
catch err
    uialert(uifigure, "Errore file: " + err.message, "Errore"); return;
end

% --- MAPPING COLONNE ---
cols = string(T_full.Properties.VariableNames);
findCol = @(pattern) find(contains(upper(cols), upper(pattern)), 1);

idx_ID   = findCol("#");
idx_Name = findCol("Nome");
idx_Out  = findCol("Fuori"); % Cerca "Fuori lista" o simile
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

id    = cleanNum(T_full{:, idx_ID});
name  = string(T_full{:, idx_Name});
fvm   = cleanNum(T_full{:, idx_FVM});
quot  = cleanNum(T_full{:, idx_Quot});
cost  = cleanNum(T_full{:, idx_Cost});
fantaTeam = string(T_full{:, idx_Team});

% LOGICA FUORI LISTA (*)
if ~isempty(idx_Out)
    rawOut = string(T_full{:, idx_Out});
    isOutList = contains(rawOut, "*");
else
    isOutList = zeros(size(id));
end

if ~isempty(idx_Age), age = cleanNum(T_full{:, idx_Age}); else, age = 99 * ones(size(id)); end

role_classic = string(T_full{:, idx_R});
if ~isempty(idx_RM), role_mantra = string(T_full{:, idx_RM}); 
else, role_mantra = repmat("", size(id)); end

cost(isnan(cost)) = 0;
isOwned = ~ismissing(fantaTeam) & strlength(strtrim(fantaTeam)) > 0 & fantaTeam ~= "-";
isForeign = zeros(size(id)); 

% Dati filtrati
id_c=id(isOwned); name_c=name(isOwned); fvm_c=fvm(isOwned); quot_c=quot(isOwned);
cost_c=cost(isOwned); team_c=fantaTeam(isOwned); age_c=age(isOwned);
rc_c=role_classic(isOwned); rm_c=role_mantra(isOwned); 
isOut_c = isOutList(isOwned); 
isForeign_c = isForeign(isOwned); 

if isempty(id_c), error("Nessun giocatore assegnato."); end

uniqueTeams = unique(team_c);
TeamBankMap = containers.Map('KeyType','char','ValueType','double');
for i = 1:numel(uniqueTeams), TeamBankMap(char(uniqueTeams(i))) = 0; end

%% ===== 2. SETTINGS COMPLETE =====
S = struct();
% LEGA
S.C_actual=0; S.C_bonus=0; S.C_malus=0; S.C_max=12000; S.epsilon=0.15; S.Wstar=10000;
% CORE
S.phi=75; S.gamma=1.00; S.alphaF=0.02;
% SOGLIE
S.pLowF=0.15; S.pHighF=0.995; S.pLowQ=0.05; S.pHighQ=1.00;
% MECCANICA
S.mu=3.00; S.k=0.90; S.boostP=1.07; S.lambda=0.25;
% TASSE
S.PlusTax=0.00; S.GrossOb=0.05; S.GrossDec=0.30; S.fee=0.00;

% RUOLI (PESI)
S.wr_P = 1.10; S.wr_D = 1.00; S.wr_C = 1.00; S.wr_A = 1.30;
S.wm_P = 1.10; S.wm_Dd = 0.95; S.wm_Ds = 0.95; S.wm_Dc = 1.00; 
S.wm_E = 0.90; S.wm_M = 0.90; S.wm_C = 1.00; S.wm_W = 1.10; 
S.wm_T = 1.25; S.wm_A = 1.15; S.wm_Pc = 1.40; S.flex_bonus = 0.03; 
S.wm_B = 1.00; % Aggiunto Braccetto B come richiesto in lista

TGT = struct(); TGT.topTarget=200; TGT.headTarget=2.00; TGT.lowTarget=10.0;
H_ui = struct(); 

%% ===== 3. UI LAYOUT =====
fig = uifigure("Name","FantaTuner - All Params Edition", "Position",[40 40 1680 950]);
fig.WindowState = "maximized";

root = uigridlayout(fig,[2 1]); root.RowHeight = {45,'1x'}; root.Padding=[10 10 10 10]; root.RowSpacing=5;

% TOP BAR
topbar = uigridlayout(root,[1 6]); topbar.Layout.Row=1; topbar.ColumnWidth={120, 120, 20, 120, 120, '1x'};
btnSave = uibutton(topbar,"Text","Salva Tutto","FontWeight","bold", "ButtonPushedFcn", @(~,~) saveConfig());
btnLoad = uibutton(topbar,"Text","Carica Tutto","FontWeight","bold", "ButtonPushedFcn", @(~,~) loadConfig());
uitextarea(topbar,"Value","|","Editable","off","BackgroundColor",[0.94 0.94 0.94],"HorizontalAlignment","center");
btnToggleL = uibutton(topbar,"Text","Toggle Sx"); btnToggleR = uibutton(topbar,"Text","Toggle Dx");
lblInfo = uitextarea(topbar, "Value", "Tutti i parametri (Lega, Core, Soglie, Meccanica, Tasse, Ruoli) sono ora disponibili nei TAB a sinistra.", ...
    "Editable","off", "FontAngle","italic", "BackgroundColor",[0.94 0.94 0.94]);

main = uigridlayout(root, [1 3]); main.Layout.Row=2; main.Padding=[0 0 0 0]; main.ColumnSpacing=8;
main.ColumnWidth = {450,'1.3x',350}; leftShown=true; rightShown=true;

% --- LEFT PANEL (IMPOSTAZIONI) ---
pLeft = uipanel(main, "Title","Pannello di Controllo", "FontWeight","bold"); pLeft.Layout.Column=1;
plLayout = uigridlayout(pLeft, [2 1]); plLayout.RowHeight={'1x', 180}; plLayout.Padding=[0 0 0 0]; 
tabsLeft = uitabgroup(plLayout); tabsLeft.Layout.Row=1;

% === TAB 1: LEGA ===
tLega = uitab(tabsLeft, "Title", "Lega"); pgL = uigridlayout(tLega, [12 3]); pgL.ColumnWidth={'1x','0.8x',80}; pgL.RowHeight=repmat({35},1,12); row=1;
createLabel(pgL,row,[1 3],"Bilancio (Somma Banche)","bold"); row=row+1;
l=uitextarea(pgL,"Value","Totale C","Editable","off","BackgroundColor",[0.94 0.94 0.94]); l.Layout.Row=row; l.Layout.Column=1;
edtC = uieditfield(pgL,"numeric","Value",S.C_actual, "Editable","off"); edtC.Layout.Row=row; edtC.Layout.Column=[2 3];
H_ui.C_actual = struct('edt', edtC); row=row+1;
H_ui.C_bonus=addInputRow(pgL, "Bonus (Cb)", "C_bonus", row, S.C_bonus); row=row+1;
H_ui.C_malus=addInputRow(pgL, "Malus (Cp)", "C_malus", row, S.C_malus); row=row+1;
H_ui.C_max=addInputRow(pgL, "Cap (Cmax)", "C_max", row, S.C_max); row=row+1;
H_ui.epsilon=addInputRow(pgL, "Margine (ε)", "epsilon", row, S.epsilon); row=row+1;

% === TAB 2: CORE ===
tCore = uitab(tabsLeft, "Title", "Core"); pg1 = uigridlayout(tCore, [12 3]); pg1.ColumnWidth={'1x','1.5x',60}; pg1.RowHeight=repmat({38},1,12); row=1;
createLabel(pg1,row,[1 3],"Parametri Fondamentali","bold"); row=row+1;
H_ui.Wstar = addParamRow(pg1, "W* (Pool)", "Wstar", 1, 30000, row, S.Wstar, "%.0f"); row=row+1;
H_ui.gamma = addParamRow(pg1, "γ (Exp 1-2.2)", "gamma", 0.5, 3.0, row, S.gamma, "%.2f"); row=row+1;
H_ui.phi = addParamRow(pg1, "φ (Peso FVM)", "phi", 0, 100, row, S.phi, "%.0f"); row=row+1;
H_ui.alphaF = addParamRow(pg1, "α (Log FVM)", "alphaF", 0.001, 0.1, row, S.alphaF, "%.3f");

% === TAB 3: SOGLIE ===
tSoglie = uitab(tabsLeft, "Title", "Soglie"); pg2 = uigridlayout(tSoglie, [12 3]); pg2.ColumnWidth={'1x','1.5x',60}; pg2.RowHeight=repmat({35},1,12); row=1;
createLabel(pg2,row,[1 3],"Tagli Percentili (Normalizzazione)","bold"); row=row+1;
H_ui.pLowF = addParamRow(pg2, "pLow FVM", "pLowF", 0, 0.4, row, S.pLowF, "%.3f"); row=row+1;
H_ui.pHighF = addParamRow(pg2, "pHigh FVM", "pHighF", 0.8, 1, row, S.pHighF, "%.3f"); row=row+1;
H_ui.pLowQ = addParamRow(pg2, "pLow Qt", "pLowQ", 0, 0.4, row, S.pLowQ, "%.3f"); row=row+1;
H_ui.pHighQ = addParamRow(pg2, "pHigh Qt", "pHighQ", 0.8, 1, row, S.pHighQ, "%.3f");

% === TAB 4: MECCANICA ===
tMecc = uitab(tabsLeft, "Title", "Mecc."); pg3 = uigridlayout(tMecc, [12 3]); pg3.ColumnWidth={'1x','1.5x',60}; pg3.RowHeight=repmat({35},1,12); row=1;
createLabel(pg3,row,[1 3],"Boost & Pavimento","bold"); row=row+1;
H_ui.mu = addParamRow(pg3, "μ (Anti-1)", "mu", 0, 10, row, S.mu, "%.2f"); row=row+1;
H_ui.k = addParamRow(pg3, "k (Scala)", "k", 0.05, 5, row, S.k, "%.2f"); row=row+1;
H_ui.boostP = addParamRow(pg3, "p (Curva Boost)", "boostP", 0.5, 3, row, S.boostP, "%.2f"); row=row+1;
H_ui.lambda = addParamRow(pg3, "λ (Peso Boost)", "lambda", 0, 1, row, S.lambda, "%.2f");

% === TAB 5: TASSE ===
tTax = uitab(tabsLeft, "Title", "Tasse"); pg4 = uigridlayout(tTax, [12 3]); pg4.ColumnWidth={'1x','1.5x',60}; pg4.RowHeight=repmat({35},1,12); row=1;
createLabel(pg4,row,[1 3],"Fisco & Malus","bold"); row=row+1;
H_ui.PlusTax = addParamRow(pg4, "tp (Plusvalenza)", "PlusTax", 0, 0.9, row, S.PlusTax, "%.2f"); row=row+1;
H_ui.GrossOb = addParamRow(pg4, "tE (Obblig *)", "GrossOb", 0, 0.5, row, S.GrossOb, "%.2f"); row=row+1;
H_ui.GrossDec = addParamRow(pg4, "tV (Decis)", "GrossDec", 0, 0.5, row, S.GrossDec, "%.2f"); row=row+1;
H_ui.fee = addParamRow(pg4, "f (Fee Fissa)", "fee", 0, 20, row, S.fee, "%.0f");

% === TAB 6: RUOLI ===
tRoles = uitab(tabsLeft, "Title", "Ruoli"); pgR = uigridlayout(tRoles, [18 3]); pgR.ColumnWidth={'1x','1.2x',60}; pgR.RowHeight=repmat({32},1,18); pgR.Scrollable="on"; row=1;
createLabel(pgR,row,[1 3],"MANTRA (Prioritario)","bold"); row=row+1;
H_ui.wm_Pc= addParamRow(pgR, "Pc (Re)",  "wm_Pc", 0.5, 2.5, row, S.wm_Pc, "%.2f"); row=row+1;
H_ui.wm_T = addParamRow(pgR, "T (Principe)", "wm_T", 0.5, 2.5, row, S.wm_T, "%.2f"); row=row+1;
H_ui.wm_A = addParamRow(pgR, "A (Jolly)", "wm_A", 0.5, 2.5, row, S.wm_A, "%.2f"); row=row+1;
H_ui.wm_W = addParamRow(pgR, "W (Ala)",     "wm_W", 0.5, 2.5, row, S.wm_W, "%.2f"); row=row+1;
H_ui.wm_C = addParamRow(pgR, "C (Interno)", "wm_C", 0.5, 2.0, row, S.wm_C, "%.2f"); row=row+1;
H_ui.wm_M  = addParamRow(pgR, "M (Mediano)", "wm_M", 0.5, 2.0, row, S.wm_M, "%.2f"); row=row+1;
H_ui.wm_E  = addParamRow(pgR, "E (Esterno)", "wm_E", 0.5, 2.0, row, S.wm_E, "%.2f"); row=row+1;
H_ui.wm_Dc = addParamRow(pgR, "Dc (Centrale)", "wm_Dc", 0.5, 2.0, row, S.wm_Dc, "%.2f"); row=row+1;
H_ui.wm_B  = addParamRow(pgR, "B (Braccetto)", "wm_B", 0.5, 2.0, row, S.wm_B, "%.2f"); row=row+1;
H_ui.wm_Dd = addParamRow(pgR, "Dd/Ds", "wm_Dd", 0.5, 2.0, row, S.wm_Dd, "%.2f"); row=row+1;
H_ui.wm_Ds = addParamRow(pgR, "Ds (Sinistro)", "wm_Ds", 0.5, 2.0, row, S.wm_Ds, "%.2f"); row=row+1;
H_ui.wm_P  = addParamRow(pgR, "P (Portiere)", "wm_P", 0.5, 2.5, row, S.wm_P, "%.2f"); row=row+1;
createLabel(pgR,row,[1 3],"EXTRA & CLASSIC","bold"); row=row+1;
H_ui.flex_bonus = addParamRow(pgR, "Flex Bonus", "flex_bonus", 0.0, 0.5, row, S.flex_bonus, "%.2f"); row=row+1;
H_ui.wr_A = addParamRow(pgR, "Classic A", "wr_A", 0.5, 2.5, row, S.wr_A, "%.2f"); row=row+1;
H_ui.wr_C = addParamRow(pgR, "Classic C", "wr_C", 0.5, 2.0, row, S.wr_C, "%.2f"); row=row+1;
H_ui.wr_D = addParamRow(pgR, "Classic D", "wr_D", 0.5, 2.0, row, S.wr_D, "%.2f"); row=row+1;
H_ui.wr_P = addParamRow(pgR, "Classic P", "wr_P", 0.5, 2.0, row, S.wr_P, "%.2f"); 

% COACH
coach = uitextarea(plLayout,"Editable","off","FontName","Segoe UI","FontSize",11,"BackgroundColor",[1 1 0.9]);
coach.Layout.Row = 2;

% --- MIDDLE & RIGHT ---
pMid = uipanel(main,"Title","Analisi", "FontWeight","bold"); pMid.Layout.Column=2;
midGrid = uigridlayout(pMid,[1 1]); midGrid.Padding=[5 5 5 5];
tabs = uitabgroup(midGrid); 
tabS = uitab(tabs,"Title","Squadre (Input Banca)"); tabD = uitab(tabs,"Title","Grafici"); 

% Tabella Squadre
sgrid = uigridlayout(tabS, [1 1]);
tblTeams = uitable(sgrid); tblTeams.ColumnSortable=true; tblTeams.FontName="Segoe UI"; tblTeams.FontSize=11;
tblTeams.ColumnEditable = [false false false true false false false]; 
tblTeams.CellEditCallback = @onTeamEdit;

% Grafici
dgrid = uigridlayout(tabD,[2 2]); dgrid.RowHeight={'1x','1.5x'}; dgrid.ColumnWidth={'1x','1x'};
axPrice=uiaxes(dgrid); axPrice.Layout.Row=1; axPrice.Layout.Column=1;
axCash=uiaxes(dgrid); axCash.Layout.Row=1; axCash.Layout.Column=2; axScore=uiaxes(dgrid); axScore.Layout.Row=2; axScore.Layout.Column=[1 2];

% RIGHT
pRight = uipanel(main,"Title","Lista & Export", "FontWeight","bold"); pRight.Layout.Column=3;
rg = uigridlayout(pRight,[4 1]); rg.RowHeight={130, 220, '1x', 40}; rg.Padding=[5 5 5 5];
kpi = uitextarea(rg,"Editable","off","FontName","Consolas","FontSize",11, "BackgroundColor",[0.95 0.98 1]); kpi.Layout.Row=1;

pTune = uipanel(rg,"Title","AutoTune"); pTune.Layout.Row=2;
ag = uigridlayout(pTune, [5 3]); ag.ColumnWidth={90,'1x',50}; ag.RowHeight=repmat({28},1,5); ag.Padding=[2 2 2 2];
autoOn = uicheckbox(ag,"Text","ON","Value",false); autoOn.Layout.Row=1; autoOn.Layout.Column=1;
btnTune = uibutton(ag,"Text","CALCOLA","FontWeight","bold","BackgroundColor",[0.6 0.8 1]); btnTune.Layout.Row=1; btnTune.Layout.Column=[2 3];
createLabel(ag,2,1,"Top","normal"); sTop=uislider(ag,"Limits",[80 350],"Value",TGT.topTarget); sTop.Layout.Row=2; sTop.Layout.Column=2; eTop=uieditfield(ag,"numeric","Limits",[80 350],"Value",TGT.topTarget,"ValueDisplayFormat","%.0f"); eTop.Layout.Row=2; eTop.Layout.Column=3;
createLabel(ag,3,1,"Head","normal"); sHead=uislider(ag,"Limits",[1.2 3.5],"Value",TGT.headTarget); sHead.Layout.Row=3; sHead.Layout.Column=2; eHead=uieditfield(ag,"numeric","Limits",[1.2 3.5],"Value",TGT.headTarget,"ValueDisplayFormat","%.2f"); eHead.Layout.Row=3; eHead.Layout.Column=3;
createLabel(ag,4,1,"Low%","normal"); sLow=uislider(ag,"Limits",[0 25],"Value",TGT.lowTarget); sLow.Layout.Row=4; sLow.Layout.Column=2; eLow=uieditfield(ag,"numeric","Limits",[0 25],"Value",TGT.lowTarget,"ValueDisplayFormat","%.1f"); eLow.Layout.Row=4; eLow.Layout.Column=3;

tbl = uitable(rg); tbl.Layout.Row=3; tbl.FontName="Segoe UI"; tbl.FontSize=11; tbl.ColumnSortable=true;
btnExport = uibutton(rg, "Text", "Esporta Excel Completo", "FontWeight","bold", "BackgroundColor",[0.8 1 0.8]); btnExport.Layout.Row=4;

outTable = table(); teamsTable = table(); selName = "";

% WIRING
tbl.CellSelectionCallback = @onSelectRow;
btnTune.ButtonPushedFcn = @(~,~) runAutoTune();
autoOn.ValueChangedFcn = @(~,~) maybeAutoTune();
btnExport.ButtonPushedFcn = @(~,~) exportFullData();
btnToggleL.ButtonPushedFcn = @(~,~) toggleLeft(); btnToggleR.ButtonPushedFcn = @(~,~) toggleRight();
sTop.ValueChangingFcn = @(~,evt) onTargetChange("top", evt.Value, true); sTop.ValueChangedFcn = @(src,~) onTargetChange("top", src.Value, false); eTop.ValueChangedFcn = @(src,~) onTargetChange("top", src.Value, false);
sHead.ValueChangingFcn = @(~,evt) onTargetChange("head", evt.Value, true); sHead.ValueChangedFcn = @(src,~) onTargetChange("head", src.Value, false); eHead.ValueChangedFcn = @(src,~) onTargetChange("head", src.Value, false);
sLow.ValueChangingFcn = @(~,evt) onTargetChange("low", evt.Value, true); sLow.ValueChangedFcn = @(src,~) onTargetChange("low", src.Value, false); eLow.ValueChangedFcn = @(src,~) onTargetChange("low", src.Value, false);

wireAllParams();
applyLayout();
sumBanksAndSync(); 
recomputeAndPlot();

%% ===== LOGIC =====

    function onTeamEdit(~, evt)
        if isempty(evt.Indices), return; end
        rowIdx = evt.Indices(1);
        tName = string(teamsTable.Squadra(rowIdx));
        if isKey(TeamBankMap, char(tName)), TeamBankMap(char(tName)) = evt.NewData; end
        sumBanksAndSync(); 
    end

    function sumBanksAndSync()
        vals = values(TeamBankMap); S.C_actual = sum([vals{:}]);
        H_ui.C_actual.edt.Value = S.C_actual; 
        calcWstarFromLeague();
    end

    function calcWstarFromLeague()
        if ~isfield(S, 'C_actual'), S.C_actual = 0; end
        if ~isfield(S, 'C_bonus'), S.C_bonus = 0; end
        if ~isfield(S, 'C_malus'), S.C_malus = 0; end
        w_new = S.C_actual + S.C_bonus - S.C_malus;
        w_safe = max(H_ui.Wstar.sld.Limits(1), min(H_ui.Wstar.sld.Limits(2), w_new));
        S.Wstar = w_safe; H_ui.Wstar.sld.Value = w_safe; H_ui.Wstar.edt.Value = w_safe;
        recomputeAndPlot();
    end

    function saveConfig()
        [fname, fpath] = uiputfile("FantaConfig.mat", "Salva");
        if fname==0, return; end
        try, save(fullfile(fpath, fname), "S", "TGT", "TeamBankMap"); uialert(fig, "Salvato!", "Info"); catch, end
    end

    function loadConfig()
        [fname, fpath] = uigetfile("*.mat", "Carica");
        if fname==0, return; end
        try, loaded = load(fullfile(fpath, fname));
            if isfield(loaded,"S"), flds=fieldnames(loaded.S); for i=1:numel(flds), S.(flds{i})=loaded.S.(flds{i}); end; end
            if isfield(loaded,"TGT"), TGT=loaded.TGT; end
            if isfield(loaded,"TeamBankMap"), TeamBankMap=loaded.TeamBankMap; end
            updateUIFromStruct(); sumBanksAndSync(); uialert(fig, "Caricato!", "Info");
        catch, end
    end

    function exportFullData()
        if isempty(outTable), uialert(fig,"Nessun dato.","Warning"); return; end
        [fname, fpath] = uiputfile("FantaManager_Export.xlsx", "Esporta Excel");
        if fname==0, return; end
        try
            T_export = T_full;
            V_vec = zeros(height(T_full), 1); S_vec = zeros(height(T_full), 1); MaxS_vec = zeros(height(T_full), 1); 
            RoleW_vec = zeros(height(T_full), 1);
            ids_out = outTable.ID; vals_out = outTable.V; cash_out = outTable.Svincolo; max_out = outTable.MaxSvincolo; rw_out = outTable.PesoRuolo;
            [tf, loc] = ismember(T_full{:, idx_ID}, ids_out);
            idx_found = find(tf);
            for k = 1:length(idx_found)
                r = idx_found(k); idx_out = loc(r);
                V_vec(r) = vals_out(idx_out); S_vec(r) = cash_out(idx_out); MaxS_vec(r) = max_out(idx_out);
                RoleW_vec(r) = rw_out(idx_out);
            end
            T_export.Valore_Reale = V_vec; T_export.Svincolo_Netto = round(S_vec); 
            T_export.Svincolo_Max = round(MaxS_vec); T_export.Peso_Ruolo = RoleW_vec;
            writetable(T_export, fullfile(fpath, fname), 'Sheet', 'Giocatori');
            writetable(teamsTable, fullfile(fpath, fname), 'Sheet', 'Squadre');
            uialert(fig, "Export completato su 2 fogli!", "Successo");
        catch err, uialert(fig, "Errore Export: " + err.message, "Errore"); end
    end

    function recomputeAndPlot()
        [V, CashOut, Score, MaxCash, RMult] = computeModel(fvm_c, quot_c, cost_c, isForeign_c, rc_c, rm_c, isOut_c, S);
        m = metricsFromV(V);
        
        totW=sum(V); res=S.Wstar-totW;
        lines=strings(0,1);
        lines(end+1)=sprintf("PLAYERS: %d (U21: %d)", numel(V), sum(age_c<=21));
        lines(end+1)=sprintf("BUDGET W*: %d", round(S.Wstar));
        lines(end+1)=sprintf("VALORE TOT: %d", round(totW));
        lines(end+1)=sprintf("RESIDUO: %d", round(res));
        lines(end+1)="----------------";
        lines(end+1)=sprintf("TOP: %d | HEAD: %.2f", m.top, m.head);
        kpi.Value=toLines(lines);
        
        teams = unique(team_c); nT=numel(teams);
        cT=strings(nT,1); cPly=strings(nT,1); cVal=zeros(nT,1); cBank=zeros(nT,1); cSvObl=zeros(nT,1); cPot=strings(nT,1); cAvg=zeros(nT,1);
        
        for i = 1:nT
            tm = teams(i); idxT = team_c == tm;
            cnt = sum(idxT); cntU = sum(idxT & (age_c <= 21));
            totV = sum(V(idxT)); avgV = mean(V(idxT));
            totCashReal = sum(CashOut(idxT)); totCashFromStar = sum(CashOut(idxT & isOut_c)); 
            currentBank = 0; if isKey(TeamBankMap, char(tm)), currentBank = TeamBankMap(char(tm)); end
            
            cT(i) = tm;
            cPly(i) = sprintf("%d (%d)", cnt, cntU);
            cVal(i) = round(totV);
            cBank(i) = currentBank;
            cSvObl(i) = round(totCashFromStar); 
            cPot(i) = sprintf("%d", round(currentBank + totCashReal)); 
            cAvg(i) = round(avgV, 1);
        end
        teamsTable = table(cT, cPly, cVal, cBank, cPot, cSvObl, cAvg, ...
            'VariableNames', {'Squadra', 'Giocatori', 'ValoreRosa', 'Banca', 'Potenziale', 'DaObblig', 'Media'});
        tblTeams.Data = teamsTable;
        tblTeams.ColumnWidth = {130, 50, 70, 80, 80, 80, 50};
        
        [Vsort, idx] = sort(V, "descend");
        out = table();
        out.Rank = (1:numel(Vsort))'; out.ID = id_c(idx); out.Name = name_c(idx);
        out.Squadra = team_c(idx); out.V = Vsort; out.FVM = fvm_c(idx); 
        out.PesoRuolo = round(RMult(idx),2); 
        out.Svincolo = round(CashOut(idx)); out.MaxSvincolo = round(MaxCash(idx));
        out.Plus = max(0, Vsort - cost_c(idx)); out.Sc = round(Score(idx), 2);
        outTable = out; tbl.Data = out;
        tbl.ColumnName = {"#","ID","Name","Team","V","FVM","Rw","Svinc","Plus","Sc"};
        tbl.ColumnWidth = {30,40,110,90,45,45,40,55,45,45};
        
        coach.Value = toLines(makeCoach(out, S, TGT, m));
        
        cla(axPrice); histogram(axPrice, V, 30, 'FaceColor','#4DBEEE'); title(axPrice,"Valori");
        cla(axCash); histogram(axCash, CashOut, 30, 'FaceColor','#77AC30'); title(axCash,"Svincoli");
        cla(axScore); scatter(axScore, Score, V, 20, "filled"); title(axScore,"Score vs V"); grid(axScore,"on");
        if strlength(selName)>0
            i0=find(lower(name_c)==lower(selName),1); if isempty(i0), i0=find(contains(lower(name_c),lower(selName)),1); end
            if ~isempty(i0)
                hold(axScore,"on"); scatter(axScore,Score(i0),V(i0),120,"filled","r"); hold(axScore,"off");
            end
        end
    end

    function runAutoTune()
        old = btnTune.BackgroundColor; btnTune.BackgroundColor=[1 0.6 0.6]; btnTune.Text="..."; drawnow;
        for it=1:8
            S.Wstar=tuneWstarToTop(S, TGT.topTarget);
            S.gamma=tuneGammaToHead(S, TGT.headTarget);
            S.mu=tuneMuToLow(S, TGT.lowTarget);
            [Vtmp,~,~,~,~]=computeModel(fvm_c, quot_c, cost_c, isForeign_c, rc_c, rm_c, isOut_c, S);
            mt=metricsFromV(Vtmp);
            if abs(mt.top-round(TGT.topTarget))<=3 && abs(mt.head-TGT.headTarget)<=0.08, break; end
        end
        updateUIFromStruct(); recomputeAndPlot();
        btnTune.BackgroundColor=old; btnTune.Text="CALCOLA";
    end
    function maybeAutoTune(), if autoOn.Value, runAutoTune(); else, recomputeAndPlot(); end; end
    function onSelectRow(~, evt)
        if isempty(evt.Indices), return; end
        rSel=evt.Indices(1,1); if isempty(outTable)||rSel<1||rSel>height(outTable), return; end
        selName=string(outTable.Name(rSel)); recomputeAndPlot();
    end
    function toggleLeft(), leftShown=~leftShown; applyLayout(); end
    function toggleRight(), rightShown=~rightShown; applyLayout(); end
    function applyLayout()
        pLeft.Visible=onOff(leftShown); pRight.Visible=onOff(rightShown);
        if leftShown && rightShown, main.ColumnWidth={440,'1.3x',350};
        elseif ~leftShown && rightShown, main.ColumnWidth={0,'1.3x',350};
        elseif leftShown && ~rightShown, main.ColumnWidth={440,'1x',0}; else, main.ColumnWidth={0,'1x',0}; end
    end
    function s=onOff(tf), if tf, s="on"; else, s="off"; end; end
    function onParam(field, v, edt, isDrag), S.(field)=v; edt.Value=v; if autoOn.Value && ~isDrag, runAutoTune(); else, recomputeAndPlot(); end; end
    function onEdit(field, v, sld), S.(field)=v; sld.Value=v; recomputeAndPlot(); end
    function onDataInput(field, v), S.(field)=v; if contains(field,'C_'), calcWstarFromLeague(); end; end
    function onTargetChange(which, v, isDragging)
        switch which
            case "top", TGT.topTarget=v; sTop.Value=v; eTop.Value=v;
            case "head",TGT.headTarget=v; sHead.Value=v; eHead.Value=v;
            case "low", TGT.lowTarget=v; sLow.Value=v; eLow.Value=v;
        end
        if autoOn.Value && ~isDragging, runAutoTune(); else, recomputeAndPlot(); end
    end
    function updateUIFromStruct()
        fields = fieldnames(H_ui);
        for i=1:numel(fields)
            f=fields{i};
            if isfield(S, f)
                if isfield(H_ui.(f), 'sld'), v=S.(f); l=H_ui.(f).sld.Limits; v=max(l(1),min(l(2),v)); H_ui.(f).sld.Value=v; H_ui.(f).edt.Value=v;
                elseif isfield(H_ui.(f), 'edt'), H_ui.(f).edt.Value=S.(f); end
            end
        end
        sTop.Value=TGT.topTarget; eTop.Value=TGT.topTarget;
    end
    function wireAllParams()
        fields = fieldnames(H_ui);
        for i=1:numel(fields)
            f=fields{i}; h=H_ui.(f);
            if isfield(h, 'sld')
                h.sld.ValueChangingFcn = @(~,evt) onParam(f, evt.Value, h.edt, true);
                h.sld.ValueChangedFcn  = @(src,~)  onParam(f, src.Value, h.edt, false);
                h.edt.ValueChangedFcn  = @(src,~)  onEdit(f, src.Value, h.sld);
            elseif isfield(h, 'edt')
                h.edt.ValueChangedFcn  = @(src,~)  onDataInput(f, src.Value);
            end
        end
    end
    function W = tuneWstarToTop(Sloc, topTarget)
        lo=1000; hi=30000;
        for j=1:20
            W=round((lo+hi)/2); Sloc.Wstar=W; [Vt,~,~,~,~]=computeModel(fvm_c, quot_c, cost_c, isForeign_c, rc_c, rm_c, isOut_c, Sloc);
            if max(Vt)<topTarget, lo=W; else, hi=W; end
        end
        W=round((lo+hi)/2);
    end
    function g = tuneGammaToHead(Sloc, headTarget)
        g=Sloc.gamma;
        for j=1:10
            [Vt,~,~,~,~]=computeModel(fvm_c, quot_c, cost_c, isForeign_c, rc_c, rm_c, isOut_c, Sloc); mt=metricsFromV(Vt);
            err=headTarget-mt.head; g=clamp(g+0.18*err, 0.50, 3.00); Sloc.gamma=g; if abs(err)<0.05, break; end
        end
    end
    function mu = tuneMuToLow(Sloc, lowTarget)
        mu=Sloc.mu;
        for j=1:12
            [Vt,~,~,~,~]=computeModel(fvm_c, quot_c, cost_c, isForeign_c, rc_c, rm_c, isOut_c, Sloc); mt=metricsFromV(Vt);
            err=mt.lowPct-lowTarget; mu=clamp(mu+0.07*err, 0.00, 10.00); Sloc.mu=mu; if abs(err)<0.8, break; end
        end
    end
end

%% ===== HELPERS =====
function createLabel(parent, row, col, txt, weight)
    if nargin<5, weight='normal'; end
    h = uitextarea(parent, "Value", txt, "Editable", "off", "FontWeight", weight, "BackgroundColor", [0.94 0.94 0.94]);
    h.Layout.Row = row; h.Layout.Column = col;
end
function h = addInputRow(parentGrid, label, ~, rr, value)
    l = uitextarea(parentGrid, "Value", label, "Editable","off", "BackgroundColor",[0.94 0.94 0.94]);
    l.Layout.Row = rr; l.Layout.Column = [1 2];
    edt = uieditfield(parentGrid,"numeric","Value",value);
    edt.Layout.Row=rr; edt.Layout.Column=3;
    h = struct("edt",edt);
end
function h = addParamRow(parentGrid, label, ~, lo, hi, rr, value, fmt)
    l = uitextarea(parentGrid, "Value", label, "Editable","off", "BackgroundColor",[0.94 0.94 0.94]);
    l.Layout.Row = rr; l.Layout.Column = 1;
    sld = uislider(parentGrid,"Limits",[lo hi],"Value",value);
    sld.MajorTicks=[]; sld.MinorTicks=[]; sld.Layout.Row=rr; sld.Layout.Column=2;
    edt = uieditfield(parentGrid,"numeric","Limits",[lo hi],"Value",value, "ValueDisplayFormat", fmt);
    edt.Layout.Row=rr; edt.Layout.Column=3;
    h = struct("sld",sld,"edt",edt);
end

%% ===== CORE LOGIC =====
function [V, CashOut, Score, MaxCash, RMult] = computeModel(fvm, quot, cost, isForeign, rc, rm, isOut, S)
    clamp01 = @(x) max(0, min(1, x)); 
    phiVal = S.phi / 100.0; omega = 1 - phiVal;
    
    fvmEff = log(1 + S.alphaF .* fvm);
    F_floor = myQuantile(fvmEff, S.pLowF); F_ceil = myQuantile(fvmEff, S.pHighF);
    Q_floor = myQuantile(quot, S.pLowQ);   Q_ceil = myQuantile(quot, S.pHighQ);
    Fnorm = clamp01((fvmEff - F_floor) ./ max(eps, (F_ceil - F_floor)));
    Qnorm = clamp01((quot   - Q_floor) ./ max(eps, (Q_ceil - Q_floor)));
    BaseScore = phiVal .* Fnorm + omega .* Qnorm;
    
    n = numel(fvm);
    RMult = ones(n, 1);
    getW = @(r) getRoleW(r, S);
    
    for i = 1:n
        rolesStr = rm(i);
        if ismissing(rolesStr) || strlength(strtrim(rolesStr))==0 || rolesStr=="-", rolesStr = rc(i); end
        parts = split(strrep(rolesStr, '/', ';'), [";", " "]);
        parts = parts(strlength(parts)>0);
        if isempty(parts), w_final = 1.0; 
        else
            ws = zeros(numel(parts), 1);
            for k = 1:numel(parts), ws(k) = getW(parts(k)); end
            w_final = max(ws) + (numel(parts) - 1) * S.flex_bonus;
        end
        RMult(i) = w_final;
    end
    
    Score = BaseScore .* RMult;
    ScorePow = Score .^ S.gamma;
    dMin = Fnorm + Qnorm; dp = dMin .^ S.boostP;
    Base = 1 + S.mu .* (dp ./ (dp + S.k));
    Weight = (ScorePow .* (dMin ./ (dMin + 1))) + S.lambda .* (Base - 1);
    WSum = sum(Weight);
    Rem = max(0, round(S.Wstar) - round(sum(Base)));
    if WSum <= 0 || isnan(WSum), V = max(1, round(Base));
    else, V = max(1, round(Base + Rem .* (Weight ./ WSum))); end
    
    Plus = max(0, V - cost);
    TaxRate = S.GrossDec .* ones(size(V)); 
    TaxRate(isOut==1) = S.GrossOb; % Se è * (Fuori lista) applica tassa Obbligatoria
    CashOut = max(0, V - TaxRate .* V - S.PlusTax .* Plus - S.fee);
    
    MaxTax = S.GrossOb .* ones(size(V));
    MaxCash = max(0, V - MaxTax .* V - S.PlusTax .* Plus - S.fee);
end

function w = getRoleW(rStr, S)
    r = upper(strtrim(rStr));
    if r=="P", w=S.wr_P; return; end 
    switch r
        case "P", w=S.wm_P; 
        case {"DD","DS"}, w=S.wm_Dd; case "DC", w=S.wm_Dc; case "B", w=S.wm_B;
        case "E", w=S.wm_E; case "M", w=S.wm_M; case "C", w=S.wm_C;
        case "W", w=S.wm_W; case "T", w=S.wm_T;
        case "A", w=S.wm_A; case "PC", w=S.wm_Pc;
        case "D", w=S.wr_D; 
        otherwise, w=1.0; 
    end
end

function m = metricsFromV(V)
    m.top = max(V); m.p90 = max(1, round(myQuantile(V, 0.90)));
    m.head = m.top / max(1, m.p90); m.lowPct = 100 * mean(V <= 3);
end
function lines = makeCoach(out, S, TGT, m)
    lines=strings(0,1); lines(end+1)="COACH TIPS:";
    lines(end+1)=sprintf("Target Diff: %+d", m.top-round(TGT.topTarget));
    if m.top < TGT.topTarget, lines(end+1)="- Top economici. Alza Gamma o W*.";
    elseif m.top > TGT.topTarget, lines(end+1)="- Top cari. Abbassa Gamma."; end
    if m.lowPct > TGT.lowTarget, lines(end+1)="- Troppi giocatori a 1. Alza Mu."; end
    lines(end+1)=" "; lines(end+1)=sprintf("W* Attuale: %d", round(S.Wstar));
end
function out = toLines(x)
    if iscell(x), out=x; elseif isstring(x), out=cellstr(x(:)); else, out=cellstr(string(x)); end
end
function q = myQuantile(x, p)
    x=x(~isnan(x)); if isempty(x), q=NaN; return; end
    x=sort(x(:)); n=numel(x); p=min(1, max(0, p));
    if n==1, q=x(1); return; end
    pos=1+(n-1)*p; lo=floor(pos); hi=ceil(pos);
    if lo==hi, q=x(lo); else, q=x(lo)*(1-(pos-lo)) + x(hi)*(pos-lo); end
end
function y = clamp(x, lo, hi), y = min(hi, max(lo, x)); end
