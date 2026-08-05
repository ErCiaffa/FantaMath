classdef tAuctionPriceTest < matlab.unittest.TestCase
    methods (Test)
        function creditsSumToBudgetOverOwnedOnly(testCase)
            % Floor set to 0 here so no value gets clamped -- clamping is intentionally
            % allowed to break the exact sum (see floorAppliesEvenToZeroWeight), tested
            % separately.
            weight = [1.0; 0.5; 0.2; 0.0];
            owned = [true; true; false; true];
            budget = 100;
            credito = src.engine.auctionPrice(weight, owned, budget, 0.5, 4.5, 0.0);
            testCase.verifyEqual(sum(credito(owned)), budget, 'AbsTol', 1e-9);
        end

        function floorAppliesEvenToZeroWeight(testCase)
            weight = [1.0; 0.0];
            owned = [true; true];
            credito = src.engine.auctionPrice(weight, owned, 50, 0.5, 4.5, 2.0);
            testCase.verifyGreaterThanOrEqual(credito(2), 2.0);
        end

        function higherWeightAlwaysMeansHigherOrEqualCredit(testCase)
            weight = [0.9; 0.5; 0.1];
            owned = [true; true; true];
            credito = src.engine.auctionPrice(weight, owned, 100, 0.52, 4.5, 1.0);
            testCase.verifyTrue(credito(1) >= credito(2));
            testCase.verifyTrue(credito(2) >= credito(3));
        end

        function stateScoresHasCreditoStimatoColumn(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyTrue(ismember('creditoStimato', state.scores.Properties.VariableNames));
            ownedMask = state.players.owned;
            % 2026-08-04: the invariant moved from gross to NET -- "se tutti svincolano
            % tutti abbiamo W*" (owner's explicit request), i.e. the post-tax total (not
            % the pre-tax creditoStimato) must equal the league budget. Gross is inflated
            % by the bisection in recomputeScores to compensate for the average tax bite.
            % 2026-08-05: W* now subtracts banca residua (bankOverride/creditiIniziali +
            % bonus/malus ledger, always additive) -- cash already sitting in bank isn't
            % also counted in the player-value pool, or a bonus given to one team would
            % inflate league-wide player values without ever reducing the pool it came
            % from (owner's explicit request, see docs/decisioni-e-logica.md).
            totalBudget = sum(state.teams.table.creditiIniziali) * (1 + state.epsilon) ...
                - sum(src.state.LeagueState.bankResiduoVector(state));
            testCase.verifyEqual(sum(state.scores.incassoNettoDecisionale(ownedMask)), totalBudget, 'AbsTol', max(1, totalBudget) * 0.01);
        end

        function setAuctionParamsRecomputesAndPersists(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});
            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            before = state.scores.creditoStimato;
            state = src.state.LeagueState.setAuctionParams(state, 1.0, 3.0, 2.0);

            testCase.verifyEqual(state.params.auctionOffsetC, 1.0);
            testCase.verifyEqual(state.params.auctionExpK, 3.0);
            testCase.verifyEqual(state.params.auctionFloor, 2.0);
            testCase.verifyFalse(isequal(before, state.scores.creditoStimato));
        end
    end
end
