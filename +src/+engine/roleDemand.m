function [demand, moduleTable] = roleDemand(Sq)
%ROLEDEMAND FORM-03 (step 3, demand side): per-role demand D_r derived from league tactics.
%
% [demand, moduleTable] = roleDemand(Sq) computes D_r, the per-role demand consumed by
% src.engine.roleScarcity, as the average across 11 standard Mantra-system tactical modules
% (assumption A6, a domain constant fixed by the planner, not a tarable formula parameter) of
% each module's per-role slot demand, scaled by Sq (number of teams in the league).
%
% Attribution rule: a slot admitting n tokens contributes 1/n to the demand of each of those
% n tokens, so a single module's total demand sums to exactly 11 (11 starting-XI slots)
% before averaging across modules or scaling by Sq. No slot in this table admits more than 2
% tokens, so every share is 1 or 0.5 and all arithmetic below is exact in double precision
% (no 1/3-style rounding).
%
% demand is a containers.Map (char token -> double) with an entry for every one of the 12
% Mantra whitelist tokens (A, B, C, Dc, Dd, Ds, E, M, Pc, Por, T, W); zero-valued entries are
% included so downstream consumers (roleScarcity) never have to special-case a missing key.
%
% moduleTable is a table with one row per module (Modulo, NSlots, DemandSum, Slots),
% inspectable by tests and by a future UI exposure of the module list; it is independent of
% Sq (a structural description of the 10 modules themselves).
    arguments
        Sq (1,1) double {mustBePositive, mustBeInteger}
    end

    whitelist = mantraRoleWhitelist();
    modules = buildMantraModules();
    nModules = numel(modules);
    nRoles = numel(whitelist);

    demandMatrix = zeros(nModules, nRoles);
    for m = 1:nModules
        slots = modules(m).slots;
        for s = 1:numel(slots)
            tokens = slots{s};
            share = 1 / numel(tokens);
            for t = 1:numel(tokens)
                idx = find(whitelist == tokens(t), 1);
                demandMatrix(m, idx) = demandMatrix(m, idx) + share;
            end
        end
    end

    avgDemand = mean(demandMatrix, 1) * Sq;
    demand = containers.Map(cellstr(whitelist), num2cell(avgDemand));

    moduleNames = strings(nModules, 1);
    nSlots = zeros(nModules, 1);
    demandSum = zeros(nModules, 1);
    slotsCell = cell(nModules, 1);
    for m = 1:nModules
        moduleNames(m) = modules(m).name;
        nSlots(m) = numel(modules(m).slots);
        demandSum(m) = sum(demandMatrix(m, :));
        slotsCell{m} = modules(m).slots;
    end
    moduleTable = table(moduleNames, nSlots, demandSum, slotsCell, ...
        'VariableNames', {'Modulo', 'NSlots', 'DemandSum', 'Slots'});
end

function w = mantraRoleWhitelist()
    w = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
end

function modules = buildMantraModules()
    % MANTRA_MODULES (assumption A6, LOCK): 11 standard Mantra-system tactical modules, each
    % 11 slots, per the league's own module reference table. Defense: Dc = centrale, Dd =
    % terzino destro, Ds = terzino sinistro, B = braccetto (the wide centre-back in a
    % three-man defense, dual-eligible Dc/B in every back-three scheme -- NOT "seconda
    % punta"; back-four schemes use plain Ds/Dd instead). Midfield: M = mediano puro,
    % C = centrale, E = esterno, W = ala, T = trequartista, with dual/triple-eligibility
    % slots where the scheme leaves a genuine choice (M/C in the middle, E/W or W/T on the
    % flanks, C/T or T/A/Pc where a scheme blends roles). Attack: Pc = punta centrale,
    % A = attaccante, with dual-eligibility A/Pc in strike partnerships and W/A on the
    % offensive flanks of a front three.
    modules = [ ...
        moduleEntry('3-4-3',   { "Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "C", "E", "E", ["W", "A"], ["W", "A"], ["A", "Pc"] }), ...
        moduleEntry('3-4-1-2', { "Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "C", "E", "E", "T", ["A", "Pc"], ["A", "Pc"] }), ...
        moduleEntry('3-5-2',   { "Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "C", "M", "E", ["E", "W"], ["A", "Pc"], ["A", "Pc"] }), ...
        moduleEntry('3-4-2-1', { "Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "M", "E", ["E", "W"], "T", ["T", "A"], ["A", "Pc"] }), ...
        moduleEntry('3-5-1-1', { "Por", "Dc", "Dc", ["Dc", "B"], "M", "C", "M", ["E", "W"], ["E", "W"], ["T", "A"], ["A", "Pc"] }), ...
        moduleEntry('4-3-3',   { "Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "C", "M", ["W", "A"], ["W", "A"], ["A", "Pc"] }), ...
        moduleEntry('4-3-1-2', { "Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "C", "M", "T", ["T", "A", "Pc"], ["A", "Pc"] }), ...
        moduleEntry('4-4-2',   { "Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "C", "E", ["E", "W"], ["A", "Pc"], ["A", "Pc"] }), ...
        moduleEntry('4-2-3-1', { "Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "M", "T", ["W", "T"], ["W", "A"], ["A", "Pc"] }), ...
        moduleEntry('4-4-1-1', { "Por", "Dc", "Dc", "Ds", "Dd", "C", "M", ["E", "W"], ["E", "W"], ["T", "A"], ["A", "Pc"] }), ...
        moduleEntry('4-1-4-1', { "Por", "Dc", "Dc", "Ds", "Dd", "M", ["C", "T"], ["E", "W"], "T", "W", ["A", "Pc"] }) ...
    ];
end

function s = moduleEntry(name, slots)
    arguments
        name (1,1) string
        slots (1,11) cell
    end
    s = struct('name', name, 'slots', {slots});
end
