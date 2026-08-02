function setActiveLeagueSlug(configDir, slug)
%SETACTIVELEAGUESLUG Write config/active.json, making slug the active league.
    arguments
        configDir (1,1) string {mustBeNonzeroLengthText}
        slug (1,1) string {mustBeNonzeroLengthText}
    end
    if ~isfolder(configDir)
        mkdir(configDir);
    end
    fid = fopen(fullfile(configDir, "active.json"), 'w');
    fwrite(fid, jsonencode(struct('activeLeague', slug)), 'char');
    fclose(fid);
end
