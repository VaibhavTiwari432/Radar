function [rangeM, edgeBin] = leadingEdge(profile, C, varargin)
%LEADINGEDGE  Leading-edge range estimate (Tier 2.1, the anti-DRFM counter).
%
%   [rangeM, edgeBin] = radar.leadingEdge(profile, C)
%   [...] = radar.leadingEdge(profile, C, 'Fraction', 0.5, 'PeakBin', b)
%
%       profile : [N x 1] pulse-compressed magnitude (or power) profile
%       rangeM  : range of the first sample rising above Fraction of the peak
%       edgeBin : that sample's index
%
%   WHY A RADAR WOULD DO THIS. A DRFM repeater must RECEIVE a pulse before it
%   can retransmit one, so its copy is always LATE by the repeater's own
%   processing latency. A radar that tracks the LEADING EDGE of the return
%   rather than its centroid or its matched-filter peak therefore locks onto
%   the genuine skin return and ignores the delayed copy sitting behind it.
%   This is a real, fielded counter to range-gate pull-off.
%
%   A PREDICTION THIS FILE GOT WRONG, CORRECTED BY MEASUREMENT. An earlier
%   version of this header argued the screen must be inert here, on the
%   grounds that an edge cannot be located more precisely than the rise time
%   1/B = 500 ns = 74.95 m at 2 MHz, against a DRFM latency of only 1.5-15 m.
%   That confuses RESOLUTION with ESTIMATION PRECISION. Resolution -- telling
%   two returns apart -- is bounded by the rise time. Locating ONE smooth
%   edge is bounded by rise time divided by SNR, and at this project's
%   operating SNR that is far finer. Measured (experiments.drfmLatency,
%   20 seeds, fs oversampled at 4B):
%
%       B = 2 MHz : single-look edge sigma 0.152 m; a 10 ns latency (1.50 m)
%                   produces a measured 1.31 m shift = 8.6 sigma
%       B = 10 MHz: sigma 0.011 m, shift 1.56 m
%       B = 50 MHz: sigma 0.002 m, shift 1.50 m (exact)
%
%   Accuracy does improve with bandwidth exactly as expected (21% error at
%   2 MHz, 0.1% at 10 MHz), but even 2 MHz sees 10 ns.
%
%   THE LIMIT THAT ACTUALLY BITES IS DIFFERENT, AND IT IS NOT A PRECISION
%   LIMIT. Every number above is a shift measured against a KNOWN
%   ZERO-LATENCY BASELINE of the same target. An operational radar has no
%   such baseline: it does not independently know the target's true range, so
%   "this edge is 1.5 m later than it should be" is not a question it can
%   ask. Leading-edge tracking works operationally only when the skin return
%   and the delayed repeat are BOTH present in the same dwell and the earlier
%   one can be picked -- and separating those two IS resolution-limited, at
%   74.95 m for B = 2 MHz. So the honest statement is:
%
%       estimator precision   : 10 ns visible even at 2 MHz  [MEASURED]
%       operational usefulness: needs the skin return to be separable from
%                               the repeat, i.e. latency > c/(2B) = 74.95 m
%                               equivalent = 500 ns at this bandwidth --
%                               5x the largest quoted DRFM latency
%
%   That two-return case is NOT measured here and is the next step.

%   THRESHOLD REFERENCE: NOISE, NOT PEAK -- and this is the whole design.
%   A fraction-of-PEAK threshold cannot see a skin return hiding under a
%   stronger repeat, because the peak IS the repeat and half of it is still
%   far above the skin echo. Measured (experiments.drfmLatency two-return
%   case, repeat 20 dB stronger): with a 0.5-of-peak threshold the edge
%   error equals the full skin-to-repeat separation at every bandwidth
%   tested, i.e. the "leading edge" tracks the repeat exactly as the peak
%   does, and the screen is worthless. Referencing the threshold to the NOISE
%   FLOOR instead is what a real leading-edge tracker does, and it is what
%   lets the weak-but-EARLY return be the first thing to cross.
%   Pass 'NoiseSigma' to use it; 'Fraction' (of peak) is retained only for
%   the single-return precision measurement, where there is nothing to hide
%   under and the two are equivalent.

    p = inputParser;
    p.addParameter('Fraction',   0.5, @(x) isscalar(x) && x > 0 && x < 1);
    p.addParameter('PeakBin',    [],  @(x) isempty(x) || isscalar(x));
    p.addParameter('NoiseSigma', [],  @(x) isempty(x) || (isscalar(x) && x > 0));
    p.addParameter('NoiseSigmas', 5,  @(x) isscalar(x) && x > 0);
    p.parse(varargin{:});
    o = p.Results;

    profile = abs(double(profile(:)));
    if isempty(o.PeakBin)
        [pk, pkBin] = max(profile);
    else
        pkBin = o.PeakBin;
        pk = profile(pkBin);
    end

    if ~isempty(o.NoiseSigma)
        % Noise-referenced: the first sample rising clear of the floor, which
        % is the earliest RETURN rather than the earliest part of the
        % strongest return.
        thresh = o.NoiseSigmas * o.NoiseSigma;
        if thresh >= pk          % nothing clears the floor; fall back rather
            thresh = o.Fraction * pk;   % than report a noise sample as an edge
        end
    else
        thresh = o.Fraction * pk;
    end
    % Walk BACK from the peak to the last sample below threshold, then take
    % the next one -- searching forward from bin 1 would lock onto the first
    % noise excursion anywhere in the buffer instead of this target's edge.
    edgeBin = pkBin;
    while edgeBin > 1 && profile(edgeBin - 1) >= thresh
        edgeBin = edgeBin - 1;
    end

    % Linear interpolation across the threshold crossing, so the estimate is
    % not quantised to whole samples -- without it the answer could only ever
    % move in 46.84 m steps and no latency below 312.5 ns could register even
    % in principle.
    if edgeBin > 1
        y0 = profile(edgeBin - 1); y1 = profile(edgeBin);
        if y1 > y0
            frac = (thresh - y0) / (y1 - y0);
            edgeBin = (edgeBin - 1) + frac;
        end
    end

    rangeM = (edgeBin - 1) * C.range_per_sample;
end
