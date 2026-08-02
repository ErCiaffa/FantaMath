classdef tActiveLeagueTest < matlab.unittest.TestCase
    methods (Test)
        function defaultsToDefaultSlugWhenActiveFileMissing(testCase)
            configDir = testCase.createConfigDir();
            slug = src.app.activeLeagueSlug(configDir);
            testCase.verifyEqual(slug, "default");
            testCase.verifyTrue(isfile(fullfile(configDir, "active.json")));
        end

        function setActiveLeagueSlugPersistsAcrossReads(testCase)
            configDir = testCase.createConfigDir();
            src.app.setActiveLeagueSlug(configDir, "provini-2027");
            slug = src.app.activeLeagueSlug(configDir);
            testCase.verifyEqual(slug, "provini-2027");
        end

        function leagueSlugSanitizesFreeTextName(testCase)
            testCase.verifyEqual(src.app.leagueSlug("Provini 2027!"), "provini-2027");
            testCase.verifyEqual(src.app.leagueSlug("Lega  Vera"), "lega-vera");
        end
    end

    methods
        function configDir = createConfigDir(testCase)
            folder = string(fullfile(tempdir, "tActiveLeagueTest_" + char(matlab.lang.makeValidName(datestr(now, 30)))));
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            configDir = folder;
        end
    end
end
