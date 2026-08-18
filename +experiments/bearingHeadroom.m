function out = bearingHeadroom(seeds)
%BEARINGHEADROOM  Does screen 2c leave the decision layer anything to learn?
%
%   Asked BEFORE building the Phase C environment around it, because
%   PHASE_C_RESULTS.md's four runs are all the evidence needed that building
%   an environment first and checking for headroom afterwards produces a
%   ceiling effect and a wasted training campaign.
%
%   THE QUESTION. Screen 2c separates a bearing-slaved phantom from a genuine
%   CV target almost perfectly on its own score (0.968 vs 0.068,
%   tests/test_bearing_rate_vs_judge.m). But +track/discriminator.m AVERAGES
%   its screens, so a phantom that forges amplitude and Doppler correctly
%   still lands above 0.5. This sweeps the screen masks a radar operator
%   could actually run, and asks in which of them 2c is DECISIVE.
%
%   THE SECOND QUESTION, which is what makes it a decision problem. The
%   evasion is documented in +track/bearingRateScreen.m: fly the mother on a
%   trajectory PROPORTIONAL to the phantom's claimed range, i.e.
%
%       Rdot_mother / R_mother(0)  ==  Rdot_phantom / R_phantom(0)
%
%   and R^2*dtheta/dt is constant again. If that works end to end, the agent
%   has something real to find: a context-dependent radial speed for its own
%   platform, coupled to the range it wants the phantom to claim.

%   WHAT IT FOUND (16 Aug 2026, 8 seeds), and both halves matter:
%
%   1. 2c IS DECISIVE ONLY WHEN IT IS NOT DILUTED. Score separates the arms
%      0.063 vs 0.968, but the phantom is still labelled `real` 8/8 under any
%      mask containing 'doppler' -- because Physics Projection makes the
%      phantom's Doppler correct BY CONSTRUCTION, so that screen scores 1.000
%      and outvotes 2c. A radar facing a DRFM that gets Doppler right by
%      construction gains nothing by running a screen that cannot fail; the
%      informative masks are {bearing} (0/8 vs 8/8) and {amplitude,bearing}
%      (2/8 vs 8/8).
%
%   2. THE INVARIANT HAS A BASIN, NOT A NEEDLE, AND A SECOND ESCAPE. The
%      analytic sweep below scores 2c against the mother's radial speed. For a
%      phantom at 2300 m closing at -50 m/s (matched value -19.6):
%         Rdot_m   +20   +10     0    -5   -10   -15   -20   -30   -40   -60
%         score   0.180 0.089 0.000 0.089 0.477 0.899 1.000 0.875 0.762 0.645
%      -- peaked exactly at the derived matched value, passing from about
%      -13 m/s outward, failing at zero and at every OPENING rate. So the
%      agent must get the SIGN and the rough magnitude right, and the right
%      magnitude depends on its own choice of phantom range and rate.
%
%      The second escape is cheaper and was not derived in advance: a phantom
%      at 3100 m closing at only -20 m/s scores NaN at every mother speed --
%      the screen ABSTAINS, because 140 m of range change over the dwell is
%      under bearingRateScreen's 3-range-cell guard, so 1/R is constant and
%      the two models are mathematically indistinguishable. Closing slowly
%      defeats the screen outright. It is not free: the amplitude screen's
%      slope fit is fitted over that same shrinking lever arm, which
%      CLAUDE.md already records as its documented weakness. That trade --
%      close fast and face 2c, or close slowly and face a weak amplitude
%      fit -- is the structure the decision layer has to navigate.

    if nargin < 1 || isempty(seeds); seeds = 1:4; end

    R_P0 = 2300; RDOT_P = -50; NFRAMES = 8;
    R_M0 = 900;  CROSS   = 3;               % mother cross-range speed [m/s]
    t = (0:NFRAMES-1);

    % The radial speed that satisfies the invariant, DERIVED not searched:
    % proportional trajectories keep R_p/R_m constant.
    matched = R_M0 * RDOT_P / R_P0;
    arms = struct( ...
        'name',   {'inconsistent(0)', 'matched(evasion)', 'overshoot(-40)'}, ...
        'motherRdot', {0, matched, -40});

    masks = { {'amplitude','doppler','micro'}, ...
              {'amplitude','doppler','micro','bearing'}, ...
              {'bearing'}, ...
              {'amplitude','bearing'} };
    maskNames = {'a+d+m (default)', 'a+d+m+b', 'b only', 'a+b'};

    fprintf('\nphantom R0=%d Rdot=%d | mother R0=%d cross=%g\n', ...
            R_P0, RDOT_P, R_M0, CROSS);
    fprintf('invariant-matching mother Rdot = %.2f m/s\n\n', matched);
    fprintf('%-18s %-18s %s\n', 'arm', 'mask', 'real / total (mean 2c score)');

    out = struct('arm', {}, 'mask', {}, 'realFrac', {}, 'meanScore', {});
    for a = 1:numel(arms)
        Rm = R_M0 + arms(a).motherRdot * t;
        az = atan2(CROSS * t, Rm);
        for m = 1:numel(masks)
            nReal = 0; sc = [];
            for s = seeds
                rng(s, 'twister');
                mat = renderPhantomScene(R_P0, RDOT_P, 'NumFrames', NFRAMES, ...
                    'SourceAzimuthRad', az, 'MotherRangeM', min(Rm), ...
                    'Tag', sprintf('hr_%d_%d_%d', a, m, s));
                fb = engine.runJudge(mat, 'EccmScreens', masks{m});
                if fb.confirmed_tracks < 1; continue; end
                nReal = nReal + double(fb.track_label{1} == "real");
                sc(end+1) = track.bearingRateScreen(fb.track_azimuth_rad{1}, ...
                                fb.track_range_m{1}, fb.track_time_s{1}); %#ok<AGROW>
            end
            fprintf('%-18s %-18s %d/%d  (%.3f)\n', arms(a).name, maskNames{m}, ...
                    nReal, numel(seeds), mean(sc, 'omitnan'));
            out(end+1) = struct('arm', arms(a).name, 'mask', maskNames{m}, ...
                'realFrac', nReal/numel(seeds), 'meanScore', mean(sc, 'omitnan')); %#ok<AGROW>
        end
    end

    localBasinSweep(R_M0, CROSS, t);
