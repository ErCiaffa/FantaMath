classdef tRoleParamsTest < matlab.unittest.TestCase
    methods (Test)
        function emptyStateHasDefaultRoleParams(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyEqual(state.params.qw, 1);
            testCase.verifyEqual(state.params.mixOwned, 1);
            testCase.verifyEqual(state.params.eta, 1);
            testCase.verifyEqual(state.params.nmax, 3);
            testCase.verifyEqual(state.params.beta, 0.2);
            testCase.verifyEqual(state.params.rho, 1);
            testCase.verifyTrue(isstruct(state.params.roleOverride));
        end

        function createFromCsvComputesRoleFactorForEveryPlayer(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyEqual(height(state.scores), height(state.players));
            testCase.verifyTrue(all(state.scores.roleFactor >= 0));
            testCase.verifyTrue(all(state.scores.pesoRuolo >= 0));
        end

        function setRoleParamsRecomputesRoleFactor(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            before = state.scores.pesoRuolo;
            state = src.state.LeagueState.setRoleParams(state, 2, 1, 2, 3, 0.5, 1);

            testCase.verifyEqual(state.params.qw, 2);
            testCase.verifyEqual(state.params.eta, 2);
            testCase.verifyEqual(state.params.nmax, 3);
            testCase.verifyEqual(state.params.beta, 0.5);
            testCase.verifyFalse(isequal(before, state.scores.pesoRuolo));
        end

        function setRoleOverrideRecomputesPesoRuoloAndPersists(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            before = state.scores.pesoRuolo;
            overrides = state.params.roleOverride;
            overrides.A = 1.3;
            state = src.state.LeagueState.setRoleOverride(state, overrides);

            testCase.verifyEqual(state.params.roleOverride.A, 1.3);
            testCase.verifyFalse(isequal(before, state.scores.pesoRuolo));
        end

        function setRoleOverrideRejectsMissingRole(testCase)
            state = src.state.LeagueState.empty();
            overrides = rmfield(state.params.roleOverride, 'A');
            testCase.verifyError(@() src.state.LeagueState.setRoleOverride(state, overrides), ...
                'FantaManager:formula:missingRoleOverride');
        end

        function roleSuggestionIsLiveNotHardcoded(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyTrue(isstruct(state.roleSuggestion));
            tokens = ["A", "B", "C", "Dc", "Dd", "Ds", "E", "M", "Pc", "Por", "T", "W"];
            recommended = zeros(1, numel(tokens));
            for i = 1:numel(tokens)
                tok = char(tokens(i));
                testCase.verifyTrue(isfield(state.roleSuggestion, tok));
                recommended(i) = state.roleSuggestion.(tok).recommended;
                % min-max onto [1.00, 1.20] (owner's explicit cap, 2026-08-03).
                testCase.verifyGreaterThanOrEqual(recommended(i), 1.0);
                testCase.verifyLessThanOrEqual(recommended(i), 1.2);
            end
            % "ogni ruolo proprio mod" -- individual per-role values, not shared tiers.
            testCase.verifyGreaterThan(numel(unique(round(recommended, 6))), 1);
            % The role with the smallest owned-vs-free FVM gap lands exactly at the 1.00 floor.
            testCase.verifyEqual(min(recommended), 1.0, 'AbsTol', 1e-9);

            % Changing qw changes ScarNorm (supply weighting), which must flow through into
            % a DIFFERENT roleSuggestion -- proving the suggestion is computed live from the
            % current scarcity, not a fixed snapshot baked in ahead of time.
            before = state.roleSuggestion;
            state2 = src.state.LeagueState.setRoleParams(state, 5, 1, 1, 3, 0.2, 1);
            testCase.verifyFalse(isequaln(before, state2.roleSuggestion));
        end

        function setRoleOverrideRejectsNonPositiveValue(testCase)
            state = src.state.LeagueState.empty();
            overrides = state.params.roleOverride;
            overrides.A = 0;
            testCase.verifyError(@() src.state.LeagueState.setRoleOverride(state, overrides), ...
                'FantaManager:formula:invalidRoleOverride');
        end
    end
end
