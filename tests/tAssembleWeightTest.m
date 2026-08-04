classdef tAssembleWeightTest < matlab.unittest.TestCase
    methods (Test)
        function roleModPicksBestRoleNotScarcityWeighted(testCase)
            override = struct('A', 1.20, 'B', 1.0, 'C', 1.0, 'Dc', 1.0, 'Dd', 1.0, 'Ds', 1.0, ...
                'E', 1.0, 'M', 1.0, 'Pc', 1.10, 'Por', 1.0, 'T', 1.0, 'W', 1.0);
            tokens = {{"Dc"}; {"Pc", "A"}; {"Por"}};
            mod = src.engine.roleMod(tokens, override);
            testCase.verifyEqual(mod, [0; 0.20; 0], 'AbsTol', 1e-12);
        end

        function roleModRejectsUnrecognizedToken(testCase)
            override = struct('A', 1.0);
            tokens = {{"Zz"}};
            testCase.verifyError(@() src.engine.roleMod(tokens, override), ...
                'FantaMath:data:unrecognizedRole');
        end

        function assembleWeightIsPureAdditive(testCase)
            score = [1.0; 0.5; 0.0];
            mod = [0.20; 0.0; 0.0];
            duttilita = [0.05; 0.03; 0.0];
            eta = [0.0; 0.10; 0.0];
            v = src.engine.assembleWeight(score, mod, duttilita, eta);
            testCase.verifyEqual(v, [1.0*1.25; 0.5*1.13; 0.0], 'AbsTol', 1e-12);
        end

        function stateScoresHasAssembleWeightColumn(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyTrue(ismember('assembleWeight', state.scores.Properties.VariableNames));
            testCase.verifyTrue(ismember('mod', state.scores.Properties.VariableNames));
            expected = state.scores.score .* (1 + state.scores.mod + (state.scores.flex - 1) + state.scores.etaWeight);
            testCase.verifyEqual(state.scores.assembleWeight, expected, 'AbsTol', 1e-9);
        end

        function assembleWeightChangesWhenRoleOverrideChanges(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            before = state.scores.assembleWeight;
            overrides = state.params.roleOverride;
            overrides.A = 1.3;
            state = src.state.LeagueState.setRoleOverride(state, overrides);

            testCase.verifyFalse(isequal(before, state.scores.assembleWeight));
        end
    end
end
