function out = getFilterState(tracker, trackID, rangeSeq, timeSeq, C, varargin)
%GETFILTERSTATE  Per-track filter diagnostics: IMM mode probabilities (if
%   this track's own filter is IMM) and multi-dwell NIS -- so
%   +track/discriminator.m can consume filter-derived evidence instead of
%   only raw CFAR peak series (BENCHMARK_RESULTS.md's "Tracker model"
%   sweep found that discriminator.m never asked the tracker anything, so
%   swapping CV/IMM/CA produced byte-identical verdicts; this is the fix).
%
%   out = track.getFilterState(tracker, trackID, rangeSeq, timeSeq, C)
%       tracker  : the LIVE trackerGNN/trackerJPDA this trackID belongs to.
%                  Its per-track filter state is read via
%                  getTrackFilterProperties -- the tracker owns the filter,
%                  there is no other public handle to it.
%       trackID  : this track's TrackID (double)
%       rangeSeq, timeSeq : this track's own hit range/time history, same
%                  convention track.nisConsistency already takes
%       C        : physics.Constants()
%
%       out.modeProbabilities [1 x nModels] IMM's current model
%                  probabilities, or [] if this track's filter has none
%                  (verified interactively: a plain CV track's
%                  trackingEKF has no 'ModelProbabilities' property at all
%                  -- MATLAB throws "Unrecognized ... 'ModelProbabilities'
%                  ... trackingEKF" -- caught here rather than propagated,
%                  same "missing vs errors" posture as discriminator.m's
%                  own dopplerMeasured guard)
%       out.dominantMode      index of max(modeProbabilities), or NaN
%       out.nis, out.meanNIS  from track.nisConsistency on rangeSeq/timeSeq
%                  (empty/NaN if rangeSeq has under 2 points)
%
%   WHY NOT +engine/+track/shadowEKF.m (CLAUDE.md Rule 2, the Golden Rule):
%   shadowEKF is the ADVERSARY's model of the radar -- its own header says
%   scoring a scene by its NIS would be "the engine marking its own
%   homework one level up", and +track may not depend on +engine at all
%   (tests/test_package_separation.m greps for exactly this). This reuses
%   track.nisConsistency instead, which is this package's OWN diagnostic
%   EKF, already tested, and was in fact built for this exact gap (see its
%   header's "WHAT THIS IS FOR").

    p = inputParser;
    p.addParameter('GateChi2', 7.81, @(x) isscalar(x) && x > 0);
    p.parse(varargin{:});

    out = struct('modeProbabilities', [], 'dominantMode', NaN, ...
                 'nis', [], 'meanNIS', NaN);

    try
        mp = getTrackFilterProperties(tracker, trackID, 'ModelProbabilities');
        out.modeProbabilities = mp{1}(:)';
        [~, out.dominantMode] = max(out.modeProbabilities);
    catch ME
        % Not IMM (e.g. plain CV/CA trackingEKF) -- genuinely no mode
        % probabilities to report, not an error condition. Any OTHER cause
        % (bad trackID, tracker not locked) should still surface loudly
        % (Rule 7), so only swallow the specific "no such property" class.
        if ~contains(ME.message, 'ModelProbabilities')
            rethrow(ME);
        end
    end

    if numel(rangeSeq) >= 2
        nisOut = track.nisConsistency(rangeSeq, timeSeq, C, 'GateChi2', p.Results.GateChi2);
        out.nis = nisOut.nis;
        out.meanNIS = nisOut.meanNIS;
    end
end
