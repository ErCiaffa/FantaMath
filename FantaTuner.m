function FantaTuner(csvFile)
% FantaTuner (MATLAB R2024a) - PROFESSIONAL EDITION
% Gestione completa con simulazione svincoli, grafici avanzati e tuner professionale

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

id    = cleanNum(T_full{:, idx_ID});
name  = string(T_full{:, idx_Name});
fvm   = cleanNum(T_full{:, idx_FVM});
quot  = cleanNum(T_full{:, idx_Quot});
cost  = cleanNum(T_full{:, idx_Cost});
fantaTeam = string(T_full{:, idx_Team});

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
TeamBonusMap = containers.Map('KeyType','char','ValueType','double');
TeamMalusMap = containers.Map('KeyType','char','ValueType','double');
for i = 1:numel(uniqueTeams)
    TeamBankMap(char(uniqueTeams(i))) = 0;
    TeamBonusMap(char(uniqueTeams(i))) = 0;
    TeamMalusMap(char(uniqueTeams(i))) = 0;
end

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
S.wm_B = 1.00;

% TUNER LOCKS
LOCKS = struct();
LOCKS.topTarget = false; LOCKS.gamma = false; LOCKS.mu = false; 
LOCKS.phi = false; LOCKS.lambda = false; LOCKS.k = false;

TGT = struct(); 
TGT.topTarget=200; TGT.midHighTarget=80; TGT.midTarget=30; TGT.lowTarget=10.0;
H_ui = struct(); 

selectedTeamForRelease = "";

%% ===== 3. UI LAYOUT =====
fig = uifigure("Name","FantaTuner - Professional Edition", "Position",[40 40 1900 1000]);
fig.WindowState = "maximized";

root = uigridlayout(fig,[2 1]); root.RowHeight = {45,'1x'}; root.Padding=[10 10 10 10]; root.RowSpacing=5;

% TOP BAR
topbar = uigridlayout(root,[1 6]); topbar.Layout.Row=1; topbar.ColumnWidth={120, 120, 20, 120, 120, '1x'};
btnSave = uibutton(topbar,"Text","💾 Salva","FontWeight","bold","FontSize",12, "ButtonPushedFcn", @(~,~) saveConfig());
btnLoad = uibutton(topbar,"Text","📂 Carica","FontWeight","bold","FontSize",12, "ButtonPushedFcn", @(~,~) loadConfig());
uitextarea(topbar,"Value","|","Editable","off","BackgroundColor",[0.94 0.94 0.94],"HorizontalAlignment","center");
btnToggleL = uibutton(topbar,"Text","◄ Panel"); btnToggleR = uibutton(topbar,"Text","Panel ►");
lblInfo = uitextarea(topbar, "Value", "✓ Simulazione svincoli | ✓ Grafici avanzati | ✓ Tuner professionale con locks", ...
    "Editable","off", "FontAngle","italic", "FontSize",11, "BackgroundColor",[0.9 0.95 1]);

main = uigridlayout(root, [1 3]); main.Layout.Row=2; main.Padding=[0 0 0 0]; main.ColumnSpacing=8;
main.ColumnWidth = {480,'1.2x',420}; leftShown=true; rightShown=true;

% --- LEFT PANEL (IMPOSTAZIONI) ---
pLeft = uipanel(main, "Title","⚙️ Pannello di Controllo", "FontWeight","bold","FontSize",12); pLeft.Layout.Column=1;
plLayout = uigridlayout(pLeft, [2 1]); plLayout.RowHeight={'1x', 200}; plLayout.Padding=[0 0 0 0]; 
tabsLeft = uitabgroup(plLayout); tabsLeft.Layout.Row=1;

% === TAB 1: LEGA ===
tLega = uitab(tabsLeft, "Title", "💰 Lega"); pgL = uigridlayout(tLega, [10 3]); pgL.ColumnWidth={'1x','0.8x',80}; pgL.RowHeight=repmat({38},1,10); row=1;
createLabel(pgL,row,[1 3],"Bilancio Automatico","bold"); row=row+1;

edtC = uieditfield(pgL,"numeric","Value",S.C_actual, "Editable","off","FontWeight","bold","FontSize",13); 
edtC.Layout.Row=row; edtC.Layout.Column=[1 3];
H_ui.C_actual = struct('edt', edtC); row=row+1;

H_ui.C_max=addInputRow(pgL, "Cap Lega (Cmax)", "C_max", row, S.C_max); row=row+1;
H_ui.epsilon=addInputRow(pgL, "Margine ε (%)", "epsilon", row, S.epsilon*100); row=row+1;
createLabel(pgL,row,[1 3],"W* = (Cmax × Squadre) × (1-ε)","italic"); row=row+1;

edtWstar = uieditfield(pgL,"numeric","Value",S.Wstar, "Editable","off","FontWeight","bold","FontSize",12,"BackgroundColor",[0.9 1 0.9]); 
edtWstar.Layout.Row=row; edtWstar.Layout.Column=[1 3];
H_ui.Wstar_display = edtWstar;

