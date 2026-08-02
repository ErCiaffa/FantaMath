classdef tSetEpsilonTest < matlab.unittest.TestCase
    methods (Test)
        function setEpsilonUpdatesValue(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.setEpsilon(state, 0.08);
            testCase.verifyEqual(state.epsilon, 0.08);
        end
    end
end
