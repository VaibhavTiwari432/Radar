classdef test_judge_measured_doppler < matlab.unittest.TestCase
%TEST_JUDGE_MEASURED_DOPPLER  The judge's Doppler screen is a real
%   measurement now, not a restatement of range.
%
%   +engine/runJudge.m used to hand track.discriminator a "doppler" series
%   it had computed as diff(range)./diff(time). The discriminator's screen 2
%   asks whether sign(mean(diff(R))) == sign(mean(D)); with D derived FROM
%   diff(R) that comparison is true by construction and cannot fail, so
%   every confirmed track this project ever judged -- genuine or phantom --
%   collected a free pass from it. The structural cause was that rx_frames
%   held one fast-time column per frame: no slow-time axis, nothing for
%   radar.rangeDoppler to transform.
%
%   These tests pin down the fix and, more importantly, the CAPABILITY it
%   buys: test_rgpo_vgpo_mismatch_is_now_catchable builds a phantom whose
%   range walks one way while its Doppler says the other -- a classic
%   RGPO/VGPO-inconsistent repeater -- and shows the judge now labels it
%   decoy, while computing, in the same test, what the OLD rule would have
%   said about the very same track (pass).

    properties (Constant)
        FS_PW    = 12e-6;
        BW_HZ    = 2e6;
        PRF_HZ   = physics.Constants().PRF;
        CARRIER  = 10e9;
        N_FRAMES = 8;
        N_PULSES = 32;
        N_FAST   = 400;
        R0_M     = 1800;
    end

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_cube_path_measures_the_real_range_rate(tc)
            vTrue = -40;
            fb = tc.judge(tc.buildConsistent(vTrue));
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, 'Nothing confirmed to screen.');
            tc.verifyEqual(fb.doppler_source, 'measured');

            measured = mean(fb.track_range_rate_mps{1});
            % Resolution of a NumPulses-long dwell: lambda*PRF/(2*N).
            lambda = physics.Constants().c / tc.CARRIER;
            velBin = lambda * tc.PRF_HZ / (2 * tc.N_PULSES);
            fprintf('[judge] true %+.1f m/s -> measured %+.1f m/s (velocity bin %.1f m/s)\n', ...
                vTrue, measured, velBin);
            tc.verifyLessThanOrEqual(abs(measured - vTrue), velBin, ...
                'Measured range-rate is more than one velocity bin from truth.');
            tc.verifyEqual(fb.num_pulses_per_frame, tc.N_PULSES);
        end

        function test_consistent_targets_pass_both_directions(tc)
            % A genuine target is labelled real whether it closes or opens --
            % the screen tests CONSISTENCY, not a preferred direction.
            for v = [-40, 40]
                fb = tc.judge(tc.buildConsistent(v));
                tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);
                fprintf('[judge] consistent v=%+d -> label=%s (rate %+.1f m/s)\n', ...
                    v, fb.eccm_label, mean(fb.track_range_rate_mps{1}));
                tc.verifyEqual(fb.eccm_label, 'real', ...
                    sprintf('A genuine v=%+d target was labelled %s.', v, fb.eccm_label));
            end
        end

        function test_rgpo_vgpo_mismatch_is_now_catchable(tc)
            % Range walks CLOSING, Doppler says OPENING. Physically
            % impossible; a naive repeater pulling its range gate without
            % matching its velocity gate does exactly this.
            fb = tc.judge(tc.buildInconsistent(-40, +40));
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, 'Nothing confirmed to screen.');

            R = fb.track_range_m{1};
            t = fb.track_time_s{1};
            measured = fb.track_range_rate_mps{1};

            % What the judge does NOW: an independent Doppler measurement
            % that disagrees in sign with the range walk.
            tc.verifyEqual(sign(mean(diff(R))), -1, 'Range should be closing.');
            tc.verifyEqual(sign(mean(measured)), 1, 'Measured Doppler should say opening.');
            tc.verifyEqual(fb.eccm_label, 'decoy', ...
                'A range/Doppler-inconsistent phantom slipped through as real.');

            % What the OLD rule would have said about this SAME track,
            % computed here so the free pass is visible rather than asserted.
            oldDoppler = diff(R) ./ diff(t); oldDoppler = [oldDoppler(1); oldDoppler];
            oldScreen2 = double(sign(mean(diff(R))) == sign(mean(oldDoppler)));
            fprintf(['[judge] RGPO/VGPO mismatch: measured rate %+.1f m/s vs range trend %+.1f m/s ' ...
                     '-> NOW %s; the old diff(range) rule scored screen 2 = %.0f (pass)\n'], ...
                     mean(measured), mean(diff(R))/mean(diff(t)), fb.eccm_label, oldScreen2);
            tc.verifyEqual(oldScreen2, 1, ...
                'The old rule did not pass this -- the tautology claim needs restating.');
        end

        function test_legacy_2d_export_disables_the_screen_instead_of_faking_it(tc)
            cube = tc.buildConsistent(-40);
            fb = tc.judge(squeeze(cube(:, 1, :)));          % drop slow time -> legacy shape
            tc.verifyEqual(fb.doppler_source, 'none-2d-export-screen-disabled');
            if fb.confirmed_tracks >= 1
                tc.verifyEqual(fb.track_range_rate_mps{1}, ...
                    zeros(size(fb.track_range_rate_mps{1})), ...
                    'A 2-D export reported a nonzero Doppler it cannot possibly have measured.');
            end
            fprintf('[judge] legacy 2-D export: doppler_source=%s, confirmed=%d, label=%s\n', ...
                fb.doppler_source, fb.confirmed_tracks, fb.eccm_label);
        end

        function test_cube_without_carrier_refuses_to_guess(tc)
            cube = tc.buildConsistent(-40);
            f = [tempname '.mat'];
            S = tc.baseConfig(); S.rx_frames = cube;        % carrier_hz deliberately absent
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f));
            tc.verifyError(@() engine.runJudge(f), 'engine:runJudge:noCarrier');
        end

    end

    % ===================== helpers =====================
    methods (Access = private)

        function S = baseConfig(tc)
            C = physics.Constants();
            S = struct('fs', C.fs, 'pulse_width_s', tc.FS_PW, 'bandwidth_hz', tc.BW_HZ, ...
                       'prf_hz', tc.PRF_HZ, 'cfar_pfa', 1e-4, 'cfar_num_training', 20, ...
                       'cfar_num_guard', 4, 'frame_interval_s', 1.0);
        end

        function fb = judge(tc, rxFrames)
            f = [tempname '.mat'];
            S = tc.baseConfig();
            S.rx_frames = rxFrames;
            S.carrier_hz = tc.CARRIER;
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end

        function cube = buildConsistent(tc, v)
        %BUILDCONSISTENT  A genuine entity through the VEE's single-source
        %   renderer: range and Doppler cannot disagree, because both come
        %   from the same propagated state. swerling 0 -- Swerling 1's
        %   scan-to-scan fluctuation swamps the amplitude-range slope over
        %   only 8 frames (measured: fitted slope -0.8 instead of -2), which
        %   is a property of Swerling, not of the screen under test here.
            rs = RandStream('twister', 'Seed', 4);
            q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);
            s = engine.entity.EntityState('range_m', tc.R0_M, 'range_rate_mps', v, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            for k = 1:tc.N_FRAMES
                c = engine.entity.render(s, 'NumPulses', tc.N_PULSES, ...
                        'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, ...
                        'PrfHz', tc.PRF_HZ, 'RandStream', rs);
                cube(:, :, k) = c + tc.noise(rs);
                s = engine.entity.propagate(s, 1.0, q, rs);
            end
        end

        function cube = buildInconsistent(tc, vRange, vDoppler)
        %BUILDINCONSISTENT  Range walks at vRange, Doppler encodes vDoppler.
        %   Deliberately built OUTSIDE engine.entity.render, because the
        %   single-source renderer cannot produce this object -- which is
        %   exactly the VEE's point. This is the old per-frame-independent
        %   knob style (+synth/synthesizeSwarm.m's delay/gain/phase) that
        %   the VEE replaces, kept here as the adversary to screen against.
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 4);
            lambda = C.c / tc.CARRIER;
            n = round(tc.FS_PW * C.fs);
            t = (0:n-1)' / C.fs;
            chirp = exp(1i * pi * (tc.BW_HZ / tc.FS_PW) * t.^2);
            slow = (0:tc.N_PULSES-1)' / tc.PRF_HZ;
            fdWrong = -2 * vDoppler / lambda;

            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            for k = 1:tc.N_FRAMES
                R = tc.R0_M + vRange * (k - 1);
                delay = round(2 * R / C.c * C.fs);
                amp = (tc.R0_M / R)^2;                      % correct 1/R^2, so only
                perPulse = amp * exp(1i * 2*pi * fdWrong * slow);  % Doppler is wrong
                c = complex(zeros(tc.N_FAST, tc.N_PULSES));
                c(delay + (1:n), :) = chirp * perPulse.';
                cube(:, :, k) = c + tc.noise(rs);
            end
        end

        function nz = noise(tc, rs)
            % Phase 1's established convention (+agent/buildEnv.m).
            nz = 0.05 * (randn(rs, tc.N_FAST, tc.N_PULSES) + ...
                    1i * randn(rs, tc.N_FAST, tc.N_PULSES)) / sqrt(2);
        end
    end
end
