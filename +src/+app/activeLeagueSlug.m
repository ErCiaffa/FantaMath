function slug = activeLeagueSlug(configDir)
%ACTIVELEAGUESLUG Read config/active.json's activeLeague slug, defaulting to and persisting
% "default" the first time (no active.json yet means this is a brand-new install).
    arguments
        configDir (1,1) string {mustBeNonzeroLengthText}
    end
    activeFile = fullfile(configDir, "active.json");
    if ~isfile(activeFile)
        slug = "default";
        src.app.setActiveLeagueSlug(configDir, slug);
        return
    end
    raw = jsondecode(fileread(activeFile));
    slug = string(raw.activeLeague);
end
