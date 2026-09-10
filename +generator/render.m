function judgeMatPath = render(preRenderMatPath, judgeMatPath, varargin)
%RENDER  Physics-Projection-approved phantom trajectories -> the judge-ready
%        .mat +engine/runJudge.m actually reads.
%
%   judgeMatPath = generator.render(preRenderMatPath, judgeMatPath, ...)
%       preRenderMatPath : written by generator.interface.export_plan_for_render
%                          (Python) -- phantom_range_m/phantom_amplitude/
%                          phantom_phase_rad [nPhantoms x nSamplesTotal],
%                          phantom_rcs_m2 [nPhantoms x 1], fs, pulse_width_s,
%                          bandwidth_hz, prf_hz, carrier_hz, frame_interval_s,
%                          num_pulses_per_frame, optional sweep_schedule.
%       judgeMatPath     : where to write rx_frames etc. for engine.runJudge.
%
%   Name-value (all optional; defaults are this project's own established
%   operating point, +physics/simUnits.m / +physics/Constants.m):
%       'FastTimeSamples'    400   receive-window length [samples]
%       'NoiseAmplitude'     0.05  the simulation's thermal-noise convention
%       'SourceAzimuthRad'   0     ONE bearing per FRAME, shared by every
%                          phantom (see below). Scalar = the historical fixed
%                          bearing; a vector of >= numFrames entries is the
%                          mother platform's own azimuth trajectory
%                          (generator/platform.py's MotherTrack.azimuth_rad).
%       'SourceElevationRad' 0     same contract, elevation.
%       'SubapertureSepM'    0.30  azimuth subaperture separation [m]
%       'SubapertureSepElM'  0.30  ELEVATION subaperture separation [m]
%       'IncludeAngleChannel' true  write rx_frames_delta or not
%       'IncludeElevationChannel' false  write rx_frames_delta_el or not.
%                          DEFAULTS OFF, and that default is load-bearing
%                          rather than cautious: the elevation channel needs
%                          its own independent thermal-noise draw, and drawing
%                          it ADVANCES THE SHARED RNG STREAM, so every
%                          subsequent pulse's sum- and difference-channel
%                          noise would differ. With it off, a given seed
%                          reproduces every previously published scene sample
%                          for sample (tests/test_generator_bearing.m pins
%                          this both ways).
%       'PhantomSweepSchedule' []  what the PHANTOM believes it should
%                          transmit each frame (+1/-1 per frame, same
%                          length convention as sweep_schedule in the .mat).
%                          Default [] = identical to the radar's actual
%                          schedule, i.e. omniscient repeater (this
%                          project's historical, "known radar" behaviour).
%                          Pass a DIFFERENT array (e.g. all-ones, or the
%                          previous frame's actual value) to model a
%                          repeater synthesizing from a stale intercept --
%                          this is what actually lets waveform agility cost
%                          a repeater anything; with the default, agility
%                          is invisible to this generator by construction,
%                          since it always happens to retransmit the
%                          correct chirp direction.
%       'NumPulsesPerFrame == 1' collapses rx_frames/rx_frames_delta to a
%                          legacy 2-D [fastTime x numFrames] shape (matches
%                          num_pulses_per_frame read from the .mat) --
%                          this is what actually reproduces "range-only,
%                          no Doppler measurement possible", not merely a
%                          cube with one degenerate pulse (see
%                          +engine/runJudge.m's own isCube = ndims==3 check,
%                          which a [400 1 8] cube would still satisfy).
%
%   WHY THIS FUNCTION EXISTS, AND WHY IT NEVER TAKES A PER-PHANTOM ANGLE.
%   Blueprint Part 2.4: a single transmit aperture cannot be projected into
%   looking angularly separated, because bearing is set by geometry, not
%   signal content. This function enforces that as an ARCHITECTURAL fact,
%   not a checked constraint -- there is exactly one bearing PER FRAME,
%   applied identically to every phantom's contribution to the sum channel
%   before the monopulse ratio is taken. There is no code path in this file
%   that could give two phantoms different bearings; Physics Projection
%   (generator/physics_projection.py) likewise has no angle-projection
%   function, because there is nothing to project. This is the mechanism
%   behind the co-bearing screen (+engine/runJudge.m) catching a
%   single-source swarm.
%
%   16 AUG 2026 -- THE BEARING VARIES IN TIME NOW, AND 2.4 IS UNCHANGED.
%   'SourceAzimuthRad' accepts a per-frame vector so a MOVING mother platform
%   can be rendered. The guarantee is exactly as strong as before: still one
%   bearing per time step, still shared identically by every phantom, still
%   no per-phantom angle argument anywhere. What is new is that the phantoms
%   now inherit the platform's bearing TRAJECTORY -- so a phantom claiming a
%   range far from the mother's implies, through v_cross = R*dtheta/dt, a
%   tangential speed inflated by the range ratio. That is a per-track
%   signature, which is what lets a LONE phantom be caught; the co-bearing
%   screen needs N >= 2 and is silent at N = 1.
%
%   The platform's own azimuth is bounded by the monopulse unambiguous sector
%   (+-2.8640 deg at 0.30 m and 10 GHz): outside it the measured phase WRAPS
%   rather than saturating, so a track that leaves the sector measures wrap
%   and not bearing rate. This function does NOT police that -- it renders
%   what it is given, including a deliberately-wrapped scene, because
%   demonstrating the wrap is a legitimate experiment. MotherTrack's
%   within_unambiguous_sector / sector_dwell_s are where a scene builder
%   checks it.
%
%   NEVER REIMPLEMENTS THE CHIRP ANALYTICALLY. Per +radar/agileWaveform.m's
%   own header, MATLAB's 'Down' sweep does not match exp(-1i*pi*k*t^2)
%   (correlation 0.0201) -- so every phantom pulse placed into rx_frames is a
%   delayed, scaled, phase-rotated copy of the SAME sample vector
%   radar.agileWaveform returns for that frame's actual transmitted waveform,
%   never a hand-written formula.
%
%   NOISE: the sum and difference channels get INDEPENDENT thermal-noise
%   draws, added AFTER the coherent signal component is split by the
%   monopulse ratio -- not the same noise scaled by the ratio. Correlated
%   channel noise would make the azimuth measurement artificially exact even
%   at low SNR, which is not how two receive chains with their own front-end
%   noise actually behave.
%
%   A phantom whose delay places its pulse entirely outside the receive
%   window this sample is silently not rendered for that sample (physically
%   correct -- the same finite-window/range-ambiguity limit a real receiver
%   has, +physics/assertPrfWindowConsistent.m), not an error.

    p = inputParser;
    p.addParameter('FastTimeSamples', 400, @(x) isscalar(x) && x > 0);
    p.addParameter('NoiseAmplitude', 0.05, @(x) isscalar(x) && x > 0);
    p.addParameter('SourceAzimuthRad', 0, @isnumeric);
    p.addParameter('SourceElevationRad', 0, @isnumeric);
    % PER-PHANTOM azimuth, for a multi-DRONE swarm: each phantom radiated from
    % its OWN bearing, so the monopulse difference channel carries each echo at
    % its own angle. [] (default) => every phantom shares SourceAzimuthRad, and
    % the delta channel is computed the historical way (one deltaRatio times the
    % summed echo), byte-identical to pre-swarm renders. Supply an
    % [nPhantoms x 1] (constant per phantom) or [nPhantoms x numFrames] matrix
    % to break the co-bearing assumption F7 rests on. Elevation stays shared:
    % the swarm varies azimuth. tests/test_multi_aperture_render.m asserts both
    % the byte-identity of the absent path and the two-bearing round trip.
    p.addParameter('PhantomAzimuthRad', [], @isnumeric);
    p.addParameter('SubapertureSepM', 0.30, @(x) isscalar(x) && x > 0);
    p.addParameter('SubapertureSepElM', 0.30, @(x) isscalar(x) && x > 0);
    % Place each phantom's pulse at a NON-INTEGER sample delay, instead of
    % rounding to the nearest whole sample.
    %
    % DEFAULTS FALSE, and that preserves every published number: rounding is
    % what this renderer has always done, so `false` is byte-identical to the
    % pre-21-Aug-2026 behaviour (tests/test_fractional_delay_render.m asserts
    % it).
    %
    % WHY IT MATTERS WHEN IT IS ON. One sample is 46.84 m here, so a target
    % slower than one cell per revisit holds a FROZEN apparent range and then
    % jumps a whole cell -- a staircase where the physics says ramp, on the one
    % observable the range-rate screens integrate. At the hardware bench's
    % 6.4 MS/s that step is 23.42 m, which is 4.0 sigma against a judge doing
    % sub-bin interpolation. Rounding does not approximate the trajectory; it
    % substitutes a different one that no real target could fly.
    %
    % It is also what makes the spec's V3 arm A expressible at all: with
    % rounding always on, arm B (integer delay) IS the baseline and there is
    % nothing to ablate against.
    p.addParameter('FractionalDelay', false, @islogical);
    p.addParameter('IncludeAngleChannel', true, @islogical);
    p.addParameter('IncludeElevationChannel', false, @islogical);
    % ---- GROUND CLUTTER (16 Aug 2026) --------------------------------------
    % 'ClutterGammaDB' empty = OFF, which is the default and is load-bearing:
    % the clutter draw advances the shared RNG stream, so switching it on
    % changes every subsequent noise sample. With it off, a given seed
    % reproduces every previously published scene sample for sample -- the
    % same posture, and the same reason, as IncludeElevationChannel.
    %
    % Set it to a terrain gamma in dB (-15 is rural land at X-band) to add
    % surface return derived by +physics/surfaceClutter.m. That function owns
    % the physics and the one cited assumption; this file only realises it.
    p.addParameter('ClutterGammaDB', [], @(x) isempty(x) || isscalar(x));
    p.addParameter('RadarHeightM', 10, @(x) isscalar(x) && x > 0);
    p.addParameter('PhantomSweepSchedule', [], @isnumeric);
    p.parse(varargin{:});
    opts = p.Results;

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);
    Cc = physics.Constants();

    S = load(preRenderMatPath);
    fs           = double(S.fs);
    pulseWidthS  = double(S.pulse_width_s);
    bandwidthHz  = double(S.bandwidth_hz);
    prfHz        = double(S.prf_hz);
    carrierHz    = double(S.carrier_hz);
    frameIntervalS = double(S.frame_interval_s);
    numPulsesPerFrame = double(S.num_pulses_per_frame);

    rangeM   = double(S.phantom_range_m);       % [nPhantoms x nSamplesTotal]
    ampSim   = double(S.phantom_amplitude);
    phaseRad = double(S.phantom_phase_rad);
    [nPhantoms, nSamplesTotal] = size(rangeM);

    assert(mod(nSamplesTotal, numPulsesPerFrame) == 0, ...
        'generator:render:badFrameLayout', ...
        'nSamplesTotal (%d) is not a multiple of num_pulses_per_frame (%d)', ...
        nSamplesTotal, numPulsesPerFrame);
    numFrames = nSamplesTotal / numPulsesPerFrame;

    if isfield(S, 'sweep_schedule')
        sweepSched = double(S.sweep_schedule(:)');
        assert(numel(sweepSched) >= numFrames, 'generator:render:shortSchedule', ...
            'sweep_schedule has %d entries for %d frames', numel(sweepSched), numFrames);
    else
        sweepSched = ones(1, numFrames);
    end

    if isempty(opts.PhantomSweepSchedule)
        phantomSched = sweepSched;   % omniscient default -- see header
    else
        phantomSched = double(opts.PhantomSweepSchedule(:)');
        assert(numel(phantomSched) >= numFrames, 'generator:render:shortPhantomSchedule', ...
            'PhantomSweepSchedule has %d entries for %d frames', numel(phantomSched), numFrames);
    end

    fastN = opts.FastTimeSamples;
    rxFrames = complex(zeros(fastN, numPulsesPerFrame, numFrames));

    % Bearing series. A scalar is broadcast to every frame, which is what
    % makes the historical fixed-bearing call reproduce exactly.
    srcAz = localBearingSeries(opts.SourceAzimuthRad, numFrames, 'SourceAzimuthRad');
    srcEl = localBearingSeries(opts.SourceElevationRad, numFrames, 'SourceElevationRad');

    if opts.IncludeAngleChannel
        rxFramesDelta = complex(zeros(fastN, numPulsesPerFrame, numFrames));
        lambda = Cc.c / carrierHz;
        % Direction cosines, so the two baselines measure orthogonal angles:
        % an azimuth baseline along y sees sin(az)*cos(el), an elevation
        % baseline along z sees sin(el). At el = 0, cos(el) = 1 and the
        % azimuth term collapses to the historical 2*pi*d*sin(az)/lambda --
        % which is why adding elevation costs the existing path nothing.
        phiAntAz   = 2*pi*opts.SubapertureSepM  .* sin(srcAz) .* cos(srcEl) / lambda;
        deltaRatio = 1i*tan(phiAntAz/2);        % [1 x numFrames]
        % Per-phantom difference-channel weight, only when a swarm is declared.
        % Row ph is that phantom's own bearing series through the same
        % Delta/Sigma = 1i*tan(phi/2) law; elevation is the shared srcEl.
        perPhantomAz = ~isempty(opts.PhantomAzimuthRad);
        if perPhantomAz
            azPh = opts.PhantomAzimuthRad;
            if size(azPh, 2) == 1; azPh = repmat(azPh, 1, numFrames); end
            assert(size(azPh, 1) == nPhantoms && size(azPh, 2) >= numFrames, ...
                'generator:render:phantomAz', ...
                'PhantomAzimuthRad must be [nPhantoms x 1] or [nPhantoms x numFrames]');
            azPh = azPh(:, 1:numFrames);
            phiAntAzPh   = 2*pi*opts.SubapertureSepM .* sin(azPh) .* cos(srcEl) / lambda;
            deltaRatioPh = 1i*tan(phiAntAzPh/2);   % [nPhantoms x numFrames]
        end
    else
        perPhantomAz = false;
    end
    if opts.IncludeElevationChannel
        rxFramesDeltaEl = complex(zeros(fastN, numPulsesPerFrame, numFrames));
        lambda = Cc.c / carrierHz;
        phiAntEl     = 2*pi*opts.SubapertureSepElM .* sin(srcEl) / lambda;
        deltaRatioEl = 1i*tan(phiAntEl/2);      % [1 x numFrames]
    end

    % Per-raw-sample clutter amplitude, one value per fast-time cell. Derived
    % once: the geometry does not change within a run.
    useClutter = ~isempty(opts.ClutterGammaDB);
    if useClutter
        cellRanges = (0:fastN-1) * (Cc.c / (2*fs));
        Sclut = physics.surfaceClutter('RangesM', max(cellRanges, 1), ...
            'GammaDB', opts.ClutterGammaDB, 'RadarHeightM', opts.RadarHeightM, ...
            'CarrierHz', carrierHz, 'NoiseAmplitude', opts.NoiseAmplitude);
        clutterAmp = Sclut.sim_amplitude(:);
    end

    for k = 1:numFrames
        % ---- ONE clutter realisation PER FRAME, held across every pulse ----
        % That is what puts ground return at ZERO DOPPLER: a scatterer field
        % that does not change between pulses has no slow-time phase
        % progression at all. Redrawn per frame because dwell-to-dwell the
        % geometry has moved and the field decorrelates.
        %
        % White in RANGE, because distributed clutter really is independent
        % cell to cell -- and because rx_frames is the RAW receive buffer, the
        % judge's own matched filter gives this field exactly the same gain it
        % gives the target echoes and the thermal noise. Adding clutter after
        % compression would double-count that gain.
        if useClutter
            clutterFrame = clutterAmp .* ...
                (randn(fastN,1) + 1i*randn(fastN,1)) / sqrt(2);
        end
        % The PHANTOM's own transmitted copy is built from its BELIEF of the
        % schedule (phantomSched), not necessarily the radar's real one
        % (sweepSched) -- see 'PhantomSweepSchedule' above. They are equal
        % by default, which is why agility costs nothing until a caller
        % deliberately supplies a stale belief.
        [~, pulseSamples] = radar.agileWaveform(phantomSched(k), fs, pulseWidthS, prfHz, bandwidthHz);
        pulseSamples = pulseSamples(:);
        pulseLen = numel(pulseSamples);

        for pIdx = 1:numPulsesPerFrame
            sampleIdx = (k-1)*numPulsesPerFrame + pIdx;

            sigBuf = complex(zeros(fastN, 1));
            if opts.IncludeAngleChannel && perPhantomAz
                sigBufDelta = complex(zeros(fastN, 1));   % per-phantom Sigma-weighted echo
            end
            for ph = 1:nPhantoms
                R = rangeM(ph, sampleIdx);
                A = ampSim(ph, sampleIdx);
                phi = phaseRad(ph, sampleIdx);
                dExact = 2*R/Cc.c * fs;
                delaySamples = round(dExact);
                if delaySamples < 0 || delaySamples >= fastN
                    continue;   % outside the receive window this sample -- not an error
                end
                % contrib + dst computed once, added to the sum channel exactly
                % as before (so sigBuf, hence rx_frames, is bit-identical), then
                % weighted by THIS phantom's own deltaRatio for the swarm delta.
                if ~opts.FractionalDelay
                    endIdx = min(fastN, delaySamples + pulseLen);
                    nCopy = endIdx - delaySamples;
                    dst = delaySamples+1:endIdx;
                    contrib = A * exp(1i*phi) * pulseSamples(1:nCopy);
                else
                    % Shape the pulse by the sub-sample remainder, then place
                    % it at the rounded index MINUS the kernel's own integer
                    % centre -- the kernel delays by (taps-1)/2 + mu, so the
                    % centre has to come back off or every phantom sits 8
                    % samples late. Same decomposition as
                    % generator/render.py's delay_pulse().
                    mu = dExact - delaySamples;
                    hFd = generator.fracDelayKernel(mu);
                    shaped = conv(pulseSamples, hFd);
                    startIdx = delaySamples - (numel(hFd)-1)/2;   % 0-based
                    srcFrom = max(1, 1 - startIdx);
                    dstFrom = max(1, startIdx + 1);
                    nCopy = min(numel(shaped) - srcFrom + 1, fastN - dstFrom + 1);
                    if nCopy <= 0
                        continue;
                    end
                    dst = dstFrom:dstFrom+nCopy-1;
                    contrib = A * exp(1i*phi) * shaped(srcFrom:srcFrom+nCopy-1);
                end
                sigBuf(dst) = sigBuf(dst) + contrib;
                if opts.IncludeAngleChannel && perPhantomAz
                    sigBufDelta(dst) = sigBufDelta(dst) + contrib * deltaRatioPh(ph, k);
                end
            end

            noiseSum = opts.NoiseAmplitude * (randn(fastN,1) + 1i*randn(fastN,1)) / sqrt(2);
            % Clutter goes into the SUM channel only, and deliberately not
            % into the difference channels below. Ground return fills the
            % whole beam, so it has no single bearing -- adding it to sigBuf
            % would hand it the SOURCE's bearing and make it look like one
            % more co-bearing emitter, which is the opposite of what it is.
            % Modelling its true angular spread is a real piece of work and is
            % not done here; the consequence is that the ANGLE channel in this
            % renderer remains clutter-free, so any monopulse result measured
            % with clutter on is optimistic about the angle measurement.
            clut = 0;
            if useClutter; clut = clutterFrame; end
            rxFrames(:, pIdx, k) = sigBuf + clut + noiseSum;

            if opts.IncludeAngleChannel
                noiseDelta = opts.NoiseAmplitude * (randn(fastN,1) + 1i*randn(fastN,1)) / sqrt(2);
                if perPhantomAz
                    rxFramesDelta(:, pIdx, k) = sigBufDelta + noiseDelta;
                else
                    % Historical single-bearing path, kept exactly: one
                    % deltaRatio times the summed echo. Byte-identical.
                    rxFramesDelta(:, pIdx, k) = sigBuf * deltaRatio(k) + noiseDelta;
                end
            end
            if opts.IncludeElevationChannel
                % Its OWN independent draw -- a third receive chain has its
                % own front-end noise. This is also why the channel defaults
                % off: this draw advances the shared stream.
                noiseDeltaEl = opts.NoiseAmplitude * (randn(fastN,1) + 1i*randn(fastN,1)) / sqrt(2);
                rxFramesDeltaEl(:, pIdx, k) = sigBuf * deltaRatioEl(k) + noiseDeltaEl;
            end
        end
    end

    if numPulsesPerFrame == 1
        % Squeeze to a true legacy 2-D [fastTime x numFrames] shape -- a
        % [fastTime x 1 x numFrames] cube would still satisfy runJudge.m's
        % ndims==3 "isCube" check and get a (degenerate, 1-sample) Doppler
        % FFT, which is not the same thing as "this radar cannot measure
        % Doppler at all". This is what actually reproduces the range-only
        % judge path (doppler_source='none-2d-export-screen-disabled').
        rxFrames = reshape(rxFrames, fastN, numFrames);
        if opts.IncludeAngleChannel
            rxFramesDelta = reshape(rxFramesDelta, fastN, numFrames);
        end
        if opts.IncludeElevationChannel
            rxFramesDeltaEl = reshape(rxFramesDeltaEl, fastN, numFrames);
        end
    end

    out = struct();
    out.rx_frames = rxFrames;
    out.fs = fs;
    out.pulse_width_s = pulseWidthS;
    out.bandwidth_hz = bandwidthHz;
    out.prf_hz = prfHz;
    out.carrier_hz = carrierHz;
    out.frame_interval_s = frameIntervalS;
    out.sweep_schedule = sweepSched;
    if opts.IncludeAngleChannel
        out.rx_frames_delta = rxFramesDelta;
        out.subaperture_sep_m = opts.SubapertureSepM;
        % The bearing the scene was actually rendered on, per frame. TRUTH,
        % exported so an analysis can compare a MEASURED per-track azimuth
        % against the transmitter's real trajectory instead of re-deriving it
        % from the scene description and hoping the two agree.
        out.source_azimuth_rad = srcAz;
        out.source_elevation_rad = srcEl;
    end
    if opts.IncludeElevationChannel
        out.rx_frames_delta_el = rxFramesDeltaEl;
        out.subaperture_sep_el_m = opts.SubapertureSepElM;
    end

    save(judgeMatPath, '-struct', 'out');
end

function s = localBearingSeries(v, numFrames, name)
%LOCALBEARINGSERIES  Scalar -> constant series; vector -> validated per-frame.
%   Trailing entries beyond numFrames are ignored, matching how
%   sweep_schedule/PhantomSweepSchedule already treat an over-long schedule.
    v = double(v(:)');
    if isscalar(v)
        s = repmat(v, 1, numFrames);
        return
    end
    assert(numel(v) >= numFrames, 'generator:render:shortBearing', ...
        '%s has %d entries for %d frames', name, numel(v), numFrames);
    s = v(1:numFrames);
end
