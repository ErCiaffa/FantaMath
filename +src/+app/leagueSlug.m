function slug = leagueSlug(name)
%LEAGUESLUG Sanitize a free-text league name into a filesystem/URL-safe slug: lowercase,
% non-alphanumeric runs collapsed to a single hyphen, no leading/trailing hyphen.
    arguments
        name (1,1) string {mustBeNonzeroLengthText}
    end
    lowered = lower(strtrim(name));
    collapsed = regexprep(lowered, '[^a-z0-9]+', '-');
    slug = string(regexprep(collapsed, '^-+|-+$', ''));
    if strlength(slug) == 0
        error('FantaManager:league:invalidName', ...
            'Il nome lega "%s" non produce uno slug valido.', name);
    end
end
