function [label, confidence] = discriminator(trackStruct, C) %#ok<INUSD>
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
%
%   trackStruct MAY also carry:
%           .dopplerMeasured  logical. TRUE means .doppler is a real
%                             measurement, so a zero in it means the target
%                             genuinely showed no Doppler. FALSE or ABSENT
%                             (the default) means Doppler was never measured
%                             at all, so a zero carries no information.
%                             +engine/runJudge.m sets this true only on its
%                             pulse-cube path. See "MISSING vs ABSENT" below.
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
        % 'residual' is DELIBERATELY NOT in this default -- see the screen's
        % own block below for the measurement that put it here. Opt in with
        % screensEnabled = {'amplitude','doppler','micro','residual'}.
        enabled = {'amplitude', 'doppler', 'micro'};
    end
    useAmplitude = any(strcmpi(enabled, 'amplitude'));
    useDoppler   = any(strcmpi(enabled, 'doppler'));
    useResidual  = any(strcmpi(enabled, 'residual'));

    scores = [];

    % ---- 1. amplitude-range consistency ----
    if useAmplitude
    if range(R) > 1e-9                          % range actually varies
        p = polyfit(log(R), log(A), 1);
        slope = p(1);
        scores(end+1) = max(0, 1 - abs(slope + 2) / 2); %#ok<AGROW>
    elseif range(A) < 1e-12                     % range AND amplitude both dead flat
        scores(end+1) = 0;                       %#ok<AGROW>  % no natural scintillation -> suspicious
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

    if isempty(scores)
        score = 0.5;                            % nothing informative either way
    else
        score = mean(scores);
    end

    % Vetoes apply AFTER the average, so they cannot be diluted by it.
    if microVeto || residualVeto
        score = 0;
    end

    if score > 0.5
        label = "real";
    else
        label = "decoy";
    end
    confidence = abs(score - 0.5) * 2;
end
