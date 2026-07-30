function [env, spec] = buildEnvEntity(C, opts)
%BUILDENVENTITY  T4 -- the D3QN action space IS an entity state, rendered
%   through engine.entity.render. (POA Phase 3, T4.)
%
%   [env, spec] = agent.buildEnvEntity(C, opts)
%
%   WHY THIS IS A SEPARATE FILE, NOT A FLAG ON buildEnvDoppler. The POA is
%   explicit that T4 "invalidates the 3-arm comparison, since those runs
%   measured an agent solving a problem that would no longer exist." Folding
%   it in behind a flag would make one file mean two different experiments
%   and put every recorded arm at risk of a silent re-baseline. The Doppler
%   env stays exactly as it was measured.
%
%   THE CHANGE. buildEnvDoppler's action is (range-delta, gain, velocity)
%   per frame -- 24 free parameters over 8 frames, and nothing forces the
%   three to describe the same object. Here the action selects a STATE and
%   engine.entity.render turns it into observables, so:
%       amplitude <-> range     is the two-way law, not a free gain
%       Doppler   <-> range-rate is geometry, not a free phase
%   Those consistencies become unviolatable rather than learnable.
%   EntityState.m's own header states the principle; the VEE adopted it and
%   this environment never had.
%
%   OPTIONS (all defaulted)
%       .latchRcs   true  RCS is chosen ONCE at k=0. An identity is picked
%                         once; re-drawing it per frame satisfies the
%                         amplitude law instantly while tracing a path no
%                         single object could trace (T1's finding). Set
%                         false to measure that difference.
%       .ampScale   3.0   absolute level, matching benchmarkSuite's phantom.
%       .shaping    true  potential-based shaping. T3 measured this as
%                         LOAD-BEARING, not a crutch: exact statistics
%                         WITHOUT it scored 0.0%.
%       .carrierHz  10e9
%
%   THREAT MODEL: CONSTANT VELOCITY, per EntityState.m. The agent may choose
%   a new range-rate each frame, which is a maneuver, not a violation -- the
%   rendering stays self-consistent whatever it picks.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): the reward comes from
%   +track/discriminator, the independent ECCM block. +engine/+entity never
%   grades its own realism.

    if nargin < 2 || isempty(opts); opts = struct(); end
    if ~isfield(opts, 'latchRcs');  opts.latchRcs  = true;  end
    if ~isfield(opts, 'ampScale');  opts.ampScale  = 3.0;   end
    if ~isfield(opts, 'shaping');   opts.shaping   = true;  end
    if ~isfield(opts, 'gamma');     opts.gamma     = 0.99;  end
    if ~isfield(opts, 'carrierHz'); opts.carrierHz = 10e9;  end
    if ~isfield(opts, 'numPulses'); opts.numPulses = 32;    end
    % T6 cross-check: retain the received cube so engine.runJudge can
    % re-score the identical signal the inline chain scored.
    if ~isfield(opts, 'keepCube');  opts.keepCube  = false; end

    lambda = C.c / opts.carrierHz;

    % ---- observation: the same 4 kinematic scalars as buildEnvDoppler ----
    % Deliberately identical so the difference between the two environments
    % is the ACTION SPACE alone, not what the agent can see.
    obsInfo = rlNumericSpec([4 1], 'Name', 'obs');
    obsInfo.LowerLimit = [0; 0; 0; -1];
    obsInfo.UpperLimit = [1; 1; 1;  1];

    % ---- action: (range-rate, RCS) -- a STATE, not three loose knobs ----
    velOptionsMps = linspace(-120, 120, 5);
    rcsOptionsDbsm = linspace(-10, 10, 5);
    actInfo = rlFiniteSetSpec(1:(numel(velOptionsMps)*numel(rcsOptionsDbsm)));
    actInfo.Name = 'entity_action';

    F = 8; dt = 1.0; R0 = 1800; nFast = 400;

    P = struct('C', C, 'F', F, 'dt', dt, 'R0', R0, 'nFast', nFast, ...
        'velOptionsMps', velOptionsMps, 'rcsOptionsDbsm', rcsOptionsDbsm, ...
        'numPulses', opts.numPulses, 'carrierHz', opts.carrierHz, ...
        'lambda', lambda, 'ampScale', opts.ampScale, ...
        'latchRcs', opts.latchRcs, 'shaping', opts.shaping, ...
        'gamma', opts.gamma, 'keepCube', opts.keepCube, ...
        'wav', phased.LinearFMWaveform('SampleRate', C.fs, ...
                 'PulseWidth', 12e-6, 'PRF', 50e3, 'SweepBandwidth', 2e6));

    env = rlFunctionEnv(obsInfo, actInfo, ...
        @(action, logged) localStep(action, logged, P), @() localReset(R0));

    spec = struct('numActions', numel(actInfo.Elements), ...
        'velOptionsMps', velOptionsMps, 'rcsOptionsDbsm', rcsOptionsDbsm, ...
        'numPulses', opts.numPulses, 'carrierHz', opts.carrierHz, ...
        'lambda', lambda, 'obsDim', 4, 'framesPerEpisode', F, 'dt', dt, ...
        'dopplerBinMps', lambda * (P.wav.PRF / opts.numPulses) / 2, ...
        'latchRcs', opts.latchRcs, 'shaping', opts.shaping, ...
        'generatorDof', 1 + F + double(~opts.latchRcs)*(F-1));