% === TAB 2: CORE ===
tCore = uitab(tabsLeft, "Title", "🎯 Core"); pg1 = uigridlayout(tCore, [12 3]); pg1.ColumnWidth={'1x','1.5x',60}; pg1.RowHeight=repmat({38},1,12); row=1;
createLabel(pg1,row,[1 3],"Parametri Fondamentali","bold"); row=row+1;
H_ui.gamma = addParamRowWithLock(pg1, "γ (Esponente)", "gamma", 0.5, 3.0, row, S.gamma, "%.2f"); row=row+1;
H_ui.phi = addParamRowWithLock(pg1, "φ (Peso FVM %)", "phi", 0, 100, row, S.phi, "%.0f"); row=row+1;
H_ui.alphaF = addParamRow(pg1, "α (Log FVM)", "alphaF", 0.001, 0.1, row, S.alphaF, "%.3f");

% === TAB 3: SOGLIE ===
tSoglie = uitab(tabsLeft, "Title", "📊 Soglie"); pg2 = uigridlayout(tSoglie, [12 3]); pg2.ColumnWidth={'1x','1.5x',60}; pg2.RowHeight=repmat({35},1,12); row=1;
createLabel(pg2,row,[1 3],"Normalizzazione Percentili","bold"); row=row+1;
H_ui.pLowF = addParamRow(pg2, "pLow FVM", "pLowF", 0, 0.4, row, S.pLowF, "%.3f"); row=row+1;
H_ui.pHighF = addParamRow(pg2, "pHigh FVM", "pHighF", 0.8, 1, row, S.pHighF, "%.3f"); row=row+1;
H_ui.pLowQ = addParamRow(pg2, "pLow Qt", "pLowQ", 0, 0.4, row, S.pLowQ, "%.3f"); row=row+1;
H_ui.pHighQ = addParamRow(pg2, "pHigh Qt", "pHighQ", 0.8, 1, row, S.pHighQ, "%.3f");

% === TAB 4: MECCANICA ===
tMecc = uitab(tabsLeft, "Title", "⚡ Mecc."); pg3 = uigridlayout(tMecc, [12 3]); pg3.ColumnWidth={'1x','1.5x',60}; pg3.RowHeight=repmat({35},1,12); row=1;
createLabel(pg3,row,[1 3],"Boost & Distribuzione","bold"); row=row+1;
H_ui.mu = addParamRowWithLock(pg3, "μ (Pavimento)", "mu", 0, 10, row, S.mu, "%.2f"); row=row+1;
H_ui.k = addParamRowWithLock(pg3, "k (Scala Boost)", "k", 0.05, 5, row, S.k, "%.2f"); row=row+1;
H_ui.boostP = addParamRow(pg3, "p (Curva Boost)", "boostP", 0.5, 3, row, S.boostP, "%.2f"); row=row+1;
H_ui.lambda = addParamRowWithLock(pg3, "λ (Peso Boost)", "lambda", 0, 1, row, S.lambda, "%.2f");

% === TAB 5: TASSE ===
tTax = uitab(tabsLeft, "Title", "💸 Tasse"); pg4 = uigridlayout(tTax, [12 3]); pg4.ColumnWidth={'1x','1.5x',60}; pg4.RowHeight=repmat({35},1,12); row=1;
createLabel(pg4,row,[1 3],"Fiscalità","bold"); row=row+1;
H_ui.PlusTax = addParamRow(pg4, "tp (Plusvalenza)", "PlusTax", 0, 0.9, row, S.PlusTax, "%.2f"); row=row+1;
H_ui.GrossOb = addParamRow(pg4, "tE (Obblig *)", "GrossOb", 0, 0.5, row, S.GrossOb, "%.2f"); row=row+1;
H_ui.GrossDec = addParamRow(pg4, "tV (Volont.)", "GrossDec", 0, 0.5, row, S.GrossDec, "%.2f"); row=row+1;
H_ui.fee = addParamRow(pg4, "f (Fee €)", "fee", 0, 20, row, S.fee, "%.0f");

% === TAB 6: RUOLI ===
tRoles = uitab(tabsLeft, "Title", "👥 Ruoli"); pgR = uigridlayout(tRoles, [18 3]); pgR.ColumnWidth={'1x','1.2x',60}; pgR.RowHeight=repmat({32},1,18); pgR.Scrollable="on"; row=1;
createLabel(pgR,row,[1 3],"MANTRA (Prioritario)","bold"); row=row+1;
H_ui.wm_Pc= addParamRow(pgR, "Pc (Re)",  "wm_Pc", 0.5, 2.5, row, S.wm_Pc, "%.2f"); row=row+1;
H_ui.wm_T = addParamRow(pgR, "T (Principe)", "wm_T", 0.5, 2.5, row, S.wm_T, "%.2f"); row=row+1;
H_ui.wm_A = addParamRow(pgR, "A (Jolly)", "wm_A", 0.5, 2.5, row, S.wm_A, "%.2f"); row=row+1;
H_ui.wm_W = addParamRow(pgR, "W (Ala)", "wm_W", 0.5, 2.5, row, S.wm_W, "%.2f"); row=row+1;
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
coach = uitextarea(plLayout,"Editable","off","FontName","Consolas","FontSize",10,"BackgroundColor",[1 1 0.95]);
coach.Layout.Row = 2;

