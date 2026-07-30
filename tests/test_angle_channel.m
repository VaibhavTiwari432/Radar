classdef test_angle_channel < matlab.unittest.TestCase
%TEST_ANGLE_CHANNEL  Monopulse azimuth and the co-bearing screen
%   (RADAR_REALISM_AUDIT.md 1.1 -- the biggest realism gap this project had).
%
%   A DRFM repeater transmits from ONE PLACE. Range, Doppler and amplitude can
%   each be forged independently per phantom -- this project has spent
%   considerable effort demonstrating exactly that, most recently
%   tests/test_vee_deception_check.m's 10/10 evasion. AZIMUTH cannot be
%   forged that way, because it is set by where the transmitter physically is.
%
%   So the decisive test is the scene this project has confirmed as four
%   believable targets since Task 1 (tests/test_four_phantom_swarm.m: "4
%   confirmed, 4 real, 0 flagged, 8/8 seeds") -- rendered again, unchanged,
%   except that the phantoms now all radiate from one bearing because one
%   jammer made them.

    properties (Constant)
        PW_S     = 12e-6;
        BW_HZ    = 2e6;
        PRF_HZ   = 50e3;
        CARRIER  = 10e9;
        N_FRAMES = 8;
        N_PULSES = 32;
        N_FAST   = 400;
        SUBAP_M  = 0.30;
        RANGES   = [1800 2600 3400 4200];
        AMP      = 3.0;
        N_SEEDS  = 8;
    end

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_monopulse_recovers_the_true_azimuth(tc)
            % Before screening anything, the angle estimator must actually work.
            C = physics.Constants();
            unamb = asin(C.c/tc.CARRIER / (2*tc.SUBAP_M));
            fprintf('\n[angle] unambiguous monopulse sector = +/-%.2f deg\n', rad2deg(unamb));
            truth = deg2rad([-2 -1 -0.5 0 0.5 1 2]);
            err = zeros(size(truth));
            for i = 1:numel(truth)
                fb = tc.judgeScene(3000, truth(i), 1, 1);
                tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, 'nothing confirmed');
                est = fb.track_azimuth_mean(1);
                err(i) = rad2deg(est - truth(i));
                fprintf('   true %+5.2f deg -> measured %+5.2f deg (err %+.3f deg)\n', ...
                    rad2deg(truth(i)), rad2deg(est), err(i));
            end
            tc.verifyEqual(fb.angle_source, 'monopulse');
            tc.verifyLessThan(max(abs(err)), 0.25, ...
                'Monopulse azimuth error exceeded 0.25 deg inside the unambiguous sector.');
        end

        function test_four_phantoms_from_one_jammer_are_all_flagged(tc)
            % THE headline. Identical to this project's own validated
            % 4-phantom swarm, except all four share the jammer's bearing.
            nAllFlagged = 0; nConfirmed = zeros(1, tc.N_SEEDS);
            for s = 1:tc.N_SEEDS
                fb = tc.judgeSwarm(repmat(deg2rad(0.8), 1, 4), s);   % ONE bearing
                nConfirmed(s) = fb.confirmed_tracks;
                allDecoy = fb.confirmed_tracks >= 2 && ...
                           all(strcmp(fb.track_label, 'decoy'));
                nAllFlagged = nAllFlagged + allDecoy;
                if s == 1
                    fprintf(['\n[angle] one-jammer swarm: %d tracks confirmed, azimuths %s deg, ' ...
                             'cobearing=%d\n   labels: %s\n'], fb.confirmed_tracks, ...
                             mat2str(round(rad2deg(fb.track_azimuth_mean),2)), ...
                             fb.cobearing_flagged, strjoin(fb.track_label, ','));
                end
            end
            fprintf('[angle] all-flagged in %d/%d seeds (mean %.1f tracks confirmed)\n', ...
                nAllFlagged, tc.N_SEEDS, mean(nConfirmed));

            tc.verifyGreaterThanOrEqual(mean(nConfirmed), 2, ...
                'Too few tracks confirmed for a co-bearing test to be meaningful.');
            tc.verifyEqual(nAllFlagged, tc.N_SEEDS, ...
                'A co-bearing phantom swarm was NOT flagged; the angle screen is not working.');
        end

        function test_genuine_targets_on_different_bearings_are_not_flagged(tc)
            % The screen must not condemn a real formation. Four genuine
            % aircraft, same ranges, spread across the beam.
            spread = deg2rad([-2 -0.8 0.8 2]);
            nFalseAlarm = 0;
            for s = 1:tc.N_SEEDS
                fb = tc.judgeSwarm(spread, s);
                anyDecoy = any(strcmp(fb.track_label, 'decoy'));
                nFalseAlarm = nFalseAlarm + anyDecoy;
                if s == 1
                    fprintf(['\n[angle] spread formation: %d tracks, azimuths %s deg, ' ...
                             'cobearing=%d\n   labels: %s\n'], fb.confirmed_tracks, ...
                             mat2str(round(rad2deg(fb.track_azimuth_mean),2)), ...
                             fb.cobearing_flagged, strjoin(fb.track_label, ','));
                end
            end
            fprintf('[angle] false alarms on a genuine spread formation: %d/%d seeds\n', ...
                nFalseAlarm, tc.N_SEEDS);
            tc.verifyLessThanOrEqual(nFalseAlarm, 1, ...
                'The co-bearing screen condemned a genuine spread formation.');
        end

        function test_no_delta_channel_means_no_angle_and_no_screen(tc)
            % Backward compatibility: a radar without the difference channel is
            % the radar this project has always had, and must say so.
            fb = tc.judgeSwarm(repmat(deg2rad(0.8), 1, 4), 1, false);
            tc.verifyEqual(fb.angle_source, 'none');
            tc.verifyFalse(fb.cobearing_flagged);
            fprintf(['\n[angle] SAME one-jammer swarm with NO angle channel: %d confirmed, ' ...
                     'labels %s\n         -- i.e. what every published number in this ' ...
                     'project has been measuring.\n'], ...
                     fb.confirmed_tracks, strjoin(fb.track_label, ','));
            tc.verifyGreaterThanOrEqual(fb.confirmed_tracks, 2);
        end

    end

    methods (Access = private)

        function fb = judgeScene(tc, rangeM, azRad, ~, seed)
            [sumC, dltC] = tc.renderObjects(rangeM, azRad, seed);
            fb = tc.judge(sumC, dltC, true);
        end

        function fb = judgeSwarm(tc, azList, seed, withAngle)
            if nargin < 4; withAngle = true; end
            [sumC, dltC] = tc.renderObjects(tc.RANGES, azList, seed);
            fb = tc.judge(sumC, dltC, withAngle);
        end

        function [sumC, dltC] = renderObjects(tc, ranges, azs, seed)
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 9000 + seed);
            q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);
            n = round(tc.PW_S * C.fs); t = (0:n-1)'/C.fs;
            chirp = exp(1i*pi*(tc.BW_HZ/tc.PW_S)*t.^2);

            states = cell(1, numel(ranges));
            ampScale = zeros(1, numel(ranges));
            for i = 1:numel(ranges)
                states{i} = engine.entity.EntityState('range_m', ranges(i), ...
                    'range_rate_mps', -60, 'class', 'fighter', 'rcs_dbsm', 0, ...
                    'swerling', 0, 'azimuth_rad', azs(i));
                % Compensated ONCE from the INITIAL range, so every object
                % starts comparably detectable but its amplitude still rises as
                % 1/R^2 while it closes. Recomputing this per frame (a first
                % version did) pins received amplitude flat over time, which is
                % precisely the naive-DRFM signature -- and the existing
                % amplitude-range screen duly flagged the GENUINE formation in
                % 7/8 seeds. The bug was in the scene, not the screen.
                ampScale(i) = tc.AMP * (ranges(i) / 1800)^2;
            end

            sumC = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            dltC = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            for k = 1:tc.N_FRAMES
                fs_ = complex(zeros(tc.N_FAST, tc.N_PULSES));
                fd_ = complex(zeros(tc.N_FAST, tc.N_PULSES));
                for i = 1:numel(states)
                    [cs, ~, cd] = engine.entity.render(states{i}, 'AmpScale', ampScale(i), ...
                        'NumPulses', tc.N_PULSES, 'FastTimeSamples', tc.N_FAST, ...
                        'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ, ...
                        'PulseWidth', tc.PW_S, 'Bandwidth', tc.BW_HZ, ...
                        'SubapertureSepM', tc.SUBAP_M, 'ChirpOverride', chirp, ...
                        'RandStream', rs);
                    fs_ = fs_ + cs; fd_ = fd_ + cd;
                end
                % Independent receiver noise in each channel -- they are
                % separate receivers, so their noise does not cancel in the
                % monopulse ratio. That is what sets the angle accuracy.
                fs_ = fs_ + tc.noise(rs);
                fd_ = fd_ + tc.noise(rs);
                sumC(:,:,k) = fs_; dltC(:,:,k) = fd_;
                for i = 1:numel(states)
                    states{i} = engine.entity.propagate(states{i}, 1.0, q, rs);
                end
            end
        end

        function nz = noise(tc, rs)
            nz = 0.05 * (randn(rs, tc.N_FAST, tc.N_PULSES) + ...
                    1i*randn(rs, tc.N_FAST, tc.N_PULSES)) / sqrt(2);
        end

        function fb = judge(tc, sumC, dltC, withAngle)
            C = physics.Constants();
            S = struct('rx_frames', sumC, 'fs', C.fs, 'pulse_width_s', tc.PW_S, ...
                'bandwidth_hz', tc.BW_HZ, 'prf_hz', tc.PRF_HZ, 'cfar_pfa', 1e-4, ...
                'cfar_num_training', 20, 'cfar_num_guard', 4, 'frame_interval_s', 1.0, ...
                'carrier_hz', tc.CARRIER);
            if withAngle
                S.rx_frames_delta = dltC;
                S.subaperture_sep_m = tc.SUBAP_M;
            end
            f = [tempname '.mat']; save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end
    end
end
