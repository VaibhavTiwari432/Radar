classdef test_vee_deception_check < matlab.unittest.TestCase
%TEST_VEE_DECEPTION_CHECK  Does the VEE's generated signal actually deceive
%   the radar? Measured, across seeds, through the real unmodified judge.
%
%   DECEPTION SUCCESS is defined once, strictly, and is NOT "the tracker saw
%   something": a phantom deceives only if the judge CONFIRMS a track AND the
%   ECCM discriminator labels it "real". Detected-but-flagged is a FAILURE.
%
%   The judge here runs the CUBE path, so its Doppler/range-rate screen is a
%   real slow-time measurement, not the pre-25-July tautology that passed
%   every track it ever saw (+engine/runJudge.m's "DOPPLER IS NOW MEASURED").
%   That matters: a deception result measured under the old free pass would
%   be worth nothing.
%
%   AVOIDING A SECOND TAUTOLOGY. Rendering "genuine" and "phantom" with the
%   same function and calling the difference deception would be circular. The
%   difference here is INFORMATIONAL, and it is the real one:
%     Arm A (genuine)  reflects the radar's ACTUAL transmitted chirp -- a real
%                      aircraft returns the waveform that hit it.
%     Arm B (phantom)  never has that. The mother drone only ever holds a
%                      NOISY INTERCEPT of the radar's pulse, and must
%                      characterise and rebuild it
%                      (+features/synthesizeTxPulse.m, this project's sole
%                      synthesis path, at its established
%                      interceptNoiseAmp=2.0). Everything the judge sees about
%                      Arm B's waveform is downstream of that noisy look.
%   So A vs B measures exactly one thing: can a phantom built from an
%   imperfect intercept pass as a physical object.
%
%   Arms C and D are the adversaries the ECCM chain is supposed to catch. If
%   they were to pass too, "B passed" would mean the judge is a rubber stamp,
%   not that the phantom is good -- which is why they are in the same run.

    properties (Constant)
        PW_S     = 12e-6;
        BW_HZ    = 2e6;
        PRF_HZ   = 50e3;
        CARRIER  = 10e9;
        N_FRAMES = 8;
        N_PULSES = 32;
        N_FAST   = 400;
        R0_M     = 1800;
        V_MPS    = -60;      % closing
        AMP      = 3.0;      % this project's validated single-phantom reference level
        N_SEEDS  = 10;
        INTERCEPT_NOISE = 2.0;   % +features/synthesizeTxPulse.m's established level
    end

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_does_the_phantom_actually_deceive(tc)
            arms = {'A-genuine', 'B-vee-phantom', 'C-naive-drfm', ...
                    'D-vee-phantom-static', 'E-noise-only'};
            nA = numel(arms);
            confirmed = zeros(1, nA);
            deceived  = zeros(1, nA);
            flagged   = zeros(1, nA);
            fellBack  = 0;

            for a = 1:nA
                for seed = 1:tc.N_SEEDS
                    [cube, degraded] = tc.buildArm(arms{a}, seed);
                    fellBack = fellBack + degraded;
                    fb = tc.judge(cube);
                    isConf = fb.confirmed_tracks >= 1;
                    isReal = isConf && any(strcmp(fb.track_label, "real"));
                    confirmed(a) = confirmed(a) + isConf;
                    deceived(a)  = deceived(a)  + isReal;
                    flagged(a)   = flagged(a) + (isConf && ~isReal);
                end
            end

            fprintf('\n=== Does the VEE signal deceive the radar? (%d seeds/arm, real judge, measured Doppler) ===\n', tc.N_SEEDS);
            fprintf('%-22s %12s %12s %14s\n', 'arm', 'confirmed', 'flagged', 'DECEIVED');
            for a = 1:nA
                fprintf('%-22s %9d/%d %9d/%d %11d/%d  (%3.0f%%)\n', arms{a}, ...
                    confirmed(a), tc.N_SEEDS, flagged(a), tc.N_SEEDS, ...
                    deceived(a), tc.N_SEEDS, 100*deceived(a)/tc.N_SEEDS);
            end
            fprintf('synthesizeTxPulse structural fallbacks fired: %d (must be 0 for arms B/D to mean anything)\n\n', fellBack);

            iA = 1; iB = 2; iC = 3; iD = 4; iE = 5;

            % --- the judge must be a working judge, or nothing else counts ---
            tc.verifyEqual(deceived(iA), tc.N_SEEDS, ...
                'Arm A: the judge rejected a GENUINE target. Nothing else in this table is interpretable.');
            tc.verifyEqual(deceived(iE), 0, ...
                'Arm E: pure noise was accepted as a real track. The judge is not discriminating.');
            tc.verifyLessThan(deceived(iC), tc.N_SEEDS, ...
                'Arm C: a naive constant-gain zero-Doppler repeater passed as often as a real target -- the ECCM chain is a rubber stamp.');

            % --- the actual question, reported not gated (Rule 5) ---
            fprintf('HEADLINE: VEE phantom deceived the radar in %d/%d seeds (%.0f%%); naive DRFM %d/%d (%.0f%%).\n', ...
                deceived(iB), tc.N_SEEDS, 100*deceived(iB)/tc.N_SEEDS, ...
                deceived(iC), tc.N_SEEDS, 100*deceived(iC)/tc.N_SEEDS);
            fprintf('Static VEE phantom (kinematics removed, everything else identical): %d/%d (%.0f%%).\n\n', ...
                deceived(iD), tc.N_SEEDS, 100*deceived(iD)/tc.N_SEEDS);

            tc.verifyEqual(fellBack, 0, ...
                'synthesizeTxPulse fell back to raw replay -- arm B is not measuring feature-matched synthesis.');
        end

        function test_which_eccm_screen_is_actually_load_bearing(tc)
        %TEST_WHICH_ECCM_SCREEN_IS_ACTUALLY_LOAD_BEARING  Why the headline
        %   above is NOT evidence that single-source consistency is what
        %   deceives this radar.
        %
        %   2x2 over the only two things track.discriminator screens:
        %   Doppler present/absent x gain law correct/flat. Everything else
        %   held identical, both geometries, 10 seeds each.
        %
        %   HISTORY, kept because the fix is only meaningful against it.
        %   When first run (25 July 2026, before track/discriminator.m's
        %   "MISSING vs ABSENT" fix) this table showed EITHER screen alone
        %   was sufficient, and a phantom transmitting NO DOPPLER AT ALL
        %   passed 10/10 provided its gain ramped correctly -- a zero-Doppler
        %   track made screen 2 uninformative, the screen was dropped from
        %   the average, and the surviving screen carried the verdict. A
        %   phantom could make the evidence against it inadmissible by
        %   declining to produce it. That row is now 0/10.
        %
        %   STILL OPEN, asserted below so it stays visible: the
        %   correct-Doppler/FLAT-gain row still passes 6-8/10. That is not
        %   the same hole. Screen 1 fits log(amplitude) vs log(range) over a
        %   range change of only ~1.27x in 8 frames, which is too short a
        %   lever arm to fit a slope reliably against noise, so the combined
        %   score sits on the ">0.5" knife edge and noise decides. Fixing it
        %   means making screen 1 a better measurement, NOT making the
        %   combination rule stricter -- a genuine Swerling-1 target's own
        %   measured screen-1 score has been seen as low as 0.402, so
        %   requiring every screen to pass would flag real aircraft.
            geoms = {struct('R0',1800,'v',-60,'F',8), struct('R0',4000,'v',-150,'F',12)};
            cases = { {true, true,  'correct', 'correct 1/R^2'}, ...
                      {true, false, 'correct', 'FLAT'}, ...
                      {false,true,  'ZERO',    'correct 1/R^2'}, ...
                      {false,false, 'ZERO',    'FLAT'} };
            dec = zeros(numel(cases), numel(geoms));
            conf = zeros(numel(cases), numel(geoms));

            fprintf('\n=== Which ECCM screen is load-bearing? (10 seeds/cell) ===\n');
            fprintf('%-9s %-15s | %-18s | %-18s\n', 'Doppler', 'gain law', ...
                'R0=1800 v=-60 F=8', 'R0=4000 v=-150 F=12');
            for i = 1:numel(cases)
                for g = 1:numel(geoms)
                    [conf(i,g), dec(i,g)] = tc.run2x2(cases{i}{1}, cases{i}{2}, geoms{g});
                end
                fprintf('%-9s %-15s | %8s conf %4s | %8s conf %4s\n', cases{i}{3}, cases{i}{4}, ...
                    sprintf('%d/10 dec', dec(i,1)), sprintf('%d/10', conf(i,1)), ...
                    sprintf('%d/10 dec', dec(i,2)), sprintf('%d/10', conf(i,2)));
            end
            fprintf('\n');

            % Every cell must actually be DETECTED, or the row says nothing
            % about the discriminator. (A first attempt at this test used
            % R0=1800/v=-150/F=12, which closes to 150 m -- inside CFAR's own
            % training+guard margin -- so the track was deleted before the run
            % ended and every cell read 0/10 for a reason that had nothing to
            % do with ECCM. Geometry is checked here, not assumed.)
            tc.assertEqual(conf, repmat(tc.N_SEEDS, size(conf)), ...
                'A 2x2 cell was not confirmed at all; its label tells you nothing.');

            iBoth = 1; iDopOnly = 2; iGainOnly = 3; iNeither = 4;
            tc.verifyEqual(dec(iNeither,:), [0 0], ...
                'Failing BOTH screens still passed -- the ECCM chain is a rubber stamp.');
            tc.verifyEqual(dec(iBoth,:), [tc.N_SEEDS tc.N_SEEDS], ...
                'A fully consistent phantom was flagged.');
            % CLOSED: a zero-Doppler phantom can no longer buy a pass by
            % making screen 2 inadmissible. This is the whole point of
            % track/discriminator.m's dopplerMeasured contradiction rule --
            % if this regresses, that rule has been weakened or the
            % dopplerMeasured flag has stopped reaching the discriminator.
            tc.verifyEqual(dec(iGainOnly,:), [0 0], ...
                ['A zero-Doppler phantom with a correct gain law passed again. ' ...
                 'Check that +engine/runJudge.m still sets dopplerMeasured on ' ...
                 'the cube path and that discriminator.m still scores an ' ...
                 'unexplained missing Doppler as 0 rather than skipping it.']);

            % STILL OPEN, deliberately: correct Doppler + flat gain passes
            % 6-8/10 because screen 1's lever arm is too short to fit a
            % slope reliably (see the header). Asserted as a RANGE so the
            % weakness cannot silently disappear or silently get worse.
            openHole = sum(dec(iDopOnly,:));
            fprintf(['STILL OPEN: correct-Doppler/flat-gain phantom passes %d/%d ' ...
                     'across both geometries -- screen 1 is too weak to catch it.\n'], ...
                     openHole, 2*tc.N_SEEDS);
            tc.verifyGreaterThan(openHole, 0, ...
                'Correct-Doppler-only no longer passes at all -- screen 1 got stronger; re-document.');
            tc.verifyLessThan(openHole, 2*tc.N_SEEDS, ...
                'Correct-Doppler-only now passes every seed -- screen 1 got weaker.');
        end

    end

    % ===================== helpers =====================
    methods (Access = private)

        function [conf, dec] = run2x2(tc, doDoppler, doGainLaw, geom)
        %RUN2X2  One 2x2 cell. Built with per-frame knobs deliberately, NOT
        %   engine.entity.render -- the single-source renderer cannot emit a
        %   phantom with correct Doppler and a flat gain law, which is
        %   precisely the point of the VEE and precisely why the adversary
        %   has to be constructed outside it.
            C = physics.Constants();
            lambda = C.c / tc.CARRIER;
            chirp = tc.idealChirp();
            nominalK = tc.BW_HZ / tc.PW_S;
            slow = (0:tc.N_PULSES-1)' / tc.PRF_HZ;
            q = engine.entity.calibrateQ('Dt', 1.0, 'Dataset', tc.dataset());
            conf = 0; dec = 0;

            for seed = 1:tc.N_SEEDS
                rs = RandStream('twister', 'Seed', 1000 + seed);
                s = engine.entity.EntityState('range_m', geom.R0, 'range_rate_mps', geom.v, ...
                        'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
                cube = complex(zeros(tc.N_FAST, tc.N_PULSES, geom.F));
                for k = 1:geom.F
                    tmpl = features.synthesizeTxPulse(chirp, C.fs, nominalK, ...
                            tc.INTERCEPT_NOISE, rs, k);
                    delay = round(2*s.range_m/C.c * C.fs);
                    amp = tc.AMP;
                    if doGainLaw; amp = tc.AMP * (geom.R0 / s.range_m)^2; end
                    ph = ones(tc.N_PULSES, 1);
                    if doDoppler
                        ph = exp(1i * 2*pi * (-2*s.range_rate_mps/lambda) * slow);
                    end
                    c = complex(zeros(tc.N_FAST, tc.N_PULSES));
                    c(delay + (1:numel(tmpl)), :) = tmpl(:) * (amp * ph).';
                    cube(:,:,k) = c + tc.noise(rs);
                    s = engine.entity.propagate(s, 1.0, q, rs);
                end
                fb = tc.judge(cube);
                isConf = fb.confirmed_tracks >= 1;
                conf = conf + isConf;
                dec = dec + (isConf && any(strcmp(fb.track_label, "real")));
            end
        end

        function [cube, nFallback] = buildArm(tc, name, seed)
            C = physics.Constants();
            rs = RandStream('twister', 'Seed', 1000 + seed);
            nFallback = 0;
            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));

            if strcmp(name, 'E-noise-only')
                for k = 1:tc.N_FRAMES
                    cube(:,:,k) = tc.noise(rs);
                end
                return;
            end

            if strcmp(name, 'C-naive-drfm')
                cube = tc.buildNaiveDrfm(rs);
                return;
            end

            q = engine.entity.calibrateQ('Dt', 1.0, 'Dataset', tc.dataset());
            v = tc.V_MPS * ~strcmp(name, 'D-vee-phantom-static');
            s = engine.entity.EntityState('range_m', tc.R0_M, 'range_rate_mps', v, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);

            cleanChirp = tc.idealChirp();
            nominalK = tc.BW_HZ / tc.PW_S;
            usesIntercept = ~strcmp(name, 'A-genuine');

            for k = 1:tc.N_FRAMES
                if usesIntercept
                    % A real DRFM re-intercepts every pulse: it never gets to
                    % keep a clean copy of the radar's waveform.
                    [tmpl, degraded] = features.synthesizeTxPulse(cleanChirp, C.fs, ...
                            nominalK, tc.INTERCEPT_NOISE, rs, k);
                    nFallback = nFallback + ~isempty(degraded);
                else
                    tmpl = cleanChirp;      % a real target reflects the actual pulse
                end
                c = engine.entity.render(s, 'AmpScale', tc.AMP, 'NumPulses', tc.N_PULSES, ...
                        'FastTimeSamples', tc.N_FAST, 'CarrierHz', tc.CARRIER, ...
                        'PrfHz', tc.PRF_HZ, 'ChirpOverride', tmpl, 'RandStream', rs);
                cube(:,:,k) = c + tc.noise(rs);
                s = engine.entity.propagate(s, 1.0, q, rs);
            end
        end

        function cube = buildNaiveDrfm(tc, rs)
        %BUILDNAIVEDRFM  The pre-VEE adversary, built with the old per-frame
        %   independent knobs (+synth/synthesizeSwarm.m's delay/gain/phase):
        %   range walks, but gain is CONSTANT (no 1/R^2 law) and there is no
        %   Doppler shift at all. Both giveaways the ECCM chain screens for.
            C = physics.Constants();
            chirp = tc.idealChirp();
            cube = complex(zeros(tc.N_FAST, tc.N_PULSES, tc.N_FRAMES));
            for k = 1:tc.N_FRAMES
                R = tc.R0_M + tc.V_MPS * (k - 1);
                delay = round(2*R/C.c * C.fs);
                c = complex(zeros(tc.N_FAST, tc.N_PULSES));
                c(delay + (1:numel(chirp)), :) = chirp * (tc.AMP * ones(1, tc.N_PULSES));
                cube(:,:,k) = c + tc.noise(rs);
            end
        end

        function chirp = idealChirp(tc)
            C = physics.Constants();
            n = round(tc.PW_S * C.fs);
            t = (0:n-1)' / C.fs;
            chirp = exp(1i * pi * (tc.BW_HZ / tc.PW_S) * t.^2);
        end

        function D = dataset(tc)
            persistent cached
            if isempty(cached)
                projectRoot = fileparts(fileparts(mfilename('fullpath')));
                f = fullfile(projectRoot, 'data', 'RadChar-Tiny.h5');
                tc.assumeTrue(isfile(f), 'No data/RadChar-*.h5; see data/README.md.');
                cached = data.loadRadChar(f);
            end
            D = cached;
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
                       'frame_interval_s', 1.0, 'carrier_hz', tc.CARRIER);
            f = [tempname '.mat'];
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end
    end
end
