function rf = roleFactor(roleTokens, scarcity, params)
%ROLEFACTOR FORM-04: multi-role RoleFactor (MAX), per-role override, duttilita bonus.
%
% rf = roleFactor(roleTokens, scarcity, params) computes, for each player i:
%   RoleFactor_i = max over r in roleTokens{i} of ( scarcity.ScarNorm(r) * params.roleOverride.(r) )
%   nRoli_i      = numel(roleTokens{i})
%   Flex_i       = 1                          if nRoli_i <= 1
%                = 1 + params.duttilita2       if 1 < nRoli_i < params.nmax
%                = 1 + params.duttilita3       if nRoli_i >= params.nmax
%     (2026-08-03: direct lookup table, editable params, replaced the earlier log-based
%     formula -- which wrongly gave every single-role player a nonzero Flex bonus)
%   PesoRuolo_i  = RoleFactor_i .^ params.rho .* Flex_i
%
% The per-role override multiplies scarcity.ScarNorm(r) BEFORE the MAX is taken (assumption
% A8, LOCK) -- a non-max role's override can make it become the new max.
%
% Blocking validation (FORM-10 edge case, no neutral-factor fallback): a role token absent
% from scarcity.ScarNorm's keys, or an empty role list for a player, throws
% FantaMath:data:unrecognizedRole -- the same identifier already used by src.io.loadListone.
    arguments
        roleTokens (:,1) cell
        scarcity (1,1) struct
        params (1,1) struct
    end

    n = numel(roleTokens);
    RoleFactor = zeros(n, 1);
    Flex = zeros(n, 1);

    badPlayers = false(n, 1);
    badTokens = strings(0, 1);

    for i = 1:n
        tokens = string(roleTokens{i});
        tokens = tokens(strlength(tokens) > 0);

        if isempty(tokens)
            badPlayers(i) = true;
            continue
        end

        best = -Inf;
        rowUnrecognized = false;
        for t = 1:numel(tokens)
            tok = tokens(t);
            if ~isKey(scarcity.ScarNorm, char(tok))
                rowUnrecognized = true;
                badTokens(end+1, 1) = tok; %#ok<AGROW>
                continue
            end
            overrideVal = 1.0;
            if isfield(params.roleOverride, char(tok))
                overrideVal = params.roleOverride.(char(tok));
            end
            candidate = scarcity.ScarNorm(char(tok)) * overrideVal;
            if candidate > best
                best = candidate;
            end
        end

        if rowUnrecognized
            badPlayers(i) = true;
            continue
        end

        RoleFactor(i) = best;

        nRoli = numel(tokens);
        if nRoli <= 1
            Flex(i) = 1.0;
        elseif nRoli < params.nmax
            Flex(i) = 1.0 + params.duttilita2;
        else
            Flex(i) = 1.0 + params.duttilita3;
        end
    end

    if any(badPlayers)
        error('FantaMath:data:unrecognizedRole', ...
            'Ruolo non riconosciuto o mancante per %d giocatori: %s. Correggi il listone e ricarica.', ...
            nnz(badPlayers), strjoin(unique(badTokens), ', '));
    end

    PesoRuolo = RoleFactor .^ params.rho .* Flex;

    rf = struct();
    rf.RoleFactor = RoleFactor;
    rf.Flex = Flex;
    rf.PesoRuolo = PesoRuolo;
end
