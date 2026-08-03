function [env, degradedEvent, spec] = buildEnvDoppler(C, pfb, opts)
%BUILDENVDOPPLER  Feature-conditioned DRFM-vs-radar environment with a REAL
%   slow-time (Doppler) axis, a MEASURED range-rate, and a reward that is
%   informative about deception rather than about being seen.
%
%   [env, degradedEvent, spec] = agent.buildEnvDoppler(C, pfb, opts)
%
%   WHY THIS FILE EXISTS -- the defect in agent.buildEnvFeatureConditioned
%   ---------------------------------------------------------------------
%   That environment renders ONE pulse per frame. There is no slow-time axis,
%   so Doppler physically cannot be measured, and it therefore SYNTHESISES the
%   quantity it hands to the ECCM screen:
%
%       dopSeq = diff(rngSeq) / dt;  dopSeq = [dopSeq(1), dopSeq];
%
%   +track/discriminator.m screen 2 then asks
%
%       sign(mean(diff(R))) == sign(mean(D))
%
%   which, with D built from diff(R), is very nearly a comparison of a
%   quantity with itself. MEASURED over 20000 synthetic episodes (see
%   tests/test_doppler_screen_coherence.m): under a COHERENT policy -- one
%   that holds a range-walk direction, i.e. exactly what a converged agent
%   produces -- screen 2 fails 0.00% of the time. It can only fail on
%   sign-alternating walks, which are exploration noise, not policy.
%
%   So half the ECCM verdict becomes a free pass precisely AS TRAINING
%   CONVERGES, and the only live gradient is the amplitude screen. That is
%   the mechanism behind the flat/declining reward curve in
%   results/feature_agent.mat (quartile means 1.347 / 1.465 / 1.387 / 1.227 --
%   the greedy policy scores WORSE than the exploratory one). It is not a
%   symptom of too small an episode budget, and training longer against it
%   cannot fix it.
%
%   WHAT CHANGES HERE
%   -----------------
%   1. PULSE CUBE. Each frame renders numPulses pulses with a true
%      pulse-to-pulse Doppler phase progression from a COMMANDED radial
%      velocity, so a slow-time axis exists to measure.
%   2. MEASURED RANGE-RATE. radar.rangeDoppler (the project's own independent
%      block) processes that cube, exactly as +engine/runJudge.m's cube path
%      does, and the range-rate comes from the Doppler bin:
%      Rdot = -lambda*f_d/2. Never diff(range). The agent is now trained
%      against the SAME measurement chain the judge scores it with.
%   3. dopplerMeasured = TRUE. This arms discriminator screen 2's
%      contradiction branch: a phantom that moves in range while showing no
%      Doppler (or vice versa) now scores 0 instead of making the evidence
%      inadmissible by declining to produce it.
%   4. VELOCITY IS AN ACTION. Adding a real screen without giving the agent a
%      knob that drives it would just make the reward constant-and-lower --
%      flatter, not better. The action space gains a commanded radial
%      velocity drawn from the SAME grid as the range-walk deltas, so for
%      every range-walk step there is EXACTLY ONE kinematically truthful
%      velocity. The learning problem is to find that diagonal.
%   5. REWARD (see localReward). Bare detection no longer pays; potential-
%      based shaping carries the terminal signal backwards instead.
%
%   INPUTS
%       C    : physics.Constants()
%       pfb  : features.buildChannelizer() (built with defaults if omitted)
%       opts : optional struct, any of
%           .numPulses   (32)    pulses per dwell -- matches the benchmark
%                                config in BENCHMARK_RESULTS.md
%           .carrierHz   (10e9)  REQUIRED to turn a Doppler bin into a
%                                range-rate. Stated, never guessed: this
%                                mirrors runJudge.m's own assert. It is a
%                                CONFIG value, not a physics.Constants
%                                derivation, because the RadChar anchors do
%                                not pin a carrier.
%           .shaping     (true)  potential-based reward shaping on/off
%           .gamma       (0.99)  MUST equal the agent's DiscountFactor for
%                                the shaping to be policy-invariant
%
%   OUTPUTS
%       env           : rlFunctionEnv
%       degradedEvent : [] or {frame,reason,confidence} if the feature-matched
%                       tx-template intercept fell back to verbatim replay --
%                       surfaced, never swallowed (same contract as
%                       agent.buildEnvWithFeatures)
%       spec          : struct describing the action grid and reward, so
%                       experiments can report the configuration they ran
%                       rather than restating it from memory.
%
%   Pairs with agent.buildAgentFeatureConditioned(env) -- that builder reads
%   obs/action dimensions from the env, so it sizes itself to this one.

    if nargin < 2 || isempty(pfb);  pfb  = features.buildChannelizer(); end
    if nargin < 3 || isempty(opts); opts = struct();                    end
    if ~isfield(opts, 'numPulses'); opts.numPulses = 32;    end
    if ~isfield(opts, 'carrierHz'); opts.carrierHz = 10e9;  end
    if ~isfield(opts, 'shaping');   opts.shaping   = true;  end
    if ~isfield(opts, 'gamma');     opts.gamma     = 0.99;  end
    % MANIFOLD PROJECTION (POA Phase 3, T1). Default OFF so every recorded
    % run stays reproducible; turn on to constrain the generator.
    if ~isfield(opts, 'project');   opts.project   = false; end
    % 54-D PFB BLOCK (POA Phase 3, T2). Default ON = the recorded arms.
    % features.featureVector runs on ONE pulse's fast-time samples, so it
    % carries no cross-frame and no slow-time information -- while every ECCM
    % screen tests cross-frame kinematics. That makes 54 of 58 observation
    % dimensions orthogonal to the verdict on a 35,182-parameter MLP. Set
    % false to measure whether they help, hurt, or do nothing.
    if ~isfield(opts, 'useFeatures'); opts.useFeatures = true; end
    % T3: running SUFFICIENT STATISTICS of the two screens the agent is
    % actually scored on. Default false so every recorded arm reproduces.
    if ~isfield(opts, 'useStats');    opts.useStats    = false; end
    % T5: MICRO-DOPPLER. 0 = off, which is every recorded arm to date.
    % A blade rate in Hz (use a MEASURED one -- EntityState.m's table) plus
    % a tip speed; beta is derived from lambda exactly as render.m does it.
    if ~isfield(opts, 'microHz');     opts.microHz     = 0;    end
    if ~isfield(opts, 'microTipMps'); opts.microTipMps = 4.55; end
    % T6: retain each frame's received cube in `logged` so an episode can be
    % re-scored by engine.runJudge instead of the inline chain. Off during
    % training -- it is pure memory the learner never reads.
    if ~isfield(opts, 'keepCube');    opts.keepCube    = false; end

    assert(~isempty(opts.carrierHz) && isfinite(opts.carrierHz) && opts.carrierHz > 0, ...
        'agent:buildEnvDoppler:noCarrier', ...
        ['A pulse cube needs a carrier frequency to turn a Doppler bin into ' ...
         'a range-rate. Refusing to guess a wavelength (see runJudge.m).']);
    lambda = C.c / opts.carrierHz;

    % ---- observation: + measured range-rate ----------------------------
    % The agent MUST be able to see the quantity it is now judged on. A
    % constraint you cannot observe is not one you can learn to satisfy, so
    % the measured range-rate joins the kinematic block. 3 -> 4 scalars.
    nFeat  = 54 * double(opts.useFeatures);
    nStats =  5 * double(opts.useStats);
    obsDim = 4 + nFeat + nStats;
    obsInfo = rlNumericSpec([obsDim 1], 'Name', 'obs');
    obsInfo.LowerLimit = [0; 0; 0; -1; -ones(nFeat,1); -ones(nStats,1)];
    obsInfo.UpperLimit = [1; 1; 1;  1;  ones(nFeat,1);  ones(nStats,1)];

    % ---- action grid ----------------------------------------------------
    % deltas and velocities share ONE grid on purpose: with dt = 1 s, a
    % range-walk of d metres per frame IS a range-rate of d m/s, so the
    % kinematically truthful action is exactly the diagonal vel == delta.
    % That makes "trajectory consistency" a directly measurable quantity
    % (see experiments.diagnoseDopplerEnv) instead of a qualitative claim.
    % BOUNDED BY v_ua, NOT BY THE TRACKER GATE (2 Aug 2026). These were
    % +-120 m/s, chosen against trackerGNN's assignment gate back when the
    % PRF was believed to be 50 kHz (v_ua +-375 m/s). At the resolved 8 kHz
    % PRF v_ua = lambda*PRF/4 = 59.958 m/s, so 4 of the 5 old options
    % (+-120, +-60) sat AT OR PAST the fold: a commanded -60 m/s renders
    % f_d = +4002.8 Hz, aliases past the +-4000 Hz Nyquist edge and is
    % MEASURED as +59.9 m/s -- range closing, Doppler opening, which is the
    % exact RGPO/VGPO signature discriminator.m screen 2 exists to catch.
    % The generator was condemning itself with its own action space.
    %
    % +-50 leaves 9.96 m/s of margin = 2.7 Doppler bins at the 32-pulse
    % dwell (bin = lambda*(PRF/32)/2 = 3.747 m/s). +-55 was rejected: only
    % 1.3 bins, too tight once a measurement lands on a bin centre.
    % Verified by tests/test_action_grid_unambiguous.m.
    %
    % deltas and velocities STILL share one grid, and that is why both had
    % to move together: with dt = 1 s, a range-walk of d metres per frame IS
    % a range-rate of d m/s, so the kinematically truthful action is the
    % diagonal vel == delta. Under projection cmdVel is DERIVED from the
    % achieved step, so leaving deltaOptionsM at +-120 would have kept the
    % fold via the range walk even with velOptionsMps fixed.
    deltaOptionsM  = linspace(-50, 50, 5);
    velOptionsMps  = linspace(-50, 50, 5);
    % GEOMETRIC gain ladder, not linear. The law the agent has to reproduce
    % (amplitude ~ 1/R^2) is multiplicative, so a multiplicative ladder gives
    % it uniform leverage across the span. Over an 8-frame walk the range can
    % change by ~3.3x, demanding a gain ratio of ~11x; a linspace(0.5,4.5)
    % ladder spans only 9x and cannot express the full ramp at the edges.
    gainOptions    = logspace(log10(0.4), log10(6.0), 5);
    numDeltas = numel(deltaOptionsM);
    numGains  = numel(gainOptions);
    numVels   = numel(velOptionsMps);

    actInfo = rlFiniteSetSpec(1:(numDeltas*numGains*numVels));   % 125
    actInfo.Name = 'drfm_action';

    % RANGE BOUNDS, DERIVED (2 Aug 2026). Were [150, 2950] m: the ceiling
    % tracked the REJECTED 50 kHz PRF's R_ua (2997.9 m), and the floor sat
    % deep inside the CA-CFAR blind zone. Both are now computed from the
    % detector and the receive window that actually bound them:
    %   floor : cells within NumTraining+NumGuard of a buffer edge are never
    %           testable, so a phantom below that range cannot be detected
    %           at all, whatever its power.
    %   ceil  : synth.synthesizeSwarm zero-fills and TRUNCATES at the window
    %           length, so a pulse must fit entirely inside it -- and the
    %           far CFAR edge needs the same training clearance.
    % Note the ceiling is NOT R_ua (18737 m): the 400-sample window cannot
    % hold a pulse placed there. Window, not ambiguity, is the binding limit.
    cfarD = radar.cfarDefaults();
    cfarGuardM = (cfarD.NumTraining + cfarD.NumGuard) * C.range_per_sample;
    pulseWidthS = 12e-6;
    sweepBandwidthHz = 2e6;
    wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
            'PulseWidth', pulseWidthS, 'PRF', physics.Constants().PRF, 'SweepBandwidth', sweepBandwidthHz);
    pulse = wav();
    bufferLen = 400;

    % Feature-matched tx template from a NOISY intercept -- unchanged from
    % agent.buildEnvFeatureConditioned, so the two environments differ ONLY
    % in the Doppler/reward axis under test and an A/B is attributable.
    activeLen = numel(getMatchedFilter(wav));
    activePulse = pulse(1:activeLen);
    interceptNoiseAmp = 2.0;             % ponytail: validated tie-point
    rngIntercept = RandStream('mt19937ar', 'Seed', 12345);
    nominalChirpRateHzS = sweepBandwidthHz / pulseWidthS;
    [txPulse, degradedEvent] = features.synthesizeTxPulse( ...
        activePulse, C.fs, nominalChirpRateHzS, interceptNoiseAmp, rngIntercept, 0);
    xTemplate = [txPulse; zeros(bufferLen - numel(txPulse), 1)];

    rangeMinM = cfarGuardM;
    rangeMaxM = (bufferLen - activeLen) * C.range_per_sample - cfarGuardM;

    F = 8; dt = 1.0;
    R0 = 1800;

    refAction = struct('delay_s', 2*R0/C.c, 'phase_rad', 0, 'gain', 1.0);
    refRx = synth.synthesizeSwarm(xTemplate, refAction, C);
    refScale = abs(features.featureVector(refRx, pfb)) + 1e-6;

    P = struct('C', C, 'wav', wav, 'xTemplate', xTemplate, 'bufferLen', bufferLen, ...
        'deltaOptionsM', deltaOptionsM, 'gainOptions', gainOptions, ...
        'velOptionsMps', velOptionsMps, 'F', F, 'dt', dt, 'pfb', pfb, ...
        'refScale', refScale, 'numPulses', opts.numPulses, 'lambda', lambda, ...
        'shaping', opts.shaping, 'gamma', opts.gamma, ...
        'project', opts.project, 'refRangeM', R0, ...
        'rangeMinM', rangeMinM, 'rangeMaxM', rangeMaxM, ...
        'useFeatures', opts.useFeatures, 'useStats', opts.useStats, ...
        'microHz', opts.microHz, 'microTipMps', opts.microTipMps, ...
        'keepCube', opts.keepCube, 'pulseWidthS', pulseWidthS, ...
        'sweepBandwidthHz', sweepBandwidthHz, 'carrierHz', opts.carrierHz);

    env = rlFunctionEnv(obsInfo, actInfo, ...
        @(action, logged) localStep(action, logged, P), @() localReset(R0, nFeat + nStats));

    % Doppler resolution is a property of the dwell, and the agent cannot be
    % asked to hit a velocity finer than one bin. Reported, not buried.
    dvBin = lambda * (wav.PRF / opts.numPulses) / 2;
    spec = struct( ...
        'numActions', numDeltas*numGains*numVels, ...
        'deltaOptionsM', deltaOptionsM, 'gainOptions', gainOptions, ...
        'velOptionsMps', velOptionsMps, 'numPulses', opts.numPulses, ...
        'carrierHz', opts.carrierHz, 'lambda', lambda, ...
        'dopplerBinMps', dvBin, ...
        'unambigVelMps', lambda * wav.PRF / 4, ...
        'obsDim', obsDim, 'framesPerEpisode', F, 'dt', dt, ...
        'shaping', opts.shaping, 'gamma', opts.gamma);
