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
