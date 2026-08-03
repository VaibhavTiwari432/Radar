classdef test_radchar_three_arm < matlab.unittest.TestCase
%TEST_RADCHAR_THREE_ARM  Task 5 (PHASE2_COMPLETION_POA.md): validate the
%   synthesis pipeline against REAL intercepted pulses (Kaggle RadChar,
%   verified schema via +data/loadRadChar.m -- 50,000 signals, 5 waveform
%   classes, 10,000 each, SNR in [-20,20] dB), not just synthetic chirps.
%
%   Built entirely in MATLAB, reusing already-validated code rather than a
%   parallel Python loader: +data/loadRadChar.m (data), +features/* (Arm B
%   synthesis), +synth/synthesizeSwarm.m (delay/gain/phase), +engine/runJudge.m
%   (the real judge, unmodified). No new package duplicates what already
%   works and is tested.
%
%   Three arms per sampled REAL pulse, same canonical kinematics (R0=1800m,
%   v=-60 m/s closing, 8 frames @ 1 Hz -- this project's own validated
%   scene) so kinematics never confounds the comparison:
%     A. GENUINE  -- the raw real RadChar pulse itself, as if a real target
%                     genuinely reflected exactly this real-world waveform.
%     B. PHANTOM  -- features.characterizeInterceptDechirp + coherentReplica
%                     run on the SAME real pulse (treated as the noisy
%                     intercept), i.e. exactly this project's feature-matched
%                     synthesis pipeline, on REAL data instead of a synthetic
%                     chirp for the first time.
%     C. NEGATIVE CONTROL -- structureless complex noise, no pulse at all
%                     (Stage3_Test.m's own "noise almost never confirms"
%                     pattern, reused not reinvented).
%
%   NO CHERRY-PICKING (mission ask): sampled across all 5 RadChar classes,
%   even though this project's judge matched-filters against a FIXED LFM
%   template (+physics/Constants.m-derived, this project's OWN radar is
%   LFM-only -- CEMConfig's own comment in planner_cem.py already
%   establishes there is no wclass variation this project's radar
%   responds to). Non-LFM classes are EXPECTED to show near-zero
%   confirmation for BOTH Arm A and Arm B -- not a deception result, a
%   waveform-mismatch-against-a-fixed-matched-filter result. Both are
%   reported, not hidden; only the LFM row is a meaningful "believable
%   phantom" A-vs-B comparison for THIS project's radar.
%
%   BOUNDARY STATEMENT (state in every report that uses these numbers):
%   waveform physics (pulse shape/modulation) is grounded in REAL RadChar
%   data; kinematics (range/velocity trajectory) remain from this
%   project's synthetic truth model, exactly as +data/README.md's own
%   "ground-truth ranges come from the native phased.* scenes" note says.

    methods (TestClassSetup)
        function requireData(tc)
            here = fileparts(mfilename('fullpath'));
            projectRoot = fileparts(here);
            addpath(projectRoot);
            tc.assumeTrue(isfile(fullfile(projectRoot, 'data', 'RadChar-Tiny.h5')), ...
                'No data/RadChar-*.h5 found. See data/README.md to download it.');
        end
    end

    methods (Test)

        function test_three_arm_per_class(tc)
            C = physics.Constants();
            here = fileparts(mfilename('fullpath'));
            projectRoot = fileparts(here);
            D = data.loadRadChar(fullfile(projectRoot, 'data', 'RadChar-Tiny.h5'));

            nPerClass = 5;
            rng(2026);   % reproducible sample selection
            classNames = {'CoherentPulseTrain','Barker','PolyBarker','Frank','LFM'};

            R0 = 1800; vClose = 40; ampRef = 3.0; F = 8; frameDt = 1.0;
            bufferLen = 400;
            nominalK = 2e6 / 12e-6;   % this project's OWN LFM nominal (+physics/Constants.m-derived elsewhere)

            rows = struct('wclass', {}, 'n', {}, 'confirmedA', {}, 'confirmedB', {}, 'rejectedC', {}, 'cFailures', {});

            for cls = 0:4
                classIdx = find(D.signal_type == cls);
                pick = classIdx(randperm(numel(classIdx), nPerClass));

                nA = 0; nB = 0; nCrej = 0; cFail = {};
                for pi = 1:numel(pick)
                    idx = pick(pi);
                    pulse = localExtractPulse(D, idx, C.fs);

                    % ---- Arm A: genuine, the raw real pulse as-is ----
                    rxA = localRenderArm(pulse, R0, vClose, ampRef, F, frameDt, bufferLen, C);
                    fbA = localRunJudge(rxA, C, frameDt);
                    if fbA.confirmed_tracks >= 1 && any(strcmp(fbA.track_label, "real"))
                        nA = nA + 1;
                    end

                    % ---- Arm B: feature-matched replica of the SAME real pulse ----
                    nominal.chirp_rate_hz_s = nominalK; nominal.n_samples = numel(pulse);
                    wp = features.characterizeInterceptDechirp(pulse, C.fs, nominal);
                    if wp.aliasingMargin > 0
                        replica = features.coherentReplica(wp, C.fs, numel(pulse));
                    else
                        replica = pulse;   % structural failure -> honest fallback, not silent (mirrors synthesizeTxPulse.m)
                    end
                    rxB = localRenderArm(replica, R0, vClose, ampRef, F, frameDt, bufferLen, C);
                    fbB = localRunJudge(rxB, C, frameDt);
                    if fbB.confirmed_tracks >= 1 && any(strcmp(fbB.track_label, "real"))
                        nB = nB + 1;
                    end

                    % ---- Arm C: negative control, structureless noise ----
                    rxC = complex(zeros(bufferLen, F));
                    for k = 1:F
                        rxC(:,k) = 0.05*(randn(bufferLen,1)+1i*randn(bufferLen,1))/sqrt(2);
                    end
                    fbC = localRunJudge(rxC, C, frameDt);
                    rejected = ~(fbC.confirmed_tracks >= 1 && any(strcmp(fbC.track_label, "real")));
                    if rejected
                        nCrej = nCrej + 1;
                    else
                        cFail{end+1} = sprintf('%s#%d', classNames{cls+1}, idx); %#ok<AGROW>
                    end
                end

                rows(end+1) = struct('wclass', classNames{cls+1}, 'n', numel(pick), ...
                    'confirmedA', nA, 'confirmedB', nB, 'rejectedC', nCrej, 'cFailures', {cFail}); %#ok<AGROW>

                fprintf('%-20s n=%d  A(genuine)=%d/%d  B(phantom)=%d/%d  C(rejected)=%d/%d\n', ...
                    classNames{cls+1}, numel(pick), nA, numel(pick), nB, numel(pick), nCrej, numel(pick));
            end

            fprintf('\n=== RadChar three-arm summary (N=%d per class, %d classes) ===\n', nPerClass, 5);
            fprintf('%-20s %6s %10s %10s %10s\n', 'Class', 'N', 'A(real)', 'B(phantom)', 'C(reject)');
            for r = rows
                fprintf('%-20s %6d %9d%% %9d%% %9d%%\n', r.wclass, r.n, ...
                    round(100*r.confirmedA/r.n), round(100*r.confirmedB/r.n), round(100*r.rejectedC/r.n));
                if ~isempty(r.cFailures)
                    fprintf('    C failures (NOT rejected -- flag, do not hide): %s\n', strjoin(r.cFailures, ', '));
                end
            end

            % Only the LFM row is a meaningful A-vs-B "believable phantom"
            % test for THIS project's LFM-only judge (see header). Structural
            % check, not a specific-number assertion (Rule 5: report the
            % number, don't bake a flattering one into the pass/fail).
            lfmRow = rows(strcmp({rows.wclass}, 'LFM'));

            % ============ PHASE E: ASSERT ARM A'S RATE ============
            % This test used to assert nothing but `true`, so the finding that
            % motivated all of Phase 3 -- genuine 0-20% vs phantom 80-100% --
            % was printed and never checked.
            %
            % Recorded baseline, 1 Aug 2026, AFTER the Phase B calibration:
            %   A(genuine) 0 / 20 / 0 / 20 / 20 %   B(phantom) 100 / 80 / 80 / 80 / 80 %
            %   C(rejected) 100 % across the board
            % IDENTICAL, cell for cell, to the pre-calibration table. The
            % assertion was deliberately set so the Phase B fix would FLIP it
            % if amplitude had been the cause. It did not flip, and that is the
            % result: Arm A's low rate was never a power problem. See
            % test_b3_isolate_where_arm_a_actually_fails for what it is
            % (pulse-compression mismatch expressed through CA-CFAR), and Arm A'
            % there for the proof that the instrument itself is sound (a genuine
            % target reflecting THIS radar's own waveform confirms 5/5).
            tc.verifyEqual(lfmRow.confirmedA, 1, ...
                ['Arm A''s LFM rate moved off its recorded 1/5. If it ROSE, something ' ...
                 'finally fixed the waveform mismatch and PHASE3_RESULTS.md B3 must be ' ...
                 're-derived; if it FELL, the judge got stricter. Either way, investigate.']);
            tc.verifyEqual(lfmRow.confirmedB, 4, 'AbsTol', 1, ...
                'Arm B''s LFM rate moved off its recorded 4/5.');
            tc.verifyEqual(lfmRow.rejectedC, 5, ...
                'The negative control stopped being rejected -- the judge is accepting noise.');
        end

        function test_b3_isolate_where_arm_a_actually_fails(tc)
        % PHASE B3's ISOLATION STEP. The brief's decision rule was: if Arm A
        % is still low after calibration, the fault is in CFAR or M-of-N, not
        % the link budget -- isolate which. This walks the chain stage by
        % stage on the LFM class (the only non-confounded row) and reports
        % where each arm is actually lost: matched filter -> CFAR -> M-of-N
        % -> ECCM. Nothing here is asserted to a flattering value; the
        % assertions only pin the DIAGNOSIS so it cannot rot.
            C = physics.Constants();
            here = fileparts(mfilename('fullpath'));
            D = data.loadRadChar(fullfile(fileparts(here), 'data', 'RadChar-Tiny.h5'));

            rng(2026);
            R0 = 1800; vClose = 40; F = 8; frameDt = 1.0; bufferLen = 400;
            nominalK = 2e6 / 12e-6;
            classIdx = find(D.signal_type == 4);          % LFM only
            pick = classIdx(randperm(numel(classIdx), 5));

            fprintf('\n=== B3 isolation: where is each arm lost? (LFM, N=5) ===\n');
            fprintf(['peak/med = global peak-to-median (what "SNR" usually means)\n' ...
                     'peak/trn = peak over the CA-CFAR TRAINING-CELL mean -- the statistic\n' ...
                     '           radar.cfarDetect actually thresholds\n' ...
                     'width    = bins above half power (response smearing)\n\n']);
            fprintf('%-4s %-4s %9s %9s %7s %10s %7s %8s %-8s\n', ...
                'rec', 'arm', 'peak/med', 'peak/trn', 'width', 'dets/frame', 'frames', 'confirm', 'label');

            stats = struct('arm', {}, 'peakSnrDb', {}, 'peakToTrainDb', {}, ...
                'widthBins', {}, 'detsPerFrame', {}, ...
                'framesWithDet', {}, 'confirmed', {}, 'label', {});
            for pi = 1:numel(pick)
                idx = pick(pi);
                pulse = localExtractPulse(D, idx, C.fs);
                nominal.chirp_rate_hz_s = nominalK; nominal.n_samples = numel(pulse);
                wp = features.characterizeInterceptDechirp(pulse, C.fs, nominal);
                if wp.aliasingMargin > 0
                    replica = features.coherentReplica(wp, C.fs, numel(pulse));
                else
                    replica = pulse;
                end

                for arm = ["A", "B"]
                    if arm == "A"; shape = pulse; else; shape = replica; end
                    rx = localRenderArm(shape, R0, vClose, [], F, frameDt, bufferLen, C);
                    s = localChainDiagnostics(rx, C, frameDt);
                    s.arm = arm;
                    fprintf('%-4d %-4s %9.2f %9.2f %7.1f %10.2f %7d %8d %-8s\n', pi, arm, ...
                        s.peakSnrDb, s.peakToTrainDb, s.widthBins, ...
                        s.detsPerFrame, s.framesWithDet, s.confirmed, s.label);
                    stats(end+1) = s; %#ok<AGROW>
                end
            end

            isA = ([stats.arm] == "A");
            agg = @(f) deal(mean([stats(isA).(f)]), mean([stats(~isA).(f)]));
            [medA, medB]   = agg('peakSnrDb');
            [trnA, trnB]   = agg('peakToTrainDb');
            [widA, widB]   = agg('widthBins');
            [detA, detB]   = agg('detsPerFrame');
            [frA,  frB]    = agg('framesWithDet');
            [cA,   cB]     = agg('confirmed');

            fprintf('\n%-28s %10s %10s %10s\n', '', 'Arm A', 'Arm B', 'A - B');
            fprintf('%-28s %10.2f %10.2f %+10.2f\n', 'peak/median [dB]', medA, medB, medA-medB);
            fprintf('%-28s %10.2f %10.2f %+10.2f\n', 'peak/CFAR-training [dB]', trnA, trnB, trnA-trnB);
            fprintf('%-28s %10.1f %10.1f %+10.1f\n', 'half-power width [bins]', widA, widB, widA-widB);
            fprintf('%-28s %10.2f %10.2f %+10.2f\n', 'CFAR detections/frame', detA, detB, detA-detB);
            fprintf('%-28s %8.1f/%d %8.1f/%d\n', 'frames with a detection', frA, F, frB, F);
            fprintf('%-28s %10.1f %10.1f\n', 'confirmed tracks', cA, cB);

            fprintf(['\nDIAGNOSIS. Both arms are now rendered at the SAME derived received\n' ...
                     'power, so nothing below is a link-budget effect.\n' ...
                     '  * NOT M-of-N: Arm A fails at the DETECTION stage, not the confirmation\n' ...
                     '    stage -- it does not reach 3-of-5 because it produces almost no\n' ...
                     '    detections at all, not because 3-of-5 is too strict.\n' ...
                     '  * NOT CFAR sensitivity: Arm A''s GLOBAL peak-to-median is high. A\n' ...
                     '    detector that was simply too insensitive would miss both arms.\n' ...
                     '  * IT IS PULSE-COMPRESSION MISMATCH, EXPRESSED THROUGH CA-CFAR. A real\n' ...
                     '    RadChar pulse has its own chirp rate and width, not this radar''s\n' ...
                     '    12 us / 2 MHz nominal, so its compressed response is SMEARED. The\n' ...
                     '    smear is what CA-CFAR puts in its own training cells, which lifts\n' ...
                     '    the local threshold with the target. peak/training is the column\n' ...
                     '    that collapses; peak/median is the column that does not.\n' ...
                     '  Same mechanism CLAUDE.md already records for waveform agility\n' ...
                     '  ("matched peak 1444 in 3 bins, mismatched 55 in 72 bins").\n']);

            tc.verifyGreaterThan(trnB, trnA, ...
                ['At equal received power the matched replica must beat the mismatched ' ...
                 'real pulse on the statistic CFAR actually tests. If not, re-derive B3.']);
            tc.verifyGreaterThan(widA, widB, ...
                'Arm A''s response must be the smeared one -- that is the whole diagnosis.');
            tc.verifyGreaterThan(medA, 30, ...
                ['Arm A must still hold a high GLOBAL peak-to-median: that is what rules ' ...
                 'out "the detector is simply too insensitive".']);

            % ============ ARM A' -- THE CONTROL THAT DECIDES THE GATE ============
            % Everything above says Arm A fails because its waveform is not
            % this radar's. That leaves one question the three-arm test could
            % never answer about itself: is the INSTRUMENT broken, or is ARM A
            % MIS-SPECIFIED? Arm A's premise is "as if a real target genuinely
            % reflected exactly this real-world waveform" -- but a monostatic
            % radar's genuine target reflects the radar's OWN transmitted
            % pulse. It cannot reflect some other radar's. So Arm A models
            % something that does not physically occur.
            %
            % Arm A' is the control Arm A should have been: a genuine target
            % reflecting THIS radar's own nominal LFM, at the SAME calibrated
            % received power, over the SAME kinematics. If A' confirms, the
            % instrument works and the low Arm A rate is a property of the
            % scenario, not of the judge.
            ownPulse = features.coherentReplica(struct('wclass', 'lfm', ...
                'chirp_rate_hz_s', nominalK, 'n_samples', round(12e-6 * C.fs), ...
                'f0_hz', 0, 'bandwidth_hz', 2e6, 'pulse_width_s', 12e-6, ...
                'confidence', 1), C.fs, round(12e-6 * C.fs));

            nPrime = 0; primeStats = [];
            for pi = 1:numel(pick)
                rx = localRenderArm(ownPulse, R0, vClose, [], F, frameDt, bufferLen, C);
                s = localChainDiagnostics(rx, C, frameDt);
                primeStats = [primeStats, s]; %#ok<AGROW>
                if s.confirmed >= 1 && s.label == "real"; nPrime = nPrime + 1; end
            end
            fprintf(['\n=== ARM A'' -- genuine target reflecting THIS radar''s OWN pulse ===\n' ...
                     '(same calibrated power, same kinematics, N=%d)\n'], numel(pick));
            fprintf('%-28s %10.2f\n', 'peak/median [dB]',        mean([primeStats.peakSnrDb]));
            fprintf('%-28s %10.2f\n', 'peak/CFAR-training [dB]', mean([primeStats.peakToTrainDb]));
            fprintf('%-28s %10.1f\n', 'half-power width [bins]', mean([primeStats.widthBins]));
            fprintf('%-28s %10.2f\n', 'CFAR detections/frame',   mean([primeStats.detsPerFrame]));
            fprintf('%-28s %8d/%d\n', 'confirmed AND real',      nPrime, numel(pick));

            tc.verifyEqual(nPrime, numel(pick), ...
                ['A GENUINE target reflecting this radar''s own waveform at the derived ' ...
                 'link-budget power must confirm every time. If THIS fails, the ' ...
                 'instrument really is broken and Phase C must not proceed.']);
        end

    end

end

% ===================== file-local helpers =============================
function pulse = localExtractPulse(D, idx, fs)
%LOCALEXTRACTPULSE  Pull just the FIRST pulse out of a RadChar record using
%   its own time_delay/pulse_width labels (a record holds 2-6 pulses across
%   a PRI-spaced burst; this project's synthesis functions expect a single
%   pulse, matching +features/*'s own established ~39-45-sample convention).
    pStart = max(1, round(D.time_delay(idx) * fs) + 1);
    pLen = max(1, round(D.pulse_width(idx) * fs));
    pEnd = pStart + pLen - 1;
    full = D.iq(:, idx);
    pEnd = min(pEnd, numel(full));
    pulse = full(pStart:pEnd);
end

function rx = localRenderArm(pulseShape, R0, vClose, ampRef, F, frameDt, bufferLen, C) %#ok<INUSL>
%LOCALRENDERARM  Delay/gain/frame one arm's rx_frames -- CALIBRATED (Phase B3).
%
%   WHAT WAS WRONG, MEASURED NOT SUSPECTED. This function used to scale each
%   arm's template by a bare `ampRef * (R0/Rk)^2` with ampRef = 3.0, applied
%   to whatever amplitude that template happened to have. The two templates
%   do not have the same scale and never did:
%
%       class        peak|Arm A|  peak|Arm B|   A/B
%       CPT              6.084       0.155    +31.91 dB
%       Barker          13.646       0.161    +38.58 dB
%       PolyBarker       6.627       0.164    +32.15 dB
%       Frank           13.898       0.158    +38.91 dB
%       LFM              5.523       0.156    +31.00 dB
%
%   Arm A carried a RAW RadChar record (arbitrary recording units); Arm B
%   carried a +features/coherentReplica.m output, which normalises to unit
%   ENERGY (its line 26). So the arms entered the scene 31-39 dB apart, and
%   the published A-vs-B table was partly a power comparison wearing a
%   waveform comparison's label.
%
%   Note the direction, because it rules out the obvious explanation: the
%   GENUINE arm was the STRONGER one by 31 dB, and still confirmed less. So
%   Arm A's 0-20% was never a power problem, and B1/B2's link budget was
%   never going to fix it. See PHASE3_RESULTS.md B3 for what it actually is.
%
%   CALIBRATED: both templates are normalised to unit energy (adopting
%   coherentReplica's own convention rather than inventing a third), then
%   scaled so the RECEIVED POWER equals what physics.targetReturn derives for
%   a sigma = 1 m^2 target at that frame's range. For a unit-energy template
%   of n samples, mean power over the pulse is g^2/n, so g = a*sqrt(n) where
%   a = physics.wattsToSimAmplitude(Pr). The 1/R^2 amplitude taper is no
%   longer written by hand either -- it falls out of Pr ~ 1/R^4.
    x = pulseShape(:);
    x = x / sqrt(sum(abs(x).^2) + 1e-12);      % unit ENERGY
    nPulse = numel(x);
    xTemplate = [x; zeros(max(0, bufferLen - nPulse), 1)];
    xTemplate = xTemplate(1:bufferLen);

    rx = complex(zeros(bufferLen, F));
    U = physics.simUnits();
    for k = 1:F
        Rk = R0 - vClose * (k - 1);
        T = physics.targetReturn('RangeM', Rk);        % sigma = 1 m^2, 1 kW, 30 dBi
        gain = T.sim_amplitude * sqrt(nPulse);
        action = struct('delay_s', 2*Rk/C.c, 'phase_rad', 0, 'gain', gain);
        y = synth.synthesizeSwarm(xTemplate, action, C);
        noise = U.noise_amplitude * ...
                (randn(bufferLen,1) + 1i*randn(bufferLen,1)) / sqrt(2);
        rx(:,k) = y + noise;
    end
end

function feedback = localRunJudge(rxFrames, C, frameDt) %#ok<INUSD>
%LOCALRUNJUDGE  Save rxFrames in engine.runJudge's expected .mat schema and
%   run it -- matched filter is ALWAYS this project's own fixed LFM
%   assumption (12us/2MHz/50kHz PRF), regardless of what waveform class
%   produced rxFrames (that mismatch IS the point for non-LFM classes).
    tmpMat = [tempname(), '.mat'];
    % Signal description only -- the judge's CFAR config no longer crosses
    % this seam at all (Phase A1); it uses radar.cfarDefaults().
    S = struct('rx_frames', rxFrames, 'fs', C.fs, 'pulse_width_s', 12e-6, ...
                'bandwidth_hz', 2e6, 'prf_hz', physics.Constants().PRF, 'frame_interval_s', frameDt);
    save(tmpMat, '-struct', 'S');
    feedback = engine.runJudge(tmpMat);
    delete(tmpMat);
end

function s = localChainDiagnostics(rxFrames, C, frameDt)
%LOCALCHAINDIAGNOSTICS  Walk one arm through the judge's chain and report
%   where it is lost: matched-filter peak SNR -> CFAR detections -> frames
%   with any detection (what M-of-N consumes) -> confirmed -> ECCM label.
%   Uses the judge's OWN components, so the diagnosis describes the judge
%   that actually scores the arms and not a re-implementation of it.
    % Argument order is (sweepSign, fs, pulseWidth, PRF, bandwidth) -- the
    % same call +engine/runJudge.m makes. Swapping PRF and bandwidth throws
    % 'phased:Waveform:NeedRatioInteger' rather than silently mis-filtering.
    wav = radar.agileWaveform(1, C.fs, 12e-6, physics.Constants().PRF, 2e6);
    F = size(rxFrames, 2);
    D = radar.cfarDefaults();
    peakSnr = zeros(1, F); nDet = zeros(1, F);
    peakTrain = zeros(1, F); width = zeros(1, F);
    for k = 1:F
        power = radar.pulseCompress(rxFrames(:, k), wav);
        [pk, pkIdx] = max(power);
        % (a) GLOBAL peak-to-median. Robust to the target peak, but NOT what
        %     CA-CFAR tests -- it cannot see a local pedestal at all.
        peakSnr(k) = 10*log10(pk / (median(power) + eps));
        % (b) LOCAL peak-to-training: the actual CA-CFAR statistic. Mean of
        %     the training cells either side of the guard band, exactly the
        %     window radar.cfarDetect builds from radar.cfarDefaults().
        lo = pkIdx - D.NumGuard - D.NumTraining; hi = pkIdx + D.NumGuard + D.NumTraining;
        idxWin = [max(1,lo):(pkIdx-D.NumGuard-1), (pkIdx+D.NumGuard+1):min(numel(power),hi)];
        idxWin = idxWin(idxWin >= 1 & idxWin <= numel(power));
        peakTrain(k) = 10*log10(pk / (mean(power(idxWin)) + eps));
        % (c) how many bins the response is smeared over (half-power width)
        width(k) = nnz(power > pk/2);
        nDet(k) = numel(radar.cfarDetect(power));
    end

    tmpMat = [tempname(), '.mat'];
    S = struct('rx_frames', rxFrames, 'fs', C.fs, 'pulse_width_s', 12e-6, ...
                'bandwidth_hz', 2e6, 'prf_hz', physics.Constants().PRF, 'frame_interval_s', frameDt);
    save(tmpMat, '-struct', 'S');
    fb = engine.runJudge(tmpMat);
    delete(tmpMat);

    lbl = "none";
    if fb.confirmed_tracks >= 1; lbl = string(fb.eccm_label); end
    s = struct('arm', "", 'peakSnrDb', mean(peakSnr), ...
        'peakToTrainDb', mean(peakTrain), 'widthBins', mean(width), ...
        'detsPerFrame', mean(nDet), 'framesWithDet', sum(nDet > 0), ...
        'confirmed', fb.confirmed_tracks, 'label', lbl);
end