end

% ------------------------------------------------------------------------
function [obs, logged] = localReset(R0, nPad)
    logged.k       = 0;
    logged.range   = R0;
    logged.dets    = {};
    logged.times   = [];
    logged.rangeHist = [];
    logged.ampHist   = [];
    logged.rateHist  = [];
    logged.detectedHist = [];
    logged.cmdVelHist   = [];
    logged.cmdRangeStep = [];
    logged.confirmedCount = 0;
    logged.eccmLabel = "";
    logged.phi = 0;                      % shaping potential of the start state
    logged.rcsAmp = NaN;                 % latched at k=0 when projecting
    logged.cubeFrames = [];              % T6: filled only when keepCube
    obs = [0; R0/3000; 0; 0; zeros(nPad,1)];
end

% ------------------------------------------------------------------------
function [obs, reward, isDone, logged] = localStep(action, logged, P)

    C = P.C;
    [di, gi, vi] = ind2sub([numel(P.deltaOptionsM) numel(P.gainOptions) numel(P.velOptionsMps)], action);
    stepM    = P.deltaOptionsM(di);
    newRange = min(P.rangeMaxM, max(P.rangeMinM, logged.range + stepM));

    if ~P.project
        gain     = P.gainOptions(gi);
        cmdVel   = P.velOptionsMps(vi);
    else
        % ---- MANIFOLD PROJECTION (POA Phase 3, T1) ------------------
        % Degrees of freedom, counted: the unprojected action is
        % (delta-range, gain, velocity) per frame = 24 free parameters over
        % an 8-frame episode. A real body under this project's CV threat
        % model has (R0, Rdot, sigma) -- three. The generator is ~8x
        % over-parameterised, and the ECCM screens do not detect "fakeness",
        % they detect OFF-MANIFOLD. Excess freedom IS the attack surface.
        %
        % Only TWO of the three knobs were ever real choices:
        %   velocity  is NOT free -- a body's range rate IS d(range)/dt, so
        %             it is projected onto the ACHIEVED step (after the
        %             clamp, so a clamped frame stays self-consistent).
        %   gain      is NOT free -- amplitude follows sqrt(RCS)/R^2, the
        %             same two-way law engine.entity.render.m applies. The
        %             gain action is REINTERPRETED as choosing RCS, which is
        %             a genuine adversarial decision (how large a target am
        %             I claiming to be), and the gain then follows.
        %
        % IDENTITY IS LATCHED, and this is the part that per-frame
        % projection alone would miss: a real object has ONE RCS for the
        % whole engagement. Re-drawing it each frame would satisfy the
        % amplitude law instant-by-instant while still tracing a path no
        % single object could trace. Cross-frame constancy is as much a part
        % of the manifold as the per-frame coupling.
        if logged.k == 0
            logged.rcsAmp = P.gainOptions(gi);      % sqrt(RCS), latched
        end
        gain   = logged.rcsAmp * (P.refRangeM / newRange)^2;
        cmdVel = (newRange - logged.range) / P.dt;  % achieved, not commanded
    end
    tau      = 2 * newRange / C.c;

    % ---- render a PULSE CUBE with a real slow-time Doppler phase --------
    % Pulse p of the dwell leaves at t_p = p/PRF. A target closing at Rdot
    % advances the two-way path by 2*Rdot*t_p, i.e. a phase of
    % -4*pi*Rdot*t_p/lambda. That is the ONLY place velocity enters, and it
    % enters as geometry -- synth.synthesizeSwarm still just delays, scales
    % and phase-shifts the intercepted template (no self-verification).
    Pn  = P.numPulses;
    prf = P.wav.PRF;
    cube = complex(zeros(P.bufferLen, Pn));
    % T5 -- MICRO-DOPPLER, AND WHY THE SYNTHESIZER DID NOT NEED CHANGING.
    % The POA framed this as "add per-pulse phase modulation to
    % synth.synthesizeSwarm". It turned out not to be needed there: the loop
    % below ALREADY hands the synthesizer a different phase per pulse (that
    % is how velocity enters), and synthesizeSwarm already applies whatever
    % phase it is given. The Bessel comb is therefore one term added to a
    % phase that was already per-pulse -- not a new capability in +synth.
    %
    % Physically faithful, not a concession: a DRFM stores the pulse and
    % retransmits it, and applying a slow-time phase program to what it
    % retransmits is exactly what a DRFM does. It changes no DELAY, so
    % causality (a phantom can only be pushed farther out by repeat-back)
    % is untouched and checkCausality's contract is unaffected.
    %
    % beta = 2*v_tip/(lambda*f_blade), the same expression as
    % +engine/+entity/render.m, so the comb narrows at a longer wavelength
    % instead of being a band-independent constant.
    microBeta = 0;
    if P.microHz > 0
        microBeta = 2 * P.microTipMps / (P.lambda * P.microHz);
    end
    for p = 0:(Pn-1)
        tp  = p / prf;
        phi = -4*pi*cmdVel*tp / P.lambda;
        if microBeta > 0
            phi = phi + microBeta * sin(2*pi * P.microHz * tp);
        end
        a   = struct('delay_s', tau, 'phase_rad', phi, 'gain', gain);
        cube(:, p+1) = synth.synthesizeSwarm(P.xTemplate, a, C);
    end
    noise = 0.05 * (randn(P.bufferLen, Pn) + 1i*randn(P.bufferLen, Pn)) / sqrt(2);
    cube = cube + noise;

    % T6: keep the RECEIVED cube (post-noise -- what the radar actually
    % gets), so engine.runJudge can re-score the identical signal the inline
    % chain scored. Scoring a differently-noised re-render would confound the
    % sim-to-judge gap with a different noise draw.
    if P.keepCube
        logged.cubeFrames(:, :, logged.k + 1) = cube;
    end

    % ---- MEASURE, the way the judge measures ----------------------------
    % Identical chain to +engine/runJudge.m's cube path: per-pulse matched
    % filter, then slow-time FFT, then "best Doppler bin per range bin" as
    % the profile handed to CFAR. Training against a different measurement
    % than the evaluation uses would make the benchmark meaningless.
    compressed = complex(zeros(P.bufferLen, Pn));
    for p = 1:Pn
        [~, compressed(:, p)] = radar.pulseCompress(cube(:, p), P.wav);
    end
    [rdMap, ~, dopAxis] = radar.rangeDoppler(compressed, P.wav, C);
    [power, dopBin] = max(rdMap, [], 2);

    frameTime = logged.k * P.dt;
    detIdx = radar.cfarDetect(power, 'Pfa', 1e-4);

    if isempty(detIdx)
        det = objectDetection.empty;
        detected = false;
        rEst = NaN; ampEst = NaN; rateEst = NaN;
    else
        [pk, im] = max(power(detIdx));
        rbin = detIdx(im);
        rEst = (rbin-1) * C.range_per_sample;
        ampEst = sqrt(pk);
        % f_d = -2*Rdot/lambda  =>  Rdot = -lambda*f_d/2. Same sign
        % convention as runJudge.m line 201 and discriminator.m ("negative =
        % closing"). This is a MEASUREMENT off the Doppler axis, not diff().
        rateEst = -P.lambda * dopAxis(dopBin(rbin)) / 2;
        detected = true;
        % MeasurementNoise matches the REAL range-bin quantisation error
        % (~C.range_per_sample, ~46.8 m std), not eye(3)'s claimed 1 m std --
        % a ~47x overconfidence that makes trackerGNN's gates falsely tight.
        % Root-caused and fixed in +engine/runJudge.m:326 (Task 2,
        % PHASE2_COMPLETION_POA.md); propagated to +agent/buildEnvEntity.m and
        % here on 2 Aug 2026 (Tier 0.2). Until then every D3QN arm was TRAINED
        % and SCORED against a tracker told its own measurements were 47x more
        % precise than they are, while the judge it is compared against was
        % not -- so the two disagreed on identical data. On buildEnvEntity the
        % same one-line fix moved the inline real-rate 49.0% -> 100.0% and
        % closed a -51.0 pp inline-vs-judge gap to 0.0 pp; the failures there
        % were tracking failures (51/100 episodes confirmed ZERO tracks), not
        % mislabels.
        measNoise = diag([C.range_per_sample^2, 1, 1]);
        det = objectDetection(frameTime, [rEst; 0; 0], 'MeasurementNoise', measNoise);
    end

    logged.dets{end+1}      = det;
    logged.times(end+1)     = frameTime;
    logged.rangeHist(end+1) = rEst;
    logged.ampHist(end+1)   = ampEst;
    logged.rateHist(end+1)  = rateEst;
    logged.detectedHist(end+1) = detected;
    logged.cmdVelHist(end+1)   = cmdVel;
    logged.cmdRangeStep(end+1) = newRange - logged.range;   % ACHIEVED step (clamped)
    logged.k     = logged.k + 1;
    logged.range = newRange;

    isDone = (logged.k >= P.F);

    [reward, logged] = localReward(logged, P, isDone);

    vObs = 0;
    if isfinite(rateEst); vObs = max(-1, min(1, rateEst / 150)); end
    obs = [logged.k/P.F; newRange/3000; double(detected); vObs];
    if P.useFeatures
        fv = features.featureVector(cube(:,1), P.pfb);
        obs = [obs; tanh(fv ./ (3*P.refScale))];
    end
    if P.useStats
        obs = [obs; localScreenStats(logged)];
    end
end

% ------------------------------------------------------------------------
function v = localScreenStats(logged)
%LOCALSCREENSTATS  T3 -- the two ECCM screens' OWN running statistics, so the
%   agent can observe the quantity it is scored on instead of inferring it
%   from a 54-D per-pulse proxy (see T2: the feature block turned out to be a
%   lossy amplitude readout, not noise).
%
%   Built from localTrackStruct, i.e. from EXACTLY the evidence the
%   discriminator will be handed -- not a second, drifting definition of the
%   same thing. The arithmetic below mirrors +track/discriminator.m:
%       screen 1  slope = polyfit(log R, log A, 1),  score = max(0,1-|s+2|/2)
%       screen 2  sign(mean(diff R)) == sign(mean D)
%
%   NOT a reward and NOT self-verification (CLAUDE.md Rule 2): this is an
%   OBSERVATION of the agent's own emitted history. It reveals no verdict,
%   no label and nothing about the genuine target -- only what the agent has
%   already transmitted. Shaping still comes from localReward.
%
%   5 dims, all in [-1, 1]:
%       1  fitted slope, centred on the physical -2 and squashed
%       2  screen-1 score as the discriminator would compute it, 0..1
%       3  mean range step, normalised
%       4  mean measured range-rate, normalised
%       5  screen-2 sign agreement: +1 agree, -1 disagree, 0 not applicable
    v = zeros(5, 1);
    ts = localTrackStruct(logged);
    if isempty(ts); return; end          % < 2 usable looks: nothing fitted yet

    R = ts.range(:); A = ts.amplitude(:); D = ts.doppler(:);
    ok = isfinite(R) & isfinite(A) & R > 0 & A > 0;
    if nnz(ok) >= 2 && range(R(ok)) > 1e-9
        p = polyfit(log(R(ok)), log(A(ok)), 1);
        v(1) = tanh((p(1) + 2) / 2);
        v(2) = max(0, 1 - abs(p(1) + 2) / 2);
    end

    dR = mean(diff(R));
    mD = mean(D);
    v(3) = tanh(dR / 120);               % one action-grid step is 120 m
    v(4) = tanh(mD / 120);
    if abs(dR) > 1e-9 && abs(mD) > 1e-9
        v(5) = double(sign(dR) == sign(mD)) * 2 - 1;
    end
end

% ------------------------------------------------------------------------
function [reward, logged] = localReward(logged, P, isDone)
%LOCALREWARD  Terminal deception reward + potential-based shaping.
%
%   THE PROBLEM WITH THE OLD REWARD. agent.buildEnvFeatureConditioned paid
%   +0.05 per DETECTED frame and +1 for merely being confirmed, against +2
%   for actually beating the ECCM. Measured over its own 300-episode run the
%   reward took four values: 0.4 (27.3% -- detected, never confirmed), 1.4
%   (49.0% -- confirmed and FLAGGED), 2.4 (23.0% -- confirmed and passed).
%   So 1.4 was available for being seen and caught, and the entire premium
%   for successful deception was a 71% uplift on a floor the agent could
%   reach by turning the gain up. That rewards being LOUD, not being REAL.
%
%   THE FIX, in two parts.
%
%   (a) Bare detection no longer pays. Detection is a PRECONDITION for
%       deception, not an achievement -- a phantom nobody sees has deceived
%       nobody. The terminal ladder is: never confirmed 0, confirmed but
%       screened as a decoy +0.5, confirmed and screened REAL +3. The
%       premium for deception is now 6x, not 1.7x.
%
%   (b) Potential-based shaping (Ng, Harada & Russell, ICML 1999) carries
%       that terminal signal backwards without changing what is optimal:
%
%           F(s,s') = gamma * Phi(s') - Phi(s)
%
%       is the ONLY shaping form that provably leaves the optimal policy
%       unchanged. Phi here is the INDEPENDENT judge's own running screen
%       score on the partial track. This is the principled answer to "sparse
%       terminal rewards never propagated through the network" -- it
%       densifies the gradient without inventing a new objective, which is
%       what an ad-hoc dense bonus (the +0.05) did.
%
%       RULE 2 IS INTACT. Phi is computed by +track/discriminator -- the
%       independent ECCM block, the same one that issues the terminal
%       verdict. It is NOT computed by +features or +synth. The synthesizer
%       still never grades its own realism.
%
%       HONEST CAVEAT. Ng et al.'s invariance is proved for Phi over the
%       MARKOV state. Phi here depends on the detection history, which lives
%       in `logged` (the true env state) but is only partially reflected in
%       the 58-D observation. Under that partial observability the guarantee
%       is approximate rather than exact. Set opts.shaping=false to train
%       without it; experiments.diagnoseDopplerEnv runs both.

    reward = 0;

    if isDone
        confirmed = track.runTracker(logged.dets, logged.times, C_of(P));
        logged.confirmedCount = numel(confirmed);
        if numel(confirmed) >= 1
            ts = localTrackStruct(logged);
            if isempty(ts)
                logged.eccmLabel = "unscreened";
                reward = reward + 0.5;
            else
                [label, ~] = track.discriminator(ts, C_of(P));
                logged.eccmLabel = label;
                if label == "real"
                    reward = reward + 3.0;
                else
                    reward = reward + 0.5;
                end
            end
        else
            logged.eccmLabel = "unconfirmed";
        end
    end

    if P.shaping
        phiNext = localPotential(logged, P, isDone);
        reward  = reward + P.gamma * phiNext - logged.phi;
        logged.phi = phiNext;
    end
end

% ------------------------------------------------------------------------
function phi = localPotential(logged, P, isDone)
%LOCALPOTENTIAL  Judge's running screen score on the partial track, in [0,1].
%   Zero at a terminal state, which is what makes the telescoping sum of
%   gamma*Phi(s') - Phi(s) vanish over a complete episode and leaves the
%   terminal reward as the only thing that accumulates.
    phi = 0;
    if isDone; return; end
    ts = localTrackStruct(logged);
    if isempty(ts); return; end
    [label, conf] = track.discriminator(ts, C_of(P));
    % discriminator returns confidence = |score-0.5|*2 and the sign only via
    % the label. Invert both back to the signed score in [0,1] so the
    % potential rises toward "looks real" rather than toward "the screen is
    % confident" -- a confidently-flagged decoy must not be rewarded.
    if label == "decoy"
        phi = 0.5 - conf/2;
    else
        phi = 0.5 + conf/2;
    end
end

% ------------------------------------------------------------------------
function ts = localTrackStruct(logged)
%LOCALTRACKSTRUCT  The evidence the ECCM gets, built ONLY from measurements.
%   .doppler is the MEASURED range-rate off the Doppler axis -- never
%   diff(range). .dopplerMeasured is TRUE, which arms discriminator screen
%   2's contradiction branch (a moving range with no Doppler now scores 0
%   instead of being ruled inadmissible).
    ts = [];
    m = ~isnan(logged.rangeHist) & ~isnan(logged.ampHist) & ~isnan(logged.rateHist);
    if nnz(m) < 2; return; end
    ts = struct( ...
        'range',           logged.rangeHist(m), ...
        'amplitude',       logged.ampHist(m), ...
        'doppler',         logged.rateHist(m), ...
        'dopplerMeasured', true);
end

% ------------------------------------------------------------------------
function C = C_of(P)
    C = P.C;
end
