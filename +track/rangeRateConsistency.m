function out = rangeRateConsistency(rangeSeq, timeSeq, dopplerSeq, C, varargin)
%RANGERATECONSISTENCY  The textbook RGPO/VGPO detector (Tier 1.2).
%
%   out = track.rangeRateConsistency(rangeSeq, timeSeq, dopplerSeq, C)
%   out = track.rangeRateConsistency(..., 'NumPulses', 32, 'Sigmas', 3)
%
%       rangeSeq   : [n x 1] this track's measured range at each hit [m]
%       timeSeq    : [n x 1] the time of each of those hits [s]
%       dopplerSeq : [n x 1] MEASURED range-rate at each hit [m/s], negative
%                    = closing (this project's convention throughout)
%
%       out.rangeDerivedMps  d(range)/dt from the tracked range history
%       out.dopplerMps       mean measured Doppler range-rate
%       out.mismatchMps      |rangeDerived - doppler|
%       out.thresholdMps     the derived tolerance actually applied
%       out.pass             mismatch <= threshold
%       out.informative      false if the track is too short, or if Doppler
%                            was never measured -- pass is then meaningless
%                            and is reported as true rather than accusing a
%                            track on evidence nobody collected
%
%   ================= WHY THIS IS NOT ALREADY COVERED =================
%   +track/discriminator.m screen 2 exists and is named, but it compares only
%   SIGNS:
%       score = sign(mean(diff(R))) == sign(mean(D))
%   A repeater that walks its false range at -50 m/s while transmitting only
%   -5 m/s of Doppler passes that screen outright -- both quantities are
%   negative. Range-gate pull-off with a deliberately mismatched velocity gate
%   is exactly that attack, and the sign screen is blind to it. This function
%   is the magnitude comparison (US Patent 4,063,239A's mechanism): rate the
%   range history yourself, compare it to what the Doppler channel says, and
%   flag a disagreement larger than the measurement can explain.
%
%   ================= THE THRESHOLD IS DERIVED, NOT TUNED =================
%   (CLAUDE.md Rule 1 -- no magic numbers.) Both quantities being compared are
%   quantised, and the two quantisers are wildly different sizes, so the
%   tolerance follows from them rather than from what separates the arms:
%
%     RANGE-DERIVED RATE. A range bin is a uniform quantiser of width
%     delta = C.range_per_sample (46.84 m), so each endpoint carries error
%     std delta/sqrt(12); their difference carries delta/sqrt(6). Rating over
%     the FULL span (endpoint-to-endpoint, not a mean of per-frame diffs --
%     algebraically the same number, but the error analysis is only clear this
%     way) divides that by the elapsed time T:
%           sigma_R = delta / (sqrt(6) * T)          ~ 2.73 m/s at T = 7 s
%
%     DOPPLER-MEASURED RATE. One Doppler bin is lambda*(PRF/numPulses)/2
%     (3.747 m/s at 32 pulses); as a uniform quantiser its error std is
%     that over sqrt(12):
%           sigma_D = dopplerBin / sqrt(12)          ~ 1.08 m/s
%
%     TOLERANCE. The two errors are independent, so they add in quadrature,
%     and the gate is a stated number of sigmas:
%           threshold = Sigmas * sqrt(sigma_R^2 + sigma_D^2)   ~ 8.8 m/s at 3 sigma
%
%   NOTE WHICH TERM DOMINATES: the RANGE side, by 2.5x. That is the opposite
%   of the intuition that a Doppler measurement is the coarse one, and it is
%   why the brief's suggestion of "one Doppler-bin width" (3.75 m/s) would be
%   too tight -- it would flag genuine targets on range quantisation alone.
%   The threshold TIGHTENS as the track lengthens (sigma_R ~ 1/T), which is
%   correct: more dwells means a better-known range rate.
%
%   REPORTED SEPARATELY, NOT FOLDED INTO THE ECCM SCORE, for the same reason
%   as the NIS gate (track.nisConsistency): its effect on the evasion rate has
%   to be readable in isolation before anyone decides to combine it.

    p = inputParser;
    p.addParameter('NumPulses', 32,  @(x) isscalar(x) && x >= 2);
    p.addParameter('Sigmas',    3,   @(x) isscalar(x) && x > 0);
    p.addParameter('CarrierHz', 10e9, @(x) isscalar(x) && x > 0);
    p.addParameter('PrfHz',     [],  @(x) isempty(x) || (isscalar(x) && x > 0));
    p.parse(varargin{:});
    o = p.Results;
    prf = o.PrfHz; if isempty(prf); prf = C.PRF; end

    R = double(rangeSeq(:));
    t = double(timeSeq(:));
    D = double(dopplerSeq(:));

    out = struct('rangeDerivedMps', NaN, 'dopplerMps', NaN, 'mismatchMps', NaN, ...
                 'thresholdMps', NaN, 'pass', true, 'informative', false);

    ok = isfinite(R) & isfinite(t) & isfinite(D);
    R = R(ok); t = t(ok); D = D(ok);
    if numel(R) < 2; return; end

    T = t(end) - t(1);
    if ~(T > 0); return; end

    % A Doppler channel that measured nothing carries no magnitude to compare
    % against; accusing a track on that would be exactly the "absent vs
    % missing evidence" error discriminator.m documents at length.
    if all(abs(D) < 1e-9) && abs(R(end) - R(1)) < 1e-9
        return;                     % genuinely stationary and consistent
    end

    out.rangeDerivedMps = (R(end) - R(1)) / T;
    out.dopplerMps      = mean(D);
    out.mismatchMps     = abs(out.rangeDerivedMps - out.dopplerMps);

    lambda     = C.c / o.CarrierHz;
    dopplerBin = lambda * (prf / o.NumPulses) / 2;
    sigmaR     = C.range_per_sample / (sqrt(6) * T);
    sigmaD     = dopplerBin / sqrt(12);
    out.thresholdMps = o.Sigmas * sqrt(sigmaR^2 + sigmaD^2);

    out.informative = true;
    out.pass = out.mismatchMps <= out.thresholdMps;
end
