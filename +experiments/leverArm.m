function out = leverArm(nEp, seeds, frameCounts)
%LEVERARM  Does lengthening the episode do what raising the speed does?
%
%   out = experiments.leverArm(nEp, seeds, frameCounts)   % 20, 1:5, [8 12 16]
%
%   WHY THIS EXPERIMENT EXISTS. Two independent lines of evidence in
%   ASSURANCE_LAYER_RESULTS.md converged on one root cause:
%
%     - Section 10: of every variable this engine logs, the ONLY one with
%       established predictive power over the judge is commanded SPEED
%       (AUC 0.576, clears chance at 99% and under Bonferroni). Its mechanism
%       is not subtle -- a faster target walks further in range over the same
%       8 frames.
%     - Section 3 and the report's section 8.3: the amplitude screen's
%       weakness is its LEVER ARM, a slope fitted over a 1.27x range change in
%       8 frames.
%
%   Those are the same quantity reached from two directions: RANGE WALK. If
%   that reading is right, then FRAMES and SPEED are interchangeable levers,
%   and adding frames should move the judge's real rate the way adding speed
%   does. This file tests that, because a mechanism agreed on by two lines of
%   evidence and never tested directly is still a hypothesis.
%
%   %% PREDICTION -- LOCKED AND COMMITTED BEFORE THE RUN
%
%   The prediction is TWO-SIDED, and that is what makes it worth running
%   rather than obvious. Adding frames is not free: the entity keeps walking,
%   and agent.buildEnvEntity's `rangeMinM` is the CA-CFAR blind zone,
%   (NumTraining + NumGuard) * range_per_sample = (20+4) * 46.84 = 1124.2 m.
%   From R0 = 1800 m at dt = 1 s:
%
%     |v| = 25 m/s :  F=8 -> 1600 m    F=12 -> 1500 m    F=16 -> 1400 m
%     |v| = 50 m/s :  F=8 -> 1400 m    F=12 -> 1200 m    F=16 -> 1000 m  <-- CLAMPS
%
%   A closing 50 m/s entity crosses the blind-zone floor between F=12 and
%   F=16 and is CLAMPED there. A clamped entity has a CONSTANT range, so its
%   received amplitude goes FLAT -- which is precisely the naive-DRFM
%   signature screen 1 exists to catch (see the report's arm C, flagged
%   10/10). So:
%
%     P1  SLOW arm (|v| = 25): judge_real RISES monotonically with F.
%         Longer lever arm, better slope fit, no floor contact.
%     P2  FAST arm (|v| = 50): judge_real rises from F=8 to F=12 and then
%         FALLS at F=16, when the clamp flattens the amplitude history.
%     P3  The amplitude screen's AUC against the judge RISES with F on the
%         slow arm. This is the one that matters: it would show the screen
%         becoming a real measurement rather than the coin flip section 7
%         measured at AUC 0.502.
%
%   COMPETING OUTCOME, equally recorded: judge_real is FLAT in F on both
%   arms. That would refute the lever-arm account outright and mean the
%   speed->judge_real relation in section 10 runs through something else
%   entirely (Doppler resolution, say, which also scales with |v| and which
%   this design does NOT separate). If P1 fails, the convergent conclusion
%   both documents now draw is wrong and must be withdrawn.
%
%   WHAT THIS DESIGN CANNOT SEPARATE, stated up front: frames change the
%   lever arm AND the number of detection opportunities AND the M-of-N
%   confirmation margin. A rise in judge_real is consistent with any of the
%   three. P3 is the discriminating test -- detection opportunities do not
%   make the amplitude SCORE more informative, only a longer lever arm does.
%
%   The verdict rule is fixed here, before the numbers: P1 holds if the slow
%   arm's judge_real at the largest F exceeds its value at F=8 by more than
%   the sum of their Wilson half-widths; P2 holds if the fast arm's F=16
%   value is below its own F=12 value on the same criterion. Anything else is
%   reported as NOT ESTABLISHED, not as a trend.
%
%   %% POWER -- RECORDED BEFORE THE RESULTS, BECAUSE P3 IS UNDER-POWERED
%
%   Noted while the run was in flight and before any output was seen, since a
%   caveat discovered after the numbers is worth much less than one stated
%   before them.
%
%   At the default 20 episodes x 5 seeds each frame count carries n = 100,
%   which splits roughly 50/50 across the two speeds, so each ARM cell holds
%   ~50 episodes and ~12 positives at the measured 23.5% base rate. Section 8
%   measured the bootstrap half-width on an AUC at n = 100 with 19 positives:
%   +/- 0.14. P3 therefore cannot establish anything short of an enormous AUC
%   shift, and a null P3 at this n is NOT evidence against the lever-arm
%   account -- it is an absence of evidence either way. P3 is reported as
%   DIRECTIONAL only, and the file prints the raw delta rather than a verdict
%   for exactly that reason.
%
%   P1 and P2 are better placed: they compare RATES, where a 10-15 pp move is
%   detectable at n ~ 50 per cell against the Wilson criterion above.
%
%   What would power P3 properly: ~400 episodes per frame count on the slow
%   arm alone (seeds 1:20, and only the |v| = 25 actions), taking the AUC
%   half-width to roughly +/- 0.07 as the n = 400 run in section 10 did. That
%   is the follow-up if P1 holds and P3 merely points the right way; it is not
%   worth paying for if P1 fails, because the account would already be dead.

    if nargin < 1 || isempty(nEp);         nEp = 20;            end
    if nargin < 2 || isempty(seeds);       seeds = 1:5;         end
    if nargin < 3 || isempty(frameCounts); frameCounts = [8 12 16]; end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    C = physics.Constants();
    cfarD = radar.cfarDefaults();
    floorM = (cfarD.NumTraining + cfarD.NumGuard) * C.range_per_sample;
    fprintf('leverArm: CA-CFAR blind-zone floor = %.1f m (derived, not assumed)\n\n', floorM);

    res = struct('F', {}, 'csv', {}, 'slow', {}, 'fast', {}, 'auc', {}, 'overall', {});
    for i = 1:numel(frameCounts)
        F = frameCounts(i);
        csv = fullfile(root, 'results', sprintf('lever_arm_F%d.csv', F));
        fprintf('--- F = %d frames (predicted end range: |v|=25 -> %.0f m, |v|=50 -> %.0f m)\n', ...
            F, max(floorM, 1800 - 25*(F-1)), max(floorM, 1800 - 50*(F-1)));
        T = experiments.calibrationLog(nEp, seeds, csv, [], 'structural', ...
                                       struct('framesPerEpisode', F));
        v = abs(T.vel_mps);
        res(i).F = F; res(i).csv = csv;
        res(i).slow    = localRate(T.judge_real(v < 40));
        res(i).fast    = localRate(T.judge_real(v >= 40));
        res(i).overall = localRate(T.judge_real);
        res(i).auc     = localAuc(T.inline_s_amp(v < 40), T.judge_real(v < 40));
    end

    fprintf('\n  %-6s %-26s %-26s %10s\n', 'F', 'SLOW |v|=25 judge_real', 'FAST |v|=50 judge_real', 's_amp AUC');
    for i = 1:numel(res)
        fprintf('  %-6d %5.1f%% [%4.1f,%5.1f] n=%3d   %5.1f%% [%4.1f,%5.1f] n=%3d   %9.3f\n', ...
            res(i).F, 100*res(i).slow.p, 100*res(i).slow.lo, 100*res(i).slow.hi, res(i).slow.n, ...
            100*res(i).fast.p, 100*res(i).fast.lo, 100*res(i).fast.hi, res(i).fast.n, res(i).auc);
    end

    % ---- verdicts, against the rule fixed in the header
    [~, iMax] = max([res.F]);
    p1 = localExceeds(res(iMax).slow, res(1).slow);
    fprintf('\n  P1 slow arm rises with F:            %s (%+.1f pp, F=%d vs F=%d)\n', ...
        localVerdict(p1), 100*(res(iMax).slow.p - res(1).slow.p), res(iMax).F, res(1).F);
    if numel(res) >= 3
        p2 = localExceeds(res(end-1).fast, res(end).fast);
        fprintf('  P2 fast arm falls at the largest F:  %s (%+.1f pp, F=%d vs F=%d)\n', ...
            localVerdict(p2), 100*(res(end).fast.p - res(end-1).fast.p), res(end).F, res(end-1).F);
    end
    fprintf('  P3 amplitude AUC rises with F:       %.3f -> %.3f (%+.3f)\n', ...
        res(1).auc, res(iMax).auc, res(iMax).auc - res(1).auc);
    if ~p1
        fprintf(['\n  P1 NOT ESTABLISHED -- the lever-arm account that both\n' ...
                 '  ASSURANCE_LAYER_RESULTS.md and the report now draw is unsupported\n' ...
                 '  by this test and must be withdrawn or re-argued.\n']);
    end

    out = struct('frameCounts', frameCounts, 'floorM', floorM, 'res', res);
    f = fullfile(root, 'results', 'lever_arm.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s\n', f);
end

% ------------------------------------------------------------------------
function r = localRate(y)
    k = sum(y ~= 0); n = numel(y);
    [lo, hi] = localWilson(k, n);
    r = struct('p', k/max(n,1), 'lo', lo, 'hi', hi, 'n', n, 'k', k);
end

% ------------------------------------------------------------------------
function tf = localExceeds(a, b)
%LOCALEXCEEDS  a is higher than b by more than the sum of their Wilson
%   half-widths -- the criterion fixed in the header, not chosen after.
    tf = (a.p - b.p) > ((a.hi - a.lo)/2 + (b.hi - b.lo)/2);
end

% ------------------------------------------------------------------------
function s = localVerdict(tf)
    if tf; s = 'HOLDS'; else; s = 'not established'; end
end

% ------------------------------------------------------------------------
function u = localAuc(s, y)
    pos = s(y ~= 0); neg = s(y == 0);
    pos = pos(~isnan(pos)); neg = neg(~isnan(neg));
    if isempty(pos) || isempty(neg); u = NaN; return; end
    w = 0;
    for i = 1:numel(pos)
        w = w + sum(pos(i) > neg) + 0.5*sum(pos(i) == neg);
    end
    u = w / (numel(pos) * numel(neg));
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end
