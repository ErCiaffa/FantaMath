classdef tAgeWeightTest < matlab.unittest.TestCase
    methods (Test)
        function linearRampFromFloorToZeroNeverNegative(testCase)
            params = struct('etaFloor', 15, 'etaZero', 38, 'etaBonusMax', 0.10);
            ages = [10; 15; 20; 26.5; 30; 38; 45; NaN];
            w = src.engine.ageWeight(ages, params);
            % <=15 clamped at max, 20 -> 0.10*18/23, 26.5 exactly midpoint -> 0.05,
            % 30 -> 0.10*8/23, >=38 (and NaN) -> 0, never negative anywhere.
            testCase.verifyEqual(w(1), 0.10, 'AbsTol', 1e-12);
            testCase.verifyEqual(w(2), 0.10, 'AbsTol', 1e-12);
            testCase.verifyEqual(w(3), 0.10 * 18 / 23, 'AbsTol', 1e-9);
            testCase.verifyEqual(w(4), 0.05, 'AbsTol', 1e-9);
            testCase.verifyEqual(w(5), 0.10 * 8 / 23, 'AbsTol', 1e-9);
            testCase.verifyEqual(w(6), 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(w(7), 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(w(8), 0, 'AbsTol', 1e-12);
            testCase.verifyTrue(all(w >= 0));
        end

        function emptyStateHasDefaultEtaParams(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyEqual(state.params.etaFloor, 15);
            testCase.verifyEqual(state.params.etaZero, 38);
            testCase.verifyEqual(state.params.etaBonusMax, 0.10);
        end

        function setEtaParamsRecomputesEtaWeightAndPersists(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            before = state.scores.etaWeight;
            state = src.state.LeagueState.setEtaParams(state, 16, 34, 0.20);

            testCase.verifyEqual(state.params.etaFloor, 16);
            testCase.verifyEqual(state.params.etaZero, 34);
            testCase.verifyEqual(state.params.etaBonusMax, 0.20);
            testCase.verifyFalse(isequal(before, state.scores.etaWeight));
            testCase.verifyTrue(all(state.scores.etaWeight >= 0));
        end

        function setEtaParamsRejectsInvalidThresholdOrder(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyError(@() src.state.LeagueState.setEtaParams(state, 30, 25, 0.05), ...
                'FantaManager:formula:invalidAgeThresholds');
        end
    end
end
