classdef tReleaseTaxTest < matlab.unittest.TestCase
    methods (Test)
        function decisionaleUsesTaxDecisionaleRate(testCase)
            params = struct('taxEstero', 0, 'taxDecisionale', 0.15, 'taxPlusvalenza', 0.10, ...
                'taxMinusvalenza', 0.15, 'taxFee', 0);
            out = src.engine.releaseTax(100, 100, false, params);
            testCase.verifyEqual(out.AliquotaValore, 0.15);
            testCase.verifyEqual(out.TassaValore, 15, 'AbsTol', 1e-9);
            testCase.verifyEqual(out.IncassoNetto, 85, 'AbsTol', 1e-9);
        end

        function obbligatorioUsesTaxEsteroRate(testCase)
            params = struct('taxEstero', 0.05, 'taxDecisionale', 0.15, 'taxPlusvalenza', 0.10, ...
                'taxMinusvalenza', 0.15, 'taxFee', 0);
            out = src.engine.releaseTax(100, 100, true, params);
            testCase.verifyEqual(out.AliquotaValore, 0.05);
        end

        function plusvalenzaTaxedAndMinusvalenzaRecovered(testCase)
            params = struct('taxEstero', 0, 'taxDecisionale', 0, 'taxPlusvalenza', 0.10, ...
                'taxMinusvalenza', 0.15, 'taxFee', 0);
            gain = src.engine.releaseTax(100, 50, false, params);
            testCase.verifyEqual(gain.Plusvalenza, 50, 'AbsTol', 1e-9);
            testCase.verifyEqual(gain.IncassoNetto, 95, 'AbsTol', 1e-9);

            loss = src.engine.releaseTax(40, 150, false, params);
            testCase.verifyEqual(loss.Minusvalenza, 110, 'AbsTol', 1e-9);
            testCase.verifyEqual(loss.IncassoNetto, 40 + 0.15*110, 'AbsTol', 1e-9);
        end

        function stateScoresHasIncassoNettoDecisionaleColumn(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);
            testCase.verifyTrue(ismember('incassoNettoDecisionale', state.scores.Properties.VariableNames));
        end

        function setTaxParamsRecomputesAndPersists(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);
            before = state.scores.incassoNettoDecisionale;
            state = src.state.LeagueState.setTaxParams(state, 0.05, 0.25, 0.2, 0.2, 1.0);
            testCase.verifyEqual(state.params.taxDecisionale, 0.25);
            testCase.verifyFalse(isequal(before, state.scores.incassoNettoDecisionale));
        end
    end
end