% --- MIDDLE PANEL ---
pMid = uipanel(main,"Title","📈 Analisi e Grafici", "FontWeight","bold","FontSize",12); pMid.Layout.Column=2;
midGrid = uigridlayout(pMid,[1 1]); midGrid.Padding=[5 5 5 5];
tabs = uitabgroup(midGrid); 
tabS = uitab(tabs,"Title","🏆 Squadre"); 
tabD = uitab(tabs,"Title","📊 Distribuzione");
tabFunc = uitab(tabs,"Title","📉 Funzione");

% === TAB SQUADRE ===
sgrid = uigridlayout(tabS, [3 1]); sgrid.RowHeight={40, '1x', 260};
sgridTop = uigridlayout(sgrid, [1 3]); sgridTop.Layout.Row=1; sgridTop.ColumnWidth={'1x', 150, 150};
lblTeamSel = uilabel(sgridTop, "Text", "Seleziona squadra per simulare svincoli:", "FontWeight","bold");
lblTeamSel.Layout.Column=1;
ddTeam = uidropdown(sgridTop, "Items", cellstr(uniqueTeams), "ValueChangedFcn", @onTeamSelected);
selectedTeamForRelease = string(ddTeam.Value);
ddTeam.Layout.Column=2;
btnSimRelease = uibutton(sgridTop, "Text", "🔄 Simula Svincoli", "FontWeight","bold", "BackgroundColor",[1 0.9 0.6]);
btnSimRelease.Layout.Column=3; btnSimRelease.ButtonPushedFcn = @(~,~) simulateReleases();

tblTeams = uitable(sgrid); tblTeams.Layout.Row=2; tblTeams.ColumnSortable=true; tblTeams.FontName="Segoe UI"; tblTeams.FontSize=10;
tblTeams.ColumnEditable = [false false false true true true false false false]; 
tblTeams.CellEditCallback = @onTeamEdit;

tblRelease = uitable(sgrid); tblRelease.Layout.Row=3; tblRelease.ColumnSortable=true; tblRelease.FontName="Segoe UI"; tblRelease.FontSize=10;
tblRelease.ColumnEditable = [true false false false false false false false false];
tblRelease.CellEditCallback = @onReleaseEdit;

% === TAB DISTRIBUZIONE ===
dgrid = uigridlayout(tabD,[2 2]); dgrid.RowHeight={'1x','1x'}; dgrid.ColumnWidth={'1x','1x'};
axPrice=uiaxes(dgrid); axPrice.Layout.Row=1; axPrice.Layout.Column=1; title(axPrice, "Distribuzione Valori");
axCash=uiaxes(dgrid); axCash.Layout.Row=1; axCash.Layout.Column=2; title(axCash, "Distribuzione Svincoli");
axBands=uiaxes(dgrid); axBands.Layout.Row=2; axBands.Layout.Column=[1 2]; title(axBands, "Fasce di Prezzo");

% === TAB FUNZIONE ===
fgrid = uigridlayout(tabFunc, [1 1]); 
axFunc = uiaxes(fgrid); title(axFunc, "Curva di Valorizzazione"); grid(axFunc, "on");

% --- RIGHT PANEL ---
pRight = uipanel(main,"Title","🎯 AutoTune & Export", "FontWeight","bold","FontSize",12); pRight.Layout.Column=3;
rg = uigridlayout(pRight,[4 1]); rg.RowHeight={140, 280, '1x', 40}; rg.Padding=[5 5 5 5];
kpi = uitextarea(rg,"Editable","off","FontName","Consolas","FontSize",10, "BackgroundColor",[0.95 0.98 1]); kpi.Layout.Row=1;

pTune = uipanel(rg,"Title","🎛️ AutoTune Professionale"); pTune.Layout.Row=2;
ag = uigridlayout(pTune, [7 3]); ag.ColumnWidth={100,'1x',60}; ag.RowHeight=repmat({32},1,7); ag.Padding=[4 4 4 4];

autoOn = uicheckbox(ag,"Text","🔄 AUTO","Value",false,"FontWeight","bold"); autoOn.Layout.Row=1; autoOn.Layout.Column=1;
btnTune = uibutton(ag,"Text","▶ CALCOLA","FontWeight","bold","FontSize",11,"BackgroundColor",[0.4 0.8 1]); 
btnTune.Layout.Row=1; btnTune.Layout.Column=[2 3];

createLabel(ag,2,1,"💎 Top (max)","bold"); 
sTop=uislider(ag,"Limits",[80 400],"Value",TGT.topTarget); sTop.Layout.Row=2; sTop.Layout.Column=2; 
eTop=uieditfield(ag,"numeric","Limits",[80 400],"Value",TGT.topTarget,"ValueDisplayFormat","%.0f"); eTop.Layout.Row=2; eTop.Layout.Column=3;

createLabel(ag,3,1,"🥈 Medio-Alto (titolari)","bold"); 
sMidHigh=uislider(ag,"Limits",[40 150],"Value",TGT.midHighTarget); sMidHigh.Layout.Row=3; sMidHigh.Layout.Column=2; 
eMidHigh=uieditfield(ag,"numeric","Limits",[40 150],"Value",TGT.midHighTarget,"ValueDisplayFormat","%.0f"); eMidHigh.Layout.Row=3; eMidHigh.Layout.Column=3;

