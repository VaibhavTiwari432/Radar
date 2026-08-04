classdef test_waveform_agility < matlab.unittest.TestCase
%TEST_WAVEFORM_AGILITY  Does making the radar unpredictable break the repeater?
%
%   RADAR_REALISM_AUDIT.md 1.2: until now this project's radar transmitted an
%   IDENTICAL LFM on every pulse of every frame, forever -- the condition
%   under which a stored intercept never goes stale, and therefore the
%   condition this project's whole feature-matched-synthesis result depends
%   on. radar.agileWaveform gives the radar a per-frame sweep-reversal
%   schedule; +engine/runJudge.m matched-filters each frame against the
%   waveform actually transmitted on THAT frame.
%
%   THE 2x2 IS THE POINT. Agility on its own proves nothing -- a repeater
%   that retransmits within the same dwell always holds the current pulse and
%   does not care what the next one looks like. Agility only bites a repeater
%   working from a STALE intercept, which is what it must do when it has
%   processing latency, or when it is trying to place a phantom CLOSER than
%   itself (predictive repeat-back -- see engine.entity.checkCausality, which
%   refuses that mode against an agile radar for exactly this reason).
%
%       radar \ repeater |  fresh intercept  |  stale intercept
%       -----------------+-------------------+------------------
%       fixed waveform   |  evades           |  evades (nothing changed)
%       AGILE waveform   |  evades           |  SHOULD COLLAPSE
%
%   Only the bottom-right cell should move. If agility hurt the fresh
%   repeater too, the experiment would be measuring a bug, not a mechanism.

    properties (Constant)
        PW_S     = 12e-6;
        BW_HZ    = 2e6;
        PRF_HZ   = physics.Constants().PRF;
        CARRIER  = 10e9;
        N_FRAMES = 8;
        N_PULSES = 32;
        N_FAST   = 400;
        GEN_R0   = 3800;      % genuine target
        PH_R0    = 2000;      % phantom
        AMP      = 3.0;
        N_SEEDS  = 10;
    end

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_agility_only_breaks_the_stale_repeater(tc)
            cells = {'fixed/fresh','fixed/stale','agile/fresh','agile/stale'};
            agile = [false false true true];
            stale = [false true  false true];
            dec = zeros(1,4); conf = zeros(1,4); genConf = zeros(1,4);

            for c = 1:4
                for s = 1:tc.N_SEEDS
                    [d, cf, gc] = tc.runCell(agile(c), stale(c), s);
                    dec(c) = dec(c) + d; conf(c) = conf(c) + cf; genConf(c) = genConf(c) + gc;
                end
            end

            fprintf('\n=== Waveform agility vs repeater staleness (%d seeds/cell) ===\n', tc.N_SEEDS);
            fprintf('%-14s %-16s %-18s %-16s\n', 'cell', 'phantom DECEIVES', 'phantom confirmed', 'genuine confirmed');
            for c = 1:4
                fprintf('%-14s %6d/%-9d %8d/%-9d %6d/%-9d\n', cells{c}, ...
                    dec(c), tc.N_SEEDS, conf(c), tc.N_SEEDS, genConf(c), tc.N_SEEDS);
            end

            iFF=1; iFS=2; iAF=3; iAS=4;
            fprintf(['\nAgility penalty on a STALE repeater: %d/%d -> %d/%d deceptions\n' ...
                     'Agility penalty on a FRESH repeater: %d/%d -> %d/%d\n'], ...
                     dec(iFS), tc.N_SEEDS, dec(iAS), tc.N_SEEDS, ...
                     dec(iFF), tc.N_SEEDS, dec(iAF), tc.N_SEEDS);

            % --- the genuine-target column is a SECOND RESULT, not a validity
            % check. A first version of this test asserted the genuine target
            % must survive in every cell; it does not, and that is physics, not
            % a bug: a mismatched repeater's response smears from 3 range bins
            % to 30 (measured), and that pedestal lifts the CA-CFAR noise floor
            % around the REAL target. Isolated, an agile radar detects a
            % lone genuine target 5/5 -- so the loss below is masking BY the
            % jammer, not self-harm by the radar.
            fprintf(['\nSide effect -- genuine target detected: fixed %d/%d and %d/%d, ' ...
                     'agile %d/%d and %d/%d.\nMaking the radar agile converts the repeater ' ...
                     'from a DECEIVER into an unintentional NOISE JAMMER: it stops planting\n' ...
                     'believable tracks and starts masking real ones instead.\n'], ...
                     genConf(iFF), tc.N_SEEDS, genConf(iFS), tc.N_SEEDS, ...
                     genConf(iAF), tc.N_SEEDS, genConf(iAS), tc.N_SEEDS);

            % Against a FIXED radar, staleness is free (the pulse never changed).
            tc.verifyEqual(dec(iFS), dec(iFF), ...
                'Staleness hurt the repeater even against a FIXED waveform -- that is a bug, not agility.');

            % THE MECHANISM: agility degrades the stale repeater.
            tc.verifyLessThan(dec(iAS), dec(iFS), ...
                'Agility did NOT degrade the stale repeater -- the mechanism is not working.');

            % A fixed radar must be deceived often enough in its own cells for
            % the agility penalty to be measurable against them.
            %
            % ==== THIS ASSERTION USED TO HARD-CODE 10/10, AND THAT WAS THE ====
            % ==== FRAGILITY, NOT A REGRESSION.                             ====
            % It measured 8/10 on 4 Aug 2026 and the whole 2x2 had moved down
            % by the same 2/10 -- including the fixed/fresh BASELINE, which
            % reaches no agility code at all (all-up schedule, repeater replays
            % the current pulse). Root-caused by measurement, not by review:
            % holding this exact cell fixed and sweeping ONLY the dwell length,
            %
            %   F= 8 frames | walk 280 m (1.163x) | confirmed 10/10 | DECEIVES  8/10 | slope -3.077
            %   F=12 frames | walk 440 m (1.282x) | confirmed 10/10 | DECEIVES 10/10 | slope -2.475
            %   F=16 frames | walk 600 m (1.429x) | confirmed 10/10 | DECEIVES 10/10 | slope -2.361
            %   F=24 frames | walk 920 m (1.852x) | confirmed 10/10 | DECEIVES 10/10 | slope -1.560
            %
            % DETECTION is 10/10 at every dwell -- so the drift is not SNR, not
            % CFAR and not the tracker. Only the LABEL moves, and it moves with
            % the amplitude screen's LEVER ARM: the fitted log-amplitude slope
            % converges toward the physical -2 as the walk lengthens, and
            % max(0, 1-|slope+2|/2) sends any seed fitting slope <= -4 to a
            % score of 0. The published 10/10 was measured when this scene flew
            % at -60 m/s (a 420 m walk); the -40 m/s retarget forced by
            % v_ua = 59.96 m/s cut it to 280 m. Restoring the ORIGINAL lever arm
            % restores the ORIGINAL number exactly (F=12 -> 440 m -> 10/10).
            %
            % So this is claim E1 -- the amplitude screen's short lever arm --
            % surfacing in a third place, and the scene is deliberately LEFT at
            % the project's default 8-frame dwell rather than lengthened to make
            % the number come back. What is fixed is the assertion: it now pins
            % the part that is structural (a fixed radar cannot penalise a
            % repeater, so the phantom must be DETECTED in every seed) and
            % requires only that the deception baseline be a clear majority,
            % which is what makes the -40% agility penalty below resolvable.
            tc.verifyEqual(conf(iFF), tc.N_SEEDS, ...
                ['The phantom was not even CONFIRMED in every fixed/fresh seed. That is a ' ...
                 'detection failure, not an ECCM verdict, and it breaks the baseline.']);
            tc.verifyGreaterThan(dec(iFF), tc.N_SEEDS/2, ...
                ['The fixed-waveform baseline is no longer a majority deception, so there ' ...
                 'is nothing for agility to degrade and the 2x2 is not measuring agility.']);
            tc.verifyEqual(genConf(iFF), tc.N_SEEDS, ...
                'The genuine target was not detected against a FIXED waveform -- the scene is broken.');
        end

        function test_agility_penalty_isolated_from_masking(tc)
        %   The 2x2 above confounds two effects: the repeater stops deceiving
        %   AND it starts masking the genuine target. This isolates the first
        %   by measuring the compression penalty directly, with no scene, no
        %   CFAR and no tracker involved -- just the matched filter.
            C = physics.Constants();
            [wUp, pUp]  = radar.agileWaveform(+1, C.fs, tc.PW_S, tc.PRF_HZ, tc.BW_HZ);
            [wDn, pDn]  = radar.agileWaveform(-1, C.fs, tc.PW_S, tc.PRF_HZ, tc.BW_HZ);

            peak = @(pulse, wav) max(radar.pulseCompress( ...
                [complex(zeros(43,1)); pulse(:); complex(zeros(tc.N_FAST-43-numel(pulse),1))], wav));
            width = @(pulse, wav) localWidth(radar.pulseCompress( ...
                [complex(zeros(43,1)); pulse(:); complex(zeros(tc.N_FAST-43-numel(pulse),1))], wav));

            mUp = peak(pUp, wUp); xUp = peak(pUp, wDn);
            mDn = peak(pDn, wDn); xDn = peak(pDn, wUp);
            fprintf(['\n[agility] matched peak %.0f (%d bins) | MISmatched peak %.0f (%d bins)\n' ...
                     '          penalty %.1f dB, response smeared %.0fx wider\n'], ...
                     mUp, width(pUp,wUp), xUp, width(pUp,wDn), ...
                     10*log10(mUp/xUp), width(pUp,wDn)/width(pUp,wUp));

            % Symmetric: neither sweep direction is privileged.
            tc.verifyEqual(mUp, mDn, 'RelTol', 1e-9);
            tc.verifyEqual(xUp, xDn, 'RelTol', 1e-9);
            % A real, large penalty -- this is the whole mechanism in one number.
            tc.verifyGreaterThan(10*log10(mUp/xUp), 10, ...
                'Sweep reversal costs a stale repeater less than 10 dB; it is not worth calling agility.');
        end

        function test_causality_refuses_predictive_against_an_agile_radar(tc)
            % engine.entity.checkCausality is the other half of the same idea.
            [ok, why] = engine.entity.checkCausality(1200, 2000, 'repeat', false);
            tc.verifyFalse(ok, 'A repeater was allowed to place a phantom inside itself.');
            fprintf('\n[causality] repeat-back, phantom 1200 m, jammer 2000 m -> REFUSED\n   %s\n', why);

            [ok2, ~] = engine.entity.checkCausality(1200, 2000, 'predictive', false);
            tc.verifyTrue(ok2, 'Predictive repeat-back should be allowed against a predictable radar.');

            [ok3, why3] = engine.entity.checkCausality(1200, 2000, 'predictive', true);
            tc.verifyFalse(ok3, 'Predictive repeat-back should be refused against an AGILE radar.');
            fprintf('[causality] predictive, AGILE radar -> REFUSED\n   %s\n', why3);

            % Farther than the jammer is always fine.
            tc.verifyTrue(engine.entity.checkCausality(3000, 2000, 'repeat', false));

            % And the renderer actually enforces it.
            s = engine.entity.EntityState('range_m', 1200, 'range_rate_mps', -40, 'class', 'fighter');
            tc.verifyError(@() engine.entity.render(s, 'JammerRangeM', 2000), ...
                'engine:entity:acausalPhantom');
        end

    end

    methods (Access = private)

        function [deceived, phConfirmed, genConfirmed] = runCell(tc, isAgile, isStale, seed)
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 7000 + seed);

            % The radar's schedule is its own secret; fixed radars use all-up.
            if isAgile
                schedRs = RandStream('twister', 'Seed', 424242 + seed);
                sched = sign(randn(schedRs, 1, tc.N_FRAMES + 1));
                sched(sched == 0) = 1;
            else
                sched = ones(1, tc.N_FRAMES + 1);
            end

            % Transmit pulse per frame, taken from MATLAB's own waveform object
            % so judge and renderer cannot drift apart (radar.agileWaveform).
            tmpl = cell(1, tc.N_FRAMES + 1);
            for k = 1:tc.N_FRAMES + 1
                [~, tmpl{k}] = radar.agileWaveform(sched(k), C.fs, tc.PW_S, tc.PRF_HZ, tc.BW_HZ);
            end

            q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);
            sg = engine.entity.EntityState('range_m', tc.GEN_R0, 'range_rate_mps', -40, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            sp = engine.entity.EntityState('range_m', tc.PH_R0, 'range_rate_mps', -40, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            genRange = zeros(tc.N_FRAMES,1); phRange = zeros(tc.N_FRAMES,1);
            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));

            for k = 1:tc.N_FRAMES
                genRange(k) = sg.range_m; phRange(k) = sp.range_m;

                % A REAL target reflects whatever the radar just transmitted.
                cg = engine.entity.render(sg, 'AmpScale', tc.AMP, 'NumPulses', tc.N_PULSES, ...
                        'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ, ...
                        'PulseWidth', tc.PW_S, 'Bandwidth', tc.BW_HZ, ...
                        'ChirpOverride', tmpl{k}, 'RandStream', rs);

                % The repeater replays frame k (fresh) or frame k-1 (stale).
                srcIdx = k; if isStale; srcIdx = max(1, k-1); end
                cp = engine.entity.render(sp, 'AmpScale', tc.AMP, 'NumPulses', tc.N_PULSES, ...
                        'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ, ...
                        'PulseWidth', tc.PW_S, 'Bandwidth', tc.BW_HZ, ...
                        'ChirpOverride', tmpl{srcIdx}, 'RandStream', rs);

                nz = 0.05 * (randn(rs, tc.N_FAST, tc.N_PULSES) + ...
                        1i*randn(rs, tc.N_FAST, tc.N_PULSES)) / sqrt(2);
                cube(:,:,k) = cg + cp + nz;
                sg = engine.entity.propagate(sg, 1.0, q, rs);
                sp = engine.entity.propagate(sp, 1.0, q, rs);
            end

            fb = tc.judge(cube, sched(1:tc.N_FRAMES));
            deceived = false; phConfirmed = false; genConfirmed = false;
            for i = 1:fb.confirmed_tracks
                rSeq = fb.track_range_m{i};
                if isempty(rSeq); continue; end
                est = mean(rSeq);
                if min(abs(phRange - est)) < min(abs(genRange - est))
                    phConfirmed = true;
                    deceived = deceived || strcmp(fb.track_label{i}, 'real');
                else
                    genConfirmed = true;
                end
            end
        end

        function fb = judge(tc, cube, sched)
            C = physics.Constants();
            S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', tc.PW_S, ...
                'bandwidth_hz', tc.BW_HZ, 'prf_hz', tc.PRF_HZ, 'cfar_pfa', 1e-4, ...
                'cfar_num_training', 20, 'cfar_num_guard', 4, 'frame_interval_s', 1.0, ...
                'carrier_hz', tc.CARRIER, 'sweep_schedule', sched);
            f = [tempname '.mat']; save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end
    end
end

function w = localWidth(power)
%LOCALWIDTH  Range bins above 10% of the compression peak.
    w = nnz(power > 0.1*max(power));
end
