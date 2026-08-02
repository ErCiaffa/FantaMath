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
    end
end