createLabel(ag,4,1,"🥉 Medio (rotazione)","bold"); 
sMid=uislider(ag,"Limits",[15 80],"Value",TGT.midTarget); sMid.Layout.Row=4; sMid.Layout.Column=2; 
eMid=uieditfield(ag,"numeric","Limits",[15 80],"Value",TGT.midTarget,"ValueDisplayFormat","%.0f"); eMid.Layout.Row=4; eMid.Layout.Column=3;

createLabel(ag,5,1,"📉 Bassi (% riserve)","bold"); 
sLow=uislider(ag,"Limits",[0 30],"Value",TGT.lowTarget); sLow.Layout.Row=5; sLow.Layout.Column=2; 
eLow=uieditfield(ag,"numeric","Limits",[0 30],"Value",TGT.lowTarget,"ValueDisplayFormat","%.1f"); eLow.Layout.Row=5; eLow.Layout.Column=3;

createLabel(ag,6,[1 3],"🔒 Locks: blocca parametri dal tuning","italic");
lockGrid = uigridlayout(ag, [1 5]); lockGrid.Layout.Row=7; lockGrid.Layout.Column=[1 3];
lockGrid.ColumnWidth={'1x','1x','1x','1x','1x'};
chkLockGamma = uicheckbox(lockGrid, "Text", "🔒γ", "Value", false); chkLockGamma.Layout.Column=1;
chkLockMu = uicheckbox(lockGrid, "Text", "🔒μ", "Value", false); chkLockMu.Layout.Column=2;
chkLockLambda = uicheckbox(lockGrid, "Text", "🔒λ", "Value", false); chkLockLambda.Layout.Column=3;
chkLockPhi = uicheckbox(lockGrid, "Text", "🔒φ", "Value", false); chkLockPhi.Layout.Column=4;
chkLockK = uicheckbox(lockGrid, "Text", "🔒k", "Value", false); chkLockK.Layout.Column=5;

tbl = uitable(rg); tbl.Layout.Row=3; tbl.FontName="Segoe UI"; tbl.FontSize=10; tbl.ColumnSortable=true;
btnExport = uibutton(rg, "Text", "📥 Esporta Excel Completo", "FontWeight","bold","FontSize",11, "BackgroundColor",[0.7 1 0.7]); btnExport.Layout.Row=4;

outTable = table(); teamsTable = table(); selName = ""; releaseSimData = table();

% WIRING
tbl.CellSelectionCallback = @onSelectRow;
btnTune.ButtonPushedFcn = @(~,~) runAutoTune();
autoOn.ValueChangedFcn = @(~,~) maybeAutoTune();
btnExport.ButtonPushedFcn = @(~,~) exportFullData();
btnToggleL.ButtonPushedFcn = @(~,~) toggleLeft(); btnToggleR.ButtonPushedFcn = @(~,~) toggleRight();

sTop.ValueChangingFcn = @(~,evt) onTargetChange("top", evt.Value, true); 
sTop.ValueChangedFcn = @(src,~) onTargetChange("top", src.Value, false); 
eTop.ValueChangedFcn = @(src,~) onTargetChange("top", src.Value, false);

sMidHigh.ValueChangingFcn = @(~,evt) onTargetChange("midhigh", evt.Value, true); 
sMidHigh.ValueChangedFcn = @(src,~) onTargetChange("midhigh", src.Value, false); 
eMidHigh.ValueChangedFcn = @(src,~) onTargetChange("midhigh", src.Value, false);

sMid.ValueChangingFcn = @(~,evt) onTargetChange("mid", evt.Value, true); 
sMid.ValueChangedFcn = @(src,~) onTargetChange("mid", src.Value, false); 
eMid.ValueChangedFcn = @(src,~) onTargetChange("mid", src.Value, false);

sLow.ValueChangingFcn = @(~,evt) onTargetChange("low", evt.Value, true); 
sLow.ValueChangedFcn = @(src,~) onTargetChange("low", src.Value, false); 
eLow.ValueChangedFcn = @(src,~) onTargetChange("low", src.Value, false);

chkLockGamma.ValueChangedFcn = @(src,~) onLockChange("gamma", src.Value);
chkLockMu.ValueChangedFcn = @(src,~) onLockChange("mu", src.Value);
chkLockLambda.ValueChangedFcn = @(src,~) onLockChange("lambda", src.Value);
chkLockPhi.ValueChangedFcn = @(src,~) onLockChange("phi", src.Value);
chkLockK.ValueChangedFcn = @(src,~) onLockChange("k", src.Value);

wireAllParams();
applyLayout();
calcWstarAuto();
recomputeAndPlot();

