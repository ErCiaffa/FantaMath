classdef tExportLegaJsonTest < matlab.unittest.TestCase
    methods (Test)
        function exportsReadableJsonWithExpectedShape(testCase)
            state = src.state.LeagueState.empty();
            state.epsilon = 0.05;
            state = src.state.LeagueState.addTeam(state, "Squadra A", 500);
            state = src.state.LeagueState.applyBonusMalus(state, "Squadra A", 20, "Premio classifica");

            jsonFile = fullfile(tempdir, "tExportLegaJsonTest_export.json");
            testCase.addTeardown(@() delete(jsonFile));

            src.io.exportLegaJson(state, string(jsonFile));

            testCase.verifyTrue(isfile(jsonFile));
            decoded = jsondecode(fileread(jsonFile));

            testCase.verifyEqual(decoded.epsilon, 0.05);
            testCase.verifyEqual(numel(decoded.teams.table), 1);
            testCase.verifyEqual(string(decoded.teams.table.name), "Squadra A");
            testCase.verifyEqual(numel(decoded.teams.transactions), 1);
            testCase.verifyEqual(string(decoded.teams.transactions.Motivo), "Premio classifica");
        end

        function exportsEmptyArraysForEmptyState(testCase)
            state = src.state.LeagueState.empty();
            jsonFile = fullfile(tempdir, "tExportLegaJsonTest_empty.json");
            testCase.addTeardown(@() delete(jsonFile));

            src.io.exportLegaJson(state, string(jsonFile));
            decoded = jsondecode(fileread(jsonFile));

            testCase.verifyEqual(decoded.players, []);
            testCase.verifyEqual(decoded.teams.table, []);
        end
    end
end
