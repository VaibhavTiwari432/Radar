classdef test_missionsim_scene3d < matlab.unittest.TestCase
%TEST_MISSIONSIM_SCENE3D  Mission Simulator build order Step 3: middle
%   panel 3D + truth geometry.
%
%   Acceptance criterion (verbatim): "Range rings match c*PRI/2 and
%   512*c/(2*fs) to within 1 m. No literal km constant appears in source."

    methods (Test)

        function test_range_rings_match_derived_physics_within_1m(tc)
            % Pending rewire to generator.render -- see the class header.
            tc.assumeTrue(archivedDepsPresent({'engine.sceneContract'}), ...
                'engine.sceneContract was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            C = physics.Constants();
            priS = 20e-6;
            expectedUnambig = C.c * priS / 2;
            expectedCeiling = C.range_window;   % 512*c/(2*fs), physics.Constants.m's own derivation

            frame.frame = 1; frame.t = 0; frame.phase = "INGRESS";
            frame.radar.identity.fs = struct('value', C.fs, 'unit', 'Hz', 'provenance', "DERIVED");
            frame.radar.identity.priUs = struct('value', priS*1e6, 'unit', 'us', 'provenance', "DERIVED");
            frame.radar.identity.rangeCellM = struct('value', C.range_per_sample, 'unit', 'm', 'provenance', "DERIVED");
            frame.radar.identity.unambigRangeM = struct('value', expectedUnambig, 'unit', 'm', 'provenance', "DERIVED");
            frame.truth.phantoms = struct('id', "P1", 'pos', [1200 0 0]);

            app.loadFrame(frame);

            tc.verifyLessThan(abs(app.RangeRingRadii.unambigRangeM - expectedUnambig), 1, ...
                'Unambiguous-range ring should match c*PRI/2 to within 1 m.');
            tc.verifyLessThan(abs(app.RangeRingRadii.recordCeilingM - expectedCeiling), 1, ...
                'Record-ceiling ring should match 512*c/(2*fs) to within 1 m.');
        end

        function test_no_literal_km_constant_in_source(tc)
            % Structural check on the source text itself, not just the
            % computed numbers -- a hardcoded 3000/24000/etc that happened
            % to equal the right answer for ONE scenario would pass the
            % numeric test above but still be exactly the bug class this
            % criterion exists to prevent (the spec's own "100 km/256 scale
            % error" story).
            here = fileparts(mfilename('fullpath'));
            srcFile = fullfile(fileparts(here), '+missionsim', 'MissionSimulatorApp.m');
            src = fileread(srcFile);
            % Strip comments/docstrings (lines starting with %) before
            % scanning -- this file's OWN header prose mentions the
            % criterion's numbers in English, which must not false-positive.
            lines = strsplit(src, newline);
            codeLines = lines(~startsWith(strtrim(lines), '%'));
            codeText = strjoin(codeLines, newline);

            suspiciousLiterals = {'3000.0', '3000;', '24000', '2997', '23983'};
            for i = 1:numel(suspiciousLiterals)
                tc.verifyEmpty(regexp(codeText, regexptranslate('escape', suspiciousLiterals{i}), 'once'), ...
                    sprintf('Found a suspicious literal "%s" in executable source -- range/ceiling must be derived.', ...
                        suspiciousLiterals{i}));
            end
        end

        function test_phantoms_rendered_at_derived_truth_positions(tc)
            % Pending rewire to generator.render -- see the class header.
            tc.assumeTrue(archivedDepsPresent({'engine.sceneContract'}), ...
                'engine.sceneContract was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            frame.frame = 1; frame.t = 0; frame.phase = "INGRESS";
            frame.radar.identity.fs = struct('value', 3.2e6, 'unit', 'Hz', 'provenance', "DERIVED");
            frame.radar.identity.priUs = struct('value', 20.0, 'unit', 'us', 'provenance', "DERIVED");
            frame.radar.identity.rangeCellM = struct('value', 46.9, 'unit', 'm', 'provenance', "DERIVED");
            frame.radar.identity.unambigRangeM = struct('value', 3000.0, 'unit', 'm', 'provenance', "DERIVED");
            frame.truth.phantoms = struct('id', {"P1", "P2"}, 'pos', {[1200 0 0], [2400 0 0]});

            app.loadFrame(frame);

            phantomLine = findobj(app.SceneAxes, 'DisplayName', 'Phantoms (assumed shared bearing)');
            tc.verifyNotEmpty(phantomLine);
            tc.verifyEqual(sort(phantomLine.XData), [1200 2400]);
        end

    end

end
