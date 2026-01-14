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
LOCKS.phi = false; LOCKS.lambda = false; LOCKS.k = false; LOCKS.targets = false;

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
sgrid = uigridlayout(tabS, [2 1]); sgrid.RowHeight={40, '1x'};
sgridTop = uigridlayout(sgrid, [1 3]); sgridTop.Layout.Row=1; sgridTop.ColumnWidth={'1x', 150, 150};
lblTeamSel = uilabel(sgridTop, "Text", "Seleziona squadra per simulare svincoli:", "FontWeight","bold");
lblTeamSel.Layout.Column=1;
ddTeam = uidropdown(sgridTop, "Items", cellstr(uniqueTeams), "ValueChangedFcn", @onTeamSelected);
ddTeam.Layout.Column=2;
btnSimRelease = uibutton(sgridTop, "Text", "🔄 Simula Svincoli", "FontWeight","bold", "BackgroundColor",[1 0.9 0.6]);
btnSimRelease.Layout.Column=3; btnSimRelease.ButtonPushedFcn = @(~,~) simulateReleases();

tblTeams = uitable(sgrid); tblTeams.Layout.Row=2; tblTeams.ColumnSortable=true; tblTeams.FontName="Segoe UI"; tblTeams.FontSize=10;
tblTeams.ColumnName = ["Squadra","Giocatori","Valore Rosa","Banca Base","Bonus","Malus","Crediti Totali","Valore Svincoli","Crediti Post Svincoli"];
tblTeams.ColumnEditable = [false false false true true true false false false];
tblTeams.CellEditCallback = @onTeamEdit;

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

createLabel(ag,2,1,"💎 Top","bold");  
sTop=uislider(ag,"Limits",[80 400],"Value",TGT.topTarget); sTop.Layout.Row=2; sTop.Layout.Column=2;  
eTop=uieditfield(ag,"numeric","Limits",[80 400],"Value",TGT.topTarget,"ValueDisplayFormat","%.0f"); eTop.Layout.Row=2; eTop.Layout.Column=3;  
 sTop.Tooltip = "Target prezzo fascia Top (giocatori elite)";
 eTop.Tooltip = "Target prezzo fascia Top (giocatori elite)";

createLabel(ag,3,1,"🥈 Medio-Alto","bold");  
sMidHigh=uislider(ag,"Limits",[40 150],"Value",TGT.midHighTarget); sMidHigh.Layout.Row=3; sMidHigh.Layout.Column=2;  
eMidHigh=uieditfield(ag,"numeric","Limits",[40 150],"Value",TGT.midHighTarget,"ValueDisplayFormat","%.0f"); eMidHigh.Layout.Row=3; eMidHigh.Layout.Column=3;  
 sMidHigh.Tooltip = "Target fascia medio-alta (titolarissimi)";
 eMidHigh.Tooltip = "Target fascia medio-alta (titolarissimi)";

createLabel(ag,4,1,"🥉 Medio","bold");  
sMid=uislider(ag,"Limits",[15 80],"Value",TGT.midTarget); sMid.Layout.Row=4; sMid.Layout.Column=2;  
eMid=uieditfield(ag,"numeric","Limits",[15 80],"Value",TGT.midTarget,"ValueDisplayFormat","%.0f"); eMid.Layout.Row=4; eMid.Layout.Column=3;  
 sMid.Tooltip = "Target fascia media (buoni titolari)";
 eMid.Tooltip = "Target fascia media (buoni titolari)";

createLabel(ag,5,1,"📉 Scarti %","bold");  
sLow=uislider(ag,"Limits",[0 30],"Value",TGT.lowTarget); sLow.Layout.Row=5; sLow.Layout.Column=2;  
eLow=uieditfield(ag,"numeric","Limits",[0 30],"Value",TGT.lowTarget,"ValueDisplayFormat","%.1f"); eLow.Layout.Row=5; eLow.Layout.Column=3;  
 sLow.Tooltip = "Sconto fascia bassa (% riduzione)";
 eLow.Tooltip = "Sconto fascia bassa (% riduzione)";

