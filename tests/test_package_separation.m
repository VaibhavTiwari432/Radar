classdef test_package_separation < matlab.unittest.TestCase
%TEST_PACKAGE_SEPARATION  Mission Simulator build order (MISSION_SIMULATOR_
%   UI_SPEC.md Section 9), Step 2: "Automated test fails if +synth imports
%   from +radar or vice versa."
%
%   This formalizes, as an actual automated check, a property CLAUDE.md's
%   Rule 2 (the Golden Rule) has stated in prose all along ("+synth NEVER
%   imports +radar/+track code or parameters, and vice versa" -- verified
%   true throughout this project's history, now made falsifiable rather
%   than just asserted). Scans SOURCE TEXT for package-qualified references
%   (`radar.something`, `import radar...`) rather than actually resolving
%   MATLAB's path/import semantics -- a deliberately simple, readable check
%   matching the spec's own "grep for cross-imports" enforcement language
%   (CLAUDE.md Rule 2).

    methods (Test)

        function test_synth_does_not_reference_radar_or_track(tc)
            violations = localFindCrossReferences('+synth', {'radar', 'track'});
            tc.verifyEmpty(violations, sprintf( ...
                '+synth must never reference +radar or +track (CLAUDE.md Rule 2). Found:\n%s', ...
                strjoin(violations, sprintf('\n'))));
        end

        function test_radar_does_not_reference_synth(tc)
            violations = localFindCrossReferences('+radar', {'synth'});
            tc.verifyEmpty(violations, sprintf( ...
                '+radar must never reference +synth (CLAUDE.md Rule 2). Found:\n%s', ...
                strjoin(violations, sprintf('\n'))));
        end

        function test_track_does_not_reference_synth(tc)
            violations = localFindCrossReferences('+track', {'synth'});
            tc.verifyEmpty(violations, sprintf( ...
                '+track must never reference +synth (CLAUDE.md Rule 2). Found:\n%s', ...
                strjoin(violations, sprintf('\n'))));
        end

        function test_check_itself_detects_a_planted_violation(tc)
            % Falsifiability check on the checker itself (Rule 3's own
            % spirit): prove localFindCrossReferences actually catches a
            % violation, not just that the real packages happen to be clean.
            tmpRoot = fullfile(tempdir, 'missionsim_pkgsep_selftest');
            tmpDir = fullfile(tmpRoot, '+faketest');
            if ~isfolder(tmpDir); mkdir(tmpDir); end
            fid = fopen(fullfile(tmpDir, 'badFcn.m'), 'w');
            fprintf(fid, 'function badFcn()\n    x = radar.pulseCompress([], []); %%#ok<NASGU>\nend\n');
            fclose(fid);
            cleanupObj = onCleanup(@() localTryRmdir(tmpRoot)); %#ok<NASGU>

            oldDir = cd(tmpRoot);
            cleanupCd = onCleanup(@() cd(oldDir)); %#ok<NASGU>
            violations = localFindCrossReferences('+faketest', {'radar'});
            tc.verifyNotEmpty(violations, 'The checker should have caught the planted radar.* reference.');
        end

    end

end

% ===================== file-local helpers =============================
function localTryRmdir(d)
%LOCALTRYRMDIR  Best-effort temp-dir cleanup -- a Windows file-lock/AV-scan
%   race leaving a stale OS temp folder behind is not this test's concern.
    try
        rmdir(d, 's');
    catch
    end
end

function violations = localFindCrossReferences(pkgFolder, forbiddenPkgs)
%LOCALFINDCROSSREFERENCES  Scan every .m file in pkgFolder's source text
%   for package-qualified references to any name in forbiddenPkgs
%   (`name.anything` or `import name...`), skipping comment-only lines and
%   this file's own docstrings/error-message mentions.
    violations = {};
    if ~isfolder(pkgFolder); return; end
    files = dir(fullfile(pkgFolder, '*.m'));
    for i = 1:numel(files)
        fpath = fullfile(files(i).folder, files(i).name);
        lines = strsplit(fileread(fpath), newline);
        for ln = 1:numel(lines)
            line = lines{ln};
            trimmed = strtrim(line);
            if isempty(trimmed) || startsWith(trimmed, '%')
                continue;   % skip blank / full-comment lines
            end
            % strip inline trailing comment before checking (a %-comment
            % mentioning the forbidden package, e.g. this file's own
            % docstrings, must not itself count as a violation)
            commentIdx = regexp(line, '(?<!%)%(?!%)', 'once');
            if ~isempty(commentIdx); line = line(1:commentIdx-1); end
            for j = 1:numel(forbiddenPkgs)
                pat = sprintf('(^|[^A-Za-z0-9_.])%s\\.[A-Za-z]', forbiddenPkgs{j});
                if ~isempty(regexp(line, pat, 'once'))
                    violations{end+1} = sprintf('%s:%d: %s', files(i).name, ln, trimmed); %#ok<AGROW>
                end
            end
        end
    end
end
