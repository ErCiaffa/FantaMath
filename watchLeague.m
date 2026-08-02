% Polls the ACTIVE league's queue.json and keeps its lega.mat + lega.json in sync. The
% active league (config/active.json) is re-read every tick, so switching league from the
% web UI takes effect on the next poll without restarting this script.
% Run from the FantaManager root: matlab -batch "watchLeague" (or run interactively).
configDir = string(fullfile(fileparts(mfilename('fullpath')), 'config'));

fprintf('FantaManager: watching leagues under %s (Ctrl+C per fermare)\n', configDir);
while true
    slug = src.app.activeLeagueSlug(configDir);
    leagueDir = fullfile(configDir, 'leagues', slug);
    queuePath = string(fullfile(leagueDir, 'queue.json'));
    statePath = string(fullfile(leagueDir, 'lega.mat'));
    jsonPath = string(fullfile(leagueDir, 'lega.json'));

    try
        src.app.processQueue(queuePath, statePath, jsonPath);
    catch ME
        % Never let one broken league (e.g. stale schema) kill the poller for every other
        % league forever -- log and keep going, matches the "never a silent stall" intent.
        fprintf('FantaManager: errore lega "%s": %s\n', slug, ME.message);
    end
    pause(2);
end
