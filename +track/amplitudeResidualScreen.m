function [score, detail] = amplitudeResidualScreen(rangeM, amplitude, varargin)
%AMPLITUDERESIDUALSCREEN  Phase 3.2b prototype: score amplitude CONSISTENCY
%   about the physical 1/R^2 law instead of trying to FIT that law's slope.
%
%   [score, detail] = track.amplitudeResidualScreen(rangeM, amplitude, ...)
%       score  in [0,1]; higher = more consistent with a real skin echo.
%       detail struct with the measured residual sigma and the band edges.
%
%   Name-value
%       'FloorDb'  0.15  below this residual sigma the track is TOO PERFECT
%       'CeilDb'   3.0   above this it does not follow the law at all
%       (see "CHOOSING THE BAND" below -- both are measured, not picked)
%
%   PATH NOTE: the scope of work asked for
%   +track/eccmDiscriminator_ResidualVariance.m. There is no
%   eccmDiscriminator.m in this repo -- the ECCM chain is +track/discriminator.m
%   -- so this is named for what it screens rather than for a file that does
%   not exist. It is a NEW, parallel function; discriminator.m is untouched.
%
%   ================= WHY A FIXED SLOPE =================
%   discriminator.m's screen 1 FITS the slope of log(A) vs log(R) and scores
%   its distance from -2. Measured on this project's own scenes, that fit is
%   under-determined: with a 1.15x range excursion over an 8-frame dwell the
%   fitted slope has std 2.67 -- 2.7x the entire half-width of the score>0.5
%   band -- so genuine and phantom tracks come out statistically identical
%   (72% vs 71% scoring <= 0.5). It is a coin flip applied to both arms.
%
%   This screen fixes the slope at the PHYSICAL -2 and fits only the
%   intercept, then scores the SCATTER of the residuals. Two consequences,
%   and they are the whole point:
%
%     1. RCS-INDEPENDENT, exactly. Writing A = sqrt(sigma)*C/R^2 and taking
%        logs, log A = -2 log R + (0.5 log sigma + log C). The unknown sigma
%        appears ONLY in the intercept, which is fitted and discarded. So
%        this needs no knowledge of the target's RCS -- which matters
%        because a radar cannot know it: a 0.1 m^2 drone at 2 km and a
%        10 m^2 aircraft at 6 km deliver identical received power.
%     2. NO LEVER ARM REQUIRED. Fitting a SLOPE needs leverage in log R;
%        measuring scatter about a KNOWN slope does not. That is why this
%        should work at the 8-frame dwell where the slope fit does not.
%
%   ================= WHY THE SCORE IS TWO-SIDED =================
%   Both tails are suspicious, for opposite reasons, and a one-sided test
%   would reward the wrong one (the same trap the VEE's gate_margin fell
%   into -- see CLAUDE.md's step-4 note, where a static decoy scored the
%   MAXIMUM margin at NIS exactly 0):
%
%     residual sigma TOO SMALL -> the return tracks 1/R^2 more perfectly than
%        any physical target can. Real echoes scintillate; engine.entity.
%        calibrateQ MEASURES that floor at 0.233 dB from 99 real RadChar
%        records (and 0.491 dB from a real target echo). A servo-driven
%        repeater holding the law exactly has no scintillation at all.
%     residual sigma TOO LARGE -> the return is not following the law:
%        constant-ERP repeater, multipath, a maneuver, or a sidelobe echo.
%
%   ================= CHOOSING THE BAND =================
%   FloorDb 0.15 dB sits just BELOW calibrateQ's measured 0.233 dB
%   scintillation floor, so a genuinely fluctuating target clears it while a
%   noiseless one does not. CeilDb 3.0 dB is the measured scatter of a
%   constant-ERP repeater over this project's own geometry. Both are
%   reported by the prototype harness rather than asserted here; retune them
%   against measured distributions, never against a desired flag rate.

    p = inputParser;
    addParameter(p, 'FloorDb', 0.15, @(x) isscalar(x) && x > 0);
    addParameter(p, 'CeilDb',  3.0,  @(x) isscalar(x) && x > 0);
    parse(p, varargin{:});
    o = p.Results;

    R = rangeM(:); A = amplitude(:);
    ok = isfinite(R) & isfinite(A) & R > 0 & A > 0;
    R = R(ok); A = A(ok);

    detail = struct('residual_sigma_db', NaN, 'n', numel(R), ...
        'floor_db', o.FloorDb, 'ceil_db', o.CeilDb, 'verdict', "insufficient");
    if numel(R) < 3
        score = NaN;      % NaN, not 0: "could not measure" is not "suspicious"
        return;
    end

    % Fix the slope at the physical -2; fit only the intercept, which absorbs
    % sqrt(sigma) and every other constant gain in the chain.
    logR = log(R); logA = log(A);
    intercept = mean(logA + 2*logR);
    resid = logA - (-2*logR + intercept);

    % Report in dB because the calibrated scintillation floor is in dB.
    % amplitude is voltage-like, so 20*log10.
    residDb = 20/log(10) * resid;
    sigmaDb = std(residDb);
    detail.residual_sigma_db = sigmaDb;

    if sigmaDb < o.FloorDb
        detail.verdict = "too-perfect";
        score = max(0, sigmaDb / o.FloorDb);          % -> 0 as scatter -> 0
    elseif sigmaDb > o.CeilDb
        detail.verdict = "not-following-law";
        score = max(0, o.CeilDb / sigmaDb);            % -> 0 as scatter grows
    else
        detail.verdict = "consistent";
        score = 1;
    end
end
