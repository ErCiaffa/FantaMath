classdef tLeagueStateTest < matlab.unittest.TestCase
    methods (Test)
        function emptyStateHasZeroRowsEverywhere(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyEqual(height(state.players), 0);
            testCase.verifyEqual(height(state.teams.table), 0);
            testCase.verifyEqual(height(state.teams.transactions), 0);
            testCase.verifyEqual(state.teams.released, zeros(0, 1));
            testCase.verifyTrue(isnan(state.epsilon));
        end

        function saveAndLoadRoundTripsState(testCase)
            state = src.state.LeagueState.empty();
            state.epsilon = 0.05;
            tmpFile = fullfile(tempdir, "tLeagueStateTest_roundtrip.mat");
            testCase.addTeardown(@() delete(tmpFile));

            src.state.LeagueState.saveState(state, string(tmpFile));
            loaded = src.state.LeagueState.loadState(string(tmpFile));

            testCase.verifyEqual(loaded.epsilon, 0.05);
            testCase.verifyEqual(height(loaded.players), 0);
        end

        function loadStateThrowsWhenFileMissing(testCase)
            missingPath = fullfile(tempdir, "tLeagueStateTest_does_not_exist.mat");
            testCase.verifyError(@() src.state.LeagueState.loadState(string(missingPath)), ...
                'FantaManager:state:notFound');
        end
    end
end
