classdef test_vee_entity < matlab.unittest.TestCase
%TEST_VEE_ENTITY  Virtual Entity Engine, build steps 1 and 2.
%
%   Step 1  engine.entity.EntityState / propagate / calibrateQ
%           one propagated state, process noise NOT zero, CV threat model
%           actually held (acceleration does not wander off).
%   Step 2  engine.entity.render
%           all four observables emitted from that ONE state, and -- the
%           mission's non-negotiable -- DOPPLER INDEPENDENTLY DERIVED FROM
%           RANGE-RATE, asserted by MEASURING it out of the rendered cube
%           through the project's own radar.pulseCompress ->
%           radar.rangeDoppler chain, not by reading the source.
%
%   Why that measurement matters: before the VEE, "Doppler" was
%   diff(range)/dt on BOTH sides of this project (cogengine/radar_twin.py
%   line ~280, +engine/runJudge.m's dSeq), which makes range and Doppler the
%   same measurement and makes +track/discriminator.m's Doppler/range-rate
%   sign screen a tautology that can never fail. The decisive test here is
%   test_doppler_is_not_a_range_difference: hold range-rate FIXED and move
%   RANGE, and the measured Doppler must not move at all. Under diff(range)
%   that is impossible by construction.

    properties (Constant)
        FRAME_DT = 1.0;          % this project's established 1 Hz revisit cadence
        PW_S     = 12e-6;        % canonical radar: +engine/runJudge.m's own
        BW_HZ    = 2e6;          % matched-filter parameters
        PRF_HZ   = physics.Constants().PRF;
        CARRIER  = 10e9;         % cogengine fixtures' own X-band value
    end

    methods (TestClassSetup)
        function addProjectPath(tc)
            here = fileparts(mfilename('fullpath'));
            addpath(fileparts(here));
            tc.assumeTrue(logical(exist('engine.entity.EntityState', 'file')) || ...
                          ~isempty(which('engine.entity.EntityState')), ...
                'engine.entity package not on the path.');
        end
    end

    methods (Test)

        % ================= step 1: state + propagator =================

        function test_process_noise_is_not_zero_and_cv_holds(tc)
            % Mission's step-1 test: propagate 40 dwells. Q must not be zero
            % (a noiseless CV target is a mathematical object), but the CV
            % threat model must still hold -- acceleration stays put.
            q = tc.calibratedQ();
            s = engine.entity.EntityState('range_m', 2800, 'range_rate_mps', -40, ...
                    'class', 'fighter', 'rcs_dbsm', 0);
            rs = RandStream('twister', 'Seed', 7);

            n = 40;
            R = zeros(n,1); V = zeros(n,1); A = zeros(n,1); rcs = zeros(n,1); posDraw = zeros(n,1);
            for k = 1:n
                [s, w] = engine.entity.propagate(s, tc.FRAME_DT, q, rs);
                R(k) = s.range_m; V(k) = s.range_rate_mps;
                A(k) = s.range_accel_mps2; rcs(k) = s.rcs_dbsm; posDraw(k) = w(1);
            end

            straightLine = 2800 - 40*(1:n)';   % matches the state's -40 m/s above
            devM = max(abs(R - straightLine));
            fprintf(['[step1] 40 dwells: R_end=%.1f m  Rdot_end=%.2f m/s  ' ...
                     'Rddot_end=%.4g m/s^2\n'], R(end), V(end), A(end));
            fprintf(['[step1] max deviation from noiseless straight line = %.2f m ' ...
                     '| per-dwell position jitter std = %.3f m | RCS wander std = %.3f dB\n'], ...
                     devM, std(posDraw), std(rcs));

            % Q is genuinely nonzero: the entity is NOT on its own ideal line.
            tc.verifyGreaterThan(devM, 0, ...
                'Process noise is zero -- the entity is a mathematical object.');
            tc.verifyTrue(all(posDraw ~= 0), 'Some dwell drew exactly zero process noise.');
            % ...and amplitude is not dead flat, which +track/discriminator.m
            % scores as decoy on sight.
            tc.verifyGreaterThan(std(rcs), 0, 'RCS is dead flat -- no scintillation at all.');

            % ...but the CV threat model still holds. Acceleration is not a
            % noise-driven state in this build (calibrateQ's G(3)==0), so it
            % must be EXACTLY unchanged, and the run must stay near-straight.
            tc.verifyEqual(A, zeros(n,1), ...
                'Acceleration moved: this is no longer the declared CV threat model.');
            tc.verifyLessThan(devM, 0.05 * 2800, ...
                'Deviation exceeded 5% of initial range -- that is a maneuvering target, not "gently closing".');
        end

        function test_calibration_says_what_is_real_data_and_what_is_not(tc)
            q = tc.calibratedQ();
            % Report WHICH floor is binding, not just its value. There are now
            % two candidates -- RadChar's bench emitter and TSMS-Drone's corner
            % reflector through a real receiver -- and calibrateQ takes the
            % larger. Printing "from N RadChar records" unconditionally, as this
            % line used to, would misattribute the number whenever the target
            % echo wins (which it does: 0.491 dB vs 0.233 dB).
            fprintf(['[step1] calibrateQ: sigma_accel=%.4f m/s^2 (NOT RadChar-derived, ' ...
                     'CV knob) | rcs floor=%.4f dB source=%s ' ...
                     '(emitter %.4f from %d REAL RadChar records, target-echo %.4f)\n'], ...
                     q.sigma_accel_mps2, q.rcs_process_std_db, q.rcs_floor_source, ...
                     q.rcs_process_std_db_emitter, q.n_records, q.rcs_process_std_db_target);
            tc.verifyGreaterThan(q.rcs_process_std_db, 0);
            tc.verifyEqual(q.rcs_process_std_db, ...
                max(q.rcs_process_std_db_emitter, q.rcs_process_std_db_target), ...
                'AbsTol', 1e-12, ...
                'the binding floor must be the LARGER of the two measured floors');
            tc.verifyGreaterThanOrEqual(q.n_records, 10, ...
                'Too few real records survived the clear-pulse filter to quote a median.');
            % G(3)==0 is the CV threat model in one number -- guard it.
            tc.verifyEqual(q.G(3), 0, ...
                'G(3) is nonzero: acceleration would random-walk, leaving the CV threat model.');
        end

        % ================= step 2: single-source renderer =================

        function test_doppler_is_not_a_range_difference(tc)
            % THE non-negotiable. Measure Doppler out of the rendered cube.
            % Same range-rate, different RANGE -> measured Doppler identical.
            % Same range, different RANGE-RATE -> measured range identical.
            % Velocities chosen so BOTH the base and the doubled case stay inside
            % v_ua = 59.96 m/s (Phase 4.1). The old -60/-120 pair folded, which
            % made 'fd moved' true for the wrong reason.
            [rA, fA] = tc.measureCube(tc.renderAt(1800, -20));
            [rB, fB] = tc.measureCube(tc.renderAt(1200, -20));
            [rC, fC] = tc.measureCube(tc.renderAt(1800, -40));

            fprintf(['[step2] R=1800 v=-20 -> range %.1f m, fd %+.1f Hz\n' ...
                     '        R=1200 v=-20 -> range %.1f m, fd %+.1f Hz  (range moved, fd must not)\n' ...
                     '        R=1800 v=-40 -> range %.1f m, fd %+.1f Hz  (fd moved, range must not)\n'], ...
                     rA, fA, rB, fB, rC, fC);

            tc.verifyNotEqual(rA, rB, 'Range did not move -- the perturbation did not take.');
            tc.verifyEqual(fB, fA, ...
                'Measured Doppler changed when only RANGE moved: Doppler is still a range difference.');

            tc.verifyEqual(rC, rA, ...
                'Measured range changed when only RANGE-RATE moved: range is contaminated by velocity.');
            tc.verifyNotEqual(fC, fA, 'Doppler did not move when range-rate doubled.');

            % ...and the measured value is the physical one, to within the
            % dwell's own Doppler resolution (PRF/NumPulses).
            lambda = physics.Constants().c / tc.CARRIER;
            binHz = tc.PRF_HZ / 32;
            % Expected Doppler derived from the SAME velocity the scene was
            % rendered at, not a re-typed literal -- the literal -60 here
            % survived the Phase 4.1 retarget and silently compared against a
            % velocity nothing was rendering.
            V_A = -20;
            tc.verifyLessThanOrEqual(abs(fA - (-2*V_A/lambda)), binHz, ...
                'Measured Doppler is not within one bin of -2*Rdot/lambda.');
        end

        function test_all_four_observables_trace_to_one_state(tc)
            s = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -40, ...
                    'class', 'drone', 'rcs_dbsm', 3, 'micro_doppler_hz', 400);
            [~, obs] = engine.entity.render(s, 'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ);
            tc.verifyEqual(obs.provenance.delay_samples,    'range_m');
            tc.verifyEqual(obs.provenance.doppler_hz,       'range_rate_mps');
            tc.verifyEqual(obs.provenance.amplitude,        'rcs_dbsm+range_m');
            tc.verifyEqual(obs.provenance.micro_doppler_hz, 'class+micro_doppler_hz');

            % A class not expected to show blade flash gets none, whatever
            % the state field says -- the render never fabricates it.
            sf = s; sf.class = 'fighter';
            [~, of] = engine.entity.render(sf, 'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ);
            tc.verifyEqual(of.micro_doppler_hz, 0, ...
                'A fighter was rendered with rotor blade flash.');
        end

        function test_amplitude_obeys_the_two_way_law(tc)
            mk = @(R) engine.entity.EntityState('range_m', R, 'range_rate_mps', -40, ...
                        'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            [~, o1] = engine.entity.render(mk(1000));
            [~, o2] = engine.entity.render(mk(2000));
            % amplitude ~ sqrt(RCS)/R^2 -> doubling range quarters amplitude
            tc.verifyEqual(o1.amplitude / o2.amplitude, 4, 'RelTol', 1e-12, ...
                'Amplitude does not follow the 1/R^2 voltage law.');
        end

        function test_micro_doppler_renders_but_needs_a_long_cpi_to_see(tc)
            % Observability limit, recorded rather than claimed away, and REVISED in
            % Phase 4.1 -- how much of the blade flash this project’s
            % default 32-pulse dwell can resolve depends entirely on the PRF.
            bladeHz = 400;
            s = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -40, ...
                    'class', 'drone', 'rcs_dbsm', 0, 'swerling', 0, 'micro_doppler_hz', bladeHz);

            % PHASE 4.1 -- THIS DOCUMENTED LIMIT HAS MOVED, IN THE GOOD
            % DIRECTION. Doppler resolution is PRF/N. At the old (non-physical)
            % 50 kHz that was 1562 Hz at the default 32-pulse dwell, coarser
            % than any blade rate. At the corrected 8 kHz it is 250 Hz, so a
            % 400 Hz blade rate IS now resolvable in the default dwell -- the
            % first time this project's standard dwell could see micro-Doppler
            % at all. The 100-200 Hz band MEASURED from TSMS-Drone still is
            % not, so the limit is narrowed rather than removed.
            binDefault = tc.PRF_HZ / 32;
            fprintf(['[step2] micro-Doppler %g Hz vs default-dwell resolution %.0f Hz ' ...
                     '-> RESOLVABLE at 32 pulses (needs >= %d)\n'], ...
                     bladeHz, binDefault, ceil(tc.PRF_HZ / bladeHz));
            fprintf(['[step2] at the OLD 50 kHz this bin was 1562 Hz; the corrected PRF\n' ...
                     '        made the default dwell 6.25x finer in Doppler.\n']);
            tc.verifyLessThan(binDefault, bladeHz, ...
                ['A 400 Hz blade rate should now be resolvable at the default dwell ' ...
                 '(PRF/32 = 250 Hz). If not, the PRF moved -- re-derive this limit.']);
            % ...but the MEASURED 100-200 Hz band still is not, at 32 pulses.
            tc.verifyGreaterThan(binDefault, 200, ...
                ['The 100-200 Hz MEASURED blade band should still be unresolvable at ' ...
                 'the default dwell -- that half of the limit stands.']);

            % At a CPI long enough to resolve it, the sidebands are really there.
            nLong = 512;
            cube = engine.entity.render(s, 'NumPulses', nLong, 'CarrierHz', tc.CARRIER, ...
                        'PrfHz', tc.PRF_HZ, 'RandStream', RandStream('twister','Seed',5));
            row = cube(cube(:,1) ~= 0, :);            % any range row holding the pulse
            spec = abs(fftshift(fft(row(1,:)))).^2;
            fAxis = ((0:nLong-1) - floor(nLong/2)) / nLong * tc.PRF_HZ;
            lambda = physics.Constants().c / tc.CARRIER;
            fd = -2*s.range_rate_mps/lambda;   % from the state, never re-typed

            main = tc.nearestBinPower(spec, fAxis, fd);
            sbHi = tc.nearestBinPower(spec, fAxis, fd + bladeHz);
            sbLo = tc.nearestBinPower(spec, fAxis, fd - bladeHz);
            floorPow = median(spec);
            fprintf(['[step2] %d-pulse CPI: main %.3g | sidebands %.3g / %.3g | ' ...
                     'noise-floor median %.3g\n'], nLong, main, sbLo, sbHi, floorPow);

            tc.verifyGreaterThan(sbHi, 100*floorPow, 'Upper micro-Doppler sideband absent.');
            tc.verifyGreaterThan(sbLo, 100*floorPow, 'Lower micro-Doppler sideband absent.');

            % DELIBERATELY NOT ASSERTED: "sideband < main". That used to be
            % here, and it was an artefact of the old AM model
            % (1 + 0.3*cos(...)), whose sidebands are 0.15 of the carrier by
            % construction. Micro-Doppler is PHASE modulation, so by
            % Jacobi-Anger the line amplitudes are J_n(beta) -- and J_0 has a
            % zero at beta = 2.405, so a realistic rotor SUPPRESSES its own
            % carrier below its sidebands. Measured here: beta = 2.02,
            % J_0^2 = 0.044 against J_1^2 = 0.331, i.e. the first sideband is
            % ~7.5x the carrine line. Re-adding that assertion would be
            % asserting the old model back into existence.
        end

        function test_micro_doppler_is_a_bessel_comb_not_two_sidebands(tc)
            % The micro-Doppler model is derived, so it is testable against
            % the derivation rather than against a tuned constant.
            % exp(i*beta*sin(w t)) = SUM_n J_n(beta) exp(i n w t), so the
            % line at n*f_blade must carry power proportional to J_n(beta)^2.
            % Grounding: beta and the 100-200 Hz blade band are MEASURED from
            % TSMS-Drone (see +engine/+entity/render.m's header).
            bladeHz = 150;
            s = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -40, ...
                    'class', 'drone', 'rcs_dbsm', 0, 'swerling', 0, ...
                    'micro_doppler_hz', bladeHz);
            nLong = 1024;
            [cube, obs] = engine.entity.render(s, 'NumPulses', nLong, ...
                        'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ, ...
                        'RandStream', RandStream('twister','Seed',5));
            row = cube(cube(:,1) ~= 0, :); row = row(1,:);
            % Hann window: without it, spectral leakage from the rectangular
            % record floors the weak outer lines and the J_n comparison below
            % measures the window, not the model.
            spec = abs(fftshift(fft(row(:) .* hann(nLong)))).^2;
            fAxis = ((0:nLong-1) - floor(nLong/2)) / nLong * tc.PRF_HZ;
            lambda = physics.Constants().c / tc.CARRIER;
            fd = -2*s.range_rate_mps/lambda;   % from the state, never re-typed

            b = obs.micro_beta;
            tc.verifyGreaterThan(b, 0.5, 'modulation index collapsed -- blade_tip_mps lost?');
            A = tc.nearestBinPower(spec, fAxis, fd) / besselj(0,b)^2;

            fprintf('[step2] beta = %.3f (v_tip %.2f m/s, f_blade %g Hz)\n', ...
                b, obs.blade_tip_mps, bladeHz);
            for n = 0:2
                meas = tc.nearestBinPower(spec, fAxis, fd + n*bladeHz);
                theo = besselj(n,b)^2 * A;
                fprintf('   n=%d  measured %.4g  J_n^2*A %.4g  ratio %.3f\n', ...
                    n, meas, theo, meas/theo);
                tc.verifyEqual(meas/theo, 1, 'RelTol', 0.30, sprintf( ...
                    ['micro-Doppler line n=%d does not follow J_n(beta)^2 -- the comb ' ...
                     'is not the Jacobi-Anger expansion render.m claims to emit'], n));
            end

            % A single-cosine AM model produces exactly two sidebands. The
            % whole point of the change is that a real rotor produces many.
            nLines = sum(spec > 0.01*max(spec));
            fprintf('   lines above 1%% of peak: %d\n', nLines);
            tc.verifyGreaterThan(nLines, 4, ...
                'comb has too few lines -- looks like the old 2-sideband AM model');
        end

    end

    % ===================== helpers =====================
    methods (Access = private)

        function q = calibratedQ(tc)
            here = fileparts(mfilename('fullpath'));
            projectRoot = fileparts(here);
            f = fullfile(projectRoot, 'data', 'RadChar-Tiny.h5');
            tc.assumeTrue(isfile(f), ...
                'No data/RadChar-*.h5 found. See data/README.md to download it.');
            q = engine.entity.calibrateQ('Dt', tc.FRAME_DT, 'RadCharFile', f);
        end

        function cube = renderAt(tc, R, v)
            s = engine.entity.EntityState('range_m', R, 'range_rate_mps', v, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            cube = engine.entity.render(s, 'CarrierHz', tc.CARRIER, 'PrfHz', tc.PRF_HZ, ...
                    'PulseWidth', tc.PW_S, 'Bandwidth', tc.BW_HZ, ...
                    'RandStream', RandStream('twister', 'Seed', 11));
        end

        function [rangeEst, dopplerEst] = measureCube(tc, cube)
        %MEASURECUBE  Range and Doppler read out of the cube through the
        %   project's OWN validated radar blocks -- no engine-side shortcut.
            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate', C.fs, 'PulseWidth', tc.PW_S, ...
                    'PRF', tc.PRF_HZ, 'SweepBandwidth', tc.BW_HZ);
            nP = size(cube, 2);
            yc = complex(zeros(size(cube)));
            for p = 1:nP
                [~, yc(:,p)] = radar.pulseCompress(cube(:,p), wav);
            end
            [rd, rangeAxis, dopAxis] = radar.rangeDoppler(yc, wav, C);
            [~, li] = max(rd(:));
            [ri, di] = ind2sub(size(rd), li);
            rangeEst = rangeAxis(ri);
            dopplerEst = dopAxis(di);
        end

        function p = nearestBinPower(~, spec, axisHz, targetHz)
            [~, i] = min(abs(axisHz - targetHz));
            p = spec(i);
        end
    end
end