createLabel(ag,6,[1 3],"🔒 Locks: blocca parametri dal tuning","italic");
lockGrid = uigridlayout(ag, [2 3]); lockGrid.Layout.Row=7; lockGrid.Layout.Column=[1 3]; lockGrid.ColumnWidth={'1x','1x','1x'}; lockGrid.RowHeight={24,24};
chkLockGamma = uicheckbox(lockGrid, "Text", "🔒γ", "Value", false); chkLockGamma.Layout.Row=1; chkLockGamma.Layout.Column=1;
chkLockMu = uicheckbox(lockGrid, "Text", "🔒μ", "Value", false); chkLockMu.Layout.Row=1; chkLockMu.Layout.Column=2;
chkLockLambda = uicheckbox(lockGrid, "Text", "🔒λ", "Value", false); chkLockLambda.Layout.Row=1; chkLockLambda.Layout.Column=3;
chkLockK = uicheckbox(lockGrid, "Text", "🔒k", "Value", false); chkLockK.Layout.Row=2; chkLockK.Layout.Column=1;
chkLockPhi = uicheckbox(lockGrid, "Text", "🔒φ", "Value", false); chkLockPhi.Layout.Row=2; chkLockPhi.Layout.Column=2;
chkLockTargets = uicheckbox(lockGrid, "Text", "🔒Target", "Value", false); chkLockTargets.Layout.Row=2; chkLockTargets.Layout.Column=3;

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
chkLockK.ValueChangedFcn = @(src,~) onLockChange("k", src.Value);
chkLockPhi.ValueChangedFcn = @(src,~) onLockChange("phi", src.Value);
chkLockTargets.ValueChangedFcn = @(src,~) onLockChange("targets", src.Value);

wireAllParams();
applyLayout();
calcWstarAuto();
recomputeAndPlot();