end

% ------------------------------------------------------------------------
function [obs, logged] = localReset(R0)
    logged.k = 0;
    logged.range = R0;
    logged.dets = {}; logged.times = [];
    logged.rangeHist = []; logged.ampHist = []; logged.rateHist = [];
    logged.detectedHist = [];
    logged.confirmedCount = 0;
    % Logged so experiments.rolloutDopplerEnv works unchanged against this
    % env too -- its velConsistency/ampSlope diagnostics read these names.
    logged.cmdVelHist = []; logged.cmdRangeStep = [];
    logged.eccmLabel = "";
    logged.phi = 0;
    logged.rcsDbsm = NaN;             % latched at k=0 when latchRcs
    logged.cubeFrames = [];           % filled only when keepCube
    obs = [0; R0/3000; 0; 0];
end

% ------------------------------------------------------------------------
function [obs, reward, isDone, logged] = localStep(action, logged, P)
    C = P.C;
    [vi, ri] = ind2sub([numel(P.velOptionsMps) numel(P.rcsOptionsDbsm)], double(action));
    rangeRate = P.velOptionsMps(vi);

    % RCS is an IDENTITY. Latched at k=0 it is chosen once for the episode;
    % re-drawn per frame it satisfies the amplitude law at every instant
    % while tracing a path no single object could trace (T1).
    if P.latchRcs
        if isnan(logged.rcsDbsm); logged.rcsDbsm = P.rcsOptionsDbsm(ri); end
    else
        logged.rcsDbsm = P.rcsOptionsDbsm(ri);
    end

    newRange = max(200, min(3000, logged.range + rangeRate * P.dt));

    % ---- ONE state -> ALL observables. This is the whole point of T4. ----
    s = engine.entity.EntityState('range_m', newRange, ...
            'range_rate_mps', rangeRate, 'rcs_dbsm', logged.rcsDbsm, ...
            'swerling', 0, 'class', 'fighter');
    cube = engine.entity.render(s, 'NumPulses', P.numPulses, ...
            'FastTimeSamples', P.nFast, 'CarrierHz', P.carrierHz, ...
            'PrfHz', P.wav.PRF, 'PulseWidth', 12e-6, 'Bandwidth', 2e6, ...
            'AmpScale', P.ampScale);

    noise = 0.05 * (randn(P.nFast, P.numPulses) + ...
                 1i*randn(P.nFast, P.numPulses)) / sqrt(2);
    cube = cube + noise;

    if P.keepCube
        logged.cubeFrames(:, :, logged.k + 1) = cube;
    end

    % ---- MEASURE exactly as buildEnvDoppler and runJudge measure --------
    compressed = complex(zeros(P.nFast, P.numPulses));
    for p = 1:P.numPulses
        [~, compressed(:, p)] = radar.pulseCompress(cube(:, p), P.wav);
    end
    [rdMap, ~, dopAxis] = radar.rangeDoppler(compressed, P.wav, C);
    [power, dopBin] = max(rdMap, [], 2);

    frameTime = logged.k * P.dt;
    detIdx = radar.cfarDetect(power, 'Pfa', 1e-4);
    if isempty(detIdx)
        det = objectDetection.empty; detected = false;
        rEst = NaN; ampEst = NaN; rateEst = NaN;
    else
        [pk, im] = max(power(detIdx));
        rbin = detIdx(im);
        rEst = (rbin-1) * C.range_per_sample;
        ampEst = sqrt(pk);
        rateEst = -P.lambda * dopAxis(dopBin(rbin)) / 2;
        detected = true;
        det = objectDetection(frameTime, [rEst; 0; 0], 'MeasurementNoise', eye(3));
    end

    logged.dets{end+1} = det;
    logged.times(end+1) = frameTime;
    logged.rangeHist(end+1) = rEst;
    logged.ampHist(end+1) = ampEst;
    logged.rateHist(end+1) = rateEst;
    logged.detectedHist(end+1) = detected;
    logged.cmdVelHist(end+1)   = rangeRate;
    logged.cmdRangeStep(end+1) = newRange - logged.range;   % ACHIEVED (clamped)
    logged.k = logged.k + 1;
    logged.range = newRange;

    isDone = (logged.k >= P.F);
    [reward, logged] = localReward(logged, P, isDone);

    vObs = 0;
    if isfinite(rateEst); vObs = max(-1, min(1, rateEst / 150)); end
    obs = [logged.k/P.F; newRange/3000; double(detected); vObs];
