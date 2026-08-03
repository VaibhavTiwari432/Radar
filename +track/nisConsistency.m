function out = nisConsistency(rangeSeq, timeSeq, C, varargin)
%NISCONSISTENCY  The JUDGE's multi-dwell track-consistency test (Tier 1.1).
%
%   out = track.nisConsistency(rangeSeq, timeSeq, C)
%   out = track.nisConsistency(..., 'GateChi2', 7.81, 'SigmaAccelMps2', 0.4903)
%
%       rangeSeq : [n x 1] this track's own measured range at each HIT [m]
%       timeSeq  : [n x 1] the time of each of those hits [s] -- the actual
%                  hit times, so a missed dwell shows up as a longer dt
%                  rather than being silently treated as one interval
%       C        : physics.Constants()
%
%       out.nis         [n x 1] normalised innovation squared per update
%                       (NaN for the birth dwell -- there is no prediction to
%                       innovate against yet, and a missing NIS must never be
%                       averaged in as if it were a perfect zero)
%       out.meanNIS     mean over the scored updates
%       out.inGateFrac  fraction of scored updates with nis <= gate
%       out.pass        true if EVERY scored update stayed inside the gate
%       out.gate        the chi-square threshold actually used
%       out.nScored     how many updates were scored (n-1, or 0 if n < 2)
%
%   ================= WHAT THIS IS FOR =================
%   A real radar's strongest anti-deception layer is the multi-dwell tracker:
%   predict where the object must be next, and test whether the measurement
%   that arrives is consistent with that prediction. +engine/runJudge.m has
%   carried a stateful trackerGNN across frames since it was written, but
%   NOTHING ever computed an innovation from it -- track.discriminator reads
%   range/amplitude/Doppler SERIES and never touches filter state. That is
%   also why the CV->IMM->CA sweep measured byte-identical results (report
%   §4.6): swapping the motion model cannot change a verdict that never reads
%   the model. This function is what makes that sweep non-null.
%
%   ================= WHY NOT REUSE shadowEKF =================
%   +engine/+track/shadowEKF.m already computes exactly this and would drop
%   straight in. IT MUST NOT BE USED HERE. It lives on the ADVERSARY's side of
%   CLAUDE.md Rule 2 -- it is the engine's MODEL of the radar, and its own
%   header says scoring a scene by its NIS "would be self-grading... the
%   engine marking its own homework one level up". The judge needs its own.
%
%   Exactly ONE parameter is deliberately different, so the shadow-vs-judge
%   NIS gap stays attributable rather than becoming a fog of several changes:
%
%       R (measurement noise variance)
%         shadow : range_per_sample^2 / 12   (sigma ~ 13.5 m) -- a range bin
%                  treated as the UNIFORM QUANTISER it is
%         judge  : range_per_sample^2        (sigma ~ 46.8 m) -- the SAME
%                  value +engine/runJudge.m:326 hands trackerGNN, so this
%                  filter is consistent with the tracker whose state it is
%                  testing
%
%   The judge is therefore systematically ~12x LESS suspicious than the
%   shadow. That is not a concession: a judge that assumed tighter
%   measurements than its own tracker uses would flag tracks its own
%   association logic had happily accepted.
%
%   ================= THE GATE IS A TUNABLE, NOT A CONSTANT =================
%   Default 7.81 = the 95% point of chi-square with 3 DOF, per the Tier 1.1
%   brief. HONEST NOTE, because the number deserves one: runJudge's
%   objectDetection is nominally 3-D ([range; 0; 0]) but only the RANGE
%   component ever carries information -- the other two are a constant 0 with
%   unit variance and contribute exactly zero innovation, every dwell. The
%   informative dimension count is 1, whose 95% point is 3.84. 7.81 is
%   therefore the CONSERVATIVE choice: it flags less, which means fewer false
%   accusations against genuine targets and correspondingly less power against
%   a decoy. Both are exposed; neither is baked in.
%
%   NOT FOLDED INTO THE ECCM SCORE. runJudge reports this as its own column
%   (feedback.track_nis_*), never averaged into track.discriminator's screens,
%   so its effect on the evasion rate can be read in isolation before anyone
%   decides whether to combine it.

    p = inputParser;
    % The declared CV threat model's unmodelled-acceleration figure: 0.05 g
    % (CLAUDE.md's threat-model callout, "gently closing" with a number
    % attached). The judge does not know the target's manoeuvre capability, so
    % it must assume one; assuming the threat model it is built to police is
    % the defensible assumption, and it is stated here rather than buried.
    p.addParameter('SigmaAccelMps2', 0.05 * 9.80665, @(x) isscalar(x) && x >= 0);
    p.addParameter('GateChi2',       7.81,           @(x) isscalar(x) && x > 0);
    p.parse(varargin{:});
    o = p.Results;

    rangeSeq = double(rangeSeq(:));
    timeSeq  = double(timeSeq(:));
    assert(numel(rangeSeq) == numel(timeSeq), 'track:nisConsistency:lengthMismatch', ...
        'rangeSeq and timeSeq must be the same length (%d vs %d).', ...
        numel(rangeSeq), numel(timeSeq));

    n = numel(rangeSeq);
    out = struct('nis', nan(n,1), 'meanNIS', NaN, 'inGateFrac', NaN, ...
                 'pass', false, 'gate', o.GateChi2, 'nScored', 0);
    if n < 2; return; end

    % Measurement noise: the SAME variance runJudge hands trackerGNN, so this
    % test is consistent with the tracker whose state it is testing.
    R = C.range_per_sample^2;

    % One-point birth, the way a radar actually starts a track: range is known
    % to the quantiser, velocity is completely unknown. A uniform prior over
    % [-vmax, +vmax] has standard deviation vmax/sqrt(3). vmax is this radar's
    % OWN unambiguous velocity -- beyond it the radar cannot measure a range
    % rate without folding, so it is the widest velocity the judge can
    % meaningfully entertain. Derived, not asserted (CLAUDE.md Rule 1).
    vmax = C.v_unambiguous;
    x = [rangeSeq(1); 0];
    P = diag([R, (vmax/sqrt(3))^2]);
    H = [1 0];

    for k = 2:n
        dt = timeSeq(k) - timeSeq(k-1);
        if ~(dt > 0)
            % Non-increasing hit times mean the caller's series is not a time
            % series. Fail loudly rather than divide by zero (Rule 7).
            error('track:nisConsistency:badDt', ...
                'hit times must strictly increase; got dt = %g at index %d.', dt, k);
        end
        F = [1 dt; 0 1];
        G = [dt^2/2; dt];                     % DWNA on the CV pair
        Q = o.SigmaAccelMps2^2 * (G * G');

        xPred = F * x;
        PPred = F * P * F' + Q;

        zPred = H * xPred;
        S     = H * PPred * H' + R;
        nu    = rangeSeq(k) - zPred;
        out.nis(k) = nu^2 / S;

        K = PPred * H' / S;
        x = xPred + K * nu;
        P = PPred - K * S * K';
        P = (P + P') / 2;                     % keep symmetric against drift
    end

    scored = out.nis(~isnan(out.nis));
    out.nScored    = numel(scored);
    out.meanNIS    = mean(scored);
    out.inGateFrac = mean(scored <= o.GateChi2);
    out.pass       = all(scored <= o.GateChi2);
end
