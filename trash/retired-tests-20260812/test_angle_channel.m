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

    methods (TestClassSetup)
        function assumeArchivedDependencyPresent(tc)
            % 7 Aug 2026 archive: every scene in this file is built by
            % engine.entity.render, which no longer exists. Report Incomplete --
            % this project's own honest "not built yet" outcome, the same
            % one DataIntegration_Test uses for an absent dataset -- rather
            % than erroring. 63 errored methods made a real regression
            % invisible; a skip keeps the suite usable as an instrument.
            % NOT a fix: rewire to generator.render to genuinely re-enable.
            tc.assumeTrue(archivedDepsPresent({'engine.entity.render'}), ...
                'engine.entity.render was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
        end
    end

    properties (Constant)
        PW_S     = 12e-6;
        BW_HZ    = 2e6;
        PRF_HZ   = physics.Constants().PRF;
        CARRIER  = 10e9;
        N_FRAMES = 8;
        N_PULSES = 32;
        N_FAST   = 400;
        SUBAP_M  = 0.30;
        RANGES   = [1800 2600 3400 4200];
        AMP      = 3.0;
        N_SEEDS  = 12;    % >= 10, per Phase 1.5 TEST 3
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

            % ========== PHASE E: A DOCUMENTED PERMANENT LIMIT ==========
            % This is not a bug and it is not a tuning target. It is a
            % property of SINGLE-APERTURE GEOMETRY: every phantom this
            % project can build is transmitted from ONE mother drone, so
            % every phantom shares that drone's instantaneous bearing.
            % Range, Doppler and amplitude can each be forged independently
            % per phantom -- this project spent considerable effort proving
            % exactly that -- but azimuth cannot, because it is set by where
            % the transmitter physically is. No amount of engine cleverness
            % changes it; only a SECOND, spatially separated transmitter
            % would, and that is a different threat model.
            %
            % CONSEQUENCE THAT MUST TRAVEL WITH EVERY OTHER NUMBER IN THIS
            % PROJECT: the angle-blind case is what every published deception
            % result here has measured. With the difference channel on, the
            % validated 4-phantom swarm is flagged 4/4 in 8/8 seeds.
            %
            % It is BOUNDED, though, and Phase D2 measured the bound:
            % tests/test_monopulse_snr_boundary.m shows the screen cannot
            % separate a fan from a genuine formation whose cross-range
            % spread is below ~40 m at this geometry, and that the bound is
            % NOT an SNR threshold (the screen is a self-calibrating ratio,
            % so it is nearly SNR-invariant from -5 to +25 dB).
            tc.verifyGreaterThanOrEqual(mean(nConfirmed), 2, ...
                'Too few tracks confirmed for a co-bearing test to be meaningful.');
            tc.verifyEqual(nAllFlagged, tc.N_SEEDS, ...
                ['A co-bearing phantom swarm was NOT flagged in every seed. This is a ' ...
                 'RECORDED PERMANENT LIMIT (4/4 flagged in 8/8 seeds), not a threshold ' ...
                 'to tune: if it has changed, single-aperture geometry has not changed, ' ...
                 'so something in the angle chain has broken.']);
        end

        function test_genuine_targets_on_different_bearings_are_not_flagged(tc)
        % ============ PHASE 1.5 TEST 3 -- RE-MEASURED, NOT PATCHED ============
        %
        % This is not a fix. The radar changed underneath the old measurement
        % (PRF 50 -> 8 kHz, v_ua 375 -> 59.96 m/s), so the boundary between
        % "genuine formation passes" and "genuine formation is condemned"
        % moved and had to be measured again rather than re-asserted.
        %
        % THREE THINGS THE OLD VERSION CONFLATED, NOW SEPARATED:
        %
        %  1. It counted ANY 'decoy' label as a co-bearing false alarm. Most
        %     of those come from the AMPLITUDE screen, not the angle screen --
        %     a weakness Phase 3 D1 already measured (a constant-ERP repeater
        %     with a perfectly flat slope is caught only 5/10 of the time, and
        %     a correct masquerade never). Retargeting to -40 m/s shortened the
        %     range walk from 420 m to 280 m over 8 frames, shortening screen
        %     1's already-short lever arm further. Reported separately now:
        %     cobearing_flagged is the angle screen; any-decoy is every screen.
        %  2. It used a fixed ANGULAR spread (+-2 deg), which is a different
        %     physical formation at every range. A real formation has a
        %     CROSS-RANGE spread in metres; the angles follow from geometry.
        %  3. It flew four objects in perfect lockstep at one velocity. Real
        %     formations do not, and the velocity spread is what makes the
        %     comparison about geometry rather than about a shared Doppler.
        %
        % Formation: 5 genuine aircraft, ~100 m cross-range spread, mean
        % -30 m/s with +-5 m/s per aircraft -- every velocity inside
        % v_ua = 59.96 m/s, so nothing folds and the discriminator is
        % geometry, not a Doppler artifact.
            C = physics.Constants();
            CROSS_RANGE_M = 100;
            nObj = 5;
            ranges = linspace(tc.RANGES(1), tc.RANGES(end), nObj);
            offsets = linspace(-CROSS_RANGE_M/2, CROSS_RANGE_M/2, nObj);
            azGen = atan2(offsets, ranges);              % cross-range -> angle
            vGen = -30 + linspace(-5, 5, nObj);          % all inside v_ua
            azPh = repmat(deg2rad(0.8), 1, nObj);        % one jammer, one bearing
            vPh  = vGen;                                  % identical otherwise

            tc.assertLessThan(max(abs(vGen)), C.v_unambiguous, ...
                'A formation velocity exceeds v_ua -- it would fold and confound this.');

            fprintf(['\n=== TEST 3: monopulse boundary, genuine formation vs one-jammer fan ===\n' ...
                     'formation: %d objects, %.0f m cross-range, ranges %.0f-%.0f m, v %.0f..%.0f m/s\n' ...
                     'azimuths: genuine %s deg | phantom all %.2f deg\n' ...
                     'seeds: %d\n\n'], nObj, CROSS_RANGE_M, ranges(1), ranges(end), ...
                     min(vGen), max(vGen), mat2str(round(rad2deg(azGen),3)), ...
                     rad2deg(azPh(1)), tc.N_SEEDS);

            [gConf, gCoBear, gAnyDecoy, gTracks] = tc.armStats(ranges, azGen, vGen);
            [pConf, pCoBear, pAnyDecoy, pTracks] = tc.armStats(ranges, azPh,  vPh);

            fprintf('%-22s %12s %14s %14s %12s\n', 'arm', 'confirmed', ...
                'co-bearing', 'any-decoy', 'mean tracks');
            fprintf('%-22s %10d/%d %12d/%d %12d/%d %12.1f\n', 'GENUINE formation', ...
                gConf, tc.N_SEEDS, gCoBear, tc.N_SEEDS, gAnyDecoy, tc.N_SEEDS, gTracks);
            fprintf('%-22s %10d/%d %12d/%d %12d/%d %12.1f\n', 'PHANTOM fan (1 jammer)', ...
                pConf, tc.N_SEEDS, pCoBear, tc.N_SEEDS, pAnyDecoy, tc.N_SEEDS, pTracks);

            gRate = 100*gCoBear/tc.N_SEEDS;  pRate = 100*pCoBear/tc.N_SEEDS;
            [gLo, gHi] = tc.wilson(gCoBear, tc.N_SEEDS);
            [pLo, pHi] = tc.wilson(pCoBear, tc.N_SEEDS);
            fprintf(['\nco-bearing flag rate: genuine %.0f%% CI[%.0f,%.0f] | ' ...
                     'phantom %.0f%% CI[%.0f,%.0f] | separation %.0f pts\n'], ...
                     gRate, 100*gLo, 100*gHi, pRate, 100*pLo, 100*pHi, abs(pRate-gRate));

            if abs(pRate - gRate) >= 20
                fprintf(['VERDICT: SEPARATED. Genuine flagged at %.0f%%, phantom at %.0f%%.\n' ...
                         '  The discriminator is GEOMETRIC SPREAD, not velocity -- every\n' ...
                         '  velocity here is inside v_ua and the two arms share them.\n'], ...
                         gRate, pRate);
            elseif abs(pRate - gRate) <= 10
                fprintf('VERDICT: boundary NOT resolved at %.0f m cross-range spread.\n', CROSS_RANGE_M);
            else
                fprintf('VERDICT: partial separation (%.0f pts) -- inconclusive.\n', abs(pRate-gRate));
            end

            % ---- sigma_theta reconciliation (Phase 3 D2's formula) ----
            % NOTE the formula takes LINEAR SNR, not dB: sqrt(2*100) = 14.14,
            % not sqrt(2*20) = 6.32. The 0.133 deg figure is the linear one.
            THETA_3DB = 3.0; K_M = 1.6; SNR_DB = 20;
            sigDeg = THETA_3DB / (K_M * sqrt(2 * 10^(SNR_DB/10)));
            sigCross = 3000 * tan(deg2rad(sigDeg));
            ratio = CROSS_RANGE_M / sigCross;
            fprintf(['\nsigma_theta = %.1f deg / (%.1f * sqrt(2*%d linear)) = %.4f deg\n' ...
                     '  -> %.2f m cross-range error at 3 km\n' ...
                     '  formation spread %.0f m / error %.2f m = %.1f:1\n'], ...
                     THETA_3DB, K_M, 10^(SNR_DB/10), sigDeg, sigCross, ...
                     CROSS_RANGE_M, sigCross, ratio);
            fprintf(['  RECONCILIATION: the spread is %.1fx the angular error, so monopulse\n' ...
                     '  CAN resolve this formation -- consistent with the measured genuine\n' ...
                     '  co-bearing rate above. (The brief phrased this as the error being\n' ...
                     '  "small enough that the radar can''t resolve the formation"; it is the\n' ...
                     '  other way round -- a SMALL error is what makes it resolvable.)\n' ...
                     '  Phase 3 D2 measured the boundary directly at ~40 m; %.0f m sits %.1fx\n' ...
                     '  above it, so a pass here is expected rather than lucky.\n'], ...
                     ratio, CROSS_RANGE_M, CROSS_RANGE_M/40);
            tc.verifyEqual(sigDeg, 0.133, 'AbsTol', 5e-4);
            tc.verifyEqual(sigCross, 6.9, 'AbsTol', 0.1);
            tc.verifyGreaterThan(ratio, 10, ...
                'Formation spread is no longer comfortably above the angular error.');

            % ---- assertions ----
            tc.verifyGreaterThanOrEqual(gTracks, 2, ...
                'Too few genuine tracks confirmed for a co-bearing test to mean anything.');
            tc.verifyLessThanOrEqual(gCoBear, 1, ...
                ['The co-bearing screen condemned a genuine formation whose cross-range ' ...
                 'spread is 14.5x the angular error. That is a false accusation against ' ...
                 'real aircraft, not a tuning matter.']);
            tc.verifyGreaterThanOrEqual(pCoBear, tc.N_SEEDS - 1, ...
                'The one-jammer fan was not flagged -- the angle screen is inert.');
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

        function [nConf, nCoBear, nAnyDecoy, meanTracks] = armStats(tc, ranges, azs, vels)
        %ARMSTATS  One arm over N_SEEDS. Reports the ANGLE screen
        %   (cobearing_flagged) separately from every screen (any 'decoy'
        %   label), because conflating them is what made the old version of
        %   this test unreadable -- see the note in the test body.
            nConf = 0; nCoBear = 0; nAnyDecoy = 0; tracks = zeros(1, tc.N_SEEDS);
            for s = 1:tc.N_SEEDS
                [sumC, dltC] = tc.renderObjects(ranges, azs, s, vels);
                fb = tc.judge(sumC, dltC, true);
                tracks(s) = fb.confirmed_tracks;
                nConf     = nConf     + (fb.confirmed_tracks >= 2);
                nCoBear   = nCoBear   + double(fb.cobearing_flagged);
                nAnyDecoy = nAnyDecoy + any(strcmp(fb.track_label, 'decoy'));
            end
            meanTracks = mean(tracks);
        end

        function [lo, hi] = wilson(~, k, n)
        %WILSON  95% Wilson score interval -- same one BENCHMARK_RESULTS.md
        %   and tests/test_monopulse_snr_boundary.m use, appropriate at small n.
            if n == 0; lo = 0; hi = 1; return; end
            z = 1.959963984540054;
            pHat = k / n; d = 1 + z^2/n; cc = pHat + z^2/(2*n);
            r = z * sqrt(pHat*(1-pHat)/n + z^2/(4*n^2));
            lo = max(0, (cc - r)/d); hi = min(1, (cc + r)/d);
        end

        function [sumC, dltC] = renderObjects(tc, ranges, azs, seed, vels)
        % vels (optional): per-object radial velocity [m/s]. Omitted -> all
        % objects at -40 m/s, this project's canonical closing rate since
        % Phase 4.1 (inside v_ua = 59.96 m/s). A GENUINE formation does not
        % fly in lockstep, so TEST 3 passes individual velocities.
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 9000 + seed);
            q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);
            n = round(tc.PW_S * C.fs); t = (0:n-1)'/C.fs;
            chirp = exp(1i*pi*(tc.BW_HZ/tc.PW_S)*t.^2);

            states = cell(1, numel(ranges));
            ampScale = zeros(1, numel(ranges));
            for i = 1:numel(ranges)
                if nargin >= 5 && ~isempty(vels); vi = vels(i); else; vi = -40; end
                states{i} = engine.entity.EntityState('range_m', ranges(i), ...
                    'range_rate_mps', vi, 'class', 'fighter', 'rcs_dbsm', 0, ...
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
