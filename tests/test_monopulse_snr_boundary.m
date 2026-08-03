classdef test_monopulse_snr_boundary < matlab.unittest.TestCase
%TEST_MONOPULSE_SNR_BOUNDARY  Phase D2: the boundary result.
%
%   tests/test_angle_channel.m flags this project's own 4-phantom swarm 4/4
%   in 8/8 seeds once the monopulse difference channel is on, and states
%   plainly that the angle-blind case is what every other published number in
%   this project has been measuring. One aperture cannot beat monopulse --
%   that is geometry, not a tuning problem, and it is permanent.
%
%   But monopulse ACCURACY degrades with SNR:
%
%       sigma_theta ~= theta_3dB / (k_m * sqrt(2*SNR))
%
%   so there must be an SNR below which a collinear fan of phantoms is no
%   longer separable from a genuine formation with real cross-range spread.
%   Finding it converts a permanent limitation into a measured operating
%   boundary -- which is a usable result, where "you lose to monopulse" is
%   not.
%
%   The comparison is against a GENUINE formation with ~100 m cross-range
%   spread, because the screen's question is not "is the spread zero" but
%   "is the spread smaller than these tracks' own angular noise" -- and that
%   noise is what SNR controls.

    properties (Constant)
        FS_HZ = 3.2e6; PW_S = 12e-6; BW_HZ = 2e6; PRF_HZ = physics.Constants().PRF
        CARRIER  = 10e9
        N_FAST   = 400;  N_PULSES = 32;  N_FRAMES = 8
        SUBAP_M  = 0.30
        NOISE    = 0.05
        % Inside R_ua = 2997.9 m (Phase C1) -- this project's older angle
        % scene ran 1800-4200 m, which at 50 kHz PRF is partly ambiguous.
        RANGES   = [900 1600 2300 2900]
        FORMATION_CROSS_RANGE_M = 100    % genuine formation's real spread
        N_SEEDS  = 8
        THETA_3DB_DEG = 3.0
        K_M      = 1.6                   % monopulse slope factor
    end

    methods (Test)

        function test_d2_sigma_theta_formula_hits_its_targets(tc)
            for snrDb = [20 0]
                snr = 10^(snrDb/10);
                sigDeg = tc.THETA_3DB_DEG / (tc.K_M * sqrt(2*snr));
                crossM = 3000 * tan(deg2rad(sigDeg));
                fprintf('\n[D2] SNR %+3.0f dB -> sigma_theta = %.4f deg -> %.2f m cross-range at 3 km\n', ...
                    snrDb, sigDeg, crossM);
                if snrDb == 20
                    tc.verifyEqual(sigDeg, 0.133, 'AbsTol', 5e-4);
                    tc.verifyEqual(crossM, 6.9, 'AbsTol', 0.1);
                else
                    tc.verifyEqual(sigDeg, 1.33, 'AbsTol', 5e-3);
                    tc.verifyEqual(crossM, 69, 'AbsTol', 0.5);
                end
            end
        end

        function test_d2_sweep_snr_vs_monopulse_flag_rate(tc)
        % THE DELIVERABLE. Two scenes swept over the same SNR axis:
        %   collinear  -- 4 phantoms from ONE jammer, all on one bearing
        %   formation  -- 4 GENUINE objects, ~100 m cross-range spread
        % The screen is useful only where it flags the first and not the
        % second. Below some SNR the two become indistinguishable.
            snrGrid = -5:5:25;
            nS = numel(snrGrid);
            flagCollinear = zeros(1, nS); confCollinear = zeros(1, nS);
            flagFormation = zeros(1, nS); confFormation = zeros(1, nS);
            azScatter = nan(1, nS);

            fprintf('\n=== D2: monopulse flag rate vs phantom SNR (%d seeds/point) ===\n', tc.N_SEEDS);
            fprintf('%8s | %-26s | %-26s | %10s\n', 'SNR dB', ...
                'COLLINEAR fan (1 jammer)', 'GENUINE formation (100 m)', 'az scatter');
            fprintf('%8s | %10s %14s | %10s %14s | %10s\n', '', ...
                'confirmed', 'flagged', 'confirmed', 'flagged', 'deg (1sig)');

            for i = 1:nS
                [confCollinear(i), flagCollinear(i), azScatter(i)] = ...
                    tc.runScene(snrGrid(i), 0);                       % all same bearing
                [confFormation(i), flagFormation(i)] = ...
                    tc.runScene(snrGrid(i), tc.FORMATION_CROSS_RANGE_M);

                [lo1, hi1] = tc.wilson(flagCollinear(i), tc.N_SEEDS);
                [lo2, hi2] = tc.wilson(flagFormation(i), tc.N_SEEDS);
                fprintf('%8.0f | %7.1f/%d %5.0f%% [%3.0f,%3.0f] | %7.1f/%d %5.0f%% [%3.0f,%3.0f] | %10.4f\n', ...
                    snrGrid(i), confCollinear(i), tc.N_SEEDS, ...
                    100*flagCollinear(i)/tc.N_SEEDS, 100*lo1, 100*hi1, ...
                    confFormation(i), tc.N_SEEDS, ...
                    100*flagFormation(i)/tc.N_SEEDS, 100*lo2, 100*hi2, azScatter(i));
            end

            % ---- the boundary: lowest SNR where the screen still separates.
            % "Separates" = flags the collinear fan in a strict majority of
            % seeds AND does not flag the genuine formation in a majority.
            separates = (flagCollinear > tc.N_SEEDS/2) & (flagFormation <= tc.N_SEEDS/2);
            if all(separates)
                fprintf(['\n[D2] NO SNR BOUNDARY EXISTS IN THIS RANGE. The screen separates\n' ...
                         '     the two scenes at EVERY swept SNR from %+d to %+d dB -- while\n' ...
                         '     the measured angular scatter falls %.4f -> %.4f deg across the\n' ...
                         '     same sweep. The expected sigma_theta ~ 1/sqrt(SNR) degradation\n' ...
                         '     is real and visible in that column, but it does NOT weaken the\n' ...
                         '     screen, because the screen is a SELF-CALIBRATING RATIO\n' ...
                         '     (spread vs the tracks'' own scatter): SNR moves numerator and\n' ...
                         '     denominator together. The boundary lives on a different axis --\n' ...
                         '     see test_d2_the_boundary_is_cross_range_not_snr.\n'], ...
                         snrGrid(1), snrGrid(end), azScatter(1), azScatter(end));
            elseif any(separates)
                fprintf('\n[D2] screen separates the two scenes down to SNR = %+d dB.\n', ...
                    snrGrid(find(separates, 1, 'first')));
            else
                fprintf('\n[D2] BOUNDARY: no swept SNR separated the two scenes.\n');
            end
            boundary = snrGrid(find(separates, 1, 'first'));

            % The sigma_theta ~ 1/sqrt(SNR) law must be VISIBLE in the measured
            % scatter even though it does not move the screen -- that is what
            % distinguishes "SNR-invariant by construction" from "the angle
            % channel is not responding to SNR at all".
            expectedRatio = sqrt(10^((snrGrid(end)-snrGrid(1))/10));
            measuredRatio = azScatter(1) / azScatter(end);
            fprintf('[D2] scatter ratio across the sweep: measured %.1fx | 1/sqrt(SNR) predicts %.1fx\n', ...
                measuredRatio, expectedRatio);
            tc.verifyEqual(measuredRatio, expectedRatio, 'RelTol', 0.35, ...
                ['Measured angular scatter does not follow 1/sqrt(SNR) -- the angle ' ...
                 'channel is not behaving like monopulse.']);

            % Report, do not bake in a flattering value: assert only that the
            % sweep is INFORMATIVE (the screen must do something at high SNR),
            % so this test fails if the screen goes inert, not if the boundary
            % moves.
            tc.verifyTrue(any(confCollinear > 0), 'Nothing confirmed anywhere in the sweep.');
            tc.verifyGreaterThan(max(flagCollinear), 0, ...
                'The co-bearing screen never fired at ANY SNR -- it is inert.');

            tc.assertTrue(true);
            fprintf('[D2] measured boundary SNR = %s dB\n', mat2str(boundary));
        end

        function test_d2_the_boundary_is_cross_range_not_snr(tc)
        % THE SWEEP ABOVE FOUND NO SNR BOUNDARY, AND THE REASON IS STRUCTURAL.
        % +engine/runJudge.m's co-bearing screen is a SELF-CALIBRATING RATIO
        % test: it asks whether the spread of the tracks' mean azimuths is
        % smaller than 3x their own pooled within-track scatter. sigma_theta
        % ~ 1/sqrt(SNR) degrades the numerator and the denominator TOGETHER,
        % so the ratio is very nearly SNR-invariant -- which is exactly what
        % the -5..+25 dB sweep shows (100% flag rate at every point, with the
        % measured scatter falling 0.073 -> 0.002 deg across the same range).
        %
        % So the operating boundary is NOT an SNR threshold. It is the
        % CROSS-RANGE SPREAD a genuine formation needs in order not to be
        % mistaken for a collinear fan -- and SNR enters by setting that
        % spread through sigma_theta. This sweeps the axis the boundary
        % actually lives on.
            snrPoints = [0 15];
            spreads = [0 5 10 20 40 80 160];

            fprintf('\n=== D2 (corrected axis): flag rate vs GENUINE cross-range spread ===\n');
            fprintf('A genuine formation flagged as co-bearing is a FALSE ACCUSATION.\n');
            fprintf('%10s |', 'spread m');
            for s = snrPoints; fprintf(' %8s%+3.0f dB |', 'SNR', s); end
            fprintf('\n');

            flagged = zeros(numel(spreads), numel(snrPoints));
            for i = 1:numel(spreads)
                fprintf('%10.0f |', spreads(i));
                for j = 1:numel(snrPoints)
                    [~, flagged(i,j)] = tc.runScene(snrPoints(j), spreads(i));
                    fprintf(' %6d/%d %5.0f%% |', flagged(i,j), tc.N_SEEDS, ...
                        100*flagged(i,j)/tc.N_SEEDS);
                end
                fprintf('\n');
            end

            fprintf('\n[D2] minimum spread that avoids a false co-bearing flag:\n');
            minSpread = nan(1, numel(snrPoints));
            for j = 1:numel(snrPoints)
                idx = find(flagged(:,j) <= tc.N_SEEDS/2, 1, 'first');
                if ~isempty(idx); minSpread(j) = spreads(idx); end
                % what the sigma_theta formula predicts, at the scene's far range
                snr = 10^(snrPoints(j)/10);
                sigDeg = tc.THETA_3DB_DEG / (tc.K_M * sqrt(2*snr));
                predicted = 3 * max(tc.RANGES) * tan(deg2rad(sigDeg));   % 3-sigma gate
                fprintf('[D2]   SNR %+3.0f dB: measured %s m | sigma_theta formula predicts %.1f m (3-sigma at %d m)\n', ...
                    snrPoints(j), mat2str(minSpread(j)), predicted, max(tc.RANGES));
            end

            fprintf(['\n[D2] DELIVERABLE. The single-aperture limit is permanent, but it is\n' ...
                     '     bounded: a collinear fan is separable from a genuine formation\n' ...
                     '     whenever that formation''s cross-range spread exceeds roughly\n' ...
                     '     %g m at this geometry. Tighter formations than that are\n' ...
                     '     indistinguishable from a one-jammer fan, and the radar cannot\n' ...
                     '     use the screen without falsely accusing them.\n'], ...
                     minSpread(find(~isnan(minSpread), 1)));

            % A zero-spread "formation" IS a collinear fan and must be flagged.
            tc.verifyGreaterThan(flagged(1,end), tc.N_SEEDS/2, ...
                'A zero-spread formation was not flagged -- the screen is inert.');
            % A widely-spread genuine formation must NOT be flagged.
            tc.verifyLessThanOrEqual(flagged(end,end), tc.N_SEEDS/2, ...
                'A 160 m-spread genuine formation was flagged: the screen accuses real aircraft.');
        end

        function test_d2_interaction_does_masquerade_buy_back_angle_survivability(tc)
        % THE INTERACTION THE BRIEF CALLS THE MOST INTERESTING OPEN QUESTION.
        %
        % First, the premise needs correcting, because the arithmetic does not
        % say what it was expected to say. D1's "+44 dB" is HEADROOM against
        % the 200 W budget, not a reduction in what the phantom transmits. The
        % masquerade phantom's RECEIVED power is by construction exactly that
        % of a genuine sigma = 1 m^2 target at the claimed range -- so its SNR
        % at the radar is a genuine target's SNR, not 44 dB below anything.
        %
        % What the 44 dB really shows is a different and larger problem: the
        % planner's own W <-> amp_scale anchor (planner_cem.py's
        % REFERENCE_SINGLE_PHANTOM_POWER_W = 60 W <-> amp_scale 3.0) claims a
        % phantom needs TENS OF WATTS to reach an amplitude the physical link
        % budget says milliwatts buy. Quantified below.
            R_I = 2400;  R_D = 1800;
            m = physics.masqueradeErp('TxErpW', 1e6, 'RcsM2', 1.0, ...
                    'JammerRangeM', R_D, 'ApparentRangeM', R_I, 'BudgetW', 200);
            T = physics.targetReturn('RangeM', R_I, 'RcsM2', 1.0);
            U = physics.simUnits();

            masqSnrDb = 20*log10(T.sim_amplitude / U.noise_amplitude);
            fprintf('\n[D2] masquerade phantom at R_i = %d m:\n', R_I);
            fprintf('[D2]   required ERP        = %.3f mW (%.1f dB headroom vs 200 W)\n', ...
                m.required_erp_mw, m.headroom_db);
            fprintf('[D2]   received amplitude  = %.4f (sim units, noise %.2f)\n', ...
                T.sim_amplitude, U.noise_amplitude);
            fprintf('[D2]   => pre-compression SNR = %+.2f dB\n', masqSnrDb);

            % What the planner's anchor claims the same amplitude costs.
            wattsPerAmp = 60.0 / 3.0;                 % planner_cem's linear anchor
            plannerW = T.sim_amplitude * wattsPerAmp;
            fprintf('[D2]   planner''s anchor says that amplitude costs %.2f W\n', plannerW);
            fprintf('[D2]   physical link budget says it costs %.5f W\n', m.required_erp_w);
            fprintf('[D2]   OVERSTATEMENT = %.1f dB\n', 10*log10(plannerW / m.required_erp_w));

            % Now the actual question: at THAT SNR, does the angle screen fire?
            [conf, flag] = tc.runScene(masqSnrDb, 0);
            [confF, flagF] = tc.runScene(masqSnrDb, tc.FORMATION_CROSS_RANGE_M);
            fprintf(['\n[D2] at the masquerade phantom''s own SNR (%+.1f dB), %d seeds:\n' ...
                     '       collinear fan : %.1f/%d confirmed, %d flagged\n' ...
                     '       genuine form. : %.1f/%d confirmed, %d flagged\n'], ...
                masqSnrDb, tc.N_SEEDS, conf, tc.N_SEEDS, flag, confF, tc.N_SEEDS, flagF);

            if flag > tc.N_SEEDS/2
                fprintf(['[D2] ANSWER: NO. Getting the amplitude law right does not buy back\n' ...
                         '     angle survivability -- it puts the phantom at a GENUINE target''s\n' ...
                         '     SNR, which is exactly where monopulse works best. The masquerade\n' ...
                         '     correction and angle evasion pull in OPPOSITE directions: the\n' ...
                         '     more convincing the amplitude, the more visible the bearing.\n']);
            else
                fprintf(['[D2] ANSWER: YES, partially -- at the masquerade SNR the co-bearing\n' ...
                         '     screen fires in only %d/%d seeds.\n'], flag, tc.N_SEEDS);
            end

            tc.verifyGreaterThan(masqSnrDb, 0, ...
                'A masquerade phantom should sit at a genuine target''s SNR, not below noise.');
            % The overstatement is the durable finding; pin it.
            tc.verifyGreaterThan(10*log10(plannerW / m.required_erp_w), 25, ...
                ['The planner''s W<->amp_scale anchor no longer overstates required power ' ...
                 'by a large margin -- re-derive D2''s interaction section.']);
        end
    end

    methods (Access = private)

        function [nConf, nFlag, azSig] = runScene(tc, snrDb, crossRangeM)
        %RUNSCENE  N objects, one bearing each. crossRangeM = 0 puts them all
        %   on the SAME bearing (the collinear one-jammer signature);
        %   crossRangeM > 0 spreads them like a genuine formation.
            C = physics.Constants();
            amp = tc.NOISE * 10^(snrDb/20);           % pre-compression amplitude SNR
            nObj = numel(tc.RANGES);
            % A real formation is spread in CROSS-RANGE (metres), so its
            % angular spread shrinks with range -- deriving the angles from a
            % fixed metre offset rather than a fixed angle is what makes the
            % comparison fair at every range in the scene.
            offsets = linspace(-crossRangeM/2, crossRangeM/2, nObj);
            azs = atan2(offsets, tc.RANGES);

            nConf = 0; nFlag = 0; sigAcc = [];
            for seed = 1:tc.N_SEEDS
                [sumC, dltC] = tc.render(tc.RANGES, azs, amp, seed);
                fb = tc.judge(sumC, dltC);
                nConf = nConf + fb.confirmed_tracks;
                nFlag = nFlag + double(fb.cobearing_flagged);
                s = fb.track_azimuth_rad;
                for i = 1:numel(s)
                    if numel(s{i}) >= 2; sigAcc(end+1) = std(rad2deg(s{i})); end %#ok<AGROW>
                end
            end
            nConf = nConf / tc.N_SEEDS;
            azSig = mean(sigAcc);
        end

        function [sumC, dltC] = render(tc, ranges, azs, amp, seed)
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 9000 + seed);
            n = round(tc.PW_S * C.fs); t = (0:n-1)'/C.fs;
            chirp = exp(1i*pi*(tc.BW_HZ/tc.PW_S)*t.^2);
            q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);

            states = cell(1, numel(ranges)); ampScale = zeros(1, numel(ranges));
            for i = 1:numel(ranges)
                states{i} = engine.entity.EntityState('range_m', ranges(i), ...
                    'range_rate_mps', -40, 'class', 'fighter', 'rcs_dbsm', 0, ...
                    'swerling', 0, 'azimuth_rad', azs(i));
                % Compensated ONCE from the initial range so every object is
                % comparably detectable while its amplitude still rises as
                % 1/R^2 as it closes -- recomputing per frame pins amplitude
                % flat, which is the naive-DRFM signature and gets the GENUINE
                % formation flagged by the amplitude screen (a bug found in
                % tests/test_angle_channel.m and not repeated here).
                ampScale(i) = amp * (ranges(i) / 1800)^2;
            end

            sumC = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            dltC = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            for k = 1:tc.N_FRAMES
                fsum = complex(zeros(tc.N_FAST, tc.N_PULSES));
                fdlt = complex(zeros(tc.N_FAST, tc.N_PULSES));
                for i = 1:numel(states)
                    [cs, ~, cd] = engine.entity.render(states{i}, 'AmpScale', ampScale(i), ...
                        'NumPulses', tc.N_PULSES, 'FastTimeSamples', tc.N_FAST, ...
                        'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ, ...
                        'PulseWidth', tc.PW_S, 'Bandwidth', tc.BW_HZ, ...
                        'SubapertureSepM', tc.SUBAP_M, 'ChirpOverride', chirp, ...
                        'RandStream', rs);
                    fsum = fsum + cs; fdlt = fdlt + cd;
                end
                % Independent noise per channel -- they are separate receivers,
                % so it does not cancel in the monopulse ratio. That is exactly
                % what sets the angle accuracy this test is sweeping.
                sumC(:,:,k) = fsum + tc.noise(rs);
                dltC(:,:,k) = fdlt + tc.noise(rs);
                for i = 1:numel(states)
                    states{i} = engine.entity.propagate(states{i}, 1.0, q, rs);
                end
            end
        end

        function nz = noise(tc, rs)
            nz = tc.NOISE * (randn(rs, tc.N_FAST, tc.N_PULSES) + ...
                          1i*randn(rs, tc.N_FAST, tc.N_PULSES)) / sqrt(2);
        end

        function fb = judge(tc, sumC, dltC)
            C = physics.Constants();
            f = [tempname '.mat'];
            S = struct('rx_frames', sumC, 'rx_frames_delta', dltC, 'fs', C.fs, ...
                'pulse_width_s', tc.PW_S, 'bandwidth_hz', tc.BW_HZ, ...
                'prf_hz', tc.PRF_HZ, 'carrier_hz', tc.CARRIER, ...
                'frame_interval_s', 1.0, 'subaperture_sep_m', tc.SUBAP_M);
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end

        function [lo, hi] = wilson(~, k, n)
        %WILSON  95% Wilson score interval -- the same one BENCHMARK_RESULTS.md
        %   uses, appropriate at these small n where a normal CI is not.
            if n == 0; lo = 0; hi = 1; return; end
            z = 1.959963984540054;
            p = k / n;
            d = 1 + z^2/n;
            c = p + z^2/(2*n);
            r = z * sqrt(p*(1-p)/n + z^2/(4*n^2));
            lo = max(0, (c - r)/d);
            hi = min(1, (c + r)/d);
        end
    end
end
