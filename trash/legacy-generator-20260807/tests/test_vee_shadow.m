classdef test_vee_shadow < matlab.unittest.TestCase
%TEST_VEE_SHADOW  Virtual Entity Engine, build steps 3 and 4.
%
%   Step 3  engine.track.shadowEKF -- the engine's own estimate of the
%           radar's predict/gate/update loop, parameterised SEPARATELY from
%           +track/runTracker.m (see shadowEKF.m's comparison table).
%   Step 4  Run one calibrated entity through BOTH the shadow filter and the
%           real MATLAB judge and report the gap. Where they diverge is
%           where the engine's model of the radar is wrong; this test's job
%           is to MEASURE that, not to make it go away.
%
%   test_shadow_vs_judge_scorecard is the deliverable. It prints a four-scene
%   table (agree / diverge per scene) and asserts only the structural
%   findings, never a flattering number (CLAUDE.md Rule 5).

    properties (Constant)
        FRAME_DT = 1.0;
        PW_S     = 12e-6;
        BW_HZ    = 2e6;
        PRF_HZ   = physics.Constants().PRF;
        CARRIER  = 10e9;
        N_FRAMES = 8;
        N_PULSES = 32;
        N_FAST   = 400;
    end

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        % ===================== step 3 =====================

        function test_nis_of_a_calibrated_entity_sits_in_band(tc)
            % The mission's step-1 gate, which needs the step-3 filter to
            % evaluate: propagate 40 dwells and confirm a RadChar-calibrated
            % entity's NIS is in-band -- not pinned near zero, not outside
            % the gate.
            q = tc.calibratedQ();
            nis = [];
            for seed = 1:5
                nis = [nis; tc.shadowRun(q.sigma_accel_mps2, q, seed, 40)]; %#ok<AGROW>
            end
            fprintf(['[step3] calibrated entity, 5 seeds x 39 dwells: NIS mean %.3f  ' ...
                     'median %.3f  p95 %.3f  max %.3f  | outside 99%% gate: %.1f%%\n'], ...
                     mean(nis), median(nis), prctile(nis,95), max(nis), ...
                     100*mean(nis > 2*erfinv(0.99)^2));

            % In-band: a correctly-specified filter has E[NIS] = 1 for a
            % 1-DOF measurement. Bracket it generously -- this asserts
            % "in-band", not a tuned value.
            tc.verifyGreaterThan(mean(nis), 0.25, 'NIS is pinned near zero.');
            tc.verifyLessThan(mean(nis), 4.0, 'NIS is running hot -- the model disagrees with the entity.');
            tc.verifyLessThan(mean(nis > 2*erfinv(0.99)^2), 0.10, ...
                'More than 10% of dwells fall outside the 99% gate.');
        end

        function test_noiseless_entity_is_NOT_distinguishable_by_kinematic_nis(tc)
            % HONEST NEGATIVE RESULT, asserted so it cannot rot silently.
            %
            % The mission's premise for step 1 was that a noiseless CV target
            % has "NIS pinned near zero, which a good ECCM flags as a
            % mathematical object". At THIS radar's range resolution that
            % does not reproduce, and the reason is arithmetic: the
            % calibrated entity's per-dwell position jitter is
            % sigma_accel*dt^2/2 = 0.245 m, while a range bin's quantisation
            % standard deviation is delta/sqrt(12) = 13.5 m -- 55x larger.
            % The measurement floor swamps the process noise either way, so
            % kinematic NIS cannot tell a jittering entity from a perfectly
            % smooth one. The "too perfect" giveaway lives in AMPLITUDE
            % (+track/discriminator.m already screens dead-flat amplitude),
            % not in the kinematic filter.
            q = tc.calibratedQ();
            live = []; dead = [];
            for seed = 1:5
                live = [live; tc.shadowRun(q.sigma_accel_mps2, q, seed, 40)]; %#ok<AGROW>
                dead = [dead; tc.shadowRun(q.sigma_accel_mps2, tc.zeroQ(q), seed, 40)]; %#ok<AGROW>
            end
            C = physics.Constants();
            fprintf(['[step3] per-dwell position jitter %.3f m vs range-bin sigma %.2f m (%.0fx) -> ' ...
                     'NIS mean: calibrated %.3f | NOISELESS %.3f  (separation %.3f)\n'], ...
                     q.sigma_accel_mps2*tc.FRAME_DT^2/2, C.range_per_sample/sqrt(12), ...
                     (C.range_per_sample/sqrt(12))/(q.sigma_accel_mps2*tc.FRAME_DT^2/2), ...
                     mean(live), mean(dead), abs(mean(live)-mean(dead)));

            tc.verifyLessThan(abs(mean(live) - mean(dead)), 0.5, ...
                ['Kinematic NIS now separates a noiseless entity from a calibrated one. ' ...
                 'That is a real change -- re-derive this documented limit rather than ' ...
                 'loosening the bound.']);
        end

        function test_shadow_is_not_parameterised_like_the_judge(tc)
            % Rule 2, one level up: if the shadow shared the judge's numbers,
            % scoring a scene by shadow NIS would be self-grading.
            C = physics.Constants();
            f = engine.track.shadowEKF([], 1800, tc.FRAME_DT, 'Class', 'fighter');
            judgeMeasVar = C.range_per_sample^2;          % +engine/runJudge.m's measNoise(1,1)
            fprintf('[step3] shadow R = %.1f m^2 (sigma %.2f m) vs judge R = %.1f m^2 (sigma %.2f m)\n', ...
                f.R, sqrt(f.R), judgeMeasVar, sqrt(judgeMeasVar));
            tc.verifyNotEqual(f.R, judgeMeasVar, ...
                'Shadow and judge now share a measurement-noise parameter.');
            tc.verifyEqual(f.R, judgeMeasVar/12, 'RelTol', 1e-12, ...
                'Shadow R should be the uniform-quantiser variance delta^2/12.');
            % The judge gates on a 200 m Euclidean distance; the shadow gates
            % on a chi-square NIS. Different KIND of gate, not just a
            % different number.
            tc.verifyEqual(f.gate, 2*erfinv(0.99)^2, 'RelTol', 1e-9);
        end

        % ===================== step 4 =====================

        function test_shadow_vs_judge_scorecard(tc)
            q = tc.calibratedQ();
            scenes = {'consistent-closing', 'static-decoy', 'rgpo-vgpo-mismatch', 'range-jump'};
            rows = struct('name', {}, 'nis', {}, 'margin', {}, 'gated', {}, ...
                          'confirmed', {}, 'label', {}, 'agree', {});

            for i = 1:numel(scenes)
                [cube, rangeTruth] = tc.buildScene(scenes{i}, q);
                fb = tc.judge(cube);

                % Shadow runs PRE-transmit on what the engine expects the
                % radar to measure: its own entity's range, quantised to the
                % radar's bin (the engine knows c/(2*fs); it is a fact, not
                % one of the judge's parameters).
                [meanNIS, minMargin, allGated] = tc.shadowOnTruth(rangeTruth, q);

                % Shadow's verdict: "this looks like a consistently-tracked
                % physical object" == every dwell stayed inside its gate.
                shadowSaysOk = allGated;
                judgeSaysOk  = fb.confirmed_tracks >= 1 && strcmp(fb.eccm_label, 'real');
                agree = (shadowSaysOk == judgeSaysOk);

                rows(end+1) = struct('name', scenes{i}, 'nis', meanNIS, ...
                    'margin', minMargin, 'gated', shadowSaysOk, ...
                    'confirmed', fb.confirmed_tracks, 'label', fb.eccm_label, ...
                    'agree', agree); %#ok<AGROW>
            end

            fprintf('\n=== Step 4: shadow EKF vs real judge ===\n');
            fprintf('%-20s %10s %10s %8s %10s %8s %8s\n', ...
                'scene', 'meanNIS', 'minMargin', 'inGate', 'confirmed', 'label', 'agree');
            for r = rows
                fprintf('%-20s %10.3f %10.3f %8d %10d %8s %8d\n', ...
                    r.name, r.nis, r.margin, r.gated, r.confirmed, r.label, r.agree);
            end
            nAgree = sum([rows.agree]);
            fprintf('agreement: %d/%d\n\n', nAgree, numel(rows));

            % --- structural findings, asserted; the rates are reported, not gated ---

            % 1. Where the shadow CAN see the problem, it does: a range jump
            %    beyond the judge's own assignment gate breaks the shadow's
            %    chi-square gate too.
            jump = rows(strcmp({rows.name}, 'range-jump'));
            tc.verifyFalse(jump.gated, 'Shadow did not notice a discontinuous range jump.');

            % 2. Where the shadow is BLIND, say so. It is a purely kinematic
            %    filter: it models range and range-rate and nothing else, so
            %    a phantom whose KINEMATICS are impeccable and whose
            %    AMPLITUDE or DOPPLER betrays it is invisible to shadow NIS
            %    while the judge flags it. This is the measured gap, and it
            %    is the concrete prerequisite for build step 5: shadow NIS
            %    alone is NOT a sufficient dense reward, because it cannot
            %    represent the two screens the judge actually decides on.
            for nm = {'static-decoy', 'rgpo-vgpo-mismatch'}
                r = rows(strcmp({rows.name}, nm{1}));
                tc.verifyTrue(r.gated, sprintf( ...
                    ['%s is no longer kinematically clean to the shadow -- if the shadow ' ...
                     'gained an amplitude/Doppler channel, update this documented gap.'], nm{1}));
                tc.verifyEqual(r.label, 'decoy', sprintf( ...
                    'Judge no longer flags %s; the divergence claim needs restating.', nm{1}));
            end

            % 3. The consistent entity is the one case both sides pass.
            good = rows(strcmp({rows.name}, 'consistent-closing'));
            tc.verifyTrue(good.gated && strcmp(good.label, 'real'), ...
                'A genuine calibrated entity failed one of the two sides.');
        end

    end

    % ===================== helpers =====================
    methods (Access = private)

        function q = calibratedQ(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            f = fullfile(projectRoot, 'data', 'RadChar-Tiny.h5');
            tc.assumeTrue(isfile(f), ...
                'No data/RadChar-*.h5 found. See data/README.md to download it.');
            q = engine.entity.calibrateQ('Dt', tc.FRAME_DT, 'RadCharFile', f);
        end

        function q0 = zeroQ(~, q)
            q0 = q; q0.sigma_accel_mps2 = 0; q0.rcs_process_std_db = 0;
        end

        function nis = shadowRun(tc, shadowSigma, entityQ, seed, nDwells)
        %SHADOWRUN  Propagate an entity and track it with the shadow filter,
        %   feeding it the range the radar's quantiser would actually report.
            C = physics.Constants();
            s = engine.entity.EntityState('range_m', 2800, 'range_rate_mps', -40, ...
                    'class', 'fighter');
            rs = RandStream('twister', 'Seed', seed);
            f = engine.track.shadowEKF([], tc.quantise(s.range_m, C), tc.FRAME_DT, ...
                    'Class', 'fighter', 'SigmaAccelMps2', shadowSigma);
            nis = zeros(nDwells-1, 1);
            for k = 1:nDwells-1
                s = engine.entity.propagate(s, tc.FRAME_DT, entityQ, rs);
                [f, out] = engine.track.shadowEKF(f, tc.quantise(s.range_m, C), tc.FRAME_DT);
                nis(k) = out.nis;
            end
        end

        function [meanNIS, minMargin, allGated] = shadowOnTruth(tc, rangeTruth, q)
            C = physics.Constants();
            f = engine.track.shadowEKF([], tc.quantise(rangeTruth(1), C), tc.FRAME_DT, ...
                    'Class', 'fighter', 'SigmaAccelMps2', q.sigma_accel_mps2);
            nis = zeros(numel(rangeTruth)-1, 1);
            margin = zeros(size(nis));
            gated = true(size(nis));
            for k = 2:numel(rangeTruth)
                [f, out] = engine.track.shadowEKF(f, tc.quantise(rangeTruth(k), C), tc.FRAME_DT);
                nis(k-1) = out.nis; margin(k-1) = out.gate_margin; gated(k-1) = out.gated;
            end
            meanNIS = mean(nis); minMargin = min(margin); allGated = all(gated);
        end

        function r = quantise(~, rangeM, C)
            % What a range bin actually reports -- the engine knows the
            % radar's bin size because it follows from c and fs, both facts.
            r = round(2*rangeM/C.c * C.fs) * C.range_per_sample;
        end

        function [cube, rangeTruth] = buildScene(tc, name, q)
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 4);
            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            rangeTruth = zeros(tc.N_FRAMES, 1);

            switch name
                case 'consistent-closing'
                    s = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -40, ...
                            'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
                    for k = 1:tc.N_FRAMES
                        rangeTruth(k) = s.range_m;
                        cube(:,:,k) = tc.renderOne(s, rs);
                        s = engine.entity.propagate(s, tc.FRAME_DT, q, rs);
                    end

                case 'static-decoy'
                    % Kinematically perfect and utterly still: the shadow has
                    % nothing to object to, the judge's amplitude screen does.
                    s = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', 0, ...
                            'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
                    for k = 1:tc.N_FRAMES
                        rangeTruth(k) = s.range_m;
                        cube(:,:,k) = tc.renderOne(s, rs);
                    end

                case 'rgpo-vgpo-mismatch'
                    % Range walks closing; Doppler says opening. Built
                    % outside engine.entity.render on purpose -- the
                    % single-source renderer CANNOT produce this object.
                    [cube, rangeTruth] = tc.buildMismatch(rs, -60, +60);

                case 'range-jump'
                    % A discontinuity past the judge's own 200 m assignment
                    % gate. The one failure a purely kinematic filter CAN see.
                    s = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -40, ...
                            'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
                    for k = 1:tc.N_FRAMES
                        if k == 5
                            s.range_m = s.range_m + 900;
                        end
                        rangeTruth(k) = s.range_m;
                        cube(:,:,k) = tc.renderOne(s, rs);
                        s = engine.entity.propagate(s, tc.FRAME_DT, q, rs);
                    end

                otherwise
                    error('unknown scene %s', name);
            end
        end

        function c = renderOne(tc, s, rs)
            c = engine.entity.render(s, 'NumPulses', tc.N_PULSES, ...
                    'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, ...
                    'PrfHz', tc.PRF_HZ, 'RandStream', rs);
            c = c + tc.noise(rs);
        end

        function [cube, rangeTruth] = buildMismatch(tc, rs, vRange, vDoppler)
            C = physics.Constants();
            lambda = C.c / tc.CARRIER;
            n = round(tc.PW_S * C.fs);
            t = (0:n-1)' / C.fs;
            chirp = exp(1i * pi * (tc.BW_HZ / tc.PW_S) * t.^2);
            slow = (0:tc.N_PULSES-1)' / tc.PRF_HZ;
            fdWrong = -2 * vDoppler / lambda;
            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            rangeTruth = zeros(tc.N_FRAMES, 1);
            for k = 1:tc.N_FRAMES
                R = 1800 + vRange * (k - 1);
                rangeTruth(k) = R;
                delay = round(2*R/C.c * C.fs);
                perPulse = (1800/R)^2 * exp(1i * 2*pi * fdWrong * slow);
                c = complex(zeros(tc.N_FAST, tc.N_PULSES));
                c(delay + (1:n), :) = chirp * perPulse.';
                cube(:,:,k) = c + tc.noise(rs);
            end
        end

        function nz = noise(tc, rs)
            nz = 0.05 * (randn(rs, tc.N_FAST, tc.N_PULSES) + ...
                    1i * randn(rs, tc.N_FAST, tc.N_PULSES)) / sqrt(2);
        end

        function fb = judge(tc, cube)
            C = physics.Constants();
            S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', tc.PW_S, ...
                       'bandwidth_hz', tc.BW_HZ, 'prf_hz', tc.PRF_HZ, 'cfar_pfa', 1e-4, ...
                       'cfar_num_training', 20, 'cfar_num_guard', 4, ...
                       'frame_interval_s', tc.FRAME_DT, 'carrier_hz', tc.CARRIER);
            f = [tempname '.mat'];
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end
    end
end
