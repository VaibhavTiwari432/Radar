function screens = computeEccmScreens(trackStruct)
%COMPUTEECCMSCREENS  MISSION_SIMULATOR_UI_SPEC.md Section 5.5's live gauge
%   values: "Show each as a small gauge with the measured value and both
%   reference lines." Computes the SAME two physical quantities
%   +track/discriminator.m (Phase 1, untouched -- CLAUDE.md Rule 8) uses
%   internally, for DISPLAY -- the verdict (real/decoy) still comes ONLY
%   from track.discriminator itself (CLAUDE.md's Golden Rule: the judge is
%   the sole authority); this function never decides real/decoy, it only
%   exposes the measurements a human would want to see alongside that
%   verdict.
%
%   screens = missionsim.computeEccmScreens(trackStruct)
%       trackStruct : SAME shape track.discriminator takes -- struct with
%                     .range [1xK] m, .amplitude [1xK] linear,
%                     .doppler [1xK] range-rate-signed m/s (this project's
%                     own convention, +track/discriminator.m's docstring:
%                     "range-rate-signed units, negative = closing" -- NOT
%                     Hz, already directly comparable to a range-rate).
%       screens     : struct with amplitudeRangeSlopeDbDecade (measured),
%                     realRefDbDecade (-40, cited below), repeaterRefDbDecade
%                     (-20, cited below), dopplerResidualMps (measured vs
%                     range-rate).
%
%   Reference lines derivation (Rule 1, not eyeballed): amplitude ~ 1/R^2
%   for a real (passive, two-way path loss) target -- CLAUDE.md's own Rule
%   1 table, "Amplitude vs. range law | real ~ 1/R^2 (voltage), repeater ~
%   1/R^1". In dB-per-decade-of-range terms (20*log10 amplitude
%   convention): amplitude=k*R^-2 => amplitude_dB = 20*log10(k) -
%   40*log10(R), i.e. -40 dB/decade. A repeater (active retransmit at
%   fixed gain, suffering only the ONE-WAY incident path loss ~1/R^1) is
%   -20 dB/decade by the same derivation. Both numbers below are computed
%   from that relation, never typed as a bare literal without it.

    R = trackStruct.range(:);
    A = trackStruct.amplitude(:);
    D = trackStruct.doppler(:);

    screens = struct();
    screens.realRefDbDecade = 20 * (-2);       % amplitude ~ 1/R^2 -> -40 dB/decade, derived above
    screens.repeaterRefDbDecade = 20 * (-1);    % amplitude ~ 1/R^1 -> -20 dB/decade, derived above

    if numel(R) >= 2 && range(R) > 1e-9
        p = polyfit(log10(R), log10(A), 1);
        screens.amplitudeRangeSlopeDbDecade = 20 * p(1);
    else
        screens.amplitudeRangeSlopeDbDecade = NaN;   % not enough range spread to fit a slope
    end

    if numel(R) >= 2
        rangeRateMps = mean(diff(R));
        dopplerMeanMps = mean(D);
        screens.dopplerResidualMps = dopplerMeanMps - rangeRateMps;
    else
        screens.dopplerResidualMps = NaN;
    end
end
