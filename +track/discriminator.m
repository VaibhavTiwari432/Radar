function [label, confidence, diag] = discriminator(trackStruct, C)
%DISCRIMINATOR  ECCM screen: is a confirmed track's signature physically
%               real, or a naive DRFM repeater? (POA Part 4 Stage 5, C7)
%
%   [label, confidence] = track.discriminator(trackStruct, C)
%       trackStruct : struct with parallel per-look fields
%           .range     [1 x K] metres
%           .amplitude [1 x K] linear (voltage/field, not power)
%           .doppler   [1 x K] range-rate-signed units (negative = closing)
%       C           : physics.Constants() (unused directly; kept for the
%                     project's standard call signature).
%
%       label      : "real" | "decoy"
%       confidence : 0..1
%       diag       : (optional 3rd output) struct recording which screens
%                    actually scored and why any of them abstained:
%                      .numScores            how many screens were informative
%                      .amplitudeSkipReason  "" if screen 1 scored, else why
%                                            it could not (see its guards)
%                    Two-output callers are unaffected.
%
%   AN ABSTAINING SCREEN IS NOT A PASS. With no informative screen at all the
%   score is 0.5 and the label is "decoy" (see the end of this function). But
%   an abstain does REMOVE that screen from the average, so a track that
%   suppresses one screen while passing another is scored on the rest -- which
%   is why every abstain has to be justified where it is written, and why
%   `diag` exists: a caller reporting a deception rate needs to be able to say
%   which screens were actually brought to bear.
%
%   trackStruct MAY also carry:
%           .dopplerMeasured  logical. TRUE means .doppler is a real
%                             measurement, so a zero in it means the target
%                             genuinely showed no Doppler. FALSE or ABSENT
%                             (the default) means Doppler was never measured
%                             at all, so a zero carries no information.
%                             +engine/runJudge.m sets this true only on its
%                             pulse-cube path. See "MISSING vs ABSENT" below.
%           .modeProbSeq      [K x nModels] this track's own IMM model
%                             probabilities at each hit, oldest first.
%                             ABSENT for CV/CA tracks and for any caller
%                             that predates it -- the manoeuvre-
%                             plausibility screen (2b, opt-in via
%                             screensEnabled) is then a no-op. See
%                             track.getFilterState, which is what extracts
%                             this from a live tracker.
%
%   Two independent screens, averaged over whichever are informative for
%   this track (a degenerate all-constant track only has one to go on):
%
%   1. Amplitude-range consistency. A real monostatic return's RECEIVED
%      POWER falls off as 1/R^4 (two-way radar equation); amplitude is
%      voltage/field, so amplitude ~ sqrt(power) ~ 1/R^2. A naive DRFM
%      repeater retransmits at a fixed gain and does not reproduce that
%      range dependence (in the limit, constant amplitude regardless of
%      range). We fit the log(amplitude) vs log(range) slope over the
%      track and score its distance from the physical value of -2.
%      Only meaningful when range actually varies over the track; if it
%      doesn't AND amplitude is exactly constant too, that absence of any
%      natural scintillation is itself the giveaway (score 0).
%
%   2. Doppler/range-rate sign consistency. A closing target (range
%      decreasing) must show a closing (negative, by this project's
%      convention) Doppler, and vice versa.
%
%   MISSING EVIDENCE vs ABSENT EVIDENCE (25 July 2026) -- read before
%   changing screen 2's guard.
%   ----------------------------------------------------------------------
%   Screen 2 used to be skipped entirely whenever mean(doppler) was ~0, and
%   the remaining screen then carried the verdict alone. That was a
%   measurable hole, not a theoretical one: with the sign screen simply
%   dropped, a phantom transmitting NO DOPPLER AT ALL passed 10/10 seeds as
%   long as its gain ramped as 1/R^2 (tests/test_vee_deception_check.m's
%   2x2). A phantom could make the evidence against it inadmissible by
%   declining to produce it -- which is a strategy, and the averaging rule
%   rewarded it.
%
%   The fix distinguishes two genuinely different situations that the old
%   guard collapsed together:
%     * Doppler was MEASURED and came back zero while the range is MOVING.
%       That is not missing evidence, it is a CONTRADICTION -- a physical
%       target cannot change range without a radial velocity. Scores 0.
%       Likewise a nonzero Doppler on a track whose range never moves.
%     * Doppler was NEVER MEASURED (no slow-time axis to measure it from --
%       every legacy 2-D caller, and every caller that predates
%       .dopplerMeasured). Genuinely uninformative; screen 2 is skipped,
%       exactly as before. Callers that do not set .dopplerMeasured keep
%       their old behaviour, by design -- this file must not start flagging
%       tracks on evidence its caller never had.
%     * Range AND Doppler both ~zero, measured: a stationary target is
%       physically possible (a hovering rotorcraft, a ground return), so
%       this is consistent, not contradictory. Screen 2 stays out of it and
%       screen 1's own flat-amplitude branch handles the decoy case.
%
%   Ref: POA Part 4 Stage 5.

    R = trackStruct.range(:);
    A = trackStruct.amplitude(:);
    D = trackStruct.doppler(:);

    % Optional screen mask, for the ECCM ablation in
    % +experiments/benchmarkSuite.m ("which screen is actually doing the
    % work?"). Absent -> every screen enabled, i.e. unchanged behaviour for
    % every existing caller.
    if isfield(trackStruct, 'screensEnabled')
        enabled = cellstr(trackStruct.screensEnabled);
    else
        % 'residual', 'maneuver', 'bearing' and 'rangerate' are DELIBERATELY
        % NOT in this default -- see each screen's own block below for why.
        % Opt in with screensEnabled = {'amplitude','doppler','micro',
        %                   'residual','maneuver','bearing','rangerate'}.
        enabled = {'amplitude', 'doppler', 'micro'};
    end
    useAmplitude = any(strcmpi(enabled, 'amplitude'));
    useDoppler   = any(strcmpi(enabled, 'doppler'));
    useResidual  = any(strcmpi(enabled, 'residual'));
    useManeuver  = any(strcmpi(enabled, 'maneuver'));
    useBearing   = any(strcmpi(enabled, 'bearing'));
    useRangeRate = any(strcmpi(enabled, 'rangerate'));

    scores = [];
    amplitudeSkipReason = "";   % non-empty when screen 1 abstained; see diag output

    % ONE fast-time sample of two-way range, for the signal .range was measured
    % from. Two screens need it (screen 1's lever guard and screen 2c's), so it
    % is resolved ONCE here rather than inside either -- putting it inside the
    % amplitude block left it undefined whenever an ablation mask turned that
    % screen off, which is a crash, not a fallback. +engine/runJudge.m supplies
    % it; callers predating 9 Sep 2026 get physics.Constants(), correct for them
    % because they all judged this project's own 3.2 MHz radar.
    if isfield(trackStruct, 'rangeResolutionM') && ...
            isfinite(trackStruct.rangeResolutionM) && trackStruct.rangeResolutionM > 0
        rangeCellM = double(trackStruct.rangeResolutionM);
    else
        rangeCellM = C.range_per_sample;
    end

    % ---- 1. amplitude-range consistency ----
    % TWO ABSTAIN GUARDS, added 8 September 2026. Read the block above them
    % before touching either -- they are the "MISSING vs ABSENT" doctrine
    % applied to screen 1, which had no version of it.
    %
    % WHAT WAS WRONG. The old guard was `range(R) > 1e-9` -- a range change of
    % one NANOMETRE was enough to make this screen fit a slope and commit to a
    % verdict. Over a short lever arm the fit is dominated by amplitude noise,
    % so the screen returned a meaningless slope, scored near 0, and CONDEMNED
    % targets whose amplitude was 1/R^2 by construction -- while believing it
    % had looked. MEASURED (STAGE_F_PHASE0p5_RESULTS.md 3.5): on a bench-config
    % walk this screen returned `decoy` for the physically honest phantom AND
    % for a constant-amplitude decoy, at both walk directions -- it could not
    % separate them at all, yet its near-zero score still dragged the composite
    % mean and handed the verdict to whichever other screen tipped it.
    % This project has seen the same thing once before and recorded it without
    % acting on it: the AUC 0.50 cell in the Stage F plan's 2.5 is this screen
    % scoring a coin flip rather than abstaining.
    %
    % WHY ABSTAINING IS SAFE HERE, given the doctrine above says suppressing
    % evidence must not be rewarded. Screen 2's hole was real because a target
    % could decline to produce Doppler while still walking its range -- the
    % attack proceeded, the evidence did not. Guard A below cannot be abused
    % that way: it fires only when the range stays inside 3 range cells, and a
    % target that is not moving in range is not executing RGPO or VGPO, which
    % are the only attacks this screen exists to catch. The dead-flat branch
    % still catches the static decoy underneath it, so nothing that used to be
    % condemned by absence of scintillation escapes.
    % Guard B is weaker on that point and it is stated rather than hidden: a
    % target COULD inflate its own amplitude residual to force an abstain. It
    % gains little -- deliberate amplitude jitter is what the opt-in residual
    % screen (+track/amplitudeResidualScreen.m) and the flat/scintillation
    % logic are looking at -- but it is not impossible, and if this screen ever
    % becomes load-bearing against a fitted adversary, Guard B should report
    % UNSCREENED upward rather than silently shrink the average.
    if useAmplitude
    rangeSpanM = range(R);
    % Guard A (geometry, decidable before any fitting). Threshold is the
    % instrument's own resolution -- 3 range cells, NOT a tuned number, and the
    % same bar +track/bearingRateScreen.m already uses for the same question.
    %
    % THE CELL SIZE MUST BE THE JUDGED SIGNAL'S, not the project's. .range is
    % built by +engine/runJudge.m from the fs carried in the .mat, so a signal
    % at a different sample rate arrives here with a different metre per bin --
    % 149.90 m at the 1 MHz bench against 46.84 m at this project's 3.2 MHz,
    % a factor of 3.2. Comparing one instrument's range span against another
    % instrument's cell size is how a guard silently stops guarding. Callers
    % that do not supply .rangeResolutionM get physics.Constants(), which is
    % correct for every caller this project had before 9 Sep 2026.
    rangeResolvable = rangeSpanM >= 3 * rangeCellM;
    if ~rangeResolvable && range(A) < 1e-12
        % Range did not measurably change AND amplitude is dead flat: no
        % natural scintillation, the original giveaway. Unchanged behaviour.
        scores(end+1) = 0;                       %#ok<AGROW>
    elseif ~rangeResolvable
        % Guard A fires: to this radar the target did not move, so there is no
        % log(R) lever to fit against. Genuinely uninformative, not a failure.
        amplitudeSkipReason = string(sprintf( ...
            'range span %.1f m is under 3 range cells (%.1f m)', ...
            rangeSpanM, 3 * rangeCellM));
    else
        [slope, seSlope] = localLogLogSlope(R, A);
        % Guard B (statistical). The score below spans its full range as
        % |slope+2| goes 0 -> 2, so a standard error of 1 means +-2 sigma
        % covers the ENTIRE scoring band: the fit cannot place the slope
        % inside its own dynamic range and any score it returns is a draw from
        % noise. Derived from the score function, not tuned. numel < 3 gives
        % seSlope = Inf: two points fit a line exactly and leave no residual,
        % so there is no uncertainty estimate to test.
        if seSlope < 1
            scores(end+1) = max(0, 1 - abs(slope + 2) / 2); %#ok<AGROW>
        else
            amplitudeSkipReason = string(sprintf( ...
                'slope %.2f has standard error %.2f: not estimable', ...
                slope, seSlope));
        end
    end
    end

    % ---- 2. Doppler / range-rate sign consistency ----
    % Default FALSE: a caller that does not say its Doppler is measured is
    % assumed not to have measured it (see "MISSING vs ABSENT" above).
    dopplerMeasured = isfield(trackStruct, 'dopplerMeasured') && ...
                      any(logical(trackStruct.dopplerMeasured));

    rangeMoving    = abs(mean(diff(R))) > 1e-9;
    dopplerPresent = abs(mean(D))       > 1e-9;

    if ~useDoppler
        % screen disabled by the caller's ablation mask
    elseif rangeMoving && dopplerPresent
        scores(end+1) = double(sign(mean(diff(R))) == sign(mean(D))); %#ok<AGROW>
    elseif dopplerMeasured && (rangeMoving ~= dopplerPresent)
        % Exactly one of the two present, and we DID look: physically
        % impossible, so this is a failed screen, not an absent one.
        scores(end+1) = 0; %#ok<AGROW>
    end

    % ---- 2c. Bearing/range kinematic consistency (the N=1 screen) ----
    % A target in straight-line constant-velocity motion conserves
    % R^2*dtheta/dt, so its bearing is an exactly LINEAR function of 1/R. A
    % phantom is radiated from the mother platform and therefore inherits the
    % MOTHER's bearing trajectory while reporting its OWN range, which breaks
    % that law. +track/bearingRateScreen.m carries the derivation, the score
    % definition and the one documented evasion.
    %
    % WHY THIS ONE MATTERS: every other per-track screen here tests a quantity
    % a DRFM can forge independently. Azimuth cannot be forged, because it is
    % set by where the transmitter physically is -- and unlike the co-bearing
    % screen in +engine/runJudge.m, which needs N >= 2 tracks to compare, this
    % test is entirely within a single track. It is the first screen in this
    % project that can condemn a LONE phantom.
    %
    % OPT-IN, and NaN-safe: absent azimuth (a sum-channel-only export, every
    % caller predating the angle channel) contributes nothing rather than
    % vetoing -- the same "the caller never had this evidence" posture as the
    % Doppler screen's dopplerMeasured guard. bearingRateScreen returns NaN
    % for a track whose bearing or range never moved, and a NaN is dropped
    % here rather than scored, because an uninformative 0.5 must never be
    % reported as a reading.
    if useBearing && isfield(trackStruct, 'azimuth') && ...
            isfield(trackStruct, 'time') && ~isempty(trackStruct.azimuth)
        bScore = track.bearingRateScreen(trackStruct.azimuth, R, ...
                                          trackStruct.time, rangeCellM);
        if ~isnan(bScore)
            scores(end+1) = bScore; %#ok<AGROW>
        end
    end

    % ---- 2b. Manoeuvre-plausibility (IMM mode-probability transition rate) ----
    % BENCHMARK_RESULTS.md's "Tracker model" generalization sweep found CV,
    % IMM and CA produced BYTE-IDENTICAL evasion/F1: this discriminator reads
    % only raw CFAR range/amplitude/Doppler series and never asked the
    % tracker's own filter anything, so the motion model could change
    % whether a track exists but structurally could not change its label.
    % This screen is what makes that sweep non-null.
    %
    % trackStruct.modeProbSeq, when present, is a [K x nModels] matrix of
    % this track's OWN IMM model probabilities at each hit, oldest first
    % (+track/runTracker.m's optional filterHistory output, threaded per
    % track the same way +engine/runJudge.m already rebuilds .range/
    % .amplitude from history). Absent for any CV/CA track and for every
    % caller that predates this field -- this screen must then be a total
    % no-op (score neutral, not vetoed), same "caller never had the
    % evidence" posture as .dopplerMeasured above.
    %
    % [ASSUMED], not measured (no real-aircraft IMM telemetry in this
    % project to calibrate against -- flagged plainly rather than dressed
    % up as derived, CLAUDE.md Rule 1/7). A genuine manoeuvring aircraft's
    % turns/climbs last many dwells at this project's 1 Hz revisit cadence,
    % not one dwell -- inertia, not signal processing, is what keeps a real
    % aircraft's IMM dominant-mode estimate from flipping every update. A
    % planner/entity walked through an abrupt, frame-to-frame commanded
    % acceleration profile (this project's CV entity carries a
    % "commandable" Rddot, CLAUDE.md's VEE section) has no such inertia
    % constraint and can flip the IMM's dominant mode far faster.
    % MAX_PLAUSIBLE_SWITCH_RATE = 1 dominant-mode switch per 4 dwells is the
    % stated assumption; tD1_imm_discriminates.m and the re-run tracker-model
    % sweep are what test whether it is doing useful work, not this comment.
    MAX_PLAUSIBLE_SWITCH_RATE = 0.25;   % [ASSUMED] switches/frame, see above
    %
    % ============ VETO-ONLY SINCE 7 AUGUST 2026, AND WHY ============
    % This screen shipped as an averaged VOTE
    % (scores(end+1) = max(0, 1 - switchRate/MAX_PLAUSIBLE_SWITCH_RATE)) and
    % that was wrong for exactly the reason this file already documents twice
    % -- once for the micro-Doppler comb ("a passing comb adds NOTHING to the
    % average") and once for the amplitude residual ("a +1 added to the mean
    % rescues a track that screen 1 or 2 had condemned"). Screen 2b was built
    % as a vote anyway and duly reintroduced the failure mode the other two
    % were designed around.
    %
    % MEASURED, not argued (generator.screenAblation, N=5 seeds, arms that
    % each violate exactly one law):
    %
    %   mask                     flat_amplitude   zero_doppler
    %   DEFAULT (a+d+micro)              0.80          1.00
    %   +maneuver (as a VOTE)            0.00          0.00
    %
    % A non-manoeuvring phantom sits far under the 0.25 ceiling, so 2b scored
    % ~1.0 and averaged the condemning screen straight back up:
    % mean([0 1 1]) = 0.67 > 0.5 -> 'real'. A decoy the Doppler screen caught
    % 5/5 escaped 5/5 BECAUSE a screen was added. The same run's
    % 'DEFAULT, IMM tracker' control was identical to DEFAULT cell for cell,
    % so this was the SCREEN, not the IMM tracker it requires.
    %
    % As a veto it can add capability but cannot subtract any, which makes it
    % safe by construction -- the same argument the residual screen makes for
    % itself. THE THRESHOLD IS UNCHANGED: the vote scored exactly 0 at
    % switchRate == MAX_PLAUSIBLE_SWITCH_RATE, so vetoing at that same point
    % preserves the line the constant already names and introduces no new
    % number. Everything below it, which used to drag the mean down by a
    % fraction, is now simply silent.
    %
    % ---- BUT THE VETO ADDS NOTHING EITHER, AND HERE IS WHY (MEASURED) ----
    % The 'maneuvering' arm exists so this screen can be shown still doing
    % its job. It does not. '+maneuver (IMM)' is identical to the
    % 'DEFAULT, IMM tracker' control in ALL FIVE arms, and the flutter
    % phantom is flagged 0.00. Measured switchRate is exactly 0 (not NaN --
    % modeProbSeq DOES reach here, the plumbing is fine), on the flutter arm
    % AND the genuine arm alike. Three compounding causes, none of them the
    % threshold:
    %
    %  1. The tracker's measurement is RANGE-ONLY, quantised to 46.84 m. The
    %     scene alternates v between -15 and -55 m/s at 1 s frames, a 40 m
    %     alternation -- UNDER one bin. Measured diffs are
    %     [-46.8 0 -46.8 -46.8 -46.8] for the flutter vs
    %     [0 -46.8 -46.8 -46.8 0] for the genuine target: the same staircase.
    %     The IMM has nothing to switch on.
    %  2. The channel that CAN see it is not wired to the filter. Measured
    %     range-rate is [-15 -56.2 -15 -56.2 -15 -56.2], a textbook
    %     alternation -- but Doppler never enters the tracker, so screen 2b
    %     reads mode probabilities driven by the one channel that is blind
    %     to the signature.
    %  3. Even given (1) and (2), the dwell is too short to resolve the
    %     line. A confirmed track here spans 6 frames = 5 transitions, so
    %     one switch scores 0.20 -- UNDER 0.25. The veto needs 2 of 5.
    %
    % So this screen is currently INERT, not merely harmless. Keep it as a
    % veto (it removes the measured regression above and costs nothing), but
    % do NOT claim it catches manoeuvring phantoms: on this instrument it
    % cannot, and no threshold change fixes that. It becomes real only if
    % range-rate reaches the tracker -- i.e. the 2-D/range-Doppler tracker
    % CLAUDE.md lists under "Still not built".
    maneuverVeto = false;
    if useManeuver && isfield(trackStruct, 'modeProbSeq') && ~isempty(trackStruct.modeProbSeq)
        mp = trackStruct.modeProbSeq;
        if size(mp, 1) >= 2
            [~, dominant] = max(mp, [], 2);
            switchRate = nnz(diff(dominant) ~= 0) / (numel(dominant) - 1);
            maneuverVeto = switchRate >= MAX_PLAUSIBLE_SWITCH_RATE;
        end
        % else: too short to compute a transition rate -- uninformative, skip.
    end
    % else: no IMM mode data at all (CV/CA filter, or a caller that never
    % supplied it) -- genuinely uninformative, screen skipped exactly like
    % screen 2's dopplerMeasured==false case.

    % ---- 3. micro-Doppler comb (the anti-repeater one) ----
    % A DRFM repeater retransmits a delayed, scaled, CONSTANT-phase copy of
    % the radar's own pulse (+synth/synthesizeSwarm.m applies exactly delay,
    % gain and one phase). A constant phase across slow time is a SINGLE
    % Doppler line. A rotor phase-modulates its return, which by Jacobi-Anger
    % is a comb of Bessel harmonics (+engine/+entity/render.m). So a comb is
    % something a repeater structurally cannot produce -- it is not in the
    % synthesizer's vocabulary at all, which is what makes this different
    % from range, Doppler and amplitude, all of which CAN be forged.
    %
    % THIS SCREEN IS NOT CLASS-AGNOSTIC, AND THAT IS WHY IT IS GATED.
    % Screens 1 and 2 are physics that applies to anything that flies. This
    % one is not: a fixed-wing target legitimately has no rotor comb, so
    % scoring its absence as suspicious would flag every genuine fighter --
    % exactly the failure mode that got the whiteness screen withdrawn
    % (BENCHMARK_RESULTS.md). It therefore runs ONLY when the caller has
    % said, in its own threat model, that the targets of interest are
    % rotorcraft (.expectMicroDoppler), AND the dwell could actually resolve
    % a comb (.microResolvable).
    %
    % THRESHOLD IS DERIVED FROM THE NULL, NOT FITTED TO THE POSITIVE CLASS.
    % A pure tone still leaks a little energy outside the mainlobe. Measured
    % worst-case leakage for a single-line repeater across dwells of
    % 32..1024 pulses (experiments.microDopplerScreenability) is 0.0457;
    % genuine rotors at resolving dwells sit at 0.375-0.658. The threshold is
    % 3x the worst measured leakage, so it is set by how flat a REPEATER
    % looks, never by how comb-like a drone looks.
    COMB_LEAKAGE_MAX = 0.0457;
    COMB_THRESHOLD   = 3 * COMB_LEAKAGE_MAX;      % 0.137

    % IT IS A VETO, NOT A VOTE -- and that is a correctness requirement, not
    % a preference. The verdict below is mean(scores) > 0.5. With two
    % screens, one failure gives 0.5 and is caught. Append a third screen
    % that PASSES and the same failure gives (0+1+1)/3 = 0.667, i.e. adding
    % this screen would have quietly rescued phantoms that the amplitude
    % screen was already catching. Averaging dilutes.
    %
    % So a passing comb adds NOTHING to the average (the older screens keep
    % their exact arithmetic, and the published benchmark stays comparable),
    % while a failing comb sets the score to 0 outright. The asymmetry is
    % physical: range, Doppler and amplitude can all be forged by a repeater
    % -- this project has spent considerable effort showing exactly that --
    % but a Bessel comb is not in synthesizeSwarm's vocabulary at all. So a
    % comb's ABSENCE, once both gates are open, is a necessary-condition
    % failure rather than one opinion among three.
    useMicro = any(strcmpi(enabled, 'micro'));
    expectMicro = isfield(trackStruct, 'expectMicroDoppler') && ...
                  any(logical(trackStruct.expectMicroDoppler));
    microResolvable = isfield(trackStruct, 'microResolvable') && ...
                      any(logical(trackStruct.microResolvable));
    microVeto = false;
    if useMicro && expectMicro && microResolvable && isfield(trackStruct, 'combFrac')
        cf = trackStruct.combFrac;
        microVeto = isfinite(cf) && (cf <= COMB_THRESHOLD);
    end

    % ---- 4. AMPLITUDE RESIDUAL CONSISTENCY (Phase 4, Screen 3) ----
    % Screen 1 fits the SLOPE of log(A) vs log(R). Measured on real pipeline
    % tracks at this project's 8-frame dwell, that fit passes only 12% of
    % GENUINE targets -- its precision accumulates with lever arm, and this
    % radar's lever arm is structurally short (bounded above by the 1124 m
    % CFAR blind zone, below by v_ua = 59.96 m/s).
    %
    % This screen fixes the slope at the physical -2, fits only the intercept,
    % and scores the SCATTER about it. Two consequences, both measured
    % (tests/test_amplitude_residual_screen.m):
    %   * RCS-independent EXACTLY -- sigma appears only in the intercept,
    %     which is fitted and discarded. That matters because a radar cannot
    %     know a target's RCS.
    %   * No lever arm needed -- 90% genuine pass at 8 frames vs slope's 12%,
    %     and 10 points of variation across an 8..32-frame sweep vs slope's 21.
    %
    % WHY THE "TOO PERFECT" BRANCH IS A VETO AND NOT AN AVERAGED SCORE.
    % Averaging was measured and it destroys the capability: a servo-driven
    % repeater scores slope 1.0 (its law is exactly -2), doppler 1.0, residual
    % 0.0 -> mean 0.67 -> "real". The one failure mode this screen exists to
    % catch would be diluted straight back to a pass. A return with LITERALLY
    % ZERO scatter about the law is not a physical object -- real RCS
    % fluctuates, floor measured at 0.233 dB (99 RadChar records) and 0.491 dB
    % (TSMS corner reflector through a real receiver). So it vetoes, exactly
    % as the micro-Doppler comb below already does for the same reason: the
    % failure is physically impossible, not merely suspicious.
    %
    % The OTHER tail (scatter too LARGE = not following the law) is left in
    % the average, because it is the same evidence screen 1 already weighs and
    % should not be counted twice as a veto.
    %
    % FLOOR OWNERSHIP (CLAUDE.md Rule 2): this number is the JUDGE's, declared
    % here. It is NOT read from engine.entity.calibrateQ -- the judge must not
    % import the engine's calibration, and +track may not reference +engine at
    % all (tests/test_package_separation.m). The provenance is cited; the value
    % is the judge's own.
    % THE FLOOR IS DERIVED PER TRACK, NOT PICKED. A first version used a flat
    % 0.15 dB and false-vetoed genuine targets: the measured genuine residual
    % distribution has mean 0.227 dB but p5 = 0.133, so a 0.15 dB floor sits
    % INSIDE the real population's lower tail.
    %
    % The right bound accounts for how badly a standard deviation is known
    % from a short track. For N samples the sample std has its own std of
    % about sigma/sqrt(2(N-1)), so a genuine track can legitimately measure
    % low by chance on a short dwell. Taking a 3-sigma lower bound:
    %
    %       floor(N) = SCINT_FLOOR_DB * max(0, 1 - 3/sqrt(2(N-1)))
    %
    %   N =  8  ->  0.046 dB      N = 16  ->  0.105 dB     N = 32  ->  0.144 dB
    %
    % It tightens as the track lengthens, which is correct: with more samples
    % a genuine target's scatter cannot plausibly measure near zero. At N <= 4
    % it goes to 0, i.e. the veto disarms itself rather than guessing on a
    % track too short to know anything about.
    SCINT_FLOOR_DB   = 0.233;   % MEASURED: median pulse-to-pulse peak-amplitude
                                % std over 99 real RadChar LFM records. The
                                % judge's own copy of a physical fact -- NOT
                                % read from engine.entity.calibrateQ, which
                                % +track may not reference (Rule 2,
                                % tests/test_package_separation.m).
    % (No ceiling constant: the "scatter too large" tail is exactly the
    % evidence screen 1 already weighs, and this screen is veto-only, so
    % there is nothing for a ceiling to do here.)
    % ============ VETO-ONLY, AND WHY -- MEASURED, NOT ASSUMED ============
    % A first integration let this screen contribute a POSITIVE score to the
    % average when the residual looked healthy. That was wrong twice over, and
    % the full deception suite caught both within one run:
    %
    %   * It DILUTED other screens' failures. A +1 added to the mean rescues a
    %     track that screen 1 or 2 had condemned. Measured: the static VEE
    %     phantom (arm D) went from 0/10 deceiving to 7/10, and the genuine arm
    %     fell from 10/10 to 5/10.
    %   * It fired where it has no meaning. This is a screen about the
    %     amplitude-RANGE law, so a track whose range never varies gives a
    %     degenerate fit -- the residual is then just amplitude scatter about
    %     its own mean, which says nothing about 1/R^2. Worse, screen 1 also
    %     contributes nothing in that case (its range guard fails and its
    %     flat-amplitude branch does not fire on a scintillating return), so
    %     scores = [1] alone and a STATIC REPEATER scored a clean pass.
    %
    % So: this screen may only ever VETO, never raise a score. It can add
    % capability but cannot subtract any, which makes integrating it safe by
    % construction. And it inherits screen 1's own range guard.
    %
    % ============ WHY IT IS OFF BY DEFAULT ============
    % Veto-only and correctly guarded, it STILL flags this project's genuine
    % reference target 10/10. That is not a screen fault -- it is the screen
    % being right about a scene that is wrong. Both genuine arms render with
    %       'swerling', 0
    % (tests/test_vee_deception_check.m:244, tests/test_angle_channel.m:296),
    % i.e. a NON-FLUCTUATING target whose amplitude follows 1/R^2 exactly.
    % Zero scintillation is precisely the servo-driven-repeater signature this
    % veto exists to catch, so it fires -- correctly -- on a "genuine" target
    % that is physically unrealistic in exactly the dimension being tested.
    %
    % Enabling this screen therefore requires FIRST rendering genuine
    % reference targets with real fluctuation (swerling >= 1). That changes
    % every reference scene and moves every published ECCM number again, so it
    % is a deliberate decision, not a side effect of this integration.
    % Measured evidence and the full before/after tables:
    % PHASE4_ECCM_INTEGRATION_RESULTS.md.
    residualVeto = false;
    if useResidual && range(R) > 1e-9
        okRA = isfinite(R) & isfinite(A) & R > 0 & A > 0;
        nR = nnz(okRA);
        if nR >= 3
            lr = log(R(okRA)); la = log(A(okRA));
            b  = mean(la + 2*lr);                 % intercept only; absorbs sqrt(sigma)
            residDb = 20/log(10) * (la - (-2*lr + b));
            sigmaDb = std(residDb);
            floorDb = SCINT_FLOOR_DB * max(0, 1 - 3/sqrt(2*(nR-1)));
            residualVeto = (floorDb > 0) && (sigmaDb < floorDb);
        end
    end

    % ---- 2d. Range-rate MAGNITUDE (the RGPO/VGPO gate) ----
    % Screen 2 above tests only the SIGN of the range walk against the sign of
    % the Doppler. +track/rangeRateConsistency.m's header names the hole that
    % leaves: "a repeater that walks its false range at -50 m/s while
    % transmitting only -5 m/s of Doppler passes that screen outright -- both
    % quantities are negative." This is the magnitude test that closes it, and
    % it has existed since Tier 1.2 as a REPORTED COLUMN in
    % +engine/runJudge.m, deliberately kept off the verdict until its effect
    % in isolation had been measured.
    %
    % A VETO, NOT A VOTE, and that is the whole reason it can be added at all.
    % DECEPTION_MAP_RESULTS.md section 6 is the cautionary case: screen 2c
    % measured a 0.968-vs-0.068 separation between a genuine target and a
    % phantom, and mean(scores) > 0.5 threw it away, because two passing
    % screens average a failing one back to `real`. F5 records the same
    % mechanism twice more. A veto cannot be diluted, so this screen can add
    % capability without subtracting any -- the identical argument the micro
    % and residual blocks above make for themselves.
    %
    % OFF BY DEFAULT, like every screen that postdates the published numbers.
    % Opt in with screensEnabled = {..., 'rangerate'}.
    %
    % GUARDED ON MEASURED EVIDENCE, not merely on presence. Without
    % dopplerMeasured the Doppler series is the legacy 2-D export's all-zero
    % placeholder, and vetoing a track for disagreeing with a number nobody
    % measured is exactly the "absent vs missing evidence" error this file
    % argues against at length for screen 2.
    rangeRateVeto = false;
    if useRangeRate && dopplerMeasured && isfield(trackStruct, 'time')
        rrArgs = {};
        if isfield(trackStruct, 'numPulses'); rrArgs = [rrArgs, {'NumPulses', trackStruct.numPulses}]; end
        if isfield(trackStruct, 'carrierHz'); rrArgs = [rrArgs, {'CarrierHz', trackStruct.carrierHz}]; end
        if isfield(trackStruct, 'prfHz');     rrArgs = [rrArgs, {'PrfHz',     trackStruct.prfHz}];     end
        if isfield(trackStruct, 'rangeSigmaM'); rrArgs = [rrArgs, {'RangeSigmaM', trackStruct.rangeSigmaM}]; end
        rr = track.rangeRateConsistency(R, trackStruct.time, D, C, rrArgs{:});
        rangeRateVeto = rr.informative && ~rr.pass;
    end

    if isempty(scores)
        score = 0.5;                            % nothing informative either way
    else
        score = mean(scores);
    end

    % Vetoes apply AFTER the average, so they cannot be diluted by it.
    if microVeto || residualVeto || maneuverVeto || rangeRateVeto
        score = 0;
    end

    if score > 0.5
        label = "real";
    else
        label = "decoy";
    end
    confidence = abs(score - 0.5) * 2;

    if nargout > 2
        diag = struct('numScores', numel(scores), ...
                      'amplitudeSkipReason', amplitudeSkipReason);
    end
end


function [slope, seSlope] = localLogLogSlope(R, A)
%LOCALLOGLOGSLOPE  Least-squares slope of log(A) vs log(R), with its standard
%   error. The standard error is the whole point: a slope on its own cannot
%   say whether it measured anything, and screen 1 committed to verdicts for
%   years on slopes it had no business trusting.
%
%   se(slope) = sqrt( SSR/(n-2) / Sxx ), the textbook OLS result. Returns Inf
%   when n < 3 (a line through two points has zero residual and therefore no
%   estimable error) or when Sxx is 0 (no lever arm at all).
    x = log(double(R(:)));
    y = log(double(A(:)));
    n = numel(x);
    p = polyfit(x, y, 1);
    slope = p(1);
    sxx = sum((x - mean(x)).^2);
    if n < 3 || sxx <= 0
        seSlope = Inf;
        return
    end
    resid = y - polyval(p, x);
    seSlope = sqrt(sum(resid.^2) / (n - 2) / sxx);
end
