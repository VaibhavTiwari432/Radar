classdef test_masquerade_amplitude < matlab.unittest.TestCase
%TEST_MASQUERADE_AMPLITUDE  Phase D1: set the phantom's ERP so the radar
%   receives exactly what a real target at the CLAIMED range would give --
%   then ask whether the 1/R^2 ECCM screen is still worth anything.
%
%   A real echo falls as 1/R^4 in power (two-way). A repeater falls as
%   1/R_d^2 (one-way, from wherever the drone actually is) while claiming
%   apparent range R_i. That mismatch is the entire amplitude screen in
%   +track/discriminator.m. Until Phase B there was no absolute amplitude
%   scale in this simulation at all, so the screen was being exercised
%   against a phantom whose power law was a convention rather than a
%   physical claim.

    properties (Constant)
        TX_ERP_W   = 1e6      % 1 kW into 30 dBi (Phase B2's resolved radar)
        RCS_M2     = 1.0
        R_DRONE_M  = 1800     % where the mother drone physically is
        BUDGET_W   = 200      % GAN_PEAK_POWER_W (cogengine/planner_cem.py)

        FS_HZ = 3.2e6; PW_S = 12e-6; BW_HZ = 2e6; PRF_HZ = physics.Constants().PRF
        CARRIER = 10e9; N_FAST = 400; N_PULSES = 32
        N_SEEDS = 10
    end

    methods (Test)

        function test_d1_hits_its_verification_targets(tc)
            m24 = physics.masqueradeErp('TxErpW', tc.TX_ERP_W, 'RcsM2', tc.RCS_M2, ...
                    'JammerRangeM', tc.R_DRONE_M, 'ApparentRangeM', 2400, ...
                    'BudgetW', tc.BUDGET_W);
            m18 = physics.masqueradeErp('TxErpW', tc.TX_ERP_W, 'RcsM2', tc.RCS_M2, ...
                    'JammerRangeM', tc.R_DRONE_M, 'ApparentRangeM', 1800, ...
                    'BudgetW', tc.BUDGET_W);

            fprintf('\n[D1] P_j*G_j = P_t*G_t * sigma * R_d^2 / (4pi * R_i^4)\n');
            fprintf('[D1] at P_t*G_t = %.0e W, sigma = %.1f m^2, R_d = %.0f m:\n', ...
                tc.TX_ERP_W, tc.RCS_M2, tc.R_DRONE_M);
            fprintf('[D1]   R_i = 2400 m -> %.3f mW   (target 7.77 mW)\n', m24.required_erp_mw);
            fprintf('[D1]   R_i = 1800 m -> %.3f mW   (target 24.6 mW)\n', m18.required_erp_mw);

            tc.verifyEqual(m24.required_erp_mw, 7.77, 'RelTol', 5e-3);
            tc.verifyEqual(m18.required_erp_mw, 24.6, 'RelTol', 5e-3);
        end

        function test_d1_eirp_compliance_is_a_verified_NON_constraint(tc)
        % Reported explicitly as a non-constraint, not dressed up as a result.
            Ri = [1800 2400 3000];
            m = physics.masqueradeErp('TxErpW', tc.TX_ERP_W, 'RcsM2', tc.RCS_M2, ...
                    'JammerRangeM', tc.R_DRONE_M, 'ApparentRangeM', Ri, ...
                    'BudgetW', tc.BUDGET_W);

            fprintf('\n[D1] headroom against the %.0f W peak budget:\n', tc.BUDGET_W);
            for i = 1:numel(Ri)
                fprintf('[D1]   R_i = %4.0f m -> %8.3f mW -> %+6.1f dB headroom\n', ...
                    Ri(i), m.required_erp_mw(i), m.headroom_db(i));
            end
            fprintf(['[D1] CONCLUSION: the masquerade ERP is MILLIWATTS against a 200 W\n' ...
                     '     budget. EIRP compliance has never been a binding constraint on\n' ...
                     '     this adversary. Every published "shared power budget" result is\n' ...
                     '     a statement about the SEARCH, not about a physical power limit.\n']);

            tc.verifyGreaterThan(min(m.headroom_db), 35, ...
                'Headroom collapsed -- the non-constraint claim needs re-deriving.');
            tc.verifyEqual(m.headroom_db(2), 44.1, 'AbsTol', 0.2);   % the brief's ~44 dB
        end

        function test_d1_masquerade_reproduces_a_real_targets_amplitude_history(tc)
        % The masquerade ERP is correct iff the amplitude the radar receives
        % over a closing pass is INDISTINGUISHABLE from a real target's.
            Ri = 2400:-60:1980;          % 8 frames closing at 60 m/s
            m = physics.masqueradeErp('TxErpW', tc.TX_ERP_W, 'RcsM2', tc.RCS_M2, ...
                    'JammerRangeM', tc.R_DRONE_M, 'ApparentRangeM', Ri, ...
                    'BudgetW', tc.BUDGET_W);

            % received power at the radar, repeater one-way from R_d
            rxRepeater = m.required_erp_w ./ (4*pi * tc.R_DRONE_M^2);
            % received power from a genuine sigma-m^2 target at the same R_i
            rxGenuine  = tc.TX_ERP_W * tc.RCS_M2 ./ ((4*pi)^2 * Ri.^4);

            fprintf('\n[D1] masquerade vs genuine received power over a closing pass:\n');
            fprintf('[D1]   max relative error %.3e\n', ...
                max(abs(rxRepeater - rxGenuine) ./ rxGenuine));
            tc.verifyEqual(rxRepeater, rxGenuine, 'RelTol', 1e-12);

            % And the slope the discriminator fits is the real -4 in power
            % (-2 in amplitude), by construction rather than by convention.
            slope = polyfit(log(Ri), log(sqrt(rxGenuine)), 1);
            fprintf('[D1]   fitted log-amplitude vs log-range slope = %.4f (physical -2)\n', slope(1));
            tc.verifyEqual(slope(1), -2, 'AbsTol', 1e-9);
        end

        function test_d1_is_the_amplitude_screen_discriminating_now(tc)
        % THE QUESTION D1 ACTUALLY ASKS. Three phantoms, identical except for
        % how they set transmit power over a closing pass, all rendered at
        % Phase B's calibrated absolute amplitude scale and judged by the real
        % judge. Either answer is a real finding.
        %
        %   masquerade : ERP varied per frame so received power matches a real
        %                sigma = 1 m^2 target at the CLAIMED range (D1's formula)
        %   constant   : ERP held fixed -- what a naive DRFM does. Received
        %                power is then flat, because R_d is not changing.
        %   genuine    : an actual target, for the control.
            arms = {'genuine', 'masquerade', 'constant-ERP'};
            conf = zeros(1,3); real_ = zeros(1,3); slopes = cell(1,3);

            fprintf('\n=== D1: is the 1/R^2 screen discriminating once amplitude is calibrated? ===\n');
            fprintf('%-14s %10s %10s %14s\n', 'arm', 'confirmed', 'labelled', 'amp-vs-range');
            fprintf('%-14s %10s %10s %14s\n', '', '', 'real', 'slope');
            for a = 1:3
                [conf(a), real_(a), slopes{a}] = tc.runArm(arms{a});
                fprintf('%-14s %8d/%d %8d/%d %14.3f\n', arms{a}, ...
                    conf(a), tc.N_SEEDS, real_(a), tc.N_SEEDS, mean(slopes{a}));
            end

            fprintf(['\nREADING: the screen fits log(amplitude) vs log(range). A genuine\n' ...
                     'target and a correct masquerade both sit near the physical -2; a\n' ...
                     'constant-ERP repeater sits near 0 because its received power does not\n' ...
                     'change at all while its claimed range does.\n']);

            tc.verifyEqual(conf(1), tc.N_SEEDS, ...
                'The genuine control did not confirm -- the comparison is vacuous.');
            % The screen must catch the naive one...
            tc.verifyLessThan(real_(3), real_(1), ...
                ['A constant-ERP repeater is labelled "real" as often as a genuine ' ...
                 'target: the amplitude screen is inert.']);
            % ...and must NOT catch the correctly-masquerading one, which is
            % the honest bad news: a repeater that gets the power law right is
            % indistinguishable on amplitude, by construction.
            tc.verifyGreaterThanOrEqual(real_(2), real_(3), ...
                'A correct masquerade scored WORSE than a naive one -- re-derive D1.');
        end
    end

    methods (Access = private)

        function [nConf, nReal, slopes] = runArm(tc, arm)
            C = physics.Constants();
            lambda = C.c / tc.CARRIER;
            slow = (0:tc.N_PULSES-1)' / tc.PRF_HZ;
            F = 8; R0 = 2400; v = -40;
            Ri = R0 + v*(0:F-1);

            % Absolute amplitude, from Phase B's calibration -- what a real
            % sigma = 1 m^2 target at each range actually puts in the receiver.
            ampGenuine = arrayfun(@(r) ...
                physics.targetReturn('RangeM', r, 'RcsM2', tc.RCS_M2).sim_amplitude, Ri);

            switch arm
                case 'genuine';     amp = ampGenuine;
                case 'masquerade';  amp = ampGenuine;   % D1's ERP makes these equal
                case 'constant-ERP'
                    % Fixed ERP: received power is constant (R_d does not move),
                    % so amplitude is pinned at its first-frame value.
                    amp = repmat(ampGenuine(1), 1, F);
            end

            nConf = 0; nReal = 0; slopes = zeros(1, tc.N_SEEDS);
            chirp = tc.idealChirp();
            for seed = 1:tc.N_SEEDS
                rs = RandStream('twister', 'Seed', 7000 + seed);
                cube = complex(zeros(tc.N_FAST, tc.N_PULSES, F));
                for k = 1:F
                    delay = round(2*Ri(k)/C.c * C.fs);
                    ph = exp(1i * 2*pi * (-2*v/lambda) * slow);
                    c = complex(zeros(tc.N_FAST, tc.N_PULSES));
                    c(delay + (1:numel(chirp)), :) = chirp(:) * (amp(k) * ph).';
                    cube(:,:,k) = c + 0.05*(randn(rs,tc.N_FAST,tc.N_PULSES) + ...
                                        1i*randn(rs,tc.N_FAST,tc.N_PULSES))/sqrt(2);
                end
                fb = tc.judge(cube);
                isConf = fb.confirmed_tracks >= 1;
                nConf = nConf + isConf;
                nReal = nReal + (isConf && any(strcmp(fb.track_label, "real")));
                if isConf
                    r = fb.track_range_m{1}(:); aSeq = fb.track_amp{1}(:);
                    ok = r > 0 & aSeq > 0;
                    if nnz(ok) >= 2
                        pf = polyfit(log(r(ok)), log(aSeq(ok)), 1);
                        slopes(seed) = pf(1);
                    end
                end
            end
        end

        function fb = judge(tc, cube)
            C = physics.Constants();
            f = [tempname '.mat'];
            S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', tc.PW_S, ...
                'bandwidth_hz', tc.BW_HZ, 'prf_hz', tc.PRF_HZ, ...
                'carrier_hz', tc.CARRIER, 'frame_interval_s', 1.0);
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end

        function chirp = idealChirp(tc)
            n = round(tc.PW_S * tc.FS_HZ);
            t = (0:n-1)' / tc.FS_HZ;
            chirp = exp(1i * pi * (tc.BW_HZ / tc.PW_S) * t.^2);
        end
    end
end
