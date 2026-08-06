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
    % SWERLING IS A STATED PARAMETER, NOT A HARDCODE (Tier 1.3, 3 Aug 2026).
    % This was a literal `'swerling', 0` in localStep -- a NON-FLUCTUATING
    % target, i.e. one whose amplitude follows 1/R^2 exactly with zero
    % scintillation. That is not a physical object: measured RCS fluctuation
    % floors are 0.233 dB (99 RadChar LFM records) and 0.491 dB (TSMS corner
    % reflector through a real receiver). So every real-rate this environment
    % has produced was measured on an entity that never had to survive a
    % fluctuation-consistency check.
    %
    % DEFAULT 1 (Swerling I): many small scatterers, RCS ~ chi-square with 2
    % DOF, ONE draw per dwell (scan-to-scan correlated) -- the standard
    % slowly-fluctuating target. Rendered by engine.entity.render's existing
    % localSwerlingGain; no new code, this is wiring.
    %
    % IT MAKES THE GENERATOR'S JOB HARDER, and that is the point. Swerling I
    % contributes ~5.6 dB of amplitude scatter across an 8-frame dwell whose
    % total 1/R^2 amplitude change is only ~4.3 dB at 50 m/s, so the
    % log(A)-vs-log(R) slope screen 1 fits now has more noise than signal.
    % Set 0 to reproduce the pre-1.3 numbers.
    if ~isfield(opts, 'swerling');  opts.swerling  = 1;     end
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
    % BOUNDED BY v_ua (2 Aug 2026). Was +-120 m/s, a bound inherited from
    % buildEnvDoppler and never retargeted after the PRF was resolved to
    % 8 kHz. v_ua = lambda*PRF/4 = 59.958 m/s, so +-120 and +-60 both FOLD:
    % the entity renders self-consistently and the radar then MEASURES a
    % Doppler that contradicts its own range walk by ~100 m/s. Measured
    % before the fix: median |diff(R)/dt - v_measured| = 100.24 m/s over 20
    % episodes. +-50 leaves 2.7 Doppler bins of margin at 32 pulses.
    velOptionsMps = linspace(-50, 50, 5);
    rcsOptionsDbsm = linspace(-10, 10, 5);
    actInfo = rlFiniteSetSpec(1:(numel(velOptionsMps)*numel(rcsOptionsDbsm)));
    actInfo.Name = 'entity_action';

    % R0 is settable (Tier 1.4): with the default 1800 m and the +-50 m/s grid
    % the maximum 8-frame drift is 400 m, so the range clamp is UNREACHABLE
    % (1800-400 = 1400 m, still clear of the 1124 m floor) -- which is why a
    % 160-episode run hit it 0 times and the clamp path had never been
    % exercised at all. A test can now start the entity near a bound and make
    % it fire.
    if ~isfield(opts, 'R0'); opts.R0 = 1800; end
    % EPISODE LENGTH is the amplitude screen's LEVER ARM, so it has to be
    % settable to be measured (experiments.leverArm). Default 8 is unchanged,
    % so every existing caller and every published number is unaffected.
    % Raising it is NOT free: the entity walks further, and rangeMinM below is
    % the CA-CFAR blind zone -- a fast closer clamps against it and its
    % amplitude goes FLAT, which is the naive-DRFM signature screen 1 exists
    % to catch. That is the documented "two constraints close on each other".
    if ~isfield(opts, 'framesPerEpisode'); opts.framesPerEpisode = 8; end
    F = opts.framesPerEpisode; dt = 1.0; R0 = opts.R0; nFast = 400;

    % RANGE BOUNDS, DERIVED (2 Aug 2026). Were [200, 3000] m: the ceiling
    % tracked the REJECTED 50 kHz PRF's R_ua (2997.9 m), the floor sat inside
    % the CA-CFAR blind zone. Same derivation as buildEnvDoppler.m -- the
    % binding limit is the 400-sample receive WINDOW (render.m errors outright
    % if a pulse will not fit), not R_ua = 18737 m.
    cfarD = radar.cfarDefaults();
    cfarGuardM = (cfarD.NumTraining + cfarD.NumGuard) * C.range_per_sample;
    pulseSamples = round(12e-6 * C.fs);
    rangeMinM = cfarGuardM;
    rangeMaxM = (nFast - pulseSamples) * C.range_per_sample - cfarGuardM;

    P = struct('C', C, 'F', F, 'dt', dt, 'R0', R0, 'nFast', nFast, ...
        'rangeMinM', rangeMinM, 'rangeMaxM', rangeMaxM, ...
        'velOptionsMps', velOptionsMps, 'rcsOptionsDbsm', rcsOptionsDbsm, ...
        'numPulses', opts.numPulses, 'carrierHz', opts.carrierHz, ...
        'lambda', lambda, 'ampScale', opts.ampScale, ...
        'latchRcs', opts.latchRcs, 'shaping', opts.shaping, ...
        'gamma', opts.gamma, 'keepCube', opts.keepCube, ...
        'swerling', opts.swerling, ...
        'wav', phased.LinearFMWaveform('SampleRate', C.fs, ...
                 'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6));

    env = rlFunctionEnv(obsInfo, actInfo, ...
        @(action, logged) localStep(action, logged, P), @() localReset(R0));

    spec = struct('numActions', numel(actInfo.Elements), ...
        'velOptionsMps', velOptionsMps, 'rcsOptionsDbsm', rcsOptionsDbsm, ...
        'numPulses', opts.numPulses, 'carrierHz', opts.carrierHz, ...
        'lambda', lambda, 'obsDim', 4, 'framesPerEpisode', F, 'dt', dt, ...
        'dopplerBinMps', lambda * (P.wav.PRF / opts.numPulses) / 2, ...
        'latchRcs', opts.latchRcs, 'shaping', opts.shaping, ...
        'swerling', opts.swerling, ...
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

    newRange = max(P.rangeMinM, min(P.rangeMaxM, logged.range + rangeRate * P.dt));

    % ---- CROSS-FRAME CONTINUITY (Tier 1.4) ------------------------------
    % The rendered range rate is the ACHIEVED one, not the commanded one --
    % the same correction agent.buildEnvDoppler.m:307 already applies. It
    % matters only when the clamp fires, but when it does, rendering the
    % COMMANDED rate would emit a phantom whose Doppler says one thing and
    % whose range walk says another: a self-inconsistency of exactly the kind
    % this environment exists to make impossible, produced by the environment
    % itself. It was latent rather than benign -- with R0 = 1800 m and a
    % +-50 m/s grid the clamp is simply unreachable in 8 frames, so nothing
    % had ever exercised it.
    %
    % ALSO NOTE: buildEnvEntity constructs a BRAND-NEW EntityState each frame
    % rather than propagating one persistent object, so nothing but this line
    % ties frame k's kinematics to frame k-1's. The assertion below is what
    % makes the "single source of truth" claim structural instead of a
    % property of how the caller happens to index.
    achievedRate = (newRange - logged.range) / P.dt;
    clampFired = abs(achievedRate - rangeRate) > 1e-9;
    assert(~clampFired || ...
           (abs(newRange - P.rangeMinM) < 1e-6 || abs(newRange - P.rangeMaxM) < 1e-6), ...
        'agent:buildEnvEntity:inconsistentRate', ...
        ['range rate %g m/s disagrees with the achieved step %g m/s but the ' ...
         'range %g m is not at either bound (%g, %g) -- the only legitimate ' ...
         'cause of a disagreement is the clamp'], ...
        rangeRate, achievedRate, newRange, P.rangeMinM, P.rangeMaxM);
    rangeRate = achievedRate;   % render what the object ACTUALLY did

    % ---- ONE state -> ALL observables. This is the whole point of T4. ----
    % CLASS IS 'drone', NOT 'fighter' (2 Aug 2026). It was 'fighter', which is
    % not in render.m's CLASSES_EXPECTING_MICRO = {'drone'}, so this generator
    % rendered ZERO micro-Doppler and never had to survive that channel at
    % all. 'Phantom 4 Pro' supplies a MEASURED blade-passage rate (200 Hz,
    % TSMS-Drone CW set) rather than a typed-in one; it is the fastest of the
    % four measured models and therefore the one closest to being resolvable
    % at the default 32-pulse dwell. blade_tip_mps stays at EntityState's
    % measured 4.55 m/s default and render.m recomputes beta from lambda.
    %
    % HONEST LIMIT, not hidden: resolving a 200 Hz comb needs NumPulses >=
    % PRF/rate = 40 pulses, and the default dwell is 32 (resolution 250 Hz).
    % So the comb is rendered but is NOT resolvable at the default dwell --
    % for ALL FOUR measured models (100-200 Hz, needing 40-80 pulses). The
    % entity is now honestly drone-shaped; the radar still cannot see it.
    %
    % Note the velocity grid is bounded by v_ua, so a drone at up to 50 m/s
    % is also inside the "unambiguously measurable" class band (PHASE4 1.3
    % lists quad cruise 15 m/s and racing 40 m/s as the two that do not fold).
    s = engine.entity.EntityState('range_m', newRange, ...
            'range_rate_mps', rangeRate, 'rcs_dbsm', logged.rcsDbsm, ...
            'swerling', P.swerling, 'class', 'drone', 'model', 'Phantom 4 Pro');
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
        % MeasurementNoise matches the REAL range-bin quantisation error
        % (~C.range_per_sample, ~46.8 m std), not eye(3)'s claimed 1 m std --
        % a ~47x overconfidence that makes trackerGNN's gates falsely tight.
        % Root-caused and fixed in +engine/runJudge.m:326 (Task 2,
        % PHASE2_COMPLETION_POA.md) and never propagated here, so this
        % environment's INLINE chain has been scoring every episode with a
        % tracker that was told its own measurements were 47x more precise
        % than they are, while the judge it is compared against was not.
        % Tier 0.2, 2 Aug 2026.
        measNoise = diag([C.range_per_sample^2, 1, 1]);
        det = objectDetection(frameTime, [rEst; 0; 0], 'MeasurementNoise', measNoise);
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
