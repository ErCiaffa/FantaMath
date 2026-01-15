classdef FantaDirector < handle
    % FANTA DIRECTOR PRO (All-In-One Edition)
    % Unico file che contiene: Interfaccia, Algoritmo, Grafica e Gestione Dati.
    
    properties
        % --- DATI ---
        T_full table          % Tabella completa giocatori
        TeamBanks containers.Map % Mappa Soldi Iniziali Squadre (Editabile)
        TeamActs containers.Map  % Mappa Azioni Svincolo (Keep/Cut)
        
        % --- CONFIGURAZIONE (SETTINGS) ---
        S struct
        Locks struct
        
        % --- INTERFACCIA (UI HANDLES) ---
        Fig matlab.ui.Figure
        H struct % Struttura per tutti i controlli (slider, tabelle, assi)
    end
    
    methods
        function obj = FantaDirector(csvFile)
            % COSTRUTTORE: Avvio App
            if nargin<1, csvFile=""; end
            
            % 1. Inizializza Parametri
            obj.initSettings();
            
            % 2. Carica Dati (con Smart Mapper)
            obj.loadData(csvFile);
            
            % 3. Costruisci Interfaccia
            obj.buildInterface();
            
            % 4. Primo Calcolo
            obj.updateWstar(); 
        end
        
        %% ================================================================
        %  SEZIONE 1: DATI E PARAMETRI (Nessuna logica persa qui!)
        %  ================================================================
        function initSettings(obj)
            s = struct();
            % LEGA
            s.C_max = 500; s.epsilon = 0.15; s.Wstar = 1000;
            % CORE ALGO
            s.phi = 75; s.gamma = 1.00; s.mu = 3.00; s.k = 0.90; s.boostP = 1.1; 
            s.alphaF = 0.02; % Log factor
            % SOGLIE
            s.pLowF = 0.15; s.pHighF = 0.995;
            % TASSE
            s.GrossDec = 0.30; s.GrossOb = 0.05; s.PlusTax = 0.00;
            % RUOLI CLASSIC
            s.wr_P=1.1; s.wr_D=1.0; s.wr_C=1.0; s.wr_A=1.4;
            % RUOLI MANTRA
            s.wm_P=1.1; s.wm_Dd=0.95; s.wm_Ds=0.95; s.wm_Dc=1.0; s.wm_B=1.0;
            s.wm_E=0.9; s.wm_M=0.9; s.wm_C=1.0; s.wm_W=1.1; 
            s.wm_T=1.25; s.wm_A=1.15; s.wm_Pc=1.4;
            
            obj.S = s;
            
            % Locks per il Tuner
            l = struct();
            l.gamma=false; l.mu=false; l.phi=false; l.boostP=false;
            obj.Locks = l;
            
            obj.TeamBanks = containers.Map();
            obj.TeamActs = containers.Map();
        end
        
        function loadData(obj, csvFile)
            % Caricamento dati robusto
            try
                if isempty(csvFile)
                    files = dir('*.csv');
                    if ~isempty(files), csvFile = files(1).name; else, csvFile=""; end
                end
                
                if isfile(csvFile)
                    opts = detectImportOptions(csvFile);
                    opts.VariableNamingRule = 'preserve';
                    T_raw = readtable(csvFile, opts);
                    obj.T_full = obj.mapColumns(T_raw);
                else
                    obj.T_full = obj.generateFakeData();
                end
                
                % Pulizia
                obj.T_full.FantaSquadra = string(obj.T_full.FantaSquadra);
                mask = ~ismissing(obj.T_full.FantaSquadra) & obj.T_full.FantaSquadra ~= "" & obj.T_full.FantaSquadra ~= "-";
                obj.T_full = obj.T_full(mask & ~isnan(obj.T_full.FVM), :);
                
                % Init Banche Squadre
                tms = unique(obj.T_full.FantaSquadra);
                for i=1:numel(tms)
                    k = char(tms(i));
                    if ~isKey(obj.TeamBanks, k), obj.TeamBanks(k) = 0; end
                end
                
            catch err
                errordlg("Errore caricamento dati: " + err.message, "Critical Error");
            end
        end
        
        function T_out = mapColumns(~, T_in)
            % Smart Mapper: Cerca le colonne con vari nomi possibili
            map.ID = ["#", "ID", "Id"];
            map.Nome = ["Nome", "Name", "Giocatore"];
            map.FantaSquadra = ["FantaSquadra", "Sq.", "Team", "Squadra"];
            map.R_ = ["R.", "Ruolo", "R"];
            map.FVM = ["FVM/1000", "FVM", "Quotazione", "Fvm"];
            map.QUOT = ["QUOT.", "QUOT", "Quot", "Q"];
            map.Costo = ["Costo", "Prezzo", "Pagato"];
            
            T_out = table();
            cols = T_in.Properties.VariableNames;
            fields = fieldnames(map);
            
            for i=1:numel(fields)
                f = fields{i};
                candidates = map.(f);
                found = false;
                for c = candidates
                    if any(strcmp(c, cols))
                        raw = T_in.(c);
                        if iscell(raw) || isstring(raw)
                            % Pulisci numeri con virgola se necessario
                            if ~strcmp(f,'Nome') && ~strcmp(f,'FantaSquadra') && ~strcmp(f,'R_')
                                raw = str2double(strrep(string(raw),',','.'));
                            end
                        end
                        T_out.(f) = raw;
                        found = true;
                        break;
                    end
                end
                if ~found
                    if strcmp(f, 'Costo') || strcmp(f, 'QUOT')
                        T_out.(f) = zeros(height(T_in), 1); % Default 0 se manca opzionale
                    else
                        error("Colonna mancante nel CSV: " + f + ". Controlla il file.");
                    end
                end
            end
        end

        %% ================================================================
        %  SEZIONE 2: INTERFACCIA (LAYOUT + WIDGETS)
        %  ================================================================
        function buildInterface(obj)
            obj.Fig = uifigure("Name", "FantaDirector Pro", "Color", [0.95 0.95 0.97]);
            obj.Fig.WindowState = 'maximized';
            
            g = uigridlayout(obj.Fig, [2 3]);
            g.RowHeight = {50, '1x'};
            g.ColumnWidth = {420, '1x', 480}; 
            g.Padding = [10 10 10 10]; g.ColumnSpacing = 15;
            
            % --- HEADER ---
            pH = uipanel(g, "BackgroundColor","white", "BorderType","none");
            pH.Layout.Column = [1 3];
            gh = uigridlayout(pH, [1 3]); gh.ColumnWidth = {150, '1x', 150};
            
            bSave = uibutton(gh, "Text","💾 SALVA", "FontWeight","bold", "ButtonPushedFcn", @(~,~) obj.saveState());
            bSave.Layout.Column=1;
            
            lTit = uilabel(gh, "Text","FANTA DIRECTOR", "FontSize",22, "FontWeight","bold", "FontColor",[0 0.3 0.6], "HorizontalAlignment","center");
            lTit.Layout.Column=2;
            
            bLoad = uibutton(gh, "Text","📂 CARICA", "FontWeight","bold", "ButtonPushedFcn", @(~,~) obj.loadState());
            bLoad.Layout.Column=3;
            
            % --- COLONNA SX: TUNER ---
            pL = uipanel(g, "Title","🎛️ CONFIGURAZIONE", "BackgroundColor","white", "FontWeight","bold");
            pL.Layout.Row=2; pL.Layout.Column=1;
            gL = uigridlayout(pL, [2 1]); gL.RowHeight={'1x', 160};
            
            tabs = uitabgroup(gL);
            
            % Tab 1: Core Params
            t1 = uitab(tabs, "Title", "Core");
            gc = uigridlayout(t1, [8 1]); gc.RowHeight=repmat({50},1,8); gc.Scrollable='on';
            obj.addCtrl(gc, "Gamma (Esponente)", "gamma", 0.5, 3.0, "%.2f");
            obj.addCtrl(gc, "Mu (Pavimento)", "mu", 0.0, 10.0, "%.2f");
            obj.addCtrl(gc, "Phi (Peso FVM %)", "phi", 0, 100, "%.0f");
            obj.addCtrl(gc, "Boost Curve", "boostP", 0.5, 2.0, "%.2f");
            
            % Tab 2: Lega
            t2 = uitab(tabs, "Title", "Lega & Tasse");
            gl = uigridlayout(t2, [8 2]); gl.RowHeight=repmat({35},1,8);
            obj.addInp(gl,1,"Budget Iniziale","C_max", @obj.updateWstar);
            obj.addInp(gl,2,"Margine % (Eps)","epsilon", @obj.updateWstar);
            obj.addInfo(gl,3,"Somma Casse","lblBank");
            obj.addInfo(gl,4,"W* POOL","lblWstar", [0 0.5 0]);
            obj.addInp(gl,5,"Tassa Volontaria (0-1)","GrossDec", @obj.recalc);
            obj.addInp(gl,6,"Tassa Obbligata (0-1)","GrossOb", @obj.recalc);
            
            % Auto-Tuner Panel
            pT = uipanel(gL, "Title","Auto-Pilot", "BackgroundColor",[0.92 0.95 1]);
            gt = uigridlayout(pT, [4 2]);
            bt = uibutton(gt, "Text","⚡ CALIBRA", "BackgroundColor",[0 0.4 0.8], "FontColor","white", "FontWeight","bold", "ButtonPushedFcn", @(~,~) obj.runAutoTune());
            bt.Layout.Row=1; bt.Layout.Column=[1 2];
            uilabel(gt,"Text","Target Top:").Layout.Row=2; obj.H.tgtTop = uieditfield(gt,"numeric","Value",180); obj.H.tgtTop.Layout.Row=2; obj.H.tgtTop.Layout.Column=2;
            
            % --- COLONNA CENTRO: ANALYTICS ---
            pM = uipanel(g, "Title","📊 DATI & GRAFICI", "BackgroundColor","white", "FontWeight","bold");
            pM.Layout.Row=2; pM.Layout.Column=2;
            gm = uigridlayout(pM, [2 1]); gm.RowHeight={90, '1x'};
            
            % KPI Cards
            pk = uigridlayout(gm, [1 3]);
            obj.addCard(pk, 1, "TOP PLAYER", "kpiTop", [0 .6 0]);
            obj.addCard(pk, 2, "HEAD RATIO", "kpiHead", [0 .4 .8]);
            obj.addCard(pk, 3, "LOW COST %", "kpiLow", [.8 0 0]);
            
            % Tabs Visuali
            tg = uitabgroup(gm);
            
            % Tab Riepilogo Squadre
            tt = uitab(tg, "Title", "Riepilogo Squadre");
            gtt = uigridlayout(tt, [1 1]);
            obj.H.tblTeams = uitable(gtt, "ColumnSortable",true, "RowStriping","on", "FontSize",11);
            obj.H.tblTeams.ColumnEditable = [false false false true false]; % Cassa Editabile
            obj.H.tblTeams.CellEditCallback = @obj.onBankEdit;
            
            % Tab Scatter
            ts = uitab(tg, "Title", "Scatter");
            gts = uigridlayout(ts, [1 1]);
            obj.H.axScat = uiaxes(gts, "Box","on", "XGrid","on", "YGrid","on");
            
            % Tab Distribuzione
            td = uitab(tg, "Title", "Distribuzione");
            gtd = uigridlayout(td, [1 1]);
            obj.H.axDist = uiaxes(gtd, "Box","on", "XGrid","on", "YGrid","on");
            
            % Tab Heatmap
            th = uitab(tg, "Title", "Heatmap");
            gth = uigridlayout(th, [1 1]);
            obj.H.pHeat = uipanel(gth, "BorderType","none", "BackgroundColor","white");
            
            % --- COLONNA DX: GESTIONE ---
            pR = uipanel(g, "Title","⚽ TEAM LAB (SVINCOLI)", "BackgroundColor","white", "FontWeight","bold");
            pR.Layout.Row=2; pR.Layout.Column=3;
            gr = uigridlayout(pR, [4 1]); gr.RowHeight={40, 60, '1x', 140};
            
            % Selector
            gs = uigridlayout(gr, [1 2]); gs.ColumnWidth={80,'1x'};
            uilabel(gs,"Text","Squadra:", "FontWeight","bold", "HorizontalAlignment","right").Layout.Column=1;
            obj.H.ddTeam = uidropdown(gs, "Items", ["- Seleziona -"], "ValueChangedFcn", @obj.onTeamSelect);
            obj.H.ddTeam.Layout.Column=2;
            
            % Info Rosa
            pir = uipanel(gr, "BackgroundColor",[0.96 0.96 0.96]); 
            gir = uigridlayout(pir, [2 2]);
            uilabel(gir,"Text","Spesa Iniziale:","HorizontalAlignment","right").Layout.Row=1;
            obj.H.tmCost = uilabel(gir,"Text","0","FontWeight","bold"); obj.H.tmCost.Layout.Row=1; obj.H.tmCost.Layout.Column=2;
            uilabel(gir,"Text","Valore Oggi:","HorizontalAlignment","right").Layout.Row=2;
            obj.H.tmVal = uilabel(gir,"Text","0","FontWeight","bold","FontColor","blue"); obj.H.tmVal.Layout.Row=2; obj.H.tmVal.Layout.Column=2;
            
            % Tabella Rosa (Cell Array per Dropdown)
            obj.H.tblSim = uitable(gr, "ColumnSortable",true, "FontSize",11);
            obj.H.tblSim.ColumnName = {'Nome','R','Pagato','Valore','Tassa','Netto','Azione'};
            obj.H.tblSim.ColumnEditable = [false false false false false false true];
            obj.H.tblSim.ColumnWidth = {'1x', 30, 50, 50, 40, 50, 110};
            obj.H.tblSim.CellEditCallback = @obj.onActionChange;
            
            % Bilancio Svincoli
            ps = uipanel(gr, "Title","Bilancio", "BackgroundColor",[0.9 1 0.9]);
            gsim = uigridlayout(ps, [4 2]);
            uilabel(gsim,"Text","Cassa Iniziale:","HorizontalAlignment","right").Layout.Row=1; 
            obj.H.simBank = uilabel(gsim,"Text","0","FontWeight","bold"); obj.H.simBank.Layout.Row=1; obj.H.simBank.Layout.Column=2;
            uilabel(gsim,"Text","Incasso Netto:","HorizontalAlignment","right").Layout.Row=2;
            obj.H.simGain = uilabel(gsim,"Text","+0","FontWeight","bold","FontColor",[0 .5 0]); obj.H.simGain.Layout.Row=2; obj.H.simGain.Layout.Column=2;
            uilabel(gsim,"Text","BUDGET FINALE:","HorizontalAlignment","right","FontWeight","bold").Layout.Row=4;
            obj.H.simFinal = uilabel(gsim,"Text","0","FontSize",18,"FontWeight","bold"); obj.H.simFinal.Layout.Row=4; obj.H.simFinal.Layout.Column=2;
            
            % Popola Dropdown
            tms = unique(obj.T_full.FantaSquadra);
            obj.H.ddTeam.Items = ["- Seleziona -"; tms];
        end
        
        %% ================================================================
        %  SEZIONE 3: LOGICA CORE (ALGORITMO)
        %  ================================================================
        function [V, Score] = runAlgo(obj)
            P = obj.S; T = obj.T_full;
            fvm = T.FVM;
            
            % 1. Normalizzazione
            logF = log(1 + P.alphaF * fvm);
            minL=min(logF); maxL=max(logF);
            if maxL==minL, Fnorm=zeros(size(fvm)); else, Fnorm=(logF-minL)./(maxL-minL); end
            
            % 2. Pesi Ruolo
            RMult = ones(height(T),1);
            r = string(T.R_);
            RMult(r=="P")=P.wr_P; RMult(r=="D")=P.wr_D; 
            RMult(r=="C")=P.wr_C; RMult(r=="A")=P.wr_A;
            
            % 3. Score Base
            if all(T.QUOT==0), Q=zeros(size(fvm)); else, Q=T.QUOT/100; end
            Score = (P.phi/100 * Fnorm + (1-P.phi/100) * Q) .* RMult;
            
            % 4. Curva & Distribuzione
            ScorePow = Score .^ P.gamma;
            Base = 1 + P.mu .* (ScorePow ./ (ScorePow + P.k));
            
            Pool = max(0, P.Wstar - sum(Base));
            sumW = sum(ScorePow);
            
            if sumW > 0
                V = Base + Pool .* (ScorePow ./ sumW);
            else
                V = Base;
            end
            
            V = round(V);
            V(V<1) = 1;
        end
        
        function updateWstar(obj)
            obj.S.C_max = obj.H.C_max.Value;
            obj.S.epsilon = obj.H.epsilon.Value;
            
            % Calcola somma casse dalla Mappa
            vals = values(obj.TeamBanks);
            bankSum = sum([vals{:}]);
            
            w = (obj.S.C_max * (1 + obj.S.epsilon)) - bankSum;
            obj.S.Wstar = max(500, round(w));
            
            obj.H.lblWstar.Text = string(obj.S.Wstar) + " 💰";
            obj.H.lblBank.Text = string(bankSum);
            
            obj.recalc();
        end
        
        function recalc(obj)
            [V, Score] = obj.runAlgo();
            
            % Update KPI
            top = max(V);
            low = mean(V<=1)*100;
            p90 = sort(V,'descend'); p90=p90(ceil(numel(V)*0.1));
            head = top/max(1,p90);
            
            obj.H.kpiTop.Text = string(round(top));
            obj.H.kpiHead.Text = sprintf("%.2f", head);
            obj.H.kpiLow.Text = sprintf("%.1f%%", low);
            
            % Update Scatter
            ax = obj.H.axScat; cla(ax);
            scatter(ax, Score, V, 25, 'filled', 'MarkerFaceAlpha',0.5);
            grid(ax,'on'); title(ax,"Score vs Valore");
            
            % Update Distribuzione
            ax2 = obj.H.axDist; cla(ax2);
            histogram(ax2, V, 50, 'FaceColor',[.2 .4 .8], 'EdgeColor','none');
            grid(ax2,'on'); title(ax2,"Distribuzione");
            xline(ax2, mean(V), 'r--', 'LineWidth', 2);
            
            % Update Heatmap
            delete(obj.H.pHeat.Children);
            try
                edges = [1 5 10 20 50 100 500];
                lbls = {'1-5','5-10','10-20','20-50','50-100','100+'};
                pc = discretize(V, edges, 'categorical', lbls);
                hData = table(obj.T_full.R_, pc, 'VariableNames',{'Ruolo','Fascia'});
                heatmap(obj.H.pHeat, hData, 'Ruolo', 'Fascia', 'ColorMethod','count', 'Title','Densità');
            catch
            end
            
            % Update Riepilogo Squadre
            obj.updateTeamsSummary(V);
            
            % Update Team Lab (se attivo)
            if ~strcmp(obj.H.ddTeam.Value, "- Seleziona -")
                obj.updateTeamLab(obj.H.ddTeam.Value, V);
            end
        end
        
        function updateTeamsSummary(obj, V)
            tms = unique(obj.T_full.FantaSquadra);
            names = strings(0); speso=[]; val=[]; count=[]; cassa=[];
            
            for i=1:numel(tms)
                tm = tms(i);
                idx = obj.T_full.FantaSquadra == tm;
                names(end+1) = tm;
                speso(end+1) = sum(obj.T_full.Costo(idx));
                val(end+1) = round(sum(V(idx)));
                count(end+1) = sum(idx);
                
                k = char(tm);
                if isKey(obj.TeamBanks, k), cassa(end+1)=obj.TeamBanks(k); else, cassa(end+1)=0; end
            end
            
            residuo = floor(obj.S.C_max - speso + cassa); 
            
            T_out = table(names', speso', val', count', cassa', residuo', ...
                'VariableNames', {'Squadra','Spesi','Valore_Oggi','N_G','Cassa_Iniz','Residuo_Stim'});
            
            obj.H.tblTeams.Data = T_out;
        end
        
        function updateTeamLab(obj, tm, V)
            idx = obj.T_full.FantaSquadra == tm;
            subT = obj.T_full(idx, :);
            subV = V(idx);
            
            % Ensure Actions
            k = char(tm);
            if ~isKey(obj.TeamActs, k)
                obj.TeamActs(k) = repmat({"Keep"}, height(subT), 1);
            end
            acts = obj.TeamActs(k);
            
            gain = 0; slots = 0; 
            taxVec = zeros(height(subT),1); netVec = zeros(height(subT),1);
            
            for i=1:height(subT)
                act = acts{i};
                v = subV(i); c = subT.Costo(i);
                plus = max(0, v - c);
                
                rate = 0;
                if strcmp(act, 'Taglio (Dec)'), rate=obj.S.GrossDec;
                elseif strcmp(act, 'Taglio (Obbl)'), rate=obj.S.GrossOb; end
                
                tax = (v*rate) + (plus * obj.S.PlusTax);
                net = max(0, v - tax);
                taxVec(i)=tax; netVec(i)=net;
                
                if ~strcmp(act, 'Keep'), gain=gain+net; slots=slots+1; end
            end
            
            % Table Data (Cell Array for Dropdowns)
            D = [cellstr(subT.Nome), cellstr(subT.R_), num2cell(subT.Costo), ...
                 num2cell(round(subV)), num2cell(round(taxVec)), num2cell(round(netVec)), acts];
            
            obj.H.tblSim.Data = D;
            obj.H.tblSim.ColumnFormat = {[],[],[],[],[],[], {'Keep','Taglio (Dec)','Taglio (Obbl)'}};
            
            % KPI
            startB = 0; if isKey(obj.TeamBanks, k), startB=obj.TeamBanks(k); end
            obj.H.tmCost.Text = string(sum(subT.Costo));
            obj.H.tmVal.Text = string(round(sum(subV)));
            obj.H.simBank.Text = string(startB);
            obj.H.simGain.Text = "+" + string(round(gain));
            obj.H.simFinal.Text = string(round(startB + gain)) + " 💰";
        end
        
        %% ================================================================
        %  SEZIONE 4: CALLBACKS INTERATTIVI
        %  ================================================================
        function onBankEdit(obj, ~, evt)
            rowIdx = evt.Indices(1);
            newVal = evt.NewData;
            tmName = obj.H.tblTeams.Data.Squadra(rowIdx);
            obj.TeamBanks(char(tmName)) = newVal;
            obj.updateWstar(); % Trigger recalc totale
        end
        
        function onTeamSelect(obj, src, ~)
            tm = src.Value;
            if strcmp(tm, "- Seleziona -"), obj.H.tblSim.Data={}; return; end
            if ~isKey(obj.TeamActs, char(tm))
                mask = obj.T_full.FantaSquadra == tm;
                obj.TeamActs(char(tm)) = repmat({"Keep"}, sum(mask), 1);
            end
            obj.recalc();
        end
        
        function onActionChange(obj, ~, evt)
            tm = obj.H.ddTeam.Value;
            r = evt.Indices(1);
            acts = obj.TeamActs(char(tm));
            acts{r} = evt.NewData;
            obj.TeamActs(char(tm)) = acts;
            % Recalc solo parziale del Lab per velocità
            [V, ~] = obj.runAlgo();
            obj.updateTeamLab(tm, V);
        end
        
        function runAutoTune(obj)
            tgt = obj.H.tgtTop.Value;
            hBtn = gcbo; hBtn.Text = "⏳..."; drawnow;
            
            for k=1:20
                [V, ~] = obj.runAlgo();
                err = max(V) - tgt;
                if abs(err) < 2, break; end
                
                if ~obj.Locks.gamma
                    step = err * 0.003;
                    obj.S.gamma = max(0.5, min(3.0, obj.S.gamma + step));
                end
            end
            
            obj.H.gamma.s.Value = obj.S.gamma; obj.H.gamma.e.Value = obj.S.gamma;
            hBtn.Text = "⚡ CALIBRA";
            obj.recalc();
        end
        
        %% ================================================================
        %  SEZIONE 5: HELPERS UI
        %  ================================================================
        function addCtrl(obj, p, txt, f, minV, maxV, fmt)
            g=uigridlayout(p,[1 4]); g.ColumnWidth={30,'1x','1x',50}; g.Padding=[0 0 0 0];
            
            isL=obj.Locks.(f); ico="🔓"; if isL, ico="🔒"; end
            
            % Fix Layout: Assegnazione separata
            btn = uibutton(g, "Text",ico, "BackgroundColor",[1 1 1], "ButtonPushedFcn", @(b,~)obj.togLock(b,f));
            btn.Layout.Column=1;
            
            l = uilabel(g, "Text",txt, "FontWeight","bold"); l.Layout.Column=2;
            
            s = uislider(g, "Limits",[minV maxV], "Value",obj.S.(f), "Enable",obj.onOff(~isL), "ValueChangedFcn", @(s,~)obj.upVal(f,s.Value)); 
            s.Layout.Column=3;
            
            e = uieditfield(g, "numeric", "Value",obj.S.(f), "ValueDisplayFormat",fmt, "Enable",obj.onOff(~isL), "ValueChangedFcn", @(e,~)obj.upVal(f,e.Value)); 
            e.Layout.Column=4;
            
            obj.H.(f)=struct('s',s,'e',e);
        end
        
        function togLock(obj, b, f)
            obj.Locks.(f) = ~obj.Locks.(f);
            if obj.Locks.(f), b.Text="🔒"; else, b.Text="🔓"; end
            st = obj.onOff(~obj.Locks.(f));
            obj.H.(f).s.Enable = st; obj.H.(f).e.Enable = st;
        end
        
        function upVal(obj, f, v)
            obj.S.(f) = v;
            obj.H.(f).s.Value = v; obj.H.(f).e.Value = v;
            obj.recalc();
        end
        
        function addInp(obj, g, r, txt, f, cb)
            l = uilabel(g,"Text",txt); l.Layout.Row=r; l.Layout.Column=1;
            e = uieditfield(g,"numeric","Value",obj.S.(f),"ValueChangedFcn",@(~,~)cb()); e.Layout.Row=r; e.Layout.Column=2;
            obj.H.(f) = e;
        end
        
        function addInfo(obj, g, r, txt, tag, col)
            if nargin<6, col=[0 0 0]; end
            l = uilabel(g,"Text",txt); l.Layout.Row=r; l.Layout.Column=1;
            v = uilabel(g,"Text","-","FontWeight","bold","FontColor",col); v.Layout.Row=r; v.Layout.Column=2;
            obj.H.(tag) = v;
        end
        
        function addCard(obj, p, idx, txt, tag, col)
            pan = uipanel(p, "BackgroundColor",[1 1 1]); pan.Layout.Column=idx;
            g = uigridlayout(pan,[2 1]); g.RowSpacing=0;
            l1 = uilabel(g,"Text",txt,"HorizontalAlignment","center","FontColor",col*.5); l1.Layout.Row=1;
            l2 = uilabel(g,"Text","-","HorizontalAlignment","center","FontSize",22,"FontWeight","bold","FontColor",col); l2.Layout.Row=2;
            obj.H.(tag) = l2;
        end
        
        function s = onOff(~, val), if val, s="on"; else, s="off"; end; end
        function saveConfig(obj), uiputfile("*.mat"); end
        function loadConfig(obj), uigetfile("*.csv"); end
        
        function T = generateFakeData(obj)
            N=200; names="P"+(1:N)'; tms=repmat(["A","B","C"],1,100)';
            T=table((1:N)', names, tms(1:N), repmat("C",N,1), randi(100,N,1), randi(50,N,1), zeros(N,1),...
                'VariableNames',{'ID','Nome','FantaSquadra','R_','FVM','QUOT','Costo'});
        end
    end
end
