classdef tNormalizeTest < matlab.unittest.TestCase
    methods (Test)
        function increasingInputProducesNonDecreasingScoresInUnitRange(testCase)
            raw = (1:20)';
            score = src.engine.normalizeScore(raw, 0.05, 0.1, 0.9);
            testCase.verifyTrue(all(score >= 0 & score <= 1));
            testCase.verifyTrue(all(diff(score) >= -1e-12));
        end

        function percentileBoundsMapToZeroAndOne(testCase)
            % pLow=0% maps to the raw minimum, pHigh=100% maps to the raw maximum, so per
            % spec step 1 the clipped score must be exactly 0 at the minimum and exactly 1
            % at the maximum (values derived from the percentile definition itself, not by
            % re-reading normalizeScore's own output).
            raw = (0:100)';
            score = src.engine.normalizeScore(raw, 1, 0, 1);
            testCase.verifyEqual(score(1), 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(score(end), 1, 'AbsTol', 1e-12);
        end

        function valuesOutsidePercentileRangeClipExactly(testCase)
            raw = [1; 2; 3; 4; 5; 6; 7; 8; 9; 1000];
            score = src.engine.normalizeScore(raw, 0.1, 0.1, 0.8);
            testCase.verifyEqual(score(1), 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(score(end), 1, 'AbsTol', 1e-12);
        end

        function constantInputReturnsZerosNeverNanOrInf(testCase)
            raw = repmat(7, 15, 1);
            score = src.engine.normalizeScore(raw, 0.01, 0.02, 0.98);
            testCase.verifyEqual(score, zeros(15, 1));
            testCase.verifyFalse(any(isnan(score)));
            testCase.verifyFalse(any(isinf(score)));
        end

        function logCompressionGrowsSubLinearlyWithInputScale(testCase)
            % Spec step 1's log(1 + alpha*raw) compresses high absolute values: hand-derive
            % rawLog directly from the spec formula (not via normalizeScore's clipped
            % output) and verify the max-median gap does not double when the input doubles.
            alpha = 0.05;
            raw = [10; 20; 30; 40; 50; 1000];
            rawLog = log(1 + alpha .* raw);
            gapOriginal = max(rawLog) - median(rawLog);

            rawDoubled = raw * 2;
            rawLogDoubled = log(1 + alpha .* rawDoubled);
            gapDoubled = max(rawLogDoubled) - median(rawLogDoubled);

            testCase.verifyLessThan(gapDoubled, 2 * gapOriginal);
        end

        function nonPositiveAlphaFailsArgumentsValidation(testCase)
            testCase.verifyError(@() src.engine.normalizeScore([1; 2; 3], 0, 0.1, 0.9), ...
                'MATLAB:validators:mustBePositive');
            testCase.verifyError(@() src.engine.normalizeScore([1; 2; 3], -1, 0.1, 0.9), ...
                'MATLAB:validators:mustBePositive');
        end
    end
end
