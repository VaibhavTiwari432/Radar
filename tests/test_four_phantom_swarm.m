classdef test_four_phantom_swarm < matlab.unittest.TestCase
%TEST_FOUR_PHANTOM_SWARM  The mission-level question: one mother drone
%   transmitting FOUR simultaneous phantom drones -- does the real,
%   independent radar (CFAR + trackerGNN + ECCM, +radar/+track, untouched)
%   get deceived?
%
%   Every phantom reuses this project's OWN already-validated single-
%   phantom recipe (Integration_Report.md's canonical scene: drone,
%   v=-60 m/s closing, rotor micro-motion n_blades=4/rpm=3000/
%   blade_len=0.25m, intercept_noise_amplitude=2.0 -- the SAME level
%   already shown to matter, engine.decideScene.m's comment) -- RANGE
%   differs per phantom (1800/3000/4200/5400 m, 1200 m spacing) and
%   amp_scale is compensated per phantom (amp_scale_i = 3.0*(range_i/1800)^2)
%   so every phantom arrives at the receiver with the SAME power as the
%   validated single-phantom case, not the raw un-compensated gain=3 for
%   all four.
%
%   Two things verified BEFORE settling on these numbers (both by actually
%   running radar.cfarDetect on the exported rx and looking at the raw
%   per-frame bins, not assumed):
%     - Un-compensated equal amp_scale=3.0 across a 4x range span gives the
%       near phantom ~24 dB more received power than the far one (1/R^2
%       amplitude law => 1/R^4 power). That imbalance let the near
%       phantom's own range sidelobes intermittently swamp/mask weaker
%       phantoms after matched filtering -- a real near-far masking
%       effect, not a code bug; compensating amp_scale per range removes
%       the confound so this test measures deception, not a self-inflicted
%       SNR-imbalance artifact.
%     - An earlier draft closing a near phantom from 1200 m for 8 frames at
%       -60 m/s drove it inside radar.cfarDetect's own documented edge
%       blind zone (cells within NumTraining+NumGuard, ~1124 m, of the
%       buffer's start are never testable -- a pre-existing Stage-1
%       limitation, unrelated to this test). Starting no closer than
%       1800 m keeps every phantom inside the testable window for the
%       whole 8-frame engagement.
%
%   Golden Rule (CLAUDE.md Rule 2): reports BOTH the twin's own prediction
%   (radar_twin.predict, the engine's imagination) and the real MATLAB
%   judge's actual verdict (engine.runJudge) -- never just one.
%
%   This test does not assert a specific deception outcome (Rule 5: the
%   outcome is the open empirical question, not something to bake into a
%   pass/fail); it asserts the Feedback is structurally sane and prints
%   the measured numbers.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_four_phantom_swarm_vs_real_judge(tc)
            C = physics.Constants(); %#ok<NASGU>

            radarState = engine.sceneContract().radarState;

            ranges = [1800.0, 3000.0, 4200.0, 5400.0];
            refRange = 1800.0; refGain = 3.0;   % this project's validated single-phantom level
            phantoms = repmat(engine.sceneContract().phantom, 1, numel(ranges));
            for i = 1:numel(ranges)
                phantoms(i).range_m = ranges(i);
                phantoms(i).radial_vel_mps = -60.0;
                phantoms(i).accel_mps2 = 0.0;
                phantoms(i).rcs_dbsm = 0.0;
                phantoms(i).swerling = 0;
                phantoms(i).amp_scale = refGain * (ranges(i) / refRange)^2;  % equalize received power
                phantoms(i).micro = struct('type', "rotor", 'n_blades', 4, ...
                                            'rpm', 3000.0, 'blade_len_m', 0.25);
            end

            scene = struct();
            scene.phantoms = phantoms;
            scene.maneuver = "swarm";
            scene.eirp_budget_dbw = 20.0;
            scene.t0_s = 0.0;
            scene.duration_s = 8.0;   % TwinConfig default: num_frames(8) * frame_interval_s(1.0)

            scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
            rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));

            % ---- 1. The engine's own imagination (twin), for comparison only ----
            twinRng = py.numpy.random.default_rng(int64(40001));
            twinFeedback = py.cogengine.radar_twin.predict(scenePy, rsPy, twinConfig, twinRng);
            twinConfirmed = double(twinFeedback.confirmed_tracks);
            twinSurviving = double(twinFeedback.false_tracks_surviving);
            twinFlagged = double(twinFeedback.flagged_decoys);

            % ---- 2. The REAL, independent judge -- the only number that counts ----
            here = fileparts(mfilename('fullpath'));
            tmpMat = fullfile(here, '_tmp_four_phantom_swarm.mat');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>

            renderRng = py.numpy.random.default_rng(int64(40002));
            degradedEvents = py.cogengine.matlab_judge.export_scene_for_judge( ...
                scenePy, rsPy, twinConfig, renderRng, tmpMat);

            feedback = engine.runJudge(tmpMat);

            fprintf('\n=== Mother drone, 4 simultaneous phantoms (ranges %s m) ===\n', ...
                mat2str(ranges));
            fprintf('TWIN  (imagination):  confirmed=%d surviving_real=%d flagged_decoy=%d\n', ...
                twinConfirmed, twinSurviving, twinFlagged);
            fprintf('JUDGE (real, independent): confirmed=%d surviving_real=%d flagged_decoy=%d degraded_events=%d\n', ...
                feedback.confirmed_tracks, feedback.false_tracks_surviving, ...
                feedback.flagged_decoys, numel(degradedEvents));
            fprintf('JUDGE per-track labels: %s\n', strjoin(string(feedback.track_label), ', '));
            lastRanges = nan(1, numel(feedback.track_range_m));
            for i = 1:numel(feedback.track_range_m)
                r = feedback.track_range_m{i};
                if ~isempty(r)
                    lastRanges(i) = r(end);
                    fprintf('  track %d: label=%s last_range_est_m=%.1f\n', ...
                        i, feedback.track_label{i}, r(end));
                end
            end

            % De-duplicate by physical position for an honest headline count:
            % trackerGNN's own AssignmentThreshold=200 (widened for single-
            % target closing rates, +track/runTracker.m) occasionally lets
            % the SAME physical phantom accumulate a second, later-initiating
            % TrackID alongside its original one when several targets are in
            % flight simultaneously (observed this run: 3 of 4 phantoms each
            % produced 2 confirmed TrackIDs landing within one CFAR range bin
            % of each other by the final frame). Confirmed real by tracing
            % the per-frame TrackID history directly -- not a masking/
            % detection failure (every phantom WAS tracked continuously),
            % and it does not change any track's real/decoy label. Left as a
            % documented caveat/future-work item (multi-target
            % AssignmentThreshold tuning is its own investigation) rather
            % than tuned away here; de-duplicating in THIS report keeps the
            % headline "how many phantoms actually survived" honest without
            % touching the judge's tuning.
            distinctRanges = [];
            for r = lastRanges(~isnan(lastRanges))
                if isempty(distinctRanges) || all(abs(distinctRanges - r) > 3 * C.range_per_sample)
                    distinctRanges(end+1) = r; %#ok<AGROW>
                end
            end
            fprintf(['Distinct physical phantoms represented among confirmed tracks: ' ...
                '%d (of %d transmitted)\n'], numel(distinctRanges), numel(ranges));

            tc.verifyGreaterThanOrEqual(feedback.confirmed_tracks, 0);
            tc.verifyTrue(all(ismember(string(feedback.track_label), ["real", "decoy", "unscreened"])));
        end

    end

end

% ===================== file-local helpers =============================
function tf = localPythonReady()
    try
        py.importlib.import_module('cogengine');
        tf = true;
    catch
        tf = false;
    end
end

function localDeleteIfExists(f)
    if isfile(f); delete(f); end
end
