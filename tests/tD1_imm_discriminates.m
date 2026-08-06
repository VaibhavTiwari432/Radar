classdef tD1_imm_discriminates < matlab.unittest.TestCase
%TD1_IMM_DISCRIMINATES  Proves the byte-identical CV/IMM/CA result
%   (BENCHMARK_RESULTS.md, "Tracker model" generalization sweep) is FIXED:
%   track.discriminator now reads the tracker's own IMM mode-probability
%   history (screen 2b, +track/getFilterState.m / +track/runTracker.m's
%   modeProbHistory / +engine/runJudge.m's modeProbSeq threading), so
%   swapping FilterModel cv<->imm on the SAME scene can change the verdict.
%
%   Scene: one genuine CV target (no commanded acceleration -- only the
%   VEE's own small process noise) and one VEE phantom WALKED with a
%   commanded, per-frame ALTERNATING acceleration -- a physically valid
%   (F-matrix-integrated) but implausibly fast "flutter" maneuver no real
%   aircraft holds, and exactly the kind of thing screen 2b's stated
%   [ASSUMED] threshold exists to catch. Both objects are rendered only
%   through engine.entity.render/propagate (not touched by this task); the
%   commanded acceleration uses the entity's own documented "carried and
%   commandable" Rddot (CLAUDE.md's VEE section), not a modification to
%   +engine/+entity itself.

    properties (Constant)
        CARRIER  = 10e9
        N_FAST   = 400
        N_PULSES = 32
        N_FRAMES = 14
        FRAME_DT = 1.0
        GENUINE_R0 = 3800
        PHANTOM_R0 = 1800
        BASE_V   = -30    % m/s, both objects -- safely inside v_ua (~60 m/s)
                          % even with the phantom's commanded swings.
        ACCEL_MPS2 = 8.0  % [ASSUMED test parameter] flutter magnitude
        SEED = 42
    end

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_cv_and_imm_runs_disagree_on_the_maneuvering_phantom(tc)
            cube = tc.buildScene();
            C = physics.Constants();

            f = [tempname '.mat'];
            S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', 12e-6, ...
                'bandwidth_hz', 2e6, 'prf_hz', C.PRF, 'frame_interval_s', tc.FRAME_DT, ...
                'carrier_hz', tc.CARRIER);
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>

            screens = {'amplitude', 'doppler', 'maneuver'};
            fbCV  = engine.runJudge(f, 'FilterModel', 'cv',  'EccmScreens', screens);
            fbIMM = engine.runJudge(f, 'FilterModel', 'imm', 'EccmScreens', screens);

            tc.assertGreaterThanOrEqual(fbCV.confirmed_tracks,  2, 'Fixture failed to confirm both objects (CV run).');
            tc.assertGreaterThanOrEqual(fbIMM.confirmed_tracks, 2, 'Fixture failed to confirm both objects (IMM run).');

            [phCV,  genCV]  = tc.splitByRange(fbCV);
            [phIMM, genIMM] = tc.splitByRange(fbIMM);

            fprintf(['\n[tD1] phantom  (maneuvering): CV score %.4f (%s)  vs  IMM score %.4f (%s)\n' ...
                       '[tD1] genuine  (CV-only)    : CV score %.4f (%s)  vs  IMM score %.4f (%s)\n'], ...
                tc.score(phCV),  phCV.label,  tc.score(phIMM),  phIMM.label, ...
                tc.score(genCV), genCV.label, tc.score(genIMM), genIMM.label);

            % ---- the headline assertion: CV and IMM must not be identical ----
            scoresIdentical = (tc.score(phCV) == tc.score(phIMM)) && (tc.score(genCV) == tc.score(genIMM));
            labelsIdentical = strcmp(phCV.label, phIMM.label) && strcmp(genCV.label, genIMM.label);
            tc.verifyFalse(scoresIdentical && labelsIdentical, ...
                ['CV and IMM runs produced IDENTICAL verdicts and scores -- the ' ...
                 'byte-identical bug this task exists to fix is still present.']);

            % ---- no regression on the false-alarm side ----
            tc.verifyEqual(genCV.label,  'real', 'Genuine target flagged decoy under CV -- regression.');
            tc.verifyEqual(genIMM.label, 'real', 'Genuine target flagged decoy under IMM -- regression.');

            % ---- the maneuvering phantom's score should MOVE under IMM: the
            % new screen has data to act on now that it didn't have under CV.
            tc.verifyNotEqual(tc.score(phCV), tc.score(phIMM), ...
                'Phantom''s discriminator score is unchanged between CV and IMM runs.');
        end

    end

    methods (Access = private)

        function cube = buildScene(tc)
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', tc.SEED);
            q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);

            sg = engine.entity.EntityState('range_m', tc.GENUINE_R0, 'range_rate_mps', tc.BASE_V, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            sp = engine.entity.EntityState('range_m', tc.PHANTOM_R0, 'range_rate_mps', tc.BASE_V, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);

            % Per-frame alternating commanded acceleration -- a physically
            % INTEGRATED (F-matrix consistent) but implausibly fast "flutter",
            % using the entity's own commandable Rddot, not a change to
            % +engine/+entity itself.
            accelSched = tc.ACCEL_MPS2 * (-1).^(1:tc.N_FRAMES);

            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            for k = 1:tc.N_FRAMES
                cg = engine.entity.render(sg, 'AmpScale', 3.0, 'NumPulses', tc.N_PULSES, ...
                        'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, 'PrfHz', C.PRF, ...
                        'RandStream', rs);
                cp = engine.entity.render(sp, 'AmpScale', 3.0, 'NumPulses', tc.N_PULSES, ...
                        'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, 'PrfHz', C.PRF, ...
                        'RandStream', rs);
                nz = 0.05 * (randn(rs, tc.N_FAST, tc.N_PULSES) + ...
                        1i * randn(rs, tc.N_FAST, tc.N_PULSES)) / sqrt(2);
                cube(:, :, k) = cg + cp + nz;

                sg = engine.entity.propagate(sg, tc.FRAME_DT, q, rs);
                sp.range_accel_mps2 = accelSched(k);   % command the flutter
                sp = engine.entity.propagate(sp, tc.FRAME_DT, q, rs);
            end
        end

        function [ph, gen] = splitByRange(tc, fb)
        %SPLITBYRANGE  Attribute each confirmed track to phantom/genuine by
        %   nearest declared R0 -- same nearest-match attribution
        %   +experiments/benchmarkSuite.m's oneTrial/attribute already uses.
            ph = struct('label', '', 'confidence', NaN);
            gen = struct('label', '', 'confidence', NaN);
            for i = 1:fb.confirmed_tracks
                r0 = fb.track_range_m{i}(1);
                if abs(r0 - tc.PHANTOM_R0) < abs(r0 - tc.GENUINE_R0)
                    ph.label = fb.track_label{i};
                    ph.confidence = fb.track_confidence(i);
                else
                    gen.label = fb.track_label{i};
                    gen.confidence = fb.track_confidence(i);
                end
            end
        end

        function s = score(~, t)
        %SCORE  Recover track.discriminator's mean-screen score from its
        %   label + confidence output (confidence = abs(score-0.5)*2).
            if strcmp(t.label, 'real')
                s = 0.5 + t.confidence / 2;
            else
                s = 0.5 - t.confidence / 2;
            end
        end
    end
end