%% ===== LOGIC =====

    function onTeamEdit(~, evt)
        if isempty(evt.Indices), return; end
        rowIdx = evt.Indices(1);
        colIdx = evt.Indices(2);
        teamName = string(tblTeams.Data{rowIdx, 1});
        if colIdx == 4
            TeamBankMap(char(teamName)) = evt.NewData;
        elseif colIdx == 5
            TeamBonusMap(char(teamName)) = evt.NewData;
        elseif colIdx == 6
            TeamMalusMap(char(teamName)) = evt.NewData;
        end
        updateTeamsTable();
        recomputeAndPlot();
    end

    function onReleaseEdit(~, evt)
        if isempty(evt.Indices), return; end
        if evt.Indices(2) ~= 1, return; end
        if isempty(selectedTeamForRelease), return; end
        updateReleaseSummary();
    end

    function onTeamSelected(src, ~)
        selectedTeamForRelease = string(src.Value);
        updateReleaseTable();
    end

    function simulateReleases()
        if strlength(selectedTeamForRelease) == 0
            selectedTeamForRelease = string(ddTeam.Value);
        end
        updateReleaseTable();
        updateReleaseSummary();
    end

    function updateTeamsTable()
        teams = uniqueTeams;
        nTeams = numel(teams);
        data = cell(nTeams, 9);
        releaseCredit = zeros(nTeams, 1);
        for iTeam = 1:nTeams
            teamName = teams(iTeam);
            maskTeam = team_c == teamName;
            spend = sum(cost_c(maskTeam), "omitnan");
            nPlayers = sum(maskTeam);
            baseBank = getMapValue(TeamBankMap, teamName);
            bonus = getMapValue(TeamBonusMap, teamName);
            malus = getMapValue(TeamMalusMap, teamName);
            bankTot = baseBank + bonus - malus;
            credits = S.C_max - spend + bankTot;
            if teamName == selectedTeamForRelease
                releaseCredit(iTeam) = getReleaseSelectedTotal();
            end
            creditsPost = credits + releaseCredit(iTeam);
            data(iTeam, :) = {char(teamName), nPlayers, round(spend), baseBank, bonus, malus, ...
                round(bankTot), round(credits), round(creditsPost)};
        end
        tblTeams.Data = data;
        tblTeams.ColumnName = {"Squadra","Giocatori","Spesa","Banca Base","Bonus","Malus","Banca Tot","Crediti","Crediti post-svincolo"};
        tblTeams.ColumnWidth = {'1x',70,80,90,70,70,90,80,130};
    end

    function updateReleaseTable()
        teamName = string(ddTeam.Value);
        selectedTeamForRelease = teamName;
        mask = team_c == teamName;
        if ~any(mask)
            tblRelease.Data = {};
            return;
        end
        [value, releaseValue, roleLabel] = computeValues();
        fvmTeam = fvm_c(mask);
        quotTeam = quot_c(mask);
        costTeam = cost_c(mask);
        nameTeam = name_c(mask);
        roleTeam = roleLabel(mask);
        valueTeam = value(mask);
        releaseTeam = releaseValue(mask);
        outTeam = isOut_c(mask);
        releaseFlags = false(sum(mask), 1);
        releaseTable = table(releaseFlags, nameTeam, roleTeam, fvmTeam, quotTeam, costTeam, valueTeam, releaseTeam, outTeam, ...
            'VariableNames', {'Svincola','Nome','Ruolo','FVM','Quot','Costo','Valore','ValoreSvincolo','OutList'});
        tblRelease.Data = tableToCellSafe(releaseTable);
        tblRelease.ColumnName = releaseTable.Properties.VariableNames;
        tblRelease.ColumnWidth = {70,'1x',70,60,60,60,70,90,70};
        updateReleaseSummary();
    end

    function updateReleaseSummary()
        updateTeamsTable();
        updateKpi();
    end

    function total = getReleaseSelectedTotal()
        total = 0;
        if isempty(tblRelease.Data)
            return;
        end
        data = tblRelease.Data;
        selected = cellfun(@(x) logical(x), data(:, 1));
        if any(selected)
            releaseValues = cell2mat(data(:, 8));
            total = sum(releaseValues(selected), "omitnan");
        end
    end

    function runAutoTune()
        applyTargets();
        recomputeAndPlot();
    end

    function maybeAutoTune()
        if autoOn.Value
            runAutoTune();
        end
    end

    function onTargetChange(targetName, value, isChanging)
        switch targetName
            case "top"
                TGT.topTarget = value;
                if ~isChanging, eTop.Value = value; end
            case "midhigh"
                TGT.midHighTarget = value;
                if ~isChanging, eMidHigh.Value = value; end
            case "mid"
                TGT.midTarget = value;
                if ~isChanging, eMid.Value = value; end
            case "low"
                TGT.lowTarget = value;
                if ~isChanging, eLow.Value = value; end
        end
        if autoOn.Value && ~isChanging
            runAutoTune();
        end
        updateBandChart();
    end

    function onLockChange(name, value)
        LOCKS.(name) = logical(value);
    end

    function applyTargets()
        if ~LOCKS.gamma
            S.gamma = clamp(0.5 + (TGT.topTarget / 400), 0.6, 2.4);
            H_ui.gamma.edt.Value = S.gamma;
        end
        if ~LOCKS.mu
            S.mu = clamp(0.5 + (TGT.lowTarget / 10), 0, 6);
            H_ui.mu.edt.Value = S.mu;
        end
        if ~LOCKS.lambda
            S.lambda = clamp((TGT.midHighTarget - 40) / 120, 0, 1);
            H_ui.lambda.edt.Value = S.lambda;
        end
        if ~LOCKS.phi
            S.phi = clamp(40 + (TGT.midTarget / 2), 0, 100);
            H_ui.phi.edt.Value = S.phi;
        end
        if ~LOCKS.k
            S.k = clamp(0.2 + (TGT.midTarget / 80), 0.05, 2.5);
            H_ui.k.edt.Value = S.k;
        end
    end

    function toggleLeft()
        leftShown = ~leftShown;
        if leftShown
            main.ColumnWidth{1} = 480;
            btnToggleL.Text = "◄ Panel";
        else
            main.ColumnWidth{1} = 0;
            btnToggleL.Text = "Panel ►";
        end
    end

    function toggleRight()
        rightShown = ~rightShown;
        if rightShown
            main.ColumnWidth{3} = 420;
            btnToggleR.Text = "Panel ►";
        else
            main.ColumnWidth{3} = 0;
            btnToggleR.Text = "◄ Panel";
        end
    end

    function applyLayout()
        updateTeamsTable();
        updateReleaseTable();
        updateKpi();
    end

    function wireAllParams()
        fields = fieldnames(H_ui);
        for i = 1:numel(fields)
            item = H_ui.(fields{i});
            if isstruct(item) && isfield(item, 'edt') && isfield(item, 'name')
                item.edt.ValueChangedFcn = @(src,~) syncParam(item.name, src.Value, 'edit');
                if isfield(item, 'slider')
                    item.slider.ValueChangedFcn = @(src,~) syncParam(item.name, src.Value, 'slider');
                end
            end
        end
    end

    function syncParam(fieldName, value, source)
        if isfield(H_ui, fieldName)
            if isfield(H_ui.(fieldName), 'slider') && strcmp(source, 'edit')
                H_ui.(fieldName).slider.Value = value;
            end
            if isfield(H_ui.(fieldName), 'edt') && strcmp(source, 'slider')
                H_ui.(fieldName).edt.Value = value;
            end
        end
        onParamChanged(fieldName, value);
    end

    function onParamChanged(fieldName, value)
        if fieldName == "epsilon"
            value = value / 100;
        end
        S.(fieldName) = value;
        if fieldName == "C_max" || fieldName == "epsilon"
            calcWstarAuto();
        end
        recomputeAndPlot();
    end

    function calcWstarAuto()
        nTeams = numel(uniqueTeams);
        S.Wstar = (S.C_max * nTeams) * (1 - S.epsilon);
        H_ui.Wstar_display.Value = round(S.Wstar);
        S.C_actual = sum(cost_c, "omitnan");
        H_ui.C_actual.edt.Value = round(S.C_actual);
        updateTeamsTable();
    end

    function recomputeAndPlot()
        [value, releaseValue, roleLabel] = computeValues();
        outTable = table(id_c, name_c, roleLabel, team_c, fvm_c, quot_c, cost_c, value, releaseValue, ...
            'VariableNames', {'ID','Nome','Ruolo','Squadra','FVM','Quot','Costo','Valore','ValoreSvincolo'});
        tbl.Data = tableToCellSafe(outTable);
        tbl.ColumnName = outTable.Properties.VariableNames;
        tbl.ColumnWidth = {60,'1x',60,80,60,60,60,70,90};
        updateKpi();
        updateCharts(value, releaseValue);
    end

    function updateCharts(value, releaseValue)
        cla(axPrice); histogram(axPrice, value, 20, 'FaceColor',[0.3 0.7 1]); grid(axPrice, "on");
        xlabel(axPrice, "Valore"); ylabel(axPrice, "Giocatori");
        cla(axCash); histogram(axCash, releaseValue, 20, 'FaceColor',[1 0.6 0.3]); grid(axCash, "on");
        xlabel(axCash, "Valore Svincolo"); ylabel(axCash, "Giocatori");
        updateBandChart();
        updateFunctionChart();
    end

    function updateBandChart()
        [value, ~, ~] = computeValues();
        edges = [0, TGT.lowTarget, TGT.midTarget, TGT.midHighTarget, TGT.topTarget, max(value) + 1];
        counts = histcounts(value, edges);
        cla(axBands);
        bar(axBands, counts, "FaceColor",[0.4 0.9 0.6]);
        axBands.XTick = 1:numel(counts);
        axBands.XTickLabel = {"Bassi","Medi","Medio-Alti","Top","Over"};
        ylabel(axBands, "Giocatori");
        title(axBands, "Fasce di Prezzo (target tuner)");
        grid(axBands, "on");
    end

    function updateFunctionChart()
        fvmRange = linspace(min(fvm_c), max(fvm_c), 100);
        quotMed = median(quot_c, "omitnan");
        dummyQuot = repmat(quotMed, size(fvmRange));
        [value, ~, ~] = computeValues(fvmRange, dummyQuot, repmat("", size(fvmRange)), repmat("", size(fvmRange)), zeros(size(fvmRange)), false(size(fvmRange)));
        cla(axFunc);
        plot(axFunc, fvmRange, value, "LineWidth",2, "Color",[0.2 0.4 0.9]);
        xlabel(axFunc, "FVM");
        ylabel(axFunc, "Valore");
        title(axFunc, "Curva di valorizzazione (FVM vs Valore)");
        grid(axFunc, "on");
    end

    function updateKpi()
        totalValue = sum(outTable.Valore, "omitnan");
        totalRelease = sum(outTable.ValoreSvincolo, "omitnan");
        nPlayers = height(outTable);
        selectedRelease = getReleaseSelectedTotal();
        kpi.Value = {
            sprintf("Giocatori: %d", nPlayers)
            sprintf("Valore totale: %.0f", totalValue)
            sprintf("Valore svincoli: %.0f", totalRelease)
            sprintf("Svincoli selezionati (%s): %.0f", selectedTeamForRelease, selectedRelease)
            sprintf("Cmax: %.0f | W*: %.0f", S.C_max, S.Wstar)
            sprintf("Parametri: γ=%.2f φ=%.0f μ=%.2f k=%.2f λ=%.2f", S.gamma, S.phi, S.mu, S.k, S.lambda)
            };
        coach.Value = {
            "Suggerimenti tuning:"
            "- Top: regola il picco dei top player"
            "- Medio/Medio-alto: controlla il plateau dei titolari"
            "- Bassi: incide sulle riserve"
            "Locks: blocca i parametri da auto-tune"
            };
    end

    function [value, releaseValue, roleLabel] = computeValues(fvmIn, quotIn, roleIn, roleClassicIn, costIn, outListIn)
        if nargin < 1
            fvmIn = fvm_c;
            quotIn = quot_c;
            roleIn = rm_c;
            roleClassicIn = role_classic;
            costIn = cost_c;
            outListIn = isOut_c;
        elseif nargin < 4
            roleClassicIn = role_classic(1:numel(fvmIn));
            costIn = zeros(size(fvmIn));
            outListIn = false(size(fvmIn));
        end
        fvmNorm = normalizePercentile(fvmIn, S.pLowF, S.pHighF);
        quotNorm = normalizePercentile(quotIn, S.pLowQ, S.pHighQ);
        base = (S.phi/100) .* fvmNorm + (1 - S.phi/100) .* quotNorm;
        base = base + S.alphaF * log(fvmIn + 1);
        base = max(base, 0);
        boost = 1 + S.lambda * ((fvmIn ./ max(S.k, 0.01)) .^ S.boostP);
        value = S.mu + (base .^ S.gamma) .* boost;
        roleWeight = arrayfun(@(i) getRoleWeight(roleIn(i), roleClassicIn(i)), 1:numel(value))';
        value = value .* roleWeight;
        value = max(value, 1);
        releaseValue = computeReleaseValue(value, costIn, outListIn);
        roleLabel = arrayfun(@(i) getRoleLabel(roleIn(i), roleClassicIn(i)), 1:numel(value))';
    end
    function releaseValue = computeReleaseValue(value, costIn, outListIn)
        releaseValue = value;
        if ~isempty(outListIn)
            releaseValue(outListIn) = releaseValue(outListIn) .* (1 - S.GrossOb);
        end
        releaseValue = releaseValue .* (1 - S.GrossDec);
        releaseValue = releaseValue - S.fee;
        gain = value - costIn;
        taxed = value - max(gain, 0) .* S.PlusTax;
        releaseValue = min(releaseValue, taxed);
        releaseValue = max(floor(releaseValue), 0);
    end

    function weight = getRoleWeight(roleMantra, roleClassic)
        roleLabel = getRoleLabel(roleMantra, roleClassic);
        switch roleLabel
            case "P"
                weight = S.wm_P;
            case "Pc"
                weight = S.wm_Pc;
            case "T"
                weight = S.wm_T;
            case "A"
                weight = S.wm_A;
            case "W"
                weight = S.wm_W;
            case "C"
                weight = S.wm_C;
            case "M"
                weight = S.wm_M;
            case "E"
                weight = S.wm_E;
            case "Dc"
                weight = S.wm_Dc;
            case "Dd"
                weight = S.wm_Dd;
            case "Ds"
                weight = S.wm_Ds;
            case "B"
                weight = S.wm_B;
            case "D"
                weight = S.wr_D;
            otherwise
                weight = S.wr_C;
        end
        if strlength(roleMantra) > 0
            parts = split(roleMantra, {'/','-',' '});
            parts = parts(parts ~= "");
            if numel(parts) > 1
                weight = weight * (1 + S.flex_bonus);
            end
        end
    end

    function roleLabel = getRoleLabel(roleMantra, roleClassic)
        if strlength(roleMantra) > 0
            parts = split(roleMantra, {'/','-',' '});
            parts = parts(parts ~= "");
            if numel(parts) > 1
                roleLabel = string(parts(1));
                return;
            else
                roleLabel = string(roleMantra);
                return;
            end
        end
        roleLabel = string(roleClassic);
    end

    function values = normalizePercentile(values, pLow, pHigh)
        if isempty(values)
            return;
        end
        mask = isfinite(values);
        if ~any(mask)
            values = zeros(size(values));
            return;
        end
        lo = prctile(values(mask), pLow * 100);
        hi = prctile(values(mask), pHigh * 100);
        values = (values - lo) ./ max(hi - lo, eps);
        values = min(max(values, 0), 1);
        values(~mask) = 0;
    end

    function val = clamp(val, lo, hi)
        val = min(max(val, lo), hi);
    end

    function val = getMapValue(map, key)
        if isKey(map, char(key))
            val = map(char(key));
        else
            val = 0;
        end
    end

    function data = tableToCellSafe(tblIn)
        data = table2cell(tblIn);
        for r = 1:size(data, 1)
            for c = 1:size(data, 2)
                if isstring(data{r, c})
                    data{r, c} = char(data{r, c});
                end
            end
        end
    end

    function saveConfig()
        [file, path] = uiputfile("*.mat", "Salva Configurazione");
        if isequal(file,0), return; end
        config = struct();
        config.S = S;
        config.TGT = TGT;
        config.LOCKS = LOCKS;
        config.TeamBankMap = TeamBankMap;
        config.TeamBonusMap = TeamBonusMap;
        config.TeamMalusMap = TeamMalusMap;
        save(fullfile(path, file), "config");
    end

    function loadConfig()
        [file, path] = uigetfile("*.mat", "Carica Configurazione");
        if isequal(file,0), return; end
        data = load(fullfile(path, file));
        if ~isfield(data, "config"), return; end
        config = data.config;
        if isfield(config, "S"), S = config.S; end
        if isfield(config, "TGT"), TGT = config.TGT; end
        if isfield(config, "LOCKS"), LOCKS = config.LOCKS; end
        if isfield(config, "TeamBankMap"), TeamBankMap = config.TeamBankMap; end
        if isfield(config, "TeamBonusMap"), TeamBonusMap = config.TeamBonusMap; end
        if isfield(config, "TeamMalusMap"), TeamMalusMap = config.TeamMalusMap; end
        refreshUIFromState();
        recomputeAndPlot();
    end

    function refreshUIFromState()
        H_ui.C_max.edt.Value = S.C_max;
        H_ui.epsilon.edt.Value = S.epsilon * 100;
        H_ui.gamma.edt.Value = S.gamma;
        H_ui.phi.edt.Value = S.phi;
        H_ui.alphaF.edt.Value = S.alphaF;
        H_ui.pLowF.edt.Value = S.pLowF;
        H_ui.pHighF.edt.Value = S.pHighF;
        H_ui.pLowQ.edt.Value = S.pLowQ;
        H_ui.pHighQ.edt.Value = S.pHighQ;
        H_ui.mu.edt.Value = S.mu;
        H_ui.k.edt.Value = S.k;
        H_ui.boostP.edt.Value = S.boostP;
        H_ui.lambda.edt.Value = S.lambda;
        H_ui.PlusTax.edt.Value = S.PlusTax;
        H_ui.GrossOb.edt.Value = S.GrossOb;
        H_ui.GrossDec.edt.Value = S.GrossDec;
        H_ui.fee.edt.Value = S.fee;
        sTop.Value = TGT.topTarget; eTop.Value = TGT.topTarget;
        sMidHigh.Value = TGT.midHighTarget; eMidHigh.Value = TGT.midHighTarget;
        sMid.Value = TGT.midTarget; eMid.Value = TGT.midTarget;
        sLow.Value = TGT.lowTarget; eLow.Value = TGT.lowTarget;
        chkLockGamma.Value = LOCKS.gamma;
        chkLockMu.Value = LOCKS.mu;
        chkLockLambda.Value = LOCKS.lambda;
        chkLockPhi.Value = LOCKS.phi;
        chkLockK.Value = LOCKS.k;
        calcWstarAuto();
    end

    function exportFullData()
        [file, path] = uiputfile("*.xlsx", "Esporta Dati Completi");
        if isequal(file,0), return; end
        writetable(outTable, fullfile(path, file), "Sheet", "Giocatori");
        teamTable = cell2table(tblTeams.Data, "VariableNames", tblTeams.ColumnName);
        writetable(teamTable, fullfile(path, file), "Sheet", "Squadre");
    end

    function onSelectRow(~, evt)
        if isempty(evt.Indices), return; end
        selRow = evt.Indices(1);
        selName = string(outTable.Nome(selRow));
        selectedTeamForRelease = string(outTable.Squadra(selRow));
        ddTeam.Value = selectedTeamForRelease;
        updateReleaseTable();
    end

    function label = createLabel(parent, row, col, text, style)
        label = uilabel(parent, "Text", text);
        if nargin > 4 && style == "bold"
            label.FontWeight = "bold";
        elseif nargin > 4 && style == "italic"
            label.FontAngle = "italic";
        end
        label.Layout.Row = row;
        label.Layout.Column = col;
    end

    function out = addInputRow(parent, label, fieldName, row, value)
        createLabel(parent, row, 1, label, "bold");
        edt = uieditfield(parent, "numeric", "Value", value);
        edt.Layout.Row = row;
        edt.Layout.Column = [2 3];
        out = struct('edt', edt, 'name', fieldName);
        H_ui.(fieldName) = out;
    end

    function out = addParamRow(parent, label, fieldName, minVal, maxVal, row, value, fmt)
        createLabel(parent, row, 1, label);
        sld = uislider(parent, "Limits", [minVal maxVal], "Value", value);
        sld.Layout.Row = row;
        sld.Layout.Column = 2;
        edt = uieditfield(parent, "numeric", "Limits", [minVal maxVal], "Value", value, "ValueDisplayFormat", fmt);
        edt.Layout.Row = row;
        edt.Layout.Column = 3;
        out = struct('slider', sld, 'edt', edt, 'name', fieldName);
        H_ui.(fieldName) = out;
        sld.ValueChangedFcn = @(src,~) edt.Value = src.Value;
        edt.ValueChangedFcn = @(src,~) sld.Value = src.Value;
    end

    function out = addParamRowWithLock(parent, label, fieldName, minVal, maxVal, row, value, fmt)
        out = addParamRow(parent, label, fieldName, minVal, maxVal, row, value, fmt);
    end
end
