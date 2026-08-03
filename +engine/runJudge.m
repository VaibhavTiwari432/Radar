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
    wavForFrame = @(k) radar.agileWaveform(sweepSched(k), S.fs, S.pulse_width_s, ...
                                            S.prf_hz, S.bandwidth_hz);
    wav = wavForFrame(1);   % representative, for the Doppler axis scaling

    times = (0:numFrames-1) * S.frame_interval_s;
    dets = cell(1, numFrames);
    peakRange = cell(1, numFrames);
    peakAmp   = cell(1, numFrames);
    peakRate  = cell(1, numFrames);   % MEASURED range-rate [m/s], cube path only
    peakAz    = cell(1, numFrames);   % MEASURED azimuth [rad], angle path only
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

        peakRange{k} = (peakBins - 1) * C.range_per_sample;
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
                az(j)  = asin(max(-1, min(1, sinTh)));   % clamp: outside the
            end                                          % unambiguous sector
            peakAz{k} = az;                              % asin would go complex
        else
            peakAz{k} = nan(numel(peakBins), 1);
        end

        % MeasurementNoise reflects the REAL range-bin quantization error
        % (~C.range_per_sample, ~46.8 m std), not eye(3)'s claimed 1 m std.
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
        measNoise = diag([C.range_per_sample^2, 1, 1]);
        detArr = objectDetection.empty;
        for j = 1:numel(peakBins)
            detArr(j) = objectDetection(times(k), [peakRange{k}(j); 0; 0], ...
                            'MeasurementNoise', measNoise); %#ok<AGROW>
        end
        dets{k} = detArr;
    end

    % Sweepable radar operating point -- from this function's OWN caller
    % (+experiments/benchmarkSuite.m's Tier-2 sweeps), never from the .mat.
    % Empty -> omitted, so +track/trackerDefaults.m's values stand.
    trkArgs = localNameValue(opts, {'AssignmentThreshold', ...
        'ConfirmationThreshold', 'DeletionThreshold', 'FilterModel', 'TrackerType'});

    [confirmedTracks, history] = track.runTracker(dets, times, C, trkArgs{:});
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
            estRange = tk(t).State(1);
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
                hitCountByID(id) = 0; missStreakByID(id) = 0; %#ok<NASGU>
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
    combByID  = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for id = confirmedIDs
        rangeByID(id) = zeros(0,1);
        ampByID(id)   = zeros(0,1);
        timeByID(id)  = zeros(0,1);
        rateByID(id)  = zeros(0,1);
        azByID(id)    = zeros(0,1);
        combByID(id)  = zeros(0,1);
    end
    for k = 1:numFrames
        tk = history{k};
        if isempty(tk) || isempty(peakRange{k}); continue; end
        for t = 1:numel(tk)
            id = tk(t).TrackID;
            if ~isKey(rangeByID, id); continue; end
            estRange = tk(t).State(1);
            [~, im] = min(abs(peakRange{k} - estRange));
            rangeByID(id) = [rangeByID(id); peakRange{k}(im)];
            ampByID(id)   = [ampByID(id);   peakAmp{k}(im)];
            timeByID(id)  = [timeByID(id);  times(k)];
            rateByID(id)  = [rateByID(id);  peakRate{k}(im)];
            azByID(id)    = [azByID(id);    peakAz{k}(im)];
            combByID(id)  = [combByID(id);  peakComb{k}(im)];
        end
    end

    trackLabel = strings(1, confirmedCount);
    trackRange = cell(1, confirmedCount);
    trackAmp   = cell(1, confirmedCount);
    trackTime  = cell(1, confirmedCount);
    trackRate  = cell(1, confirmedCount);
    lifetimes  = zeros(1, confirmedCount);
    for i = 1:confirmedCount
        id = confirmedTracks(i).TrackID;
        rSeq = rangeByID(id); aSeq = ampByID(id); tSeq = timeByID(id);
        dSeq = rateByID(id);
        trackRange{i} = rSeq;
        trackAmp{i}   = aSeq;
        trackTime{i}  = tSeq;   % exposes the actual per-hit times (gaps visible), not just frame_interval_s multiples
        trackRate{i}  = dSeq;
        lifetimes(i)  = numel(rSeq);
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
                        'dopplerMeasured', isCube);
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
            if ~isempty(opts.EccmScreens)     % ablation mask, absent -> all screens on
                ts.screensEnabled = cellstr(opts.EccmScreens);
            end
            [lbl, ~] = track.discriminator(ts, C);
            trackLabel(i) = string(lbl);
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
        a = a(~isnan(a));
        trackAz{i} = a;
        if ~isempty(a); azMeans(i) = mean(a); end
        if numel(a) >= 2; azStds(i) = std(a); end
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
                            'Sigmas', opts.RangeRateSigmas);
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
    feedback.track_range_m = trackRange;
    feedback.track_amp     = trackAmp;
    feedback.track_time_s  = trackTime;
    feedback.track_range_rate_mps = trackRate;   % MEASURED (cube path) or zeros (legacy 2-D)
    feedback.track_azimuth_rad    = trackAz;     % MEASURED (angle path) or empty
    feedback.track_azimuth_mean   = azMeans;
    feedback.cobearing_flagged    = coBearing;
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
    p.parse(args{:});
    opts = p.Results;
end

function nv = localNameValue(opts, names)
%LOCALNAMEVALUE  Flatten the specified-only options into a name-value list.
    nv = {};
    for i = 1:numel(names)
        v = opts.(names{i});
        if ~isempty(v); nv = [nv, {names{i}, v}]; end %#ok<AGROW>
    end
end
