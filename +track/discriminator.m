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
        enabled = {'amplitude', 'doppler', 'micro'};
    end
    useAmplitude = any(strcmpi(enabled, 'amplitude'));
    useDoppler   = any(strcmpi(enabled, 'doppler'));

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

    if isempty(scores)
        score = 0.5;                            % nothing informative either way
    else
        score = mean(scores);
    end

    % Veto applies AFTER the average, so it cannot be diluted by it.
    if microVeto
        score = 0;
    end

    if score > 0.5
        label = "real";
    else
        label = "decoy";
    end
    confidence = abs(score - 0.5) * 2;
end
