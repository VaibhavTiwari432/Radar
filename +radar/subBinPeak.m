function [refinedBin, fracBin] = subBinPeak(profile, peakBin)
%SUBBINPEAK  Sub-range-bin peak location by parabolic interpolation.
%
%   [refinedBin, fracBin] = radar.subBinPeak(PROFILE, PEAKBIN)
%       profile    : [N x 1] non-negative pulse-compressed POWER profile
%       peakBin    : integer index of a local maximum (1-based)
%       refinedBin : peakBin + fracBin, a non-integer bin index
%       fracBin    : the sub-bin offset, in [-0.5, +0.5]
%
%   WHY THE JUDGE NEEDS THIS AT ALL. Without it a detection's range can only
%   ever be an integer multiple of C.range_per_sample (46.84 m here), so a
%   target's range does not MOVE until it has crossed a whole bin. At 20 m/s
%   that takes 2.3 s in this simulation, during which the measured range is a
%   constant and any screen that reads a range RATE is reading zero. A radar
%   that cannot see motion cannot be deceived about motion, and a deception
%   score against it means nothing -- which is the anti-strawman requirement
%   in PHANTOM_GENERATOR_ARCHITECTURE_v1.md section 5.1.
%
%   THE LOG DOMAIN IS NOT A STYLE CHOICE, IT WAS MEASURED. A three-point
%   parabolic fit can be taken on power, on magnitude, or on log-power. All
%   three were run against a KNOWN sub-bin truth, 41 fractional offsets,
%   21 Aug 2026 (rms bin error):
%
%     oversampling fs/B   raw bin    on power    on |.|      on log
%       1.60              0.2958     0.2379      0.2308      0.2242
%       3.20              0.2958     0.0276      0.0158      0.0039
%
%   Log wins at both. Cross-checked in MATLAB and in Python through two
%   independent truth models, agreeing to 3% at fs/B = 3.20
%   (tests/test_sub_bin_interp.m, generator/render.py).
%
%   WHERE THIS IS WORTH SWITCHING ON, AND WHERE IT IS NOT.
%   Accuracy is set by the oversampling ratio. At the bench's fs/B = 3.20 the
%   estimator reaches 0.0036 bins = 0.09 m, a 74x improvement on the raw bin.
%   At fs/B = 1.60 it reaches 0.0133 bins -- still 20x, so the ratio alone is
%   NOT the problem.
%
%   THE PROBLEM IN THIS SIMULATION IS ALIASING, NOT OVERSAMPLING.
%   +physics/Constants.m declares fs = 3.2 MHz and bandwidth = 2 MHz, and a
%   0..B sweep needs fs > 2B. MEASURED: radar.agileWaveform's Up chirp at C.fs
%   sweeps +104 kHz to -1377 kHz -- it wraps through Nyquist -- with 18.2% of
%   its energy at negative frequencies a one-sided sweep should not reach.
%   +generator/render.m inserts those samples and radar.pulseCompress
%   correlates against the same aliased reference, so the compressed mainlobe
%   is corrupted and interpolating it returns 0.267 bins rms against the raw
%   bin's 0.266. IN THE SIMULATION AS IT STANDS THIS FUNCTION BUYS NOTHING.
%
%   So the anti-strawman requirement cannot be met in simulation by adding an
%   interpolator; it needs C.fs > 2*C.bandwidth first. Anyone switching
%   SubBinInterp on here and then TIGHTENING a threshold on the strength of it
%   would be tightening on a gain that is not there -- see the RangeSigmaM
%   note in +track/rangeRateConsistency.m.
%
%   Returns fracBin = 0 rather than erroring whenever the fit is not defined
%   -- at an array edge, on a non-positive sample (log undefined), or where
%   the three points are not concave, which means peakBin was not a local
%   maximum and the caller's premise was wrong. A zero offset degrades exactly
%   to the previous integer-bin behaviour, which is the right failure.

    profile = double(profile(:));
    peakBin = double(peakBin);
    fracBin = 0;

    if ~isscalar(peakBin) || peakBin ~= fix(peakBin)
        error('radar:subBinPeak:badPeak', 'peakBin must be an integer scalar.');
    end
    if peakBin <= 1 || peakBin >= numel(profile)
        refinedBin = peakBin;                 % no neighbours: nothing to fit
        return;
    end

    y = profile(peakBin-1 : peakBin+1);
    if any(~isfinite(y)) || any(y <= 0)
        refinedBin = peakBin;                 % log undefined on this triple
        return;
    end

    y = log(y);
    den = y(1) - 2*y(2) + y(3);

    % den >= 0 means the three points are not concave, i.e. peakBin is not a
    % local maximum. Refuse rather than extrapolate off the shoulder.
    if ~(den < 0)
        refinedBin = peakBin;
        return;
    end

    fracBin = 0.5 * (y(1) - y(3)) / den;

    % A true parabola through a local max cannot place the vertex outside the
    % centre cell. Clamping guards the case where noise has made one shoulder
    % nearly equal to the peak.
    fracBin = max(-0.5, min(0.5, fracBin));
    refinedBin = peakBin + fracBin;
end
