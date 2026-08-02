classdef tProcessQueueTest < matlab.unittest.TestCase
    methods (Test)
        function createLeagueEntryAppliesAndExportsJson(testCase)
            work = testCase.createWorkDir();
            csvFile = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'listone_min.csv');

            queue = {struct('id', "a1", 'type', "createLeague", 'status', "pending", ...
                'payload', struct('csvPath', string(csvFile), 'epsilon', 0.05, ...
                    'credits', [struct('teamName', "LAMINCHIADURA", 'value', 500); ...
                                struct('teamName', "Eintracht Piangoforte", 'value', 480)]))};
            testCase.writeQueue(work.queuePath, queue);

            src.app.processQueue(work.queuePath, work.statePath, work.jsonPath);

            testCase.verifyTrue(isfile(work.statePath));
            testCase.verifyTrue(isfile(work.jsonPath));

            resultQueue = jsondecode(fileread(work.queuePath));
            testCase.verifyEqual(string(resultQueue.status), "applied");

            state = src.state.LeagueState.loadState(work.statePath);
            testCase.verifyEqual(height(state.teams.table), 2);
        end

        function unknownTeamBonusMalusEntryIsMarkedFailed(testCase)
            work = testCase.createWorkDir();
            state = src.state.LeagueState.empty();
            src.state.LeagueState.saveState(state, work.statePath);
            src.io.exportLegaJson(state, work.jsonPath);

            queue = {struct('id', "b1", 'type', "applyBonusMalus", 'status', "pending", ...
                'payload', struct('teamName', "Fantasma", 'amount', 10, 'motivo', "test"))};
            testCase.writeQueue(work.queuePath, queue);

            src.app.processQueue(work.queuePath, work.statePath, work.jsonPath);

            resultQueue = jsondecode(fileread(work.queuePath));
            testCase.verifyEqual(string(resultQueue.status), "failed");
            testCase.verifyNotEmpty(char(resultQueue.error));
        end

        function missingQueueFileStillExportsCurrentState(testCase)
            work = testCase.createWorkDir();
            src.app.processQueue(work.queuePath, work.statePath, work.jsonPath);
            testCase.verifyTrue(isfile(work.statePath));
            testCase.verifyTrue(isfile(work.jsonPath));
        end
    end

    methods
        function work = createWorkDir(testCase)
            folder = string(fullfile(tempdir, "tProcessQueueTest_" + char(matlab.lang.makeValidName(datestr(now, 30)))));
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            work = struct('queuePath', fullfile(folder, "queue.json"), ...
                'statePath', fullfile(folder, "lega.mat"), ...
                'jsonPath', fullfile(folder, "lega.json"));
        end

        function writeQueue(~, queuePath, entries)
            fid = fopen(queuePath, 'w');
            fwrite(fid, jsonencode(entries), 'char');
            fclose(fid);
        end
    end
end