%% ===== LOGIC =====
    function onTeamEdit(~, evt)
        if isempty(evt.Indices) || isempty(teamsTable)
            return;
        end
        rowIdx = evt.Indices(1);
        colIdx = evt.Indices(2);
        if rowIdx > height(teamsTable)
            return;
        end
        teamName = teamsTable.Squadra(rowIdx);
        newValue = evt.NewData;
        switch colIdx
            case 4
                TeamBankMap(char(teamName)) = max(0, newValue);
            case 5
                TeamBonusMap(char(teamName)) = newValue;
            case 6
                TeamMalusMap(char(teamName)) = newValue;
            otherwise
                return;
        end
        recomputeAndPlot();
    end

    function onTeamSelected(~, ~)
        selectedTeamForRelease = ddTeam.Value;
    end

    function simulateReleases()
        teamName = string(ddTeam.Value);
        if strlength(teamName) == 0
            return;
        end
        selectedTeamForRelease = teamName;
        idx = team_c == teamName;
        if ~any(idx)
            uialert(fig, "Nessun giocatore per la squadra selezionata.", "Svincoli");
            return;
        end
        [values, releaseValues] = computeValues(fvm_c(idx), quot_c(idx), rc_c(idx), rm_c(idx));
        baseCredits = getTeamCredits(teamName);
        releaseSimData = table(name_c(idx), fvm_c(idx), quot_c(idx), values, releaseValues, ...
            "VariableNames", {"Nome","FVM","Quot","Valore","ValoreSvincolo"});
        releaseSimData = sortrows(releaseSimData, "ValoreSvincolo", "descend");
        releaseSimData.CreditiPostSvincolo = baseCredits + cumsum(releaseSimData.ValoreSvincolo);

        simFig = uifigure("Name", "Simulazione Svincoli - " + teamName, "Position", [100 100 750 500]);
        simGrid = uigridlayout(simFig, [2 1]);
        simGrid.RowHeight = {40, "1x"};
        simInfo = uilabel(simGrid, "Text", "Crediti iniziali: " + num2str(baseCredits, "%.0f") + ...
            " | Crediti finali (tutti svincoli): " + num2str(baseCredits + sum(releaseSimData.ValoreSvincolo), "%.0f"), ...
            "FontWeight", "bold");
        simTable = uitable(simGrid);
        simTable.Data = releaseSimData;
        simTable.ColumnSortable = true;
    end

    function onTargetChange(whichTarget, value, isPreview)
        if LOCKS.targets
            refreshTargetControls();
            return;
        end
        switch whichTarget
            case "top"
                TGT.topTarget = value;
            case "midhigh"
                TGT.midHighTarget = value;
            case "mid"
                TGT.midTarget = value;
            case "low"
                TGT.lowTarget = value;
        end
        if ~isPreview
            refreshTargetControls();
            maybeAutoTune();
        else
            refreshTargetControls(false);
        end
    end

    function onLockChange(lockName, value)
        if isfield(LOCKS, lockName)
            LOCKS.(lockName) = value;
        end
        applyLocks();
    end

    function applyLocks()
        setControlLock(H_ui.gamma, LOCKS.gamma);
        setControlLock(H_ui.mu, LOCKS.mu);
        setControlLock(H_ui.lambda, LOCKS.lambda);
        setControlLock(H_ui.k, LOCKS.k);
        setControlLock(H_ui.phi, LOCKS.phi);

        lockTargets = LOCKS.targets;
        sTop.Enable = onOff(~lockTargets);
        eTop.Editable = ~lockTargets;
        sMidHigh.Enable = onOff(~lockTargets);
        eMidHigh.Editable = ~lockTargets;
        sMid.Enable = onOff(~lockTargets);
        eMid.Editable = ~lockTargets;
        sLow.Enable = onOff(~lockTargets);
        eLow.Editable = ~lockTargets;
    end

    function setControlLock(ctrl, isLocked)
        if ~isstruct(ctrl)
            return;
        end
        if isfield(ctrl, "slider") && ~isempty(ctrl.slider)
            ctrl.slider.Enable = onOff(~isLocked);
        end
        if isfield(ctrl, "edt") && ~isempty(ctrl.edt)
            ctrl.edt.Editable = ~isLocked;
        end
    end

    function refreshTargetControls(updateValues)
        if nargin < 1
            updateValues = true;
        end
        if updateValues
            sTop.Value = TGT.topTarget;
            eTop.Value = TGT.topTarget;
            sMidHigh.Value = TGT.midHighTarget;
            eMidHigh.Value = TGT.midHighTarget;
            sMid.Value = TGT.midTarget;
            eMid.Value = TGT.midTarget;
            sLow.Value = TGT.lowTarget;
            eLow.Value = TGT.lowTarget;
        end
    end

    function maybeAutoTune()
        if autoOn.Value
            runAutoTune();
        end
    end

    function runAutoTune()
        recomputeAndPlot(false);
        [values, ~] = computeValues(fvm_c, quot_c, rc_c, rm_c);
        if isempty(values)
            return;
        end
        topNow = prctile(values, 98);
        midHighNow = prctile(values, 90);
        midNow = prctile(values, 70);

        scaleTop = safeDiv(TGT.topTarget, topNow);
        scaleMidHigh = safeDiv(TGT.midHighTarget, midHighNow);
        scaleMid = safeDiv(TGT.midTarget, midNow);

        if ~LOCKS.gamma
            S.gamma = clamp(S.gamma * scaleTop^0.15, 0.5, 3.0);
        end
        if ~LOCKS.k
            S.k = clamp(S.k * scaleMidHigh^0.2, 0.05, 5);
        end
        if ~LOCKS.mu
            S.mu = clamp(S.mu + (scaleMid - 1) * 1.5, 0, 10);
        end
        if ~LOCKS.lambda
            S.lambda = clamp(S.lambda * scaleTop^0.1, 0, 1);
        end
        if ~LOCKS.phi
            S.phi = clamp(S.phi + (scaleMidHigh - 1) * 8, 0, 100);
        end
        syncUIFromS();
        recomputeAndPlot();
    end

    function recomputeAndPlot(runCharts)
        if nargin < 1
            runCharts = true;
        end
        syncSFromUI();
        calcWstarAuto();
        [playerValues, releaseValues] = computeValues(fvm_c, quot_c, rc_c, rm_c);

        outTable = table(id_c, name_c, team_c, rc_c, rm_c, fvm_c, quot_c, cost_c, playerValues, releaseValues, ...
            "VariableNames", {"ID","Nome","Squadra","Ruolo","Mantra","FVM","Quot","Costo","Valore","ValoreSvincolo"});
        tbl.Data = outTable;
        tbl.ColumnName = outTable.Properties.VariableNames;
        tbl.ColumnEditable = false(1, width(outTable));
        tbl.RowName = {};

        updateTeamsTable(playerValues, releaseValues);
        updateKpi(playerValues, releaseValues);

        if runCharts
            updateCharts(playerValues, releaseValues);
        end
    end

    function updateTeamsTable(values, releaseValues)
        if nargin < 2
            [values, releaseValues] = computeValues(fvm_c, quot_c, rc_c, rm_c);
        end
        teamList = uniqueTeams;
        rows = numel(teamList);
        teams = strings(rows, 1);
        players = zeros(rows, 1);
        rosaValue = zeros(rows, 1);
        bank = zeros(rows, 1);
        bonus = zeros(rows, 1);
        malus = zeros(rows, 1);
        credits = zeros(rows, 1);
        relValue = zeros(rows, 1);
        creditsAfter = zeros(rows, 1);
        for i = 1:rows
            tName = teamList(i);
            teams(i) = tName;
            idx = team_c == tName;
            players(i) = sum(idx);
            rosaValue(i) = sum(values(idx), "omitnan");
            bank(i) = getMapValue(TeamBankMap, tName);
            bonus(i) = getMapValue(TeamBonusMap, tName);
            malus(i) = getMapValue(TeamMalusMap, tName);
            credits(i) = bank(i) + bonus(i) - malus(i);
            relValue(i) = sum(releaseValues(idx), "omitnan");
            creditsAfter(i) = credits(i) + relValue(i);
        end
        teamsTable = table(teams, players, rosaValue, bank, bonus, malus, credits, relValue, creditsAfter, ...
            "VariableNames", cellstr(tblTeams.ColumnName));
        tblTeams.Data = teamsTable;
        tblTeams.RowName = {};
    end

    function updateKpi(playerValues, releaseValues)
        totalValue = sum(playerValues, "omitnan");
        totalRelease = sum(releaseValues, "omitnan");
        baseValues = cell2mat(values(TeamBankMap));
        bonusValues = cell2mat(values(TeamBonusMap));
        malusValues = cell2mat(values(TeamMalusMap));
        if isempty(baseValues)
            totalCredits = 0;
        else
            totalCredits = sum(baseValues, "omitnan") + sum(bonusValues, "omitnan") - sum(malusValues, "omitnan");
        end
        kpi.Value = sprintf([ ...
            "Giocatori: %d\n", ...
            "Valore Totale Rosa: %.1f\n", ...
            "Valore Totale Svincoli: %.1f\n", ...
            "Crediti Base Totali: %.0f\n", ...
            "W*: %.0f\n", ...
            "Cmax: %.0f | ε: %.2f%%\n", ...
            "AutoTune: %s"], ...
            numel(playerValues), totalValue, totalRelease, totalCredits, S.Wstar, S.C_max, S.epsilon * 100, onOff(autoOn.Value));
    end

    function updateCharts(values, releaseValues)
        if isempty(values)
            return;
        end
        cla(axPrice);
        cla(axCash);
        cla(axBands);
        histogram(axPrice, values, 20, "FaceColor", [0.2 0.6 0.9]);
        xlabel(axPrice, "Valore"); ylabel(axPrice, "Giocatori");
        histogram(axCash, releaseValues, 20, "FaceColor", [0.9 0.6 0.2]);
        xlabel(axCash, "Valore Svincolo"); ylabel(axCash, "Giocatori");

        bands = [0 5 10 20 30 50 80 120 200 400];
        counts = histcounts(values, bands);
        bar(axBands, bands(1:end-1), counts, "FaceColor", [0.3 0.8 0.6]);
        xlabel(axBands, "Fasce Prezzo"); ylabel(axBands, "N. giocatori");
        axBands.XLim = [bands(1) bands(end)];
        axBands.XTick = bands(1:end-1);
        axBands.XGrid = "on";

        cla(axFunc);
        x = linspace(0, 1, 100);
        y = valuationCurve(x);
        area(axFunc, x, y, "FaceColor", [0.7 0.8 1], "EdgeColor", [0.2 0.4 0.8]);
        hold(axFunc, "on");
        plot(axFunc, x, y, "LineWidth", 2, "Color", [0.2 0.4 0.8]);
        hold(axFunc, "off");
        xlabel(axFunc, "Score Normalizzato");
        ylabel(axFunc, "Valore");
        grid(axFunc, "on");
    end

    function val = valuationCurve(x)
        base = (x .^ S.gamma);
        val = S.mu + S.k * (base * 100) .* (1 + S.lambda * (x .^ S.boostP));
    end

    function [values, releaseValues] = computeValues(fvmVals, quotVals, rcVals, rmVals)
        if isempty(fvmVals)
            values = [];
            releaseValues = [];
            return;
        end
        scoreF = normalizePercentile(fvmVals, S.pLowF, S.pHighF);
        scoreQ = normalizePercentile(quotVals, S.pLowQ, S.pHighQ);
        phi = S.phi / 100;
        baseScore = phi * scoreF + (1 - phi) * scoreQ;
        baseScore = max(0, min(1, baseScore));
        weight = roleWeight(rcVals, rmVals);
        values = valuationCurve(baseScore) .* weight;
        values = max(0, values);
        releaseValues = max(0, values .* (1 - S.GrossDec) - S.fee);
    end

    function weights = roleWeight(rcVals, rmVals)
        n = numel(rcVals);
        weights = ones(n, 1);
        for i = 1:n
            mantra = strtrim(rmVals(i));
            classic = strtrim(rcVals(i));
            if strlength(mantra) > 0
                tokens = split(mantra, {"/", ","});
                tokens = strtrim(tokens);
                weights(i) = max(cellfun(@(t) roleWeightToken(t), cellstr(tokens)));
            else
                weights(i) = roleWeightClassic(classic);
            end
        end
    end

    function w = roleWeightToken(token)
        switch upper(token)
            case "PC"
                w = S.wm_Pc;
            case "T"
                w = S.wm_T;
            case "A"
                w = S.wm_A;
            case "W"
                w = S.wm_W;
            case "C"
                w = S.wm_C;
            case "M"
                w = S.wm_M;
            case "E"
                w = S.wm_E;
            case "DC"
                w = S.wm_Dc;
            case "B"
                w = S.wm_B;
            case "DD"
                w = S.wm_Dd;
            case "DS"
                w = S.wm_Ds;
            case "P"
                w = S.wm_P;
            otherwise
                w = 1.0;
        end
    end

    function w = roleWeightClassic(token)
        switch upper(token)
            case "P"
                w = S.wr_P;
            case "D"
                w = S.wr_D;
            case "C"
                w = S.wr_C;
            case "A"
                w = S.wr_A;
            otherwise
                w = 1.0;
        end
    end

    function nrm = normalizePercentile(values, pLow, pHigh)
        if all(isnan(values))
            nrm = zeros(size(values));
            return;
        end
        lo = quantile(values, pLow);
        hi = quantile(values, pHigh);
        if hi == lo
            nrm = zeros(size(values));
            return;
        end
        nrm = (values - lo) ./ (hi - lo);
        nrm = max(0, min(1, nrm));
    end

    function syncSFromUI()
        S.C_max = H_ui.C_max.edt.Value;
        S.epsilon = H_ui.epsilon.edt.Value / 100;
        S.gamma = H_ui.gamma.edt.Value;
        S.phi = H_ui.phi.edt.Value;
        S.alphaF = H_ui.alphaF.edt.Value;
        S.pLowF = H_ui.pLowF.edt.Value;
        S.pHighF = H_ui.pHighF.edt.Value;
        S.pLowQ = H_ui.pLowQ.edt.Value;
        S.pHighQ = H_ui.pHighQ.edt.Value;
        S.mu = H_ui.mu.edt.Value;
        S.k = H_ui.k.edt.Value;
        S.boostP = H_ui.boostP.edt.Value;
        S.lambda = H_ui.lambda.edt.Value;
        S.PlusTax = H_ui.PlusTax.edt.Value;
        S.GrossOb = H_ui.GrossOb.edt.Value;
        S.GrossDec = H_ui.GrossDec.edt.Value;
        S.fee = H_ui.fee.edt.Value;
        S.wm_Pc = H_ui.wm_Pc.edt.Value;
        S.wm_T = H_ui.wm_T.edt.Value;
        S.wm_A = H_ui.wm_A.edt.Value;
        S.wm_W = H_ui.wm_W.edt.Value;
        S.wm_C = H_ui.wm_C.edt.Value;
        S.wm_M = H_ui.wm_M.edt.Value;
        S.wm_E = H_ui.wm_E.edt.Value;
        S.wm_Dc = H_ui.wm_Dc.edt.Value;
        S.wm_B = H_ui.wm_B.edt.Value;
        S.wm_Dd = H_ui.wm_Dd.edt.Value;
        S.wm_Ds = H_ui.wm_Ds.edt.Value;
        S.wm_P = H_ui.wm_P.edt.Value;
        S.flex_bonus = H_ui.flex_bonus.edt.Value;
        S.wr_A = H_ui.wr_A.edt.Value;
        S.wr_C = H_ui.wr_C.edt.Value;
        S.wr_D = H_ui.wr_D.edt.Value;
        S.wr_P = H_ui.wr_P.edt.Value;
    end

    function syncUIFromS()
        setParamUI(H_ui.C_max, S.C_max);
        setParamUI(H_ui.epsilon, S.epsilon * 100);
        setParamUI(H_ui.gamma, S.gamma);
        setParamUI(H_ui.phi, S.phi);
        setParamUI(H_ui.alphaF, S.alphaF);
        setParamUI(H_ui.pLowF, S.pLowF);
        setParamUI(H_ui.pHighF, S.pHighF);
        setParamUI(H_ui.pLowQ, S.pLowQ);
        setParamUI(H_ui.pHighQ, S.pHighQ);
        setParamUI(H_ui.mu, S.mu);
        setParamUI(H_ui.k, S.k);
        setParamUI(H_ui.boostP, S.boostP);
        setParamUI(H_ui.lambda, S.lambda);
        setParamUI(H_ui.PlusTax, S.PlusTax);
        setParamUI(H_ui.GrossOb, S.GrossOb);
        setParamUI(H_ui.GrossDec, S.GrossDec);
        setParamUI(H_ui.fee, S.fee);
        setParamUI(H_ui.wm_Pc, S.wm_Pc);
        setParamUI(H_ui.wm_T, S.wm_T);
        setParamUI(H_ui.wm_A, S.wm_A);
        setParamUI(H_ui.wm_W, S.wm_W);
        setParamUI(H_ui.wm_C, S.wm_C);
        setParamUI(H_ui.wm_M, S.wm_M);
        setParamUI(H_ui.wm_E, S.wm_E);
        setParamUI(H_ui.wm_Dc, S.wm_Dc);
        setParamUI(H_ui.wm_B, S.wm_B);
        setParamUI(H_ui.wm_Dd, S.wm_Dd);
        setParamUI(H_ui.wm_Ds, S.wm_Ds);
        setParamUI(H_ui.wm_P, S.wm_P);
        setParamUI(H_ui.flex_bonus, S.flex_bonus);
        setParamUI(H_ui.wr_A, S.wr_A);
        setParamUI(H_ui.wr_C, S.wr_C);
        setParamUI(H_ui.wr_D, S.wr_D);
        setParamUI(H_ui.wr_P, S.wr_P);
    end

    function setParamUI(ctrl, value)
        if isfield(ctrl, "edt")
            ctrl.edt.Value = value;
        end
        if isfield(ctrl, "slider") && ~isempty(ctrl.slider)
            ctrl.slider.Value = value;
        end
    end

    function calcWstarAuto()
        teamCount = numel(uniqueTeams);
        S.Wstar = (S.C_max * teamCount) * (1 - S.epsilon);
        H_ui.Wstar_display.Value = S.Wstar;
        baseValues = cell2mat(values(TeamBankMap));
        bonusValues = cell2mat(values(TeamBonusMap));
        malusValues = cell2mat(values(TeamMalusMap));
        if isempty(baseValues)
            H_ui.C_actual.edt.Value = 0;
        else
            H_ui.C_actual.edt.Value = sum(baseValues, "omitnan") + sum(bonusValues, "omitnan") - sum(malusValues, "omitnan");
        end
    end

    function exportFullData()
        [file, path] = uiputfile("FantaTuner_Export.xlsx", "Esporta Excel Completo");
        if isequal(file, 0)
            return;
        end
        fullPath = fullfile(path, file);
        try
            writetable(outTable, fullPath, "Sheet", "Giocatori");
            writetable(teamsTable, fullPath, "Sheet", "Squadre");
            if ~isempty(releaseSimData)
                writetable(releaseSimData, fullPath, "Sheet", "Svincoli");
            end
            uialert(fig, "Export completato: " + fullPath, "Export");
        catch err
            uialert(fig, "Errore export: " + err.message, "Errore");
        end
    end

    function saveConfig()
        [file, path] = uiputfile("FantaTuner_Config.mat", "Salva configurazione");
        if isequal(file, 0)
            return;
        end
        cfg = struct();
        cfg.S = S;
        cfg.TGT = TGT;
        cfg.LOCKS = LOCKS;
        cfg.TeamBankMap = TeamBankMap;
        cfg.TeamBonusMap = TeamBonusMap;
        cfg.TeamMalusMap = TeamMalusMap;
        cfg.selectedTeam = ddTeam.Value;
        save(fullfile(path, file), "-struct", "cfg");
    end

    function loadConfig()
        [file, path] = uigetfile("*.mat", "Carica configurazione");
        if isequal(file, 0)
            return;
        end
        cfg = load(fullfile(path, file));
        if isfield(cfg, "S"), S = cfg.S; end
        if isfield(cfg, "TGT"), TGT = cfg.TGT; end
        if isfield(cfg, "LOCKS"), LOCKS = cfg.LOCKS; end
        if isfield(cfg, "TeamBankMap"), TeamBankMap = cfg.TeamBankMap; end
        if isfield(cfg, "TeamBonusMap"), TeamBonusMap = cfg.TeamBonusMap; end
        if isfield(cfg, "TeamMalusMap"), TeamMalusMap = cfg.TeamMalusMap; end
        syncUIFromS();
        refreshTargetControls();
        applyLocks();
        if isfield(cfg, "selectedTeam")
            ddTeam.Value = cfg.selectedTeam;
        end
        recomputeAndPlot();
    end

    function onSelectRow(~, evt)
        if isempty(evt.Indices)
            return;
        end
        row = evt.Indices(1);
        if row <= height(outTable)
            selName = outTable.Nome{row};
        end
    end

    function toggleLeft()
        leftShown = ~leftShown;
        applyLayout();
    end

    function toggleRight()
        rightShown = ~rightShown;
        applyLayout();
    end

    function applyLayout()
        if leftShown && rightShown
            main.ColumnWidth = {480, "1.2x", 420};
        elseif leftShown
            main.ColumnWidth = {480, "1x", 0};
        elseif rightShown
            main.ColumnWidth = {0, "1x", 420};
        else
            main.ColumnWidth = {0, "1x", 0};
        end
    end

    function wireAllParams()
        applyLocks();
        refreshTargetControls();
    end

    function ctrl = addInputRow(grid, labelText, paramName, row, value)
        createLabel(grid, row, 1, labelText);
        edt = uieditfield(grid, "numeric", "Value", value);
        edt.Layout.Row = row;
        edt.Layout.Column = [2 3];
        edt.ValueChangedFcn = @(src, ~) onParamChange(paramName, src.Value);
        ctrl = struct("edt", edt, "slider", []);
    end

    function ctrl = addParamRow(grid, labelText, paramName, minVal, maxVal, row, value, format)
        if nargin < 8
            format = "%.2f";
        end
        createLabel(grid, row, 1, labelText);
        slider = uislider(grid, "Limits", [minVal maxVal], "Value", value);
        slider.Layout.Row = row;
        slider.Layout.Column = 2;
        edt = uieditfield(grid, "numeric", "Limits", [minVal maxVal], "Value", value, "ValueDisplayFormat", format);
        edt.Layout.Row = row;
        edt.Layout.Column = 3;
        slider.ValueChangingFcn = @(~, evt) onParamPreview(paramName, evt.Value, edt);
        slider.ValueChangedFcn = @(src, ~) onParamChange(paramName, src.Value);
        edt.ValueChangedFcn = @(src, ~) onParamChange(paramName, src.Value);
        ctrl = struct("slider", slider, "edt", edt);
    end

    function ctrl = addParamRowWithLock(grid, labelText, paramName, minVal, maxVal, row, value, format)
        ctrl = addParamRow(grid, labelText, paramName, minVal, maxVal, row, value, format);
    end

    function onParamPreview(paramName, value, edt)
        edt.Value = value;
        if ~strcmp(paramName, "epsilon")
            updateCoach("Anteprima " + paramName + ": " + num2str(value, "%.2f"));
        end
    end

    function onParamChange(paramName, value)
        switch paramName
            case "epsilon"
                value = value / 100;
            otherwise
        end
        S.(paramName) = value;
        if isfield(H_ui, paramName)
            if paramName == "epsilon"
                setParamUI(H_ui.(paramName), value * 100);
            else
                setParamUI(H_ui.(paramName), value);
            end
        end
        recomputeAndPlot();
    end

    function createLabel(grid, row, col, textValue, fontStyle)
        if nargin < 5
            fontStyle = "normal";
        end
        if strcmpi(fontStyle, "italic")
            lbl = uilabel(grid, "Text", textValue, "FontAngle", "italic");
        else
            lbl = uilabel(grid, "Text", textValue, "FontWeight", fontStyle);
        end
        lbl.Layout.Row = row;
        lbl.Layout.Column = col;
    end

    function val = getMapValue(mapObj, key)
        if isKey(mapObj, char(key))
            val = mapObj(char(key));
        else
            val = 0;
        end
    end

    function credits = getTeamCredits(teamName)
        credits = getMapValue(TeamBankMap, teamName) + getMapValue(TeamBonusMap, teamName) - getMapValue(TeamMalusMap, teamName);
    end

    function updateCoach(msg)
        if isempty(coach.Value)
            coach.Value = msg;
        else
            coach.Value = [coach.Value; msg];
        end
    end

    function val = clamp(val, minVal, maxVal)
        val = min(max(val, minVal), maxVal);
    end

    function result = safeDiv(a, b)
        if b == 0
            result = 1;
        else
            result = a / b;
        end
    end

    function state = onOff(flag)
        if flag
            state = "on";
        else
            state = "off";
        end
    end
end
