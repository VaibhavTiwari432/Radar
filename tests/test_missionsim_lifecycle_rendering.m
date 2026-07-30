classdef test_missionsim_lifecycle_rendering < matlab.unittest.TestCase
%TEST_MISSIONSIM_LIFECYCLE_RENDERING  Mission Simulator build order Step 6:
%   track lifecycle rendering.
%
%   Acceptance criterion (verbatim): "COASTING opacity decreases
%   monotonically with consecutive misses; the miss counter matches the
%   tracker's internal count exactly."

    methods (Test)

        function test_coasting_opacity_decreases_monotonically(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            baseFrame = struct('frame', 1, 't', 0, 'phase', "ENGINE_ACTIVE", ...
                'radar', struct('identity', struct( ...
                    'fs', struct('value', 3.2e6, 'unit', 'Hz', 'provenance', "DERIVED"), ...
                    'priUs', struct('value', 20.0, 'unit', 'us', 'provenance', "DERIVED"), ...
                    'rangeCellM', struct('value', 46.9, 'unit', 'm', 'provenance', "DERIVED"), ...
                    'unambigRangeM', struct('value', 3000.0, 'unit', 'm', 'provenance', "DERIVED"))));

            opacities = zeros(1, app.DELETION_THRESHOLD_MISSES);
            for missCount = 1:app.DELETION_THRESHOLD_MISSES
                f = baseFrame;
                f.radar.tracks = struct('id', "T01", 'state', "COASTING", 'ageFrames', 5+missCount, ...
                    'hits', 4, 'misses', missCount, 'eccmVerdict', "UNSCREENED", 'rangeEst', 1500);
                app.loadFrame(f);
                opacities(missCount) = app.TrackMarkerOpacities("T01");

                % Miss counter must match the tracker's internal count EXACTLY.
                tc.verifyEqual(app.TrackTable.Data{1,5}, sprintf('%d/%d to deletion', missCount, app.DELETION_THRESHOLD_MISSES));
            end

            fprintf('opacities across increasing miss streak: %s\n', mat2str(opacities, 4));
            tc.verifyTrue(all(diff(opacities) < 0), ...
                'Opacity must decrease monotonically as consecutive misses increase.');
            tc.verifyEqual(opacities(1), 1 - 1/app.DELETION_THRESHOLD_MISSES, 'AbsTol', 1e-9);
        end

        function test_confirmed_track_full_opacity_deleted_track_not_rendered(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            f.frame = 1; f.t = 0; f.phase = "ENGINE_ACTIVE";
            f.radar.identity.fs = struct('value', 3.2e6, 'unit', 'Hz', 'provenance', "DERIVED");
            f.radar.identity.priUs = struct('value', 20.0, 'unit', 'us', 'provenance', "DERIVED");
            f.radar.identity.rangeCellM = struct('value', 46.9, 'unit', 'm', 'provenance', "DERIVED");
            f.radar.identity.unambigRangeM = struct('value', 3000.0, 'unit', 'm', 'provenance', "DERIVED");
            f.radar.tracks = [ ...
                struct('id', "T01", 'state', "CONFIRMED", 'ageFrames', 8, 'hits', 8, ...
                       'misses', 0, 'eccmVerdict', "REAL", 'rangeEst', 1500), ...
                struct('id', "T02", 'state', "DELETED", 'ageFrames', NaN, 'hits', NaN, ...
                       'misses', NaN, 'eccmVerdict', "UNSCREENED", 'rangeEst', NaN)];

            app.loadFrame(f);

            tc.verifyEqual(app.TrackMarkerOpacities("T01"), 1.0);
            deletedMarker = findobj(app.SceneAxes, 'DisplayName', 'T02 (DELETED)');
            tc.verifyEmpty(deletedMarker, 'A DELETED track must not be rendered in the 3D view.');
        end

    end

end