end


function localBasinSweep(Rm0, cross, t)
%LOCALBASINSWEEP  How SHARP is the invariant constraint, and where does the
%   screen abstain? Computed in CLOSED FORM, with no rendering: the score
%   depends only on the bearing and range series, both of which are known
%   exactly. Rendering would add measurement noise to a question about
%   geometry, and cost ~1.5 s per point to answer it worse.
    t = t(:);
    phantoms = [2300 -50; 3100 -20; 1900 -50; 2700 -35];
    rdots = [20 10 0 -5 -10 -15 -20 -30 -40 -60];

    fprintf('\n2c score vs the MOTHER''s radial speed (closed form)\n');
    fprintf('%-14s %-9s', 'phantom', 'matched');
    fprintf('%7d', rdots); fprintf('\n');
    for i = 1:size(phantoms, 1)
        Rp0 = phantoms(i,1); Rdp = phantoms(i,2);
        Rp = Rp0 + Rdp*t;
        fprintf('%-14s %-9.1f', sprintf('%d/%d', Rp0, Rdp), Rm0*Rdp/Rp0);
        for r = rdots
            s = track.bearingRateScreen(atan2(cross*t, Rm0 + r*t), Rp, t);
            if isnan(s); fprintf('    nan'); else; fprintf('%7.3f', s); end
        end
        fprintf('\n');
    end
    fprintf(['nan = the screen ABSTAINS: range span under 3 range cells, so ' ...
             '1/R is\n      constant and the two models cannot be told apart.\n']);
end
