% Polls config/queue.json and keeps config/lega.mat + config/lega.json in sync.
% Run from the FantaManager root: matlab -batch "watchLeague" (or run interactively).
configDir = fullfile(fileparts(mfilename('fullpath')), 'config');
queuePath = string(fullfile(configDir, 'queue.json'));
statePath = string(fullfile(configDir, 'lega.mat'));
jsonPath = string(fullfile(configDir, 'lega.json'));

fprintf('FantaManager: watching %s (Ctrl+C per fermare)\n', queuePath);
while true
    src.app.processQueue(queuePath, statePath, jsonPath);
    pause(2);
end
