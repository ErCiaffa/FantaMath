classdef tMergePlayersTest < matlab.unittest.TestCase
    methods (Test)
        function mergeAppliesAllFourOutcomes(testCase)
            fixturesDir = fullfile(fileparts(mfilename('fullpath')), 'fixtures');
            oldPlayers = src.io.loadListone(string(fullfile(fixturesDir, 'listone_merge_old.csv')));
            newPlayers = src.io.loadListone(string(fullfile(fixturesDir, 'listone_merge_new.csv')));

            merged = src.io.mergePlayers(oldPlayers, newPlayers);

            testCase.verifyEqual(height(merged), 5);

            idxChiesa = find(merged.nome == "Chiesa", 1);
            testCase.verifyTrue(merged.fuoriLista(idxChiesa));
            testCase.verifyEqual(merged.costo(idxChiesa), 18);

            idxYildiz = find(merged.nome == "Yildiz", 1);
            testCase.verifyFalse(isempty(idxYildiz));
            testCase.verifyEqual(merged.costo(idxYildiz), 22);

            idxMartinez = find(merged.nome == "Martinez L.", 1);
            testCase.verifyEqual(merged.costo(idxMartinez), 149);
            testCase.verifyEqual(merged.fvm(idxMartinez), 360);

            idxPulisic = find(merged.nome == "Pulisic", 1);
            testCase.verifyEqual(merged.costo(idxPulisic), 112);

            idxMcTominay = find(merged.nome == "McTominay", 1);
            testCase.verifyEqual(merged.costo(idxMcTominay), 76);
            testCase.verifyEqual(merged.team(idxMcTominay), "LAMINCHIADURA");
        end

        function mergeAgainstEmptyOldReturnsNewUnchanged(testCase)
            fixturesDir = fullfile(fileparts(mfilename('fullpath')), 'fixtures');
            newPlayers = src.io.loadListone(string(fullfile(fixturesDir, 'listone_merge_new.csv')));
            emptyOld = newPlayers([], :);

            merged = src.io.mergePlayers(emptyOld, newPlayers);

            testCase.verifyEqual(height(merged), height(newPlayers));
        end
    end
end
