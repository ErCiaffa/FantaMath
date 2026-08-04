function mod = roleMod(roleTokens, roleOverride)
%ROLEMOD Per-player additive role modifier for assembleWeight (2026-08-03/04 decision).
%
% mod = roleMod(roleTokens, roleOverride) computes, for each player i:
%   mod_i = max over r in roleTokens{i} of ( roleOverride.(r) - 1 )
%
% Unlike roleFactor.m (which multiplies ScarNorm(r) * override(r) -- scarcity always in the
% loop), this is the DIRECT manual modifier the league owner types in the Ruoli page, with
% scarcity/ScarNorm excluded entirely: an override of 1.20 means +20% (mod=0.20), regardless
% of that role's ScarNorm. A player eligible for multiple roles gets the best (MAX) of their
% roles' mods, same "pick your best role" principle as roleFactor's own MAX.
%
% Blocking validation (same policy as roleFactor.m, FORM-10): a role token absent from
% roleOverride's fields, or an empty role list for a player, throws
% FantaMath:data:unrecognizedRole.
    arguments
        roleTokens (:,1) cell
        roleOverride (1,1) struct
    end

    n = numel(roleTokens);
    mod = zeros(n, 1);

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
            if ~isfield(roleOverride, char(tok))
                rowUnrecognized = true;
                badTokens(end+1, 1) = tok; %#ok<AGROW>
                continue
            end
            candidate = roleOverride.(char(tok)) - 1.0;
            if candidate > best
                best = candidate;
            end
        end

        if rowUnrecognized
            badPlayers(i) = true;
            continue
        end

        mod(i) = best;
    end

    if any(badPlayers)
        error('FantaMath:data:unrecognizedRole', ...
            'Ruolo non riconosciuto o mancante per %d giocatori: %s. Correggi il listone e ricarica.', ...
            nnz(badPlayers), strjoin(unique(badTokens), ', '));
    end
end