end

% ------------------------------------------------------------------------
function [reward, logged] = localReward(logged, P, isDone)
%LOCALREWARD  Terminal ladder + potential-based shaping, numerically
%   IDENTICAL to buildEnvDoppler's so the two environments' real-rates are
%   read against the same scale: never confirmed 0, confirmed but screened
%   decoy +0.5, confirmed and screened REAL +3.
%
%   ponytail: duplicated from buildEnvDoppler rather than extracted to a
%   shared +agent/dopplerReward.m, because extracting means editing the file
%   that holds every recorded arm. Two copies is tolerable; if a THIRD
%   environment needs it, extract then.
    reward = 0;
    if isDone
        confirmed = track.runTracker(logged.dets, logged.times, P.C);
        logged.confirmedCount = numel(confirmed);
        if numel(confirmed) >= 1
            ts = localTrackStruct(logged);
            if isempty(ts)
                logged.eccmLabel = "unscreened"; reward = reward + 0.5;
            else
                [label, ~] = track.discriminator(ts, P.C);
                logged.eccmLabel = label;
                if label == "real"; reward = reward + 3.0;
                else;               reward = reward + 0.5; end
            end
        else
            logged.eccmLabel = "unconfirmed";
        end
    end
    if P.shaping
        phiNext = localPotential(logged, P, isDone);
        reward = reward + P.gamma * phiNext - logged.phi;
        logged.phi = phiNext;
    end
end

function phi = localPotential(logged, P, isDone)
    phi = 0;
    if isDone; return; end
    ts = localTrackStruct(logged);
    if isempty(ts); return; end
    [label, conf] = track.discriminator(ts, P.C);
    if label == "decoy"; phi = 0.5 - conf/2; else; phi = 0.5 + conf/2; end
end

function ts = localTrackStruct(logged)
    ts = [];
    m = ~isnan(logged.rangeHist) & ~isnan(logged.ampHist) & ~isnan(logged.rateHist);
    if nnz(m) < 2; return; end
    ts = struct('range', logged.rangeHist(m), 'amplitude', logged.ampHist(m), ...
        'doppler', logged.rateHist(m), 'dopplerMeasured', true);
end
