classdef tMixScoresTest < matlab.unittest.TestCase
    methods (Test)
        function phiOneReturnsExactlyFScore(testCase)
            f = [0.1; 0.5; 0.9; 1.0];
            q = [0.9; 0.2; 0.0; 0.3];
            S = src.engine.mixScores(f, q, 1);
            testCase.verifyEqual(S, f, 'AbsTol', 1e-12);
        end

        function phiZeroReturnsExactlyQScore(testCase)
            f = [0.1; 0.5; 0.9; 1.0];
            q = [0.9; 0.2; 0.0; 0.3];
            S = src.engine.mixScores(f, q, 0);
            testCase.verifyEqual(S, q, 'AbsTol', 1e-12);
        end

        function phiHalfReturnsArithmeticMean(testCase)
            f = [0.2; 0.6; 1.0];
            q = [0.8; 0.0; 0.4];
            S = src.engine.mixScores(f, q, 0.5);
            expected = (f + q) / 2;
            testCase.verifyEqual(S, expected, 'AbsTol', 1e-12);
        end

        function intermediatePhiStaysWithinMinMaxRange(testCase)
            f = [0.1; 0.9; 0.3; 0.7];
            q = [0.8; 0.2; 0.3; 0.5];
            for phi = [0.1, 0.25, 0.5, 0.75, 0.9]
                S = src.engine.mixScores(f, q, phi);
                testCase.verifyTrue(all(S >= min(f, q) - 1e-12));
                testCase.verifyTrue(all(S <= max(f, q) + 1e-12));
            end
        end

        function phiOutsideRangeFailsArgumentsValidation(testCase)
            f = [0.1; 0.5];
            q = [0.2; 0.4];
            testCase.verifyError(@() src.engine.mixScores(f, q, 1.5), ...
                'MATLAB:validators:mustBeInRange');
            testCase.verifyError(@() src.engine.mixScores(f, q, -0.1), ...
                'MATLAB:validators:mustBeInRange');
        end
    end
end
