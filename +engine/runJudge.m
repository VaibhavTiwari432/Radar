function feedback = runJudge(matFile, varargin)
%RUNJUDGE  Run any exported Scene's rx buffers (from
%   cogengine.matlab_judge.export_scene_for_judge, Phase 2 build-order
%   step 5) through the Phase 1 MATLAB judge (+radar/+track) and return a
%   Feedback-shaped struct.
%
%   feedback = engine.runJudge(matFile)
%   feedback = engine.runJudge(matFile, 'Name', value, ...)
%       matFile : path to a .mat written by
%                 cogengine.matlab_judge.export_scene_for_judge
%       feedback: struct with confirmed_tracks, false_tracks_surviving,
%                 flagged_decoys, mean_track_lifetime_frames, eccm_label,
%                 plus per-track detail (track_range_m, track_amp,
%                 track_label) for however many simultaneous targets the
%                 tracker actually confirmed.
%
%   INDEPENDENT judge side of CLAUDE.md Rule 2's twin/judge split: this
%   function never imports or calls anything from cogengine/*.py -- it
%   only ever sees the rendered rx signal and generic config numbers that
%   crossed the seam in matFile.
%
%   THE JUDGE'S OWN CONFIGURATION NEVER CROSSES THAT SEAM (Phase A1). This
%   function used to read cfar_pfa / cfar_num_training / cfar_num_guard /
%   assignment_gate_m / confirmation_threshold / deletion_threshold /
%   filter_model / tracker_type / eccm_screens / expect_micro_doppler /
%   micro_blade_hz_min out of the .mat -- a file the ADVERSARY's exporter
%   writes. cogengine.matlab_judge.export_scene_for_judge was in fact
%   writing its twin's own CFAR settings into it. That the values happened
%   to be identical to +radar/cfarDetect.m's defaults is what made the wire
%   invisible, not harmless: nothing prevented a planner from turning the
%   judge's detector down. Those reads are gone. Every one of those knobs
%   is now an explicit name-value argument, settable only by this
%   function's MATLAB caller (+experiments/*), never by the .mat:
%
%       'Pfa' 'NumTraining' 'NumGuard'          -> radar.cfarDetect
%       'AssignmentThreshold' 'ConfirmationThreshold' 'DeletionThreshold'
%       'FilterModel' 'TrackerType'             -> track.runTracker
%       'EccmScreens' 'ExpectMicroDoppler' 'MicroBladeHzMin'
%                                               -> track.discriminator
%
%   Each defaults to [] meaning "do not pass it on" -- so the value in
%   force is the one +radar/cfarDetect.m, +track/trackerDefaults.m or
%   +track/discriminator.m declares. This file re-declares none of them
%   (the C3 bug: a literal ASSIGNMENT_GATE_M = 200 copied out of the
%   tracker went stale the moment a caller swept the gate).
%
%   The .mat still carries what DESCRIBES THE SIGNAL, which the judge has
%   no other way to know and which is a Rule-1 shared physical fact, not a
%   model parameter: fs, pulse_width_s, bandwidth_hz, prf_hz, carrier_hz,
%   frame_interval_s, sweep_schedule, subaperture_sep_m, rx_frames_delta.
%
%   MULTI-TARGET (was single-target until this revision): a scene's
%   rx_frames already sum ALL of its phantoms' returns per frame
%   (cogengine.matlab_judge.export_scene_for_judge docstring) -- but this
%   function used to keep only the single strongest CFAR peak each frame
%   before handing it to the tracker, silently discarding every other
%   phantom. A 4-phantom "mother drone" scene therefore could never be
%   judged as anything but 0 or 1 confirmed track, regardless of how many
%   phantoms actually survived. Fixed: every CFAR peak this frame becomes
%   its own detection (radar.cfarDetect already returns all of them --
%   localMaxPeaks below only collapses the handful of ADJACENT bins one
%   physical return commonly crosses threshold on into a single peak, so
%   one target doesn't masquerade as several). track.runTracker's
%   trackerGNN is MathWorks' own multi-target tracker -- it was never the
%   bottleneck, only this file's single-peak-per-frame habit was.
%
%   Per-track history for the ECCM discriminator: trackerGNN's public
%   output doesn't expose which detection it assigned to which track, so
%   each confirmed track's own range/amplitude series is rebuilt here by
%   nearest-range match between that track's own filtered state estimate
%   and that frame's peaks -- reliable as long as simultaneous phantoms
%   are gated apart by more than AssignmentThreshold (200 m,
%   +track/runTracker.m), which this project's scene-spread convention
%   (cogengine/planner_cem.py's DEFAULT_BOUNDS range span) already respects.
%
%   ================= DOPPLER IS NOW MEASURED, NOT ASSUMED =================
%   Until the Virtual Entity Engine build, this function computed the
%   "doppler" series it handed to track.discriminator as
%       dSeq = diff(rSeq) ./ diff(tSeq)
%   -- a RANGE DIFFERENCE. The discriminator's screen 2 then asked whether
%   sign(mean(diff(R))) == sign(mean(D)), which for D derived from diff(R)
%   is TRUE BY CONSTRUCTION. That screen could never fail, in either
%   direction: it awarded a free pass to every confirmed track, real or
%   phantom, and had done so for every number this project has published.
%   The structural cause was upstream: rx_frames carried ONE fast-time
%   column per frame, so there was no slow-time axis and physically nothing
%   for radar.rangeDoppler to transform.
%
%   Two input shapes are now accepted:
%     rx_frames [fastTime x numPulses x numFrames] (a real pulse cube --
%         cogengine.matlab_judge.export_scene_for_judge and
%         engine.entity.render both emit this). Each frame is
%         pulse-compressed per pulse, run through radar.rangeDoppler, and
%         the winning Doppler bin at each detected range bin is converted
%         to a range-rate, -lambda*f_d/2. That is a genuinely independent
%         measurement: it comes from slow-time phase, not from range.
%         Requires carrier_hz in the .mat (no default -- guessing a
%         wavelength would silently corrupt every velocity).
%     rx_frames [fastTime x numFrames] (legacy 2-D exports, and the frozen
%         historical fixtures). No slow-time axis exists, so NO Doppler is
%         reported at all and the discriminator's screen 2 correctly
%         self-disables as uninformative (its own abs(dopplerMean) > 1e-9
%         guard). This is NOT backwards-compatible in RESULT, only in
%         interface: labels computed from 2-D exports can change, because
%         the free pass is gone. That is the fix, not a regression.
%
%   feedback.doppler_source records which path ran, so no caller can quote
%   a label without knowing whether a Doppler screen was behind it.

    here = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(here);
    addpath(projectRoot);

    C = physics.Constants();
    opts = localParseJudgeConfig(varargin);

    S = load(matFile);
    rxFrames = S.rx_frames;

    % ================= THE RANGE AXIS IS THE SIGNAL'S, NOT THE PROJECT'S ====
    % One fast-time sample is c/(2*fs) of two-way range, and fs is a property
    % of THE SIGNAL BEING JUDGED -- it arrives in the .mat, and line ~200
    % already uses S.fs to rebuild the matched filter's own waveform. Until
    % 9 Sep 2026 the three places below instead used C.range_per_sample, i.e.
    % physics.Constants()'s 3.2 MHz, no matter what fs the .mat carried.
    %
    % IDENTICAL FOR EVERY RESULT THIS PROJECT HAS PUBLISHED: C.range_per_sample
    % IS c/(2*C.fs), and every existing exporter writes fs = C.fs = 3.2 MHz, so
    % this derives the same 46.84 m it always did. tests/test_sim_units.m and
    % the whole suite are unchanged by it.
    %
    % IT MATTERS FOR STAGE F, which judges a 1 MHz bench signal whose real bin
    % is 149.9 m. With the old constant every range this function reported was
    % compressed by 3.2x. That was SELF-CONSISTENT -- the ranges, the
    % MeasurementNoise and the Cartesian covariance all shared the error, so
    % the tracker and the log-log amplitude SLOPE were unaffected -- which is
    % exactly why it survived unnoticed. What it broke is anything quoted in
    % metres: a caller passing AssignmentThreshold in real metres was silently
    % handing the tracker a 3.2x wider gate, and +track/discriminator.m's
    % 3-range-cell lever guard was measured in the wrong instrument's cells.
    if isfield(S, 'fs') && isfinite(S.fs) && S.fs > 0
        rangePerSample = C.c / (2 * double(S.fs));
    else
        % A .mat with no fs at all: fall back to the project radar and say so,
        % rather than silently assuming the caller meant 3.2 MHz.
        rangePerSample = C.range_per_sample;
        warning('engine:runJudge:noSampleRate', ...
            ['%s carries no fs; range axis falls back to physics.Constants() ' ...
             '(%.2f m/sample). Any range this run reports is in the project ' ...
             'radar''s metres.'], matFile, rangePerSample);
    end

    % Pulse cube [fastTime x numPulses x numFrames] vs legacy [fastTime x
    % numFrames]. See "DOPPLER IS NOW MEASURED" in the header.
    isCube = (ndims(rxFrames) == 3);
    if isCube
        numPulses = size(rxFrames, 2);
        numFrames = size(rxFrames, 3);
        assert(isfield(S, 'carrier_hz'), 'engine:runJudge:noCarrier', ...
            ['A pulse-cube rx_frames needs carrier_hz in the .mat to turn a ' ...
             'Doppler bin into a range-rate. Refusing to guess a wavelength.']);
        lambda = C.c / double(S.carrier_hz);
    else
        numPulses = 1;
        numFrames = size(rxFrames, 2);
        lambda = NaN;
    end

    % double() cast: a Python-exported .mat's numeric fields are only as
    % well-typed as whatever produced them -- a RadarState/Scene built via
    % engine.decideScene's JSON seam can carry a whole-number field (e.g.
    % prf_hz=50000) that scipy.io.savemat writes as int64, and
    % phased.LinearFMWaveform rejects int64 outright ("Expected PRF ... "
    % "double. Instead ... int64" -- verified via tests/test_decideScene.m).
    % cogengine.schema's dataclasses now coerce these to float at
    % construction (the root-cause fix), but this load boundary casts
    % defensively too, since S here can come from ANY .mat exporter, not
    % just ones honoring that contract.
    % WAVEFORM AGILITY. sweep_schedule, when present, is a per-frame +1/-1
    % vector selecting an up- or down-chirp for that dwell -- the radar's own
    % secret, not a shared parameter (radar.agileWaveform). Absent -> a fixed
    % up-chirp on every frame, i.e. this project's historical behaviour, so
    % every existing exporter is unaffected.
    if isfield(S, 'sweep_schedule')
        sweepSched = double(S.sweep_schedule(:)');
        assert(numel(sweepSched) >= numFrames, 'engine:runJudge:shortSchedule', ...
            'sweep_schedule has %d entries for %d frames', numel(sweepSched), numFrames);
    else
        sweepSched = ones(1, numFrames);
    end
    % ANGLE CHANNEL (RADAR_REALISM_AUDIT.md 1.1). rx_frames_delta, when
    % present, is the monopulse DIFFERENCE channel matching rx_frames (the SUM
    % channel), same shape. Absent -> this radar has no angle at all, exactly
    % as before, and feedback.angle_source says so.
    hasAngle = isCube && isfield(S, 'rx_frames_delta');
    if hasAngle
        rxDelta = S.rx_frames_delta;
        assert(isequal(size(rxDelta), size(rxFrames)), 'engine:runJudge:deltaShape', ...
            'rx_frames_delta %s does not match rx_frames %s', ...
            mat2str(size(rxDelta)), mat2str(size(rxFrames)));
        if isfield(S, 'subaperture_sep_m'); subSep = double(S.subaperture_sep_m); else; subSep = 0.30; end
    end
    % SECOND azimuth baseline (SWARM_RESULTS.md counter): a wider subaperture
    % whose ambiguous-but-precise phase the coarse baseline disambiguates. When
    % present the azimuth estimate below is refined to it; absent -> the single
    % coarse baseline exactly as before.
    hasBaseline2 = hasAngle && isfield(S, 'rx_frames_delta2');
    if hasBaseline2
        rxDelta2 = S.rx_frames_delta2;
        assert(isequal(size(rxDelta2), size(rxFrames)), 'engine:runJudge:delta2Shape', ...
            'rx_frames_delta2 %s does not match rx_frames %s', ...
            mat2str(size(rxDelta2)), mat2str(size(rxFrames)));
        if isfield(S, 'subaperture_sep_m_2'); subSep2 = double(S.subaperture_sep_m_2); else; subSep2 = 0.90; end
    end
    % ELEVATION channel (S3). Its own orthogonal subaperture pair, written by
    % +generator/render.m's IncludeElevationChannel. Gated on hasAngle too: an
    % elevation difference channel without an azimuth one is not a
    % configuration this receiver has.
    % S3: track in real (x, y, z) instead of [R; 0; 0]. Opt-in -- see the
    % 'MeasurementSpace' parameter for why the default must stay 'range'.
    useCartesian = strcmpi(char(opts.MeasurementSpace), 'cartesian');
    assert(useCartesian || strcmpi(char(opts.MeasurementSpace), 'range'), ...
        'engine:runJudge:badMeasurementSpace', ...
        'MeasurementSpace must be ''range'' or ''cartesian'', got ''%s''', ...
        char(opts.MeasurementSpace));
    assert(~useCartesian || hasAngle, 'engine:runJudge:cartesianNeedsAngle', ...
        ['MeasurementSpace=''cartesian'' needs the monopulse difference ' ...
         'channel: with no measured bearing every detection would sit on ' ...
         'boresight and the Cartesian space would carry no more information ' ...
         'than [R;0;0] while costing two extra state dimensions.']);
    subSepEl2 = 0.30;   % used by the Cartesian branch even with no el channel
    hasElev = hasAngle && isfield(S, 'rx_frames_delta_el');
    if hasElev
        rxDeltaEl = S.rx_frames_delta_el;
        assert(isequal(size(rxDeltaEl), size(rxFrames)), 'engine:runJudge:deltaElShape', ...
            'rx_frames_delta_el %s does not match rx_frames %s', ...
            mat2str(size(rxDeltaEl)), mat2str(size(rxFrames)));
        if isfield(S, 'subaperture_sep_el_m')
            subSepEl = double(S.subaperture_sep_el_m);
        else
            subSepEl = 0.30;
        end
        subSepEl2 = subSepEl;
    end
    wavForFrame = @(k) radar.agileWaveform(sweepSched(k), S.fs, S.pulse_width_s, ...
                                            S.prf_hz, S.bandwidth_hz);
    wav = wavForFrame(1);   % representative, for the Doppler axis scaling

    times = (0:numFrames-1) * S.frame_interval_s;
    dets = cell(1, numFrames);
    peakRange = cell(1, numFrames);
    peakAmp   = cell(1, numFrames);
    peakRate  = cell(1, numFrames);   % MEASURED range-rate [m/s], cube path only
    peakAz    = cell(1, numFrames);   % MEASURED azimuth [rad], angle path only
    peakEl    = cell(1, numFrames);   % MEASURED elevation [rad], el channel only
    peakComb  = cell(1, numFrames);   % MEASURED micro-Doppler comb fraction

    % Judge-side detector config, from THIS function's caller only (never
    % the .mat). Empty -> omitted, so radar.cfarDetect's own defaults stand.
    cfarArgs = localNameValue(opts, {'Pfa', 'NumTraining', 'NumGuard'});

    % ---- micro-Doppler resolvability, decided ONCE from the waveform ----
    % A comb at f_blade is invisible unless some line clears the slow-time
    % mainlobe. Measured criterion (experiments.microDopplerScreenability):
    % nPulses > PRF/f_blade, i.e. Doppler resolution finer than the blade
    % rate. Uses the SLOWEST blade rate the screen must cover, because that
    % is the hardest case; 100 Hz is the low end of the 100-200 Hz band
    % measured across four drone types in the TSMS-Drone CW set.
    % ---- RANGE AMBIGUITY (Phase C1) --------------------------------------
    % Report the radar's real unambiguous envelope alongside every result, and
    % state whether the receive window it was handed is even consistent with
    % the PRF it declares. Reporting only -- this does NOT re-bin anything,
    % because the fold happens in the receiver at acquisition time and cannot
    % be undone downstream. What it prevents is quoting a 5000 m track from a
    % radar that physically cannot place one past 2998 m without saying so.
    ambigInfo = physics.assertPrfWindowConsistent(double(S.prf_hz), ...
                    size(rxFrames, 1), 'Mode', 'silent');

    bladeMinHz = opts.MicroBladeHzMin;
    if isCube
        dopplerResHz  = double(S.prf_hz) / numPulses;
        microResolvable = dopplerResHz < bladeMinHz;
    else
        dopplerResHz = NaN;
        microResolvable = false;      % no slow-time axis at all
    end

    for k = 1:numFrames
        % Match-filter THIS frame against the waveform the radar actually
        % transmitted on THIS frame. A repeater replaying a stale intercept
        % is now compressing against the wrong reference.
        wavK = wavForFrame(k);
        if isCube
            % Compress every pulse (keeping PHASE -- pulseCompress's second
            % output), then Doppler-process the slow-time axis. The range
            % profile handed to CFAR is the best Doppler bin per range bin,
            % which is what a radar holding a pulse cube actually does; the
            % same map's argmax gives that bin's range-rate for free.
            frameCube = rxFrames(:, :, k);
            compressed = complex(zeros(size(frameCube)));
            for pIdx = 1:numPulses
                [~, compressed(:, pIdx)] = radar.pulseCompress(frameCube(:, pIdx), wavK);
            end
            [rdMap, ~, dopAxis] = radar.rangeDoppler(compressed, wavK, C);
            % ---- MTI: discard the zero-Doppler filters -------------------
            % Ground return is stationary, so it lands in the bins around
            % zero radial velocity. Zeroing them before the max over Doppler
            % is what a pulse-Doppler radar does with its clutter filter --
            % the output is discarded, not thresholded alongside the rest.
            % Zeroed rather than set to -Inf so that a scene where EVERY bin
            % is notched degrades to "no detection" instead of erroring.
            if opts.MtiNotchMps > 0
                binVel = -lambda * dopAxis / 2;      % same convention as peakRate
                rdMap(:, abs(binVel) < opts.MtiNotchMps) = 0;
            end
            [power, dopBin] = max(rdMap, [], 2);
            % Keep the COMPLEX slow-time spectrum of both channels: the
            % monopulse ratio needs phase, and |.|^2 has thrown it away.
            if hasAngle
                deltaCube = rxDelta(:, :, k);
                compressedD = complex(zeros(size(deltaCube)));
                for pIdx = 1:numPulses
                    [~, compressedD(:, pIdx)] = radar.pulseCompress(deltaCube(:, pIdx), wavK);
                end
                sumSpec   = fftshift(fft(compressed,  numPulses, 2), 2);
                deltaSpec = fftshift(fft(compressedD, numPulses, 2), 2);
                if hasBaseline2
                    deltaCube2 = rxDelta2(:, :, k);
                    compressedD2 = complex(zeros(size(deltaCube2)));
                    for pIdx = 1:numPulses
                        [~, compressedD2(:, pIdx)] = radar.pulseCompress(deltaCube2(:, pIdx), wavK);
                    end
                    deltaSpec2 = fftshift(fft(compressedD2, numPulses, 2), 2);
                end
            end
            if hasElev
                deltaElCube = rxDeltaEl(:, :, k);
                compressedE = complex(zeros(size(deltaElCube)));
                for pIdx = 1:numPulses
                    [~, compressedE(:, pIdx)] = radar.pulseCompress(deltaElCube(:, pIdx), wavK);
                end
                deltaElSpec = fftshift(fft(compressedE, numPulses, 2), 2);
            end
        else
            power = radar.pulseCompress(rxFrames(:, k), wavK);
            dopBin = [];
        end

        detIdx = radar.cfarDetect(power, cfarArgs{:});
        peakBins = localMaxPeaks(detIdx, power);

        if isempty(peakBins)
            dets{k} = objectDetection.empty;
            peakRange{k} = zeros(0,1);
            peakAmp{k}   = zeros(0,1);
            peakRate{k}  = zeros(0,1);
            peakAz{k}    = zeros(0,1);
            peakComb{k}  = zeros(0,1);
            continue;
        end

        % Range: integer bin, or refined to sub-bin if the caller asked. The
        % AMPLITUDE deliberately stays the peak CELL's value even when the
        % range is refined -- interpolating it too would change what the
        % amplitude screen fits, which is a separate decision from being able
        % to see a target move, and bundling them would make neither
        % attributable.
        if opts.SubBinInterp
            refinedBins = zeros(numel(peakBins), 1);
            for iPk = 1:numel(peakBins)
                refinedBins(iPk) = radar.subBinPeak(power, peakBins(iPk));
            end
            peakRange{k} = (refinedBins - 1) * rangePerSample;
        else
            peakRange{k} = (peakBins - 1) * rangePerSample;
        end
        peakAmp{k}   = sqrt(power(peakBins));
        if isCube
            % f_d = -2*Rdot/lambda  =>  Rdot = -lambda*f_d/2. Negative =
            % closing, matching +track/discriminator.m's stated convention
            % and cogengine/renderer.py's doppler_hz.
            peakRate{k} = -lambda * dopAxis(dopBin(peakBins)) / 2;
            peakRate{k} = peakRate{k}(:);
            % MICRO-DOPPLER: fraction of this range cell's slow-time energy
            % lying outside the dominant Doppler mainlobe. A DRFM repeater
            % transmits a delayed, scaled, CONSTANT-phase copy
            % (+synth/synthesizeSwarm.m), which is a single Doppler line; a
            % rotor phase-modulates its return into a Bessel comb
            % (+engine/+entity/render.m). Blind by construction -- it does not
            % assume knowledge of the blade rate, because a screen is not told
            % the rotor speed of what it is looking at.
            peakComb{k} = zeros(numel(peakBins), 1);
            for pb = 1:numel(peakBins)
                spec = rdMap(peakBins(pb), :);
                tot = sum(spec);
                if tot > 0
                    [~, db] = max(spec);
                    ix = 1:numel(spec);
                    peakComb{k}(pb) = sum(spec(abs(ix - db) > 2)) / tot;
                end
            end
        else
            peakRate{k} = zeros(numel(peakBins), 1);
            peakComb{k} = nan(numel(peakBins), 1);   % no slow-time axis to look at
        end

        % ---- monopulse azimuth, at each detected peak's own Doppler bin ----
        if hasAngle
            az = zeros(numel(peakBins), 1);
            for j = 1:numel(peakBins)
                b = peakBins(j); dB = dopBin(b);
                sig = sumSpec(b, dB); dif = deltaSpec(b, dB);
                if abs(sig) < eps
                    az(j) = NaN; continue;
                end
                % Delta/Sigma = 1i*tan(phi/2)  =>  phi = 2*atan(imag(ratio))
                ratio = dif / sig;
                phiEst = 2 * atan(imag(ratio));
                sinTh  = phiEst * lambda / (2*pi*subSep);
                if hasBaseline2
                    % Two-baseline resolve: the coarse baseline picks which
                    % fringe of the finer, wider baseline the target sits in,
                    % then the fine phase gives the precise angle. The fine
                    % electrical phase Phi_f = 2*pi*d2*sin(az)/lambda is measured
                    % wrapped into (-pi,pi); add the multiple of 2*pi that lands
                    % it nearest the coarse estimate, then invert.
                    dif2 = deltaSpec2(b, dB);
                    phiF = 2 * atan(imag(dif2 / sig));
                    phiFexpected = 2*pi*subSep2 * sinTh / lambda;   % from coarse
                    n = round((phiFexpected - phiF) / (2*pi));
                    sinTh = (phiF + 2*pi*n) * lambda / (2*pi*subSep2);
                end
                az(j)  = asin(max(-1, min(1, sinTh)));   % clamp: outside the
            end                                          % unambiguous sector
            peakAz{k} = az;                              % asin would go complex
        else
            peakAz{k} = nan(numel(peakBins), 1);
        end

        % ---- monopulse ELEVATION, same estimator, orthogonal baseline ----
        % Written by +generator/render.m only when its IncludeElevationChannel
        % is on (it defaults off, because the extra receive chain's own noise
        % draw perturbs the shared RNG stream). Absent -> no elevation, and
        % the Cartesian measurement below correctly treats the target as being
        % in the horizontal plane rather than inventing a height.
        if hasElev
            el = zeros(numel(peakBins), 1);
            for j = 1:numel(peakBins)
                b = peakBins(j); dB = dopBin(b);
                sig = sumSpec(b, dB); dif = deltaElSpec(b, dB);
                if abs(sig) < eps
                    el(j) = NaN; continue;
                end
                ratio  = dif / sig;
                phiEst = 2 * atan(imag(ratio));
                sinPh  = phiEst * lambda / (2*pi*subSepEl);
                el(j)  = asin(max(-1, min(1, sinPh)));
            end
            peakEl{k} = el;
        else
            peakEl{k} = nan(numel(peakBins), 1);
        end

        % MeasurementNoise reflects the REAL range-bin quantization error
        % (~rangePerSample, ~46.8 m std at this project's own fs), not
        % eye(3)'s claimed 1 m std.
        % That mismatch was a real bug (Task 2, PHASE2_COMPLETION_POA.md):
        % telling the tracker its measurements are ~47x more precise than
        % they actually are makes trackerGNN's gates falsely tight, so two
        % or more tracks born in the SAME frame (identical, uninformative
        % birth covariance -- no velocity estimate yet) occasionally miss
        % their own next detection and spawn a duplicate TrackID for the
        % same physical target. Verified directly: on a real 4-phantom
        % rendered scene's exact CFAR peak sequence, eye(3) produced 7
        % confirmed tracks for 4 physical phantoms; measNoise matching the
        % true bin resolution produced exactly 4, no duplicates, same data.
        % Single-target callers (Stage3_Test.m, the frozen
        % cogengine/fixtures/runJudgeBatch*.m historical scripts) build
        % their OWN objectDetection with their OWN MeasurementNoise and are
        % untouched -- this fix is local to this function's own detections.
        measNoise = diag([rangePerSample^2, 1, 1]);
        detArr = objectDetection.empty;
        for j = 1:numel(peakBins)
            if useCartesian
                % ---- the real (x, y, z) the measurement implies (S3) ----
                % [R;0;0] told the tracker the last two components were
                % measured, at 0, to a 1 m standard deviation. That was never
                % true (RADAR_REALISM_AUDIT.md Tier 1) and it silently made
                % every target collinear with boresight, which is exactly the
                % geometry a co-bearing swarm has -- so the tracker could not
                % have separated a genuine formation from a fan even in
                % principle.
                %
                % Covariance by the standard spherical->Cartesian JACOBIAN of
                % (R, az, el), NOT by rotating a diagonal guess: the
                % cross-range error is R*sigma_az, so it GROWS with range and
                % the off-diagonal terms are real. sigma_R stays the range-bin
                % quantiser. sigma_az/sigma_el are the estimator's own scatter
                % (localAngleSigma), and an unmeasured angle is given the full
                % half-sector rather than zero -- an unknown bearing must
                % widen the gate, never tighten it.
                Rj  = peakRange{k}(j);
                azj = peakAz{k}(j); elj = peakEl{k}(j);
                sAz = localAngleSigma(azj, subSep, lambda);
                sEl = localAngleSigma(elj, subSepEl2, lambda);
                if ~isfinite(azj); azj = 0; end
                if ~isfinite(elj); elj = 0; end
                [pos, Rcov] = localSphericalToCartesian(Rj, azj, elj, ...
                                  rangePerSample, sAz, sEl);
                detArr(j) = objectDetection(times(k), pos, ...
                                'MeasurementNoise', Rcov);
            else
                detArr(j) = objectDetection(times(k), [peakRange{k}(j); 0; 0], ...
                                'MeasurementNoise', measNoise);
            end
        end
        dets{k} = detArr;
    end

    % Sweepable radar operating point -- from this function's OWN caller
    % (+experiments/benchmarkSuite.m's Tier-2 sweeps), never from the .mat.
    % Empty -> omitted, so +track/trackerDefaults.m's values stand.
    trkArgs = localNameValue(opts, {'AssignmentThreshold', ...
        'ConfirmationThreshold', 'DeletionThreshold', 'FilterModel', 'TrackerType'});

    [confirmedTracks, history, modeProbHistory] = track.runTracker(dets, times, C, trkArgs{:});
    confirmedCount = numel(confirmedTracks);

    % Per-frame track log (additive -- Mission Simulator's animated replay,
    % MISSION_SIMULATOR_UI_SPEC.md Section 7/Section 9 Step 5/6, needs each
    % track's STATE MACHINE over time, not just the final aggregate this
    % function already returned). "Hit this frame" is approximated the same
    % way this function already associates a track to its own range history
    % elsewhere (nearest peak within the tracker's own AssignmentThreshold
    % gate, +track/runTracker.m) -- not a literal readout of trackerGNN's
    % internal assignment (its public API doesn't expose that), but the
    % same defensible approximation already used and documented above.
    % C3: this was a literal 200 copied out of the tracker, which went stale
    % the instant a caller swept the gate -- the frame log then reported hits
    % against a threshold the tracker was not using. Read the gate ACTUALLY
    % in force instead: the caller's override if there was one, otherwise
    % +track/trackerDefaults.m, which is where the number now lives once.
    if isempty(opts.AssignmentThreshold)
        gateVec = track.trackerDefaults().AssignmentThreshold;
    else
        gateVec = opts.AssignmentThreshold;
    end
    ASSIGNMENT_GATE_M = gateVec(1);
    hitCountByID = containers.Map('KeyType', 'double', 'ValueType', 'double');
    missStreakByID = containers.Map('KeyType', 'double', 'ValueType', 'double');
    frameLog = cell(1, numFrames);
    for k = 1:numFrames
        tk = history{k};
        frameTracks = struct('trackId', {}, 'rangeEst', {}, 'isConfirmed', {}, ...
            'age', {}, 'hitThisFrame', {}, 'hits', {}, 'missStreak', {}, ...
            'hitRange', {}, 'hitAmp', {});
        for t = 1:numel(tk)
            id = tk(t).TrackID;
            estRange = localTrackRange(tk(t).State, useCartesian);
            isHit = false; hitRange = NaN; hitAmp = NaN;
            if ~isempty(peakRange{k})
                [dmin, im] = min(abs(peakRange{k} - estRange));
                isHit = dmin < ASSIGNMENT_GATE_M;
                if isHit
                    hitRange = peakRange{k}(im);
                    hitAmp   = peakAmp{k}(im);
                end
            end
            if ~isKey(hitCountByID, id)
                hitCountByID(id) = 0; missStreakByID(id) = 0;
            end
            if isHit
                hitCountByID(id) = hitCountByID(id) + 1;
                missStreakByID(id) = 0;
            else
                missStreakByID(id) = missStreakByID(id) + 1;
            end
            frameTracks(end+1) = struct('trackId', id, 'rangeEst', estRange, ...
                'isConfirmed', logical(tk(t).IsConfirmed), 'age', tk(t).Age, ...
                'hitThisFrame', isHit, 'hits', hitCountByID(id), ...
                'missStreak', missStreakByID(id), ...
                'hitRange', hitRange, 'hitAmp', hitAmp); %#ok<AGROW>
        end
        frameLog{k} = frameTracks;
    end

    % Rebuild each confirmed track's own range/amplitude series by
    % nearest-range match to that frame's peaks (see header).
    confirmedIDs = [confirmedTracks.TrackID];
    rangeByID = containers.Map('KeyType', 'double', 'ValueType', 'any');
    ampByID   = containers.Map('KeyType', 'double', 'ValueType', 'any');
    timeByID  = containers.Map('KeyType', 'double', 'ValueType', 'any');
    rateByID  = containers.Map('KeyType', 'double', 'ValueType', 'any');
    azByID    = containers.Map('KeyType', 'double', 'ValueType', 'any');
    elByID    = containers.Map('KeyType', 'double', 'ValueType', 'any');
    combByID  = containers.Map('KeyType', 'double', 'ValueType', 'any');
    modeProbByID = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for id = confirmedIDs
        rangeByID(id) = zeros(0,1);
        ampByID(id)   = zeros(0,1);
        timeByID(id)  = zeros(0,1);
        rateByID(id)  = zeros(0,1);
        azByID(id)    = zeros(0,1);
        elByID(id)    = zeros(0,1);
        combByID(id)  = zeros(0,1);
        modeProbByID(id) = zeros(0,3);   % nModels fixed by initekfimm's CV/CA/CT bank
    end
    for k = 1:numFrames
        tk = history{k};
        if isempty(tk) || isempty(peakRange{k}); continue; end
        estAll = arrayfun(@(x) localTrackRange(x.State, useCartesian), tk);
        for t = 1:numel(tk)
            id = tk(t).TrackID;
            if ~isKey(rangeByID, id); continue; end
            estRange = estAll(t);
            [~, im] = min(abs(peakRange{k} - estRange));
            % ONE PEAK, ONE TRACK (11 Sep 2026) -- trackerGNN's own rule. A
            % track COASTING through a missed frame used to borrow whatever
            % peak was nearest, even one GNN had already given to another
            % track -- measured: a weak skin track at 4403 m exported
            % [4403 3185 4356 3138 4356 3138], alternating with its 3185 m
            % neighbour, and every exported series (range, az, rate, NIS...)
            % inherited the splice. Keep the peak only if this track is also
            % the peak's nearest track. NOT the frame log's 200 "m" gate:
            % trackerGNN reads that number as a normalised distance (~14
            % sigma), so as metres it empties genuinely confirmed tracks at
            % low SNR (test_monopulse_snr_boundary D2, 0 dB). Skipping the
            % whole frame keeps every per-track series aligned.
            [~, owner] = min(abs(estAll - peakRange{k}(im)));
            if owner ~= t; continue; end
            rangeByID(id) = [rangeByID(id); peakRange{k}(im)];
            ampByID(id)   = [ampByID(id);   peakAmp{k}(im)];
            timeByID(id)  = [timeByID(id);  times(k)];
            rateByID(id)  = [rateByID(id);  peakRate{k}(im)];
            azByID(id)    = [azByID(id);    peakAz{k}(im)];
            elByID(id)    = [elByID(id);    peakEl{k}(im)];
            combByID(id)  = [combByID(id);  peakComb{k}(im)];
            % IMM mode probabilities, THIS track, THIS frame -- direct
            % TrackID lookup (track.runTracker's own map), no nearest-match
            % needed since this is the tracker's own per-track filter
            % state, not a CFAR peak. Empty Map (FilterModel ~= 'imm') ->
            % isKey false for every id -> modeProbByID stays 0-row, so
            % track.discriminator's screen 2b sees an absent field and
            % no-ops, exactly as documented.
            mpMap = modeProbHistory{k};
            if isKey(mpMap, id)
                modeProbByID(id) = [modeProbByID(id); mpMap(id)];
            end
        end
    end

    trackLabel = strings(1, confirmedCount);
    trackConfidence = nan(1, confirmedCount);
    trackModeSwitchRate = nan(1, confirmedCount);   % screen 2b's own input, reported not folded
    trackRange = cell(1, confirmedCount);
    trackAmp   = cell(1, confirmedCount);
    trackTime  = cell(1, confirmedCount);
    trackRate  = cell(1, confirmedCount);
    trackEl    = cell(1, confirmedCount);
    trackXYZ   = cell(1, confirmedCount);
    trackVel   = cell(1, confirmedCount);
    lifetimes  = zeros(1, confirmedCount);
    for i = 1:confirmedCount
        id = confirmedTracks(i).TrackID;
        rSeq = rangeByID(id); aSeq = ampByID(id); tSeq = timeByID(id);
        dSeq = rateByID(id);
        trackRange{i} = rSeq;
        trackAmp{i}   = aSeq;
        trackTime{i}  = tSeq;   % exposes the actual per-hit times (gaps visible), not just frame_interval_s multiples
        trackRate{i}  = dSeq;
        trackEl{i}    = elByID(id);
        lifetimes(i)  = numel(rSeq);
        % ---- THE TRAJECTORY, IN COORDINATES (position + velocity) ----
        % Assembled from the three MEASUREMENTS already made above -- delay,
        % monopulse angle, and (for the cross-check the caller can run) the
        % slow-time Doppler. This is an ASSEMBLY, not a fourth estimate: the
        % exported position reproduces track_range_m exactly by construction.
        %
        % It exists because a coordinate that is only ever re-derived by the
        % caller is not something the radar recorded. Before this,
        % tests/test_cartesian_measurement.m had to compute R*sin(az) in test
        % code to see the cross-range the difference channel had measured.
        [trackXYZ{i}, trackVel{i}] = localTrackKinematics(rSeq, azByID(id), ...
                                                          elByID(id), tSeq);
        if numel(rSeq) >= 2
            % dSeq is the MEASURED range-rate from the slow-time Doppler
            % processing above (cube path), or an all-zero vector (legacy
            % 2-D path, no slow-time axis to measure from). It is NEVER
            % diff(rSeq) again -- see "DOPPLER IS NOW MEASURED" in the
            % header for what that cost. All-zero correctly trips
            % track.discriminator's own abs(dopplerMean) > 1e-9 guard, so
            % screen 2 self-disables as uninformative instead of handing
            % out a tautological pass.
            %
            % The Doppler-at-gap fix this replaced (Task 4,
            % PHASE2_COMPLETION_POA.md) is no longer needed on the cube
            % path: a per-frame Doppler measurement has no dependence on
            % the elapsed time between DETECTED frames at all, so a missed
            % detection can no longer scale a range-rate by the gap factor.
            % dopplerMeasured tells the discriminator whether a ZERO in
            % dSeq means "this target showed no Doppler" (cube path, a real
            % measurement -> a contradiction against a moving range) or
            % "we never looked" (2-D path -> genuinely uninformative).
            % Without it the discriminator cannot tell the two apart and a
            % zero-Doppler phantom passes by making the evidence
            % inadmissible -- see track/discriminator.m's "MISSING vs
            % ABSENT" block.
            ts = struct('range', rSeq, 'amplitude', aSeq, 'doppler', dSeq, ...
                        'dopplerMeasured', isCube, ...
                        'rangeResolutionM', rangePerSample);
            % rangeResolutionM travels WITH the range series, and must: rSeq is
            % now in the judged signal's own metres (see the range-axis note at
            % the top), so a screen comparing it against physics.Constants()'s
            % 46.84 m would be mixing two instruments' units. Screen 1's lever
            % guard is the consumer.
            % MEASURED per-hit azimuth and the times it was measured at, for
            % screen 2c (bearing/range kinematic consistency). Set only when
            % the angle channel actually produced finite azimuths: on a
            % sum-channel-only export azByID is all-NaN, and passing that
            % would make the screen look available when no bearing was ever
            % measured. Paired with .time so the screen sees the real hit
            % spacing -- a coasted frame leaves a genuine gap, and closing it
            % would fabricate a bearing rate across a dwell the radar never
            % held the track.
            % tSeq is set UNCONDITIONALLY. It used to be attached only
            % alongside a finite azimuth, because screen 2c was the only
            % consumer -- but screen 2d (range-rate magnitude) needs the time
            % base and has nothing to do with the angle channel, and a
            % sum-channel-only export would otherwise silently disable it.
            % Attaching time does NOT enable the bearing screen: that one
            % guards on isfield(trackStruct,'azimuth') separately.
            ts.time = tSeq;
            azSeq = azByID(id);
            if any(isfinite(azSeq))
                ts.azimuth = azSeq;
            end
            % The radar this track was measured by, so screen 2d sizes its
            % Doppler bin from the ACTUAL carrier and PRF rather than
            % rangeRateConsistency's 10 GHz / C.PRF fallbacks. Each is guarded
            % on presence: prf_hz and carrier_hz are only guaranteed on the
            % cube path, and a legacy 2-D export must not be made to error by
            % a screen that is off by default and cannot fire on it anyway
            % (screen 2d needs dopplerMeasured, which is false there).
            ts.numPulses = numPulses;
            if isfield(S, 'carrier_hz') && ~isempty(S.carrier_hz)
                ts.carrierHz = double(S.carrier_hz);
            end
            if isfield(S, 'prf_hz') && ~isempty(S.prf_hz)
                ts.prfHz = double(S.prf_hz);
            end
            ts.rangeSigmaM = opts.RangeSigmaM;
            % MICRO-DOPPLER evidence. Two gates, both of which must be open
            % before discriminator.m is allowed to score it:
            %   microResolvable  -- this dwell could physically see a comb
            %                       (PRF/numPulses < slowest blade rate)
            %   expect_micro_doppler -- the CALLER's threat model says the
            %                       targets of interest are rotorcraft.
            % The second gate exists because this screen, unlike the other
            % two, is NOT class-agnostic: a fixed-wing target legitimately
            % has no rotor comb, so scoring its absence without that
            % assumption would flag every genuine fighter. Default FALSE, so
            % no existing caller changes behaviour.
            cSeq = combByID(id);
            cSeq = cSeq(~isnan(cSeq));
            if ~isempty(cSeq)
                ts.combFrac = mean(cSeq);
            end
            ts.microResolvable = microResolvable;
            if ~isempty(opts.ExpectMicroDoppler)
                ts.expectMicroDoppler = logical(opts.ExpectMicroDoppler);
            end
            % IMM mode-probability series (screen 2b). Absent entirely for
            % CV/CA (modeProbByID(id) stays 0-row -- see the assembly loop
            % above), so the field is only set when there is something to
            % screen, matching .modeProbSeq's documented "absent, not empty"
            % contract in track.discriminator's header.
            mpSeq = modeProbByID(id);
            if ~isempty(mpSeq)
                ts.modeProbSeq = mpSeq;
                % Report the quantity screen 2b actually decides on, as its
                % own column. Without it, a silent 2b is indistinguishable
                % from a 2b whose IMM never moved -- exactly the ambiguity
                % that made the 7 Aug veto conversion hard to interpret.
                % Same posture as track_nis_* and track_confidence:
                % observable, NOT folded into the label.
                if size(mpSeq, 1) >= 2
                    [~, dom] = max(mpSeq, [], 2);
                    % (i), not (t): this loop is over CONFIRMED TRACKS. `t`
                    % is a leftover from the frame-assembly loop above, so
                    % every track's switch rate was being written to one
                    % arbitrary slot. Found while adding the per-track
                    % coordinate export below, which indexes the same way.
                    trackModeSwitchRate(i) = nnz(diff(dom) ~= 0) / (numel(dom) - 1);
                end
            end
            if ~isempty(opts.EccmScreens)     % ablation mask, absent -> all screens on
                ts.screensEnabled = cellstr(opts.EccmScreens);
            end
            [lbl, conf] = track.discriminator(ts, C);
            trackLabel(i) = string(lbl);
            trackConfidence(i) = conf;
        else
            trackLabel(i) = "unscreened";
        end
    end

    % ================= CO-BEARING SCREEN (the anti-DRFM one) =================
    % A repeater transmits from ONE PLACE. Range, Doppler and amplitude can
    % each be forged independently per phantom -- this project has spent a lot
    % of effort showing exactly that -- but AZIMUTH cannot, because it is set
    % by where the transmitter physically is. So N false targets strung along
    % one bearing at wildly different ranges is the classic false-target ECM
    % signature, and catching it needs no amplitude or Doppler reasoning at all.
    %
    % THIS SCREEN LIVES HERE, NOT IN track/discriminator.m, ON PURPOSE. It is
    % inherently MULTI-TRACK: the question "do these tracks share a bearing?"
    % cannot be answered by any per-track function, and discriminator.m is
    % called once per track. This is the first screen in the project that
    % reasons across tracks.
    %
    % THRESHOLD IS SELF-CALIBRATING, not a tuned constant: compare the spread
    % of the tracks' MEAN azimuths against the scatter WITHIN each track's own
    % azimuth series. If several tracks sit closer together than one track's
    % own measurement noise, they are one emitter. That adapts automatically to
    % SNR, integration length and subaperture geometry.
    coBearing = false;
    trackAz = cell(1, confirmedCount);
    azMeans = nan(1, confirmedCount); azStds = nan(1, confirmedCount);
    for i = 1:confirmedCount
        a = azByID(confirmedTracks(i).TrackID);
        % EXPORTED ALIGNED, stripped only for the statistics below. It used to
        % be exported NaN-stripped while track_time_s and track_range_m were
        % not, so any caller pairing the three -- and every one of them does,
        % including +track/bearingRateScreen.m's own inputs in
        % +experiments/bearingHeadroom.m -- silently compared azimuth k
        % against the time and range of hit k+1 the moment one peak yielded a
        % non-finite angle. Alignment is the series' contract; the co-bearing
        % statistics can drop their own NaNs locally.
        trackAz{i} = a;
        aFin = a(~isnan(a));
        if ~isempty(aFin); azMeans(i) = mean(aFin); end
        if numel(aFin) >= 2; azStds(i) = std(aFin); end
    end
    % ============ THE SCREEN HAS AN UPPER VALIDITY LIMIT TOO ============
    % The documented bound on this screen has always been a LOWER one (a
    % genuine formation needs ~40 m of cross-range spread not to look like a
    % fan). There is an UPPER one as well, and it was undocumented until
    % tests/test_monopulse_snr_boundary.m failed on it.
    %
    % Phase-comparison monopulse is unambiguous only within
    % asin(lambda/(2*subSep)) -- +-2.866 deg at 0.30 m and 10 GHz. phiEst
    % above is 2*atan(imag(.)), which lives in (-pi, pi), so a target OUTSIDE
    % that sector does not saturate: its phase WRAPS and it is reported at a
    % completely wrong azimuth. Measured on this project's own geometry: a
    % genuine object 80 m off boresight at 900 m is truly at +5.100 deg and is
    % MEASURED at -0.637 deg.
    %
    % The consequence is the opposite of the screen's intent. A genuine
    % formation WIDER than the sector has its outer members folded back
    % toward the middle, its apparent azimuth spread collapses, and it is
    % condemned as co-bearing -- the screen accuses real aircraft precisely
    % when they are most widely separated. Measured flag rate against genuine
    % cross-range spread is therefore NON-MONOTONIC: 100/50/38/25/12/0% out to
    % 80 m, then back up to 75% at 160 m.
    %
    % THIS CANNOT BE FIXED IN SOFTWARE HERE, and saying so is the honest
    % answer: one aperture cannot distinguish +5.100 deg from -0.637 deg,
    % because they produce the identical phase. Resolving it needs a second
    % baseline (a third subaperture, or a second PRF/wavelength). What CAN be
    % done is to REPORT the limit so no caller quotes a co-bearing verdict
    % without knowing the sector it is valid inside -- feedback.unambiguous_az_rad
    % below, and the cross-range ceiling it implies at each track's own range.
    CO_BEARING_SIGMAS = 3;      % 3-sigma: "closer together than one track's own noise"
    valid = ~isnan(azMeans);
    if hasAngle && nnz(valid) >= 2
        pooledStd = sqrt(mean(azStds(~isnan(azStds)).^2));
        if isnan(pooledStd) || pooledStd <= 0
            pooledStd = eps;    % degenerate: no within-track scatter to compare against
        end
        spread = max(azMeans(valid)) - min(azMeans(valid));
        coBearing = spread < CO_BEARING_SIGMAS * pooledStd;
        if coBearing
            % Every co-bearing track is condemned together -- that is the
            % point: the giveaway is the GROUP, not any individual track.
            trackLabel(valid) = "decoy";
        end
    end

    % ============= NIS CONSISTENCY (Tier 1.1), a SEPARATE column =============
    % The stateful tracker has always run across frames; nothing ever computed
    % an innovation from it. This does -- per confirmed track, from that
    % track's own hit ranges and hit TIMES (so a missed dwell lengthens dt
    % instead of being silently counted as one interval).
    %
    % DELIBERATELY NOT FOLDED INTO trackLabel. The Tier 1.1 brief is explicit:
    % report it alongside first, so its effect on the evasion rate can be seen
    % in isolation before anyone decides to combine it with the four screens.
    % Combining it here would make that measurement impossible to take.
    nisMean = nan(1, confirmedCount);
    nisInGate = nan(1, confirmedCount);
    nisPass = false(1, confirmedCount);
    % Tier 1.2 -- the explicit RGPO/VGPO MAGNITUDE detector. Also a separate
    % column, for the same reason. Note it is NOT redundant with
    % track.discriminator screen 2, which compares only SIGNS: a phantom
    % walking range at -50 m/s while transmitting -5 m/s of Doppler passes
    % that screen and fails this one.
    rrMismatch = nan(1, confirmedCount);
    rrThreshold = nan(1, confirmedCount);
    rrPass = true(1, confirmedCount);
    for i = 1:confirmedCount
        if numel(trackRange{i}) >= 2
            nisOut = track.nisConsistency(trackRange{i}, trackTime{i}, C, ...
                        'GateChi2', opts.NisGateChi2);
            nisMean(i)   = nisOut.meanNIS;
            nisInGate(i) = nisOut.inGateFrac;
            nisPass(i)   = nisOut.pass;

            % Only meaningful where a Doppler measurement exists at all; on
            % the legacy 2-D path trackRate is an all-zero placeholder and
            % accusing a track on it would be exactly the "absent vs missing
            % evidence" error track/discriminator.m documents.
            if isCube
                rrOut = track.rangeRateConsistency(trackRange{i}, trackTime{i}, ...
                            trackRate{i}, C, 'NumPulses', numPulses, ...
                            'CarrierHz', double(S.carrier_hz), 'PrfHz', double(S.prf_hz), ...
                            'Sigmas', opts.RangeRateSigmas, ...
                            'RangeSigmaM', opts.RangeSigmaM);
                rrMismatch(i)  = rrOut.mismatchMps;
                rrThreshold(i) = rrOut.thresholdMps;
                rrPass(i)      = rrOut.pass;
            end
        end
    end

    isReal  = trackLabel == "real";
    isDecoy = trackLabel == "decoy";

    feedback = struct();
    feedback.confirmed_tracks = confirmedCount;
    feedback.false_tracks_surviving = nnz(isReal);
    feedback.flagged_decoys = nnz(isDecoy);
    feedback.mean_track_lifetime_frames = mean([lifetimes, 0]); % mean([],0)-safe when confirmedCount==0
    % Aggregate label for single-track/back-compat callers (unanimous ->
    % that label; mixed real+decoy tracks -> "mixed"; none confirmed -> "").
    if confirmedCount == 0
        feedback.eccm_label = "";
    elseif all(trackLabel == trackLabel(1))
        feedback.eccm_label = char(trackLabel(1));
    else
        feedback.eccm_label = 'mixed';
    end
    feedback.track_label  = cellstr(trackLabel);
    % Recoverable mean-screen SCORE (0.5 +/- confidence/2, signed by label)
    % from track.discriminator's own confidence output -- additive column,
    % same pattern as track_nis_mean below, so a caller comparing two runs
    % (e.g. FilterModel cv vs imm) can report an actual score delta instead
    % of only a label flip.
    feedback.track_confidence = trackConfidence;
    feedback.track_mode_switch_rate = trackModeSwitchRate;   % NaN unless FilterModel='imm'
    feedback.track_range_m = trackRange;
    feedback.track_amp     = trackAmp;
    feedback.track_time_s  = trackTime;
    feedback.track_range_rate_mps = trackRate;   % MEASURED (cube path) or zeros (legacy 2-D)
    feedback.track_azimuth_rad    = trackAz;     % MEASURED (angle path) or empty
    feedback.track_azimuth_mean   = azMeans;
    feedback.cobearing_flagged    = coBearing;
    % ---- the mapped trajectory, in coordinates ----------------------------
    % Radar at the origin, +x boresight, +y cross-range right, +z up -- the
    % same convention as generator/platform.py, stated in both places so the
    % two cannot drift.
    feedback.track_elevation_rad    = trackEl;    % MEASURED, NaN where absent
    feedback.track_position_xyz_m   = trackXYZ;   % [3 x K] per confirmed track
    feedback.track_velocity_xyz_mps = trackVel;   % [3 x 1], CV fit over the above
    % ---- the two quantities that tie a track back to its emitter ----------
    % ANGULAR RATE is the invariant a single transmitter cannot vary between
    % the phantoms it radiates. Every phantom leaves the same aperture, so
    % every one of them sweeps at the PLATFORM's dtheta/dt regardless of the
    % range it claims. A genuine formation cannot do this: independent
    % aircraft at different ranges have independent angular rates, because
    % omega = v_cross / R and neither term is shared.
    %
    % IMPLIED CROSS SPEED is that same fact in metres per second -- what
    % tangential speed this track's own claimed range demands to explain the
    % bearing sweep actually measured. It is the number that makes the
    % deception legible: a phantom at 4 km fed by a platform at 900 m implies
    % 4.4x the platform's real cross-range speed, and N phantoms at N ranges
    % imply N speeds in exact proportion to their ranges.
    %
    % REPORTED, NOT FOLDED INTO THE LABEL -- same posture as track_nis_* and
    % track_confidence. The screen that scores this is 2c
    % (+track/bearingRateScreen.m) and it is opt-in; these columns are always
    % available so a caller can do the comparison itself, visibly.
    trackOmega = nan(1, confirmedCount);
    trackCross = nan(1, confirmedCount);
    for i = 1:confirmedCount
        % azByID, NOT trackAz: the latter is NaN-stripped for the co-bearing
        % statistics and so no longer aligns with the time and range series.
        aSeq = azByID(confirmedTracks(i).TrackID); aSeq = aSeq(:);
        tSeq = trackTime{i}(:); rSeq = trackRange{i}(:);
        ok = isfinite(aSeq) & isfinite(tSeq);
        if nnz(ok) >= 2 && (max(tSeq(ok)) - min(tSeq(ok))) > 0
            pf = polyfit(tSeq(ok), aSeq(ok), 1);
            trackOmega(i) = pf(1);
            trackCross(i) = pf(1) * mean(rSeq(ok));
        end
    end
    feedback.track_angular_rate_rad_s      = trackOmega;
    feedback.track_implied_cross_speed_mps = trackCross;
    if hasElev
        feedback.elevation_source = 'monopulse';
    else
        % z is ASSUMED zero, not measured to be zero. Same posture as
        % angle_source and dopplerMeasured: the caller must be able to tell
        % "we looked and it was flat" from "we never had the channel".
        feedback.elevation_source = 'none';
    end
    % Tier 1.1 -- the NIS column. Separate from track_label BY DESIGN; a
    % caller wanting a combined verdict must combine them itself, visibly.
    feedback.track_nis_mean     = nisMean;
    feedback.track_nis_in_gate  = nisInGate;
    feedback.track_nis_pass     = nisPass;
    feedback.nis_gate_chi2      = opts.NisGateChi2;
    % Tier 1.2 -- the RGPO/VGPO magnitude column, also separate from track_label.
    feedback.track_rate_mismatch_mps = rrMismatch;
    feedback.track_rate_threshold_mps = rrThreshold;
    feedback.track_rate_pass    = rrPass;
    if hasAngle
        feedback.angle_source = 'monopulse';
        % The sector the azimuths above are VALID inside. A track reported
        % outside it is not clamped, it is WRAPPED -- see the co-bearing block.
        feedback.unambiguous_az_rad = asin(min(1, lambda/(2*subSep)));
        % ... and what that sector is worth in metres at each confirmed
        % track's own range, since a formation's spread is a cross-range
        % quantity and the angular limit alone is easy to misread.
        if confirmedCount > 0
            lastR = cellfun(@(r) localLastOrNaN(r), trackRange);
            feedback.cross_range_ceiling_m = lastR .* tan(feedback.unambiguous_az_rad);
        else
            feedback.cross_range_ceiling_m = [];
        end
    else
        feedback.angle_source = 'none';          % this radar cannot measure angle
        feedback.unambiguous_az_rad = NaN;
        feedback.cross_range_ceiling_m = [];
    end
    % ================= BACKTRACK: WHERE IS THE EMITTER? ======================
    % Run the deception backwards. Every phantom from one aperture carries that
    % platform's OWN bearing (Blueprint 2.4). Pooling the tracks' measured
    % azimuths therefore estimates the EMITTER's bearing, and does so better
    % the more phantoms it transmits: the adversary pays for each extra false
    % target with another independent look at itself.
    %
    % ONLY WHEN THE TRACKS SHARE A BEARING (11 Sep 2026). A genuine formation,
    % or a multi-drone swarm (+generator/render.m PhantomAzimuthRad), puts its
    % tracks at several bearings; their mean is no emitter's bearing, yet it
    % used to be exported as a 'nearest-cobearing' fix regardless. The pool is
    % now taken only for one track or a co-bearing group; otherwise the fix is
    % 'none-multiple-bearings' and pairwise attribution is
    % +track/skinBacktrack.m's job.
    %
    % WHAT ONE APERTURE CAN AND CANNOT RECOVER, stated plainly because the
    % difference is geometry and no amount of processing changes it:
    %   BEARING  recovered, and it is a real measurement.
    %   RANGE    NOT recoverable from the phantoms alone. The apparent range
    %            of a phantom is R_mother + c*tau/2 for a repeater delay tau
    %            the radar never observes, and bearings-only motion analysis
    %            from a STATIONARY receiver leaves range unobservable for a
    %            constant-velocity emitter (it needs an observer manoeuvre or
    %            a second receiver). What IS available is a hard upper bound
    %            from causality -- a repeater cannot plant a phantom in front
    %            of itself, so R_emitter <= min over tracks of that track's
    %            own nearest range.
    % So the fix reported here is a bearing plus a bounded range, and the
    % nearest co-bearing track is the tightest bound the scene offers. If the
    % platform is itself detectable -- a drone has an RCS and reflects the
    % radar's own pulse -- that nearest return IS the platform, and the bound
    % collapses onto a genuine position. The export does not claim to know
    % which case it is in; it reports the bound and lets the caller say.
    emitterAz = NaN; emitterEl = NaN; emitterRangeMax = Inf;
    emitterPos = nan(3,1); emitterFix = 'none';
    multiBearing = hasAngle && nnz(valid) >= 2 && ~coBearing;
    if multiBearing
        emitterFix = 'none-multiple-bearings';
    elseif hasAngle && confirmedCount > 0
        azAll = cell2mat(cellfun(@(a) a(:), trackAz(:)', 'UniformOutput', false)');
        emitterAz = mean(azAll(isfinite(azAll)));
        elAll = cell2mat(cellfun(@(e) e(:), trackEl(:)', 'UniformOutput', false)');
        if any(isfinite(elAll)); emitterEl = mean(elAll(isfinite(elAll))); end
        % [r; Inf]: a confirmed track can own no peak at all (every frame's
        % nearest peak belonged to another track), and min([]) is [].
        nearestPerTrack = cellfun(@(r) min([r(:); Inf]), trackRange);
        [emitterRangeMax, iNear] = min(nearestPerTrack);
        elForPos = emitterEl; if ~isfinite(elForPos); elForPos = 0; end
        emitterPos = localSphericalToCartesian(emitterRangeMax, emitterAz, ...
                                                elForPos, 0, 0, 0);
        emitterFix = 'nearest-cobearing';
        feedback.emitter_track_index = iNear;
    end
    feedback.emitter_az_rad        = emitterAz;
    feedback.emitter_el_rad        = emitterEl;
    feedback.emitter_range_max_m   = emitterRangeMax;   % causality UPPER BOUND
    feedback.emitter_position_xyz_m = emitterPos;       % that bound, in coordinates
    feedback.emitter_fix           = emitterFix;
    % ---- range ambiguity, reported with every result (Phase C1) ----------
    feedback.unambiguous_range_m = ambigInfo.unambiguous_range_m;
    feedback.range_window_m      = ambigInfo.window_span_m;
    feedback.prf_window_consistent = ambigInfo.consistent;
    % Where each confirmed track's measured range WOULD fold to if this
    % radar's declared PRF is the honest one. Equal to track_range_m for any
    % track inside R_ua, so a caller comparing the two sees the ambiguity
    % order directly.
    if isempty(trackRange)
        feedback.track_apparent_range_m = {};
    else
        feedback.track_apparent_range_m = cellfun( ...
            @(r) physics.apparentRange(r, double(S.prf_hz)), trackRange, ...
            'UniformOutput', false);
    end
    feedback.frame_log     = frameLog;
    feedback.num_frames    = numFrames;
    feedback.num_pulses_per_frame = numPulses;
    feedback.frame_interval_s = S.frame_interval_s;
    % No caller may quote a track label without knowing whether a Doppler
    % screen was actually behind it (CLAUDE.md Rule 7).
    if isCube
        feedback.doppler_source = 'measured';
    else
        feedback.doppler_source = 'none-2d-export-screen-disabled';
    end
end

% ===================== file-local helpers =============================
function peaks = localMaxPeaks(detIdx, power)
%LOCALMAXPEAKS  Collapse a CFAR detIdx list into one local-max bin per
%   contiguous run of adjacent indices -- a single physical target's
%   return commonly crosses the CFAR threshold over several neighboring
%   range bins; without this, one target would spawn several "detections"
%   in the same frame and corrupt the multi-target tracker/discriminator.
    detIdx = sort(detIdx(:));
    peaks = zeros(0,1);
    n = numel(detIdx);
    if n == 0; return; end
    runStart = 1;
    for i = 2:n+1
        atBreak = (i > n) || (detIdx(i) - detIdx(i-1) > 1);
        if atBreak
            run = detIdx(runStart:i-1);
            [~, im] = max(power(run));
            peaks(end+1,1) = run(im); %#ok<AGROW>
            runStart = i;
        end
    end
end

function v = localLastOrNaN(r)
%LOCALLASTORNAN  Last element, or NaN for an empty series.
    if isempty(r); v = NaN; else; v = r(end); end
end

function opts = localParseJudgeConfig(args)
%LOCALPARSEJUDGECONFIG  The judge's own operating point, settable ONLY here.
%   Every default is [] = "not specified", so the value actually in force is
%   the one declared by radar.cfarDetect / track.trackerDefaults /
%   track.discriminator. This function deliberately re-declares none of
%   them; a copy here is exactly the C3 staleness bug.
%
%   MicroBladeHzMin is the one exception and it is the JUDGE's own screen
%   constant, not a copy of anything: 100 Hz, the low end of the 100-200 Hz
%   blade-rate band measured across four drone types in the TSMS-Drone CW
%   set (experiments.microDopplerScreenability). It used to be overridable
%   from the .mat, i.e. by the adversary.
    p = inputParser;
    p.addParameter('Pfa',                   []);
    p.addParameter('NumTraining',           []);
    p.addParameter('NumGuard',              []);
    p.addParameter('AssignmentThreshold',   []);
    p.addParameter('ConfirmationThreshold', []);
    p.addParameter('DeletionThreshold',     []);
    p.addParameter('FilterModel',           []);
    p.addParameter('TrackerType',           []);
    p.addParameter('EccmScreens',           []);
    p.addParameter('ExpectMicroDoppler',    []);
    p.addParameter('MicroBladeHzMin',       100);
    % Tier 1.1 -- the multi-dwell NIS gate. Reported as its OWN column, never
    % folded into the ECCM score. See track.nisConsistency for why 7.81 is the
    % conservative choice and 3.84 the tight one; it is a tunable either way.
    p.addParameter('NisGateChi2',           7.81);
    % Tier 1.2 -- sigmas on the derived range-rate-vs-Doppler tolerance. The
    % tolerance itself is DERIVED from the two quantisers (see
    % track.rangeRateConsistency); this is only how many sigmas of it to allow.
    p.addParameter('RangeRateSigmas',       3);
    % ---- Sub-bin peak interpolation (21 Aug 2026) --------------------------
    % false = report the integer CFAR peak bin, which is what every published
    % number in this repo was measured with. true = refine it with
    % radar.subBinPeak, so a track's range can move by less than one 46.84 m
    % cell.
    %
    % DEFAULTS TO false, same posture as MeasurementSpace above and for the
    % same reason: range is the quantity the tracker gates on, the
    % discriminator fits and rangeRateConsistency differences, so switching it
    % on moves association, confirmation and every screen at once. Opt in per
    % caller.
    %
    % AND ON THIS RADAR IT CURRENTLY BUYS NOTHING, which is the reason this is
    % a flag rather than simply the new behaviour. C.bandwidth = 2 MHz against
    % C.fs = 3.2 MHz aliases the transmit waveform -- MEASURED, 18.2% of the
    % chirp's energy folds past +-fs/2 -- so the compressed mainlobe is
    % corrupted and interpolating it returns 0.267 bins rms against the raw
    % bin's 0.266. At the bench's clean 6.4/2 = 3.20 the same estimator
    % reaches 0.0036 bins, a 74x improvement. Switch this on for a bench
    % campaign; switching it on here fixes nothing until C.fs > 2*C.bandwidth.
    % Numbers and cross-checks: radar.subBinPeak, tests/test_sub_bin_interp.m.
    p.addParameter('SubBinInterp', false, @(x) isscalar(x) && islogical(x));
    % The per-endpoint range accuracy, in metres, that track.rangeRateConsistency
    % should size its gate from. [] = let it use its own uniform-quantiser
    % derivation, delta/sqrt(12), which is correct WHEN AND ONLY WHEN
    % SubBinInterp is false.
    %
    % This is a separate knob from SubBinInterp on purpose. The judge must not
    % GUESS its own range accuracy: with interpolation on, accuracy depends on
    % the oversampling ratio and the detection SNR, neither of which runJudge
    % measures, and a self-assessed sigma would let the gate quietly re-size
    % itself scene by scene. Whoever characterised the instrument states the
    % number; tests/test_sub_bin_interp.m is where this one was characterised.
    %
    % Turning SubBinInterp on and leaving this empty is not an error, but it
    % leaves the gate sized for a coarser range than the one being measured --
    % i.e. LOOSE by ~23% at this simulation's fs/B. Stated so the combination
    % is a choice rather than an oversight.
    p.addParameter('RangeSigmaM', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    % S3 -- what the tracker is handed as a measurement.
    %   'range'      [R; 0; 0] with diag([dR^2, 1, 1]) -- the historical
    %                shape, and a lie the tracker was never told about: the
    %                last two components are hardcoded zeros with a claimed
    %                1 m standard deviation (RADAR_REALISM_AUDIT.md Tier 1,
    %                "no angle channel at all").
    %   'cartesian'  the real (x, y, z) the measured range/azimuth/elevation
    %                imply, with the covariance the spherical->Cartesian
    %                Jacobian gives.
    % DEFAULTS TO 'range', and that is deliberate rather than timid: changing
    % the measurement SPACE changes gating and association for every scene in
    % the repo, so every published confirmed-track count would move at once
    % and no single result would be attributable. Opt in per caller, the same
    % posture FilterModel='imm' and the elevation channel already take.
    p.addParameter('MeasurementSpace',      'range');
    % ---- MTI / clutter notch (16 Aug 2026) ---------------------------------
    % Half-width in METRES PER SECOND of the zero-Doppler filter this radar
    % discards. 0 = OFF, which is the default and preserves every published
    % detection number: until +physics/surfaceClutter.m existed there was no
    % clutter to reject, so no result in this repo was measured with a notch.
    %
    % WHY IT IS EXPRESSED AS A SPEED. A notch is a statement about what the
    % radar refuses to believe is moving, and that is physical. Converting to
    % bins is arithmetic the judge can do: the velocity bin here is
    % lambda*PRF/(2*numPulses) = 3.75 m/s, so 3.75 notches +-1 bin.
    %
    % WHY IT IS NOT DERIVED AND SET AUTOMATICALLY. The right width is the
    % clutter's own spectral extent -- internal motion of wind-blown terrain,
    % plus whatever the FFT window's sidelobes smear -- and this project
    % models neither. Picking a number and calling it derived would be a magic
    % constant with a justification attached. It is a parameter, and any
    % result that uses it must say which value.
    %
    % AND IT IS NOT FREE. The same filter that removes ground return removes
    % genuinely slow and tangential targets: a hovering drone has no radial
    % rate and is indistinguishable from clutter to any MTI radar. That is a
    % real limitation of real radars, not an artefact here, and
    % +experiments/clutterImpact.m measures both sides of it.
    p.addParameter('MtiNotchMps',           0, @(x) isscalar(x) && x >= 0);
    p.parse(args{:});
    opts = p.Results;
end

function r = localTrackRange(state, useCartesian)
%LOCALTRACKRANGE  A track's estimated SLANT RANGE, whichever space it lives in.
%
%   THIS FUNCTION IS THE CONTAINMENT RULE FOR S3, and it is the reason a
%   Cartesian tracker does not cascade through the repo. +track/discriminator.m
%   reads trackStruct.range -- a scalar series -- and so do every screen, every
%   fixture and every published label. Moving the tracker into (x,y,z) changes
%   what State() means; converting back to a slant range HERE keeps every
%   downstream contract byte-identical, so the blast radius stays inside
%   runJudge and runTracker.
%
%   'range' space  : initcvekf's state is [R; Rdot; 0; 0; 0; 0], so State(1)
%                    IS the range, exactly as before.
%   'cartesian'    : the state is [x; vx; y; vy; z; vz] and the range is the
%                    norm of the position components (1, 3, 5).
    if useCartesian
        r = norm([state(1), state(3), state(5)]);
    else
        r = state(1);
    end
end


function s = localAngleSigma(angleRad, subSepM, lambda)
%LOCALANGLESIGMA  Standard deviation to attach to one angle measurement.
%   A MEASURED angle gets the estimator's own scatter, taken as one tenth of
%   the unambiguous half-sector asin(lambda/(2*d)) -- a deliberately
%   conservative stand-in for the 0.0726 deg worst-case within-track scatter
%   tests/test_monopulse_snr_boundary.m measured, chosen so it degrades with
%   the geometry (a shorter baseline widens the sector AND the error) rather
%   than being one number typed in.
%
%   An UNMEASURED angle (no difference channel, or a bin where the sum was
%   zero) gets the FULL half-sector. That direction is the safe one: an
%   unknown bearing must widen the gate. Giving it a small sigma would tell
%   the tracker the target is confidently on boresight, which is the failure
%   the [R;0;0] measurement had.
    half = asin(min(1, lambda / (2 * subSepM)));
    if isfinite(angleRad)
        s = half / 10;
    else
        s = half;
    end
end


function [pos, Rcov] = localSphericalToCartesian(R, az, el, sR, sAz, sEl)
%LOCALSPHERICALTOCARTESIAN  Position and its covariance, by the Jacobian.
%   x = R*cos(el)*cos(az), y = R*cos(el)*sin(az), z = R*sin(el)
%   Rcov = J * diag([sR^2, sAz^2, sEl^2]) * J'
%   Same convention as generator/platform.py: +x boresight, +y cross-range
%   right, +z up.
    ce = cos(el); se = sin(el); ca = cos(az); sa = sin(az);
    pos = [R*ce*ca; R*ce*sa; R*se];
    J = [ce*ca, -R*ce*sa, -R*se*ca; ...
         ce*sa,  R*ce*ca, -R*se*sa; ...
         se,     0,        R*ce];
    Rcov = J * diag([sR^2, sAz^2, sEl^2]) * J';
    Rcov = (Rcov + Rcov') / 2;      % symmetrise against round-off; trackerGNN
end                                  % rejects a non-symmetric covariance


function [P, V] = localTrackKinematics(rSeq, azSeq, elSeq, tSeq)
%LOCALTRACKKINEMATICS  One track's measured trajectory, as coordinates.
%   P  [3 x K] position at each hit, radar at the origin
%   V  [3 x 1] constant-velocity fit over P, or NaN if under-determined
%
%   POSITION IS AN ASSEMBLY, NOT AN ESTIMATE. x = R*cos(el)*cos(az) etc, from
%   the measurements already made -- so norm(P(:,k)) reproduces the range
%   series the ECCM screens read, exactly. Nothing here re-measures anything.
%
%   AN UNMEASURED ANGLE IS TAKEN AS ZERO, which is an ASSUMPTION and is
%   reported as one (feedback.angle_source / elevation_source). Zero is the
%   right assumption to make visible rather than the right answer: with no
%   difference channel the target is assumed on boresight, and that
%   assumption is precisely the [R;0;0] lie this export exists to expose.
%
%   VELOCITY IS A CV FIT, matching this project's declared threat model
%   (CLAUDE.md's standing callout), one least-squares slope per axis. It is
%   NOT the tracker's filter state: that state is only three-dimensional in
%   MeasurementSpace='cartesian', and this export must mean the same thing in
%   both spaces. Deliberately INDEPENDENT of the slow-time Doppler, so a
%   caller can project V onto the line of sight and compare it against
%   track_range_rate_mps -- two extractions from different parts of the
%   signal, which is only a check if neither is derived from the other.
%
%   ITS RADIAL COMPONENT IS THE WORSE OF THE TWO, BY A LOT. The range series
%   is quantised, not noisy: a target crossing range cells at a non-integer
%   rate produces a staircase, and a straight line through a staircase can
%   only realise slopes that are whole cells over the fit span. The error is
%   therefore bounded by range_per_sample / span -- about 9 m/s over a 5 s
%   track here, against the 1.3 m/s the slow-time Doppler achieves on the
%   same target. READ track_range_rate_mps FOR RADIAL SPEED. What this vector
%   uniquely provides is the CROSS-RANGE component, which comes from the
%   bearing rate and which no Doppler measurement can supply at all.
    K = numel(rSeq);
    P = zeros(3, K); V = nan(3, 1);
    if K == 0; return; end
    az = azSeq(:); el = elSeq(:);
    az(~isfinite(az)) = 0;
    el(~isfinite(el)) = 0;
    r = rSeq(:);
    P = [r .* cos(el) .* cos(az), r .* cos(el) .* sin(az), r .* sin(el)]';
    % 2 points minimum for a slope, and the times must actually differ --
    % a single-frame track has no velocity, and saying NaN is the honest
    % answer rather than 0, which would read as "measured, stationary".
    t = tSeq(:);
    if K < 2 || (max(t) - min(t)) <= 0; return; end
    for ax = 1:3
        c = polyfit(t, P(ax, :)', 1);
        V(ax) = c(1);
    end
end


function nv = localNameValue(opts, names)
%LOCALNAMEVALUE  Flatten the specified-only options into a name-value list.
    nv = {};
    for i = 1:numel(names)
        v = opts.(names{i});
        if ~isempty(v); nv = [nv, {names{i}, v}]; end %#ok<AGROW>
    end
end
