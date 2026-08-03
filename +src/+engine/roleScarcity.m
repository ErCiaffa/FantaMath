function scarcity = roleScarcity(players, S, params)
%ROLESCARCITY FORM-03: role scarcity from demand/supply, dual measure (total + owned).
%
% scarcity = roleScarcity(players, S, params) computes, for each of the 12 Mantra whitelist
% tokens r:
%   Q_r_total = sum(1 + qw*S(g)) over non-"fuori lista" players g whose roleTokens include r
%   Q_r_owned = same sum, restricted to players g with owned == true
%   S_r       = mix_owned * Q_r_owned + (1 - mix_owned) * Q_r_total
%   Scar_r    = (D_r / max(1, S_r)) ^ eta, with D_r from src.engine.roleDemand(params.Sq)
%   Scar_norm_r = Scar_r / median(Scar_r over roles with nonzero demand or supply)
%
% A player covering multiple roles counts a full unit in EACH role it covers (the literal
% reading of "per ogni giocatore g che copre ruolo r" in the canonical spec).
%
% "Fuori lista" (*) players are excluded from every aggregate (assumption A2, LOCK); their
% count is returned as nFuoriListaEsclusi so the caller can surface it in the UI, never a
% silent exclusion.
%
% No rounding is applied anywhere: every value stays in double precision.
    arguments
        players table
        S (:,1) double
        params (1,1) struct
    end

    if height(players) ~= numel(S)
        error('FantaMath:data:sizeMismatch', ...
            'players (%d righe) e S (%d elementi) devono avere la stessa lunghezza.', ...
            height(players), numel(S));
    end

    whitelist = mantraRoleWhitelist();
    nRoles = numel(whitelist);

    included = ~players.fuoriLista;
    nFuoriListaEsclusi = nnz(~included);

    weight = 1 + params.qw .* S;

    QTotal = zeros(1, nRoles);
    QOwned = zeros(1, nRoles);

    includedIdx = find(included)';
    for g = includedIdx
        tokens = players.roleTokens{g};
        tokens = tokens(strlength(string(tokens)) > 0);
        for t = 1:numel(tokens)
            idx = find(whitelist == tokens(t), 1);
            if isempty(idx)
                continue % unrecognized tokens are already blocked at load time (FORM-10)
            end
            QTotal(idx) = QTotal(idx) + weight(g);
            if players.owned(g)
                QOwned(idx) = QOwned(idx) + weight(g);
            end
        end
    end

    Svec = params.mix_owned .* QOwned + (1 - params.mix_owned) .* QTotal;

    demandMap = src.engine.roleDemand(params.Sq);
    Dvec = zeros(1, nRoles);
    for i = 1:nRoles
        Dvec(i) = demandMap(char(whitelist(i)));
    end

    Scar = (Dvec ./ max(1, Svec)) .^ params.eta;

    consideredMask = (Dvec > 0) | (Svec > 0);
    if any(consideredMask)
        medScar = median(Scar(consideredMask));
    else
        medScar = 1; % degenerate: no role carries any signal, avoid a meaningless divide
    end
    if medScar == 0
        medScar = 1; % avoid Inf/NaN when the considered-roles median is itself exactly zero
    end
    ScarNorm = Scar ./ medScar;

    scarcity = struct();
    scarcity.ScarNorm = containers.Map(cellstr(whitelist), num2cell(ScarNorm));
    scarcity.Scar = containers.Map(cellstr(whitelist), num2cell(Scar));
    scarcity.supply = containers.Map(cellstr(whitelist), num2cell(Svec));
    scarcity.demand = containers.Map(cellstr(whitelist), num2cell(Dvec));
    scarcity.nFuoriListaEsclusi = nFuoriListaEsclusi;
end

function w = mantraRoleWhitelist()
    w = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
end
