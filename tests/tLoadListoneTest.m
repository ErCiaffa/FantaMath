classdef tLoadListoneTest < matlab.unittest.TestCase
    methods (Test)
        function loadsAllRowsFromMinimalFixture(testCase)
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');
            players = src.io.loadListone(string(csvFile));
            testCase.verifyEqual(height(players), 4);
            testCase.verifyEqual(players.nome(1), "Martinez L.");
            testCase.verifyEqual(players.costo(1), 149);
            testCase.verifyTrue(players.owned(1));
            testCase.verifyFalse(players.owned(4));
            testCase.verifyEqual(players.roleTokens{3}, ["B"; "Ds"; "E"]);
        end

        function missingCostoOnOwnedRowThrows(testCase)
            csvFile = fullfile(tempdir, "tLoadListoneTest_missingcost.csv");
            fid = fopen(csvFile, 'w');
            fprintf(fid, '%s\n', '#;Nome;Fuori lista;Sq.;Under;R.;R.MANTRA;PGv;MV;FM;FVM/1000;QUOT.;FantaSquadra;Costo');
            fprintf(fid, '%s\n', '1;Senza Costo;;Inter;28;A;Pc;18;6,36;8,19;353;34;LAMINCHIADURA;');
            fclose(fid);
            testCase.addTeardown(@() delete(csvFile));
            testCase.verifyError(@() src.io.loadListone(string(csvFile)), 'FantaMath:data:missingCost');
        end
    end
end
