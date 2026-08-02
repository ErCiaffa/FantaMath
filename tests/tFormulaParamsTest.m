classdef tFormulaParamsTest < matlab.unittest.TestCase
    methods (Test)
        function emptyStateHasDefaultParamsAndEmptyScores(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyEqual(state.params.phi, 0.5);
            testCase.verifyEqual(state.params.alphaF, 0.0005);
            testCase.verifyEqual(state.params.alphaQ, 0.0005);
            testCase.verifyEqual(state.params.pLow, 0);
            testCase.verifyEqual(state.params.pHigh, 1);
            testCase.verifyEqual(height(state.scores), 0);
        end

        function createFromCsvComputesScoresForEveryPlayer(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyEqual(height(state.scores), height(state.players));
            testCase.verifyTrue(all(state.scores.score >= 0 & state.scores.score <= 1));
        end

        function setFormulaParamsPhiOneMakesScoreEqualFScore(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            state = src.state.LeagueState.setFormulaParams(state, 1, 0.0005, 0.0005, 0, 1);

            testCase.verifyEqual(state.scores.score, state.scores.fScore, 'AbsTol', 1e-12);
        end

        function setFormulaParamsRejectsOutOfRangePhi(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyError(@() src.state.LeagueState.setFormulaParams(state, 1.5, 0.0005, 0.0005, 0, 1), ...
                'MATLAB:validators:mustBeInRange');
        end

        function setFormulaParamsRejectsPLowNotLessThanPHigh(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyError(@() src.state.LeagueState.setFormulaParams(state, 0.5, 0.0005, 0.0005, 0.9, 0.1), ...
                'FantaManager:formula:invalidPercentileRange');
        end
    end
end
