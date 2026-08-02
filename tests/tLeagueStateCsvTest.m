classdef tLeagueStateCsvTest < matlab.unittest.TestCase
    methods (Test)
        function createFromCsvBuildsTeamsWithValueAndCredits(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA', 'Eintracht Piangoforte'}, {500, 480});

            state = src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05);

            testCase.verifyEqual(height(state.players), 4);
            testCase.verifyEqual(state.epsilon, 0.05);
            testCase.verifyEqual(height(state.teams.table), 2);

            idxLam = find(state.teams.table.name == "LAMINCHIADURA", 1);
            testCase.verifyEqual(state.teams.table.creditiIniziali(idxLam), 500);
            testCase.verifyEqual(state.teams.table.teamValue(idxLam), 149 + 18);
        end

        function createFromCsvThrowsWhenATeamHasNoCredits(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            creditiMap = containers.Map({'LAMINCHIADURA'}, {500});
            testCase.verifyError(@() src.state.LeagueState.createFromCsv(string(csvFile), creditiMap, 0.05), ...
                'FantaManager:setup:missingCredits');
        end

        function addTeamAppendsRowThenThrowsOnDuplicate(testCase)
            state = src.state.LeagueState.empty();
            state = src.state.LeagueState.addTeam(state, "Nuova Squadra", 500);
            testCase.verifyEqual(height(state.teams.table), 1);
            testCase.verifyEqual(state.teams.table.creditiIniziali(1), 500);
            testCase.verifyTrue(isnan(state.teams.table.bankOverride(1)));

            testCase.verifyError(@() src.state.LeagueState.addTeam(state, "Nuova Squadra", 100), ...
                'FantaManager:state:teamAlreadyExists');
        end
    end
end
