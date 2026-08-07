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
%       'SourceAzimuthRad'   0     ONE scalar for the WHOLE scene (see below)
%       'SubapertureSepM'    0.30  monopulse subaperture separation [m]
%       'IncludeAngleChannel' true  write rx_frames_delta or not
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
%   not a checked constraint -- there is exactly one 'SourceAzimuthRad'
%   argument for the entire call, applied identically to every phantom's
%   contribution to the sum channel before the monopulse ratio is taken.
%   There is no code path in this file that could give two phantoms
%   different bearings; Physics Projection (generator/physics_projection.py)
%   likewise has no angle-projection function, because there is nothing to
%   project. This is the mechanism behind the co-bearing screen
%   (+engine/runJudge.m) catching a single-source swarm.
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
    p.addParameter('SourceAzimuthRad', 0, @isscalar);
    p.addParameter('SubapertureSepM', 0.30, @(x) isscalar(x) && x > 0);
    p.addParameter('IncludeAngleChannel', true, @islogical);
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
    if opts.IncludeAngleChannel
        rxFramesDelta = complex(zeros(fastN, numPulsesPerFrame, numFrames));
        lambda = Cc.c / carrierHz;
        phiAnt = 2*pi*opts.SubapertureSepM*sin(opts.SourceAzimuthRad)/lambda;
        deltaRatio = 1i*tan(phiAnt/2);
    end

    for k = 1:numFrames
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
            for ph = 1:nPhantoms
                R = rangeM(ph, sampleIdx);
                A = ampSim(ph, sampleIdx);
                phi = phaseRad(ph, sampleIdx);
                delaySamples = round(2*R/Cc.c * fs);
                if delaySamples < 0 || delaySamples >= fastN
                    continue;   % outside the receive window this sample -- not an error
                end
                endIdx = min(fastN, delaySamples + pulseLen);
                nCopy = endIdx - delaySamples;
                sigBuf(delaySamples+1:endIdx) = sigBuf(delaySamples+1:endIdx) + ...
                    A * exp(1i*phi) * pulseSamples(1:nCopy);
            end

            noiseSum = opts.NoiseAmplitude * (randn(fastN,1) + 1i*randn(fastN,1)) / sqrt(2);
            rxFrames(:, pIdx, k) = sigBuf + noiseSum;

            if opts.IncludeAngleChannel
                noiseDelta = opts.NoiseAmplitude * (randn(fastN,1) + 1i*randn(fastN,1)) / sqrt(2);
                rxFramesDelta(:, pIdx, k) = sigBuf * deltaRatio + noiseDelta;
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
    end

    save(judgeMatPath, '-struct', 'out');
end
