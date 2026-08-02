classdef tLeagueStateBankTest < matlab.unittest.TestCase
    methods (Test)
        function bankResiduoDefaultsToCreditiIniziali(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            bank = src.state.LeagueState.bankResiduoVector(state);
            testCase.verifyEqual(bank, 500);
        end

        function setBankOverrideWinsOverComputedValue(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            state = src.state.LeagueState.setBankOverride(state, "Squadra A", 340);
            bank = src.state.LeagueState.bankResiduoVector(state);
            testCase.verifyEqual(bank, 340);
        end

        function setBankOverrideOnUnknownTeamThrows(testCase)
            state = src.state.LeagueState.empty();
            testCase.verifyError(@() src.state.LeagueState.setBankOverride(state, "Fantasma", 10), ...
                'FantaManager:transaction:unknownTeam');
        end

        function applyBonusMalusAddsSignedTransactionAndShiftsBank(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            state = src.state.LeagueState.applyBonusMalus(state, "Squadra A", 20, "Premio classifica");
            state = src.state.LeagueState.applyBonusMalus(state, "Squadra A", -5, "Penalita disciplinare");

            testCase.verifyEqual(height(state.teams.transactions), 2);
            bank = src.state.LeagueState.bankResiduoVector(state);
            testCase.verifyEqual(bank, 515);
        end

        function applyBonusMalusRejectsEmptyMotivo(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            testCase.verifyError(@() src.state.LeagueState.applyBonusMalus(state, "Squadra A", 20, "   "), ...
                'FantaManager:transaction:missingMotivo');
        end
    end
end
