function [score, diag] = bearingRateScreen(azRad, rangeM, timeS, rangeCellM)
%BEARINGRATESCREEN  Is this track's BEARING consistent with its own RANGE?
%   The first screen in this project that can condemn a SINGLE phantom.
%
%   score : [0,1], > 0.5 leans genuine, NaN = uninformative (screen skipped)
%   diag  : struct of the quantities the score was computed from, so a caller
%           can report WHY rather than only WHAT
%
%   rangeCellM : (optional) one fast-time sample of two-way range, c/(2*fs),
%           for THE SIGNAL rangeM was measured from. Guard 2 below is stated
%           in range cells, so it needs the cell size of the instrument that
%           produced the track -- not of whichever radar physics.Constants()
%           happens to describe. Omit it and you get physics.Constants()'s
%           46.84 m, which is correct for every caller written before
%           9 September 2026 because they all judged 3.2 MHz signals.
%
%           WHY THIS IS AN ARGUMENT NOW. +engine/runJudge.m builds rangeM from
%           the fs carried in the .mat it is judging, so at the 1 MHz hardware
%           bench a range cell is 149.90 m, not 46.84 m -- a factor of 3.2.
%           Comparing one instrument's range span against another instrument's
%           cell size is how a guard silently stops guarding: at the bench the
%           old constant made this guard 140.5 m when it should have been
%           449.7 m, so tracks that had NOT resolvably moved would have been
%           scored instead of skipped. Same fix as +track/discriminator.m's
%           screen 1 lever guard, same reason.
%
%   THE HOLE THIS CLOSES. Every existing screen is either per-track and
%   forgeable (range, Doppler and amplitude can each be synthesised
%   independently -- this project spent considerable effort proving exactly
%   that) or unforgeable but MULTI-track. The co-bearing screen in
%   +engine/runJudge.m is the second kind: its own header says "the question
%   'do these tracks share a bearing?' cannot be answered by any per-track
%   function". At N = 1 there is nothing to compare against and it is silent,
%   which is why PHASE_B_RESULTS.md records single-phantom P_confirm = 1.00
%   across every radar class. This screen is per-track AND unforgeable.
%
%   THE INVARIANT, DERIVED NOT FITTED. A target in straight-line
%   constant-velocity motion conserves specific angular momentum about the
%   radar -- |r x v| is constant because r x v has zero time derivative when
%   v is constant. In polar terms that is
%
%       R^2 * dtheta/dt = h = const                                   (1)
%
%   (the same conservation law that gives Kepler's equal-areas result; here it
%   needs no gravity, only that the velocity vector does not change).
%   Substituting a constant-velocity range law R(t) = R0 + Rdot*t and
%   integrating (1):
%
%       theta(t) = theta0 + (h/Rdot) * (1/R0 - 1/R(t))
%
%   so for a genuine CV target THETA IS AN EXACTLY LINEAR FUNCTION OF 1/R.
%   That is the whole test, and it is a straight-line fit -- no optimiser, no
%   tuned constant, no assumed airframe envelope.
%
%   WHY A PHANTOM CANNOT SATISFY IT. The phantom is radiated from the mother
%   platform, so it inherits the MOTHER's bearing trajectory -- Blueprint 2.4,
%   enforced architecturally in +generator/render.m (one bearing per frame,
%   shared by every phantom, no per-phantom angle argument exists). Its
%   dtheta/dt is therefore set by the mother's geometry while the R it reports
%   is its own. Against a platform holding station in range, dtheta/dt is
%   constant, so theta is linear in TIME instead of linear in 1/R. Those two
%   models coincide only when the range does not change.
%
%   THE SCORE IS A MODEL COMPARISON between exactly those two:
%       G (genuine)  theta ~ a + b*(1/R)
%       P (phantom)  theta ~ c + d*t
%       score = rmsP^2 / (rmsP^2 + rmsG^2)
%   1 when the CV-consistent law fits far better, 0 when the constant-rate law
%   does, 0.5 when they are indistinguishable. Self-calibrating: it compares
%   two fits to the SAME data, so it needs no noise model and no threshold
%   tuned to SNR -- the same posture as the co-bearing screen's spread-versus-
%   scatter ratio.
%
%   THE KNOWN EVASION, STATED PLAINLY BECAUSE IT IS THE INTERESTING PART.
%   The two models also coincide if the mother's OWN range trajectory is
%   proportional to the phantom's claimed one (R_p/R_m constant), since then
%   R_p^2*dtheta/dt is constant too. So this screen does not make deception
%   impossible -- it CONSTRAINS it: the adversary must now fly its own
%   platform on a trajectory coupled to the range it wants the phantom to
%   claim, at the ratio R_p/R_m, while also satisfying causality
%   (R_p >= R_m + c*tau/2). That is a genuine physical cost and a genuine
%   decision problem, which is precisely what the previous action space
%   lacked (PHASE_C_RESULTS.md sections 1-2: the veto refused 0% of actions
%   and the task reduced to avoiding range_rate = 0).
%
%   TWO GUARDS, both returning NaN rather than a verdict, on the same
%   "missing evidence is not absent evidence" principle as the Doppler
%   screen's dopplerMeasured flag:
%     1. The bearing must actually MOVE, by more than the fit residual can
%        explain. A parked platform produces a flat bearing in which both
%        models fit noise equally well and the ratio is 0.5 by construction --
%        an uninformative 0.5 must never be reported as a real reading.
%     2. The RANGE must actually change, by more than a few range cells.
%        1/R is constant otherwise, model G degenerates, and the comparison
%        is meaningless.

    score = NaN;
    diag = struct('rmsGenuineRad', NaN, 'rmsPhantomRad', NaN, ...
                  'bearingSpanRad', NaN, 'rangeSpanM', NaN, ...
                  'impliedCrossSpeedMps', NaN, 'skipReason', "");

    az = double(azRad(:)); R = double(rangeM(:)); t = double(timeS(:));
    keep = isfinite(az) & isfinite(R) & isfinite(t) & R > 0;
    az = az(keep); R = R(keep); t = t(keep);

    % 4 points minimum: each model spends 2 degrees of freedom, so 3 would
    % leave a single residual and the ratio would be comparing two numbers
    % that are almost fitting artefacts.
    if numel(az) < 4
        diag.skipReason = "fewer than 4 azimuth samples";
        return
    end

    diag.bearingSpanRad = max(az) - min(az);
    diag.rangeSpanM = max(R) - min(R);

    % Guard 2 first: it is a property of the geometry alone, so it can be
    % decided before any fitting. Threshold is the instrument's own
    % resolution -- 3 range cells, not a tuned number.
    if nargin < 4 || isempty(rangeCellM) || ~isfinite(rangeCellM) || rangeCellM <= 0
        C = physics.Constants();
        rangeCellM = C.range_per_sample;
    else
        rangeCellM = double(rangeCellM);
    end
    if diag.rangeSpanM < 3 * rangeCellM
        % The threshold goes into the reason: "barely changed" is not checkable
        % by a reader who does not know which radar's cells were meant.
        diag.skipReason = string(sprintf( ...
            ['range barely changed: span %.1f m is under 3 range cells ' ...
             '(%.1f m), so 1/R is constant and model G degenerates'], ...
            diag.rangeSpanM, 3 * rangeCellM));
        return
    end

    rmsG = localFitRms(1 ./ R, az);
    rmsP = localFitRms(t, az);
    diag.rmsGenuineRad = rmsG;
    diag.rmsPhantomRad = rmsP;

    % Guard 1: the bearing must move by more than its own fit residual can
    % account for. Compared against the SMALLER residual, because a genuine
    % track fits one model well and the other badly by design -- testing
    % against the larger would skip exactly the tracks this screen exists for.
    %
    % THE FACTOR IS DERIVED FROM THE FIT, NOT TUNED TO A SCENE. For K samples
    % of white noise the expected peak-to-peak range is about d_K*sigma
    % (d_K = 2.85 at K = 8) while the RMS residual of a 2-parameter fit is
    % sigma*sqrt((K-2)/K) = 0.87*sigma. So pure noise already produces a
    % span/residual ratio of ~3.3, and a threshold at 3 -- the first value
    % tried -- passed noise straight through (caught by this screen's own
    % static-bearing test, which is why that test exists). 6 is ~2x the
    % noise-only ratio: comfortably above what scatter alone can manufacture,
    % far below what any real platform motion produces (a mother at 900 m
    % crossing at 5 m/s sweeps 2.5 deg in an 8 s dwell, hundreds of times the
    % 0.0726 deg worst-case within-track scatter measured in
    % tests/test_monopulse_snr_boundary.m).
    NOISE_SPAN_TO_RESIDUAL = 6;
    if diag.bearingSpanRad < NOISE_SPAN_TO_RESIDUAL * min(rmsG, rmsP)
        diag.skipReason = "bearing did not move beyond its own fit residual";
        return
    end

    % Reported, never scored on: what tangential speed the measured bearing
    % rate implies at this track's own range. This is the quantity that makes
    % the mechanism legible in a report (a phantom at 4 km fed by a mother at
    % 900 m implies 4.4x the mother's own cross-range speed), but it is NOT
    % the test -- an absolute speed envelope would flag fast real aircraft,
    % the same mistake the withdrawn innovation-whiteness screen made.
    pAz = polyfit(t, az, 1);
    diag.impliedCrossSpeedMps = pAz(1) * mean(R);

    denom = rmsP^2 + rmsG^2;
    if denom <= 0
        diag.skipReason = "both models fit exactly; nothing to compare";
        return
    end
    score = rmsP^2 / denom;
end


function r = localFitRms(x, y)
%LOCALFITRMS  RMS residual of a first-order least-squares fit of y on x.
%   Guarded against a degenerate x (all samples identical), which polyfit
%   would warn on and return a meaningless slope for.
    x = x(:); y = y(:);
    if max(x) - min(x) <= 0
        r = std(y);            % no predictor: the best fit is the mean
        return
    end
    p = polyfit(x, y, 1);
    r = sqrt(mean((y - polyval(p, x)).^2));
end
