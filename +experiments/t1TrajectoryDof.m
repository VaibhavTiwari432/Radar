function out = t1TrajectoryDof(nEp, seed)
%T1TRAJECTORYDOF  Is the residual failure after manifold projection caused by
%   the RANGE TRAJECTORY still being free, rather than by the per-frame
%   couplings projection already fixed?
%
%   POA Phase 3, T1 follow-up. The falsification run gave, for a RANDOM
%   policy with projection on: trajectory consistency 100%, amplitude slope
%   -2.09 (both as predicted), but only 54.0% [47.1, 60.8] labelled real
%   against a predicted ~100%.
%
%   HYPOTHESIS. Projection couples gain and velocity to range, but leaves the
%   range WALK free: 8 independent steps. A real body under this project's CV
%   threat model traces R(t) = R0 + v*t -- two parameters, not eight. So the
%   DOF count after projection is 8 (steps) + 1 (RCS) = 9 against a manifold
%   of 3. Still 3x over.
%
%   TEST. Hold one delta for the whole episode (a CV trajectory) and one RCS,
%   with projection on. If the hypothesis is right this should approach the
%   truthful reference's 100%, and the remaining gap is attributable to the
%   trajectory DOF -- which is exactly what T4 (state-space action) removes.
%   If it does NOT, the residual is something else and T4 is not justified by
%   this evidence.

    if nargin < 1 || isempty(nEp);  nEp = 200; end
    if nargin < 2 || isempty(seed); seed = 77; end

    C = physics.Constants();
    env = agent.buildEnvDoppler(C, [], struct('project', true, 'shaping', false));

    rng(seed);
    isReal = false(nEp,1); isConf = false(nEp,1);
    slopes = nan(nEp,1); drift = nan(nEp,1); diUsed = zeros(nEp,1);

    for e = 1:nEp
        reset(env);
        di = randi(5); gi = randi(5);        % ONE delta, ONE rcs, held all episode
        diUsed(e) = di;
        a  = sub2ind([5 5 5], di, gi, 3);    % vel index ignored under projection
        lg = [];
        for k = 1:8
            [~, ~, ~, lg] = step(env, a);
        end
        isReal(e) = (lg.eccmLabel == "real");
        isConf(e) = lg.confirmedCount >= 1;
        m = ~isnan(lg.rangeHist) & ~isnan(lg.ampHist);
        if nnz(m) >= 2 && range(lg.rangeHist(m)) > 1e-9
            p = polyfit(log(lg.rangeHist(m)), log(lg.ampHist(m)), 1);
            slopes(e) = p(1);
        end
        r = lg.rangeHist(m);
        if numel(r) >= 2; drift(e) = r(end) - r(1); end
    end

    [lo, hi] = localWilson(sum(isReal), nEp);
    out = struct('realRate', mean(isReal), 'realLo', lo, 'realHi', hi, ...
        'confirmRate', mean(isConf), 'medianAmpSlope', median(slopes,'omitnan'), ...
        'medianAbsDrift', median(abs(drift),'omitnan'), 'nEp', nEp);

    fprintf('\nPROJECTED + COHERENT (CV trajectory, %d ep)\n', nEp);
    fprintf('   real %.1f%% [%.1f, %.1f] | confirmed %.1f%% | medSlope %+.2f | median |drift| %.0f m\n', ...
        100*out.realRate, 100*lo, 100*hi, 100*out.confirmRate, ...
        out.medianAmpSlope, out.medianAbsDrift);
    fprintf('   compare: projected+INCOHERENT random 54.0%% [47.1, 60.8]\n');
    fprintf('            unprojected random           7.0%% [ 4.2, 11.4]\n');
    fprintf('            trained+shaped, unprojected 44.0%% [37.3, 50.9]\n');
    fprintf('            truthful reference         100.0%% [96.9, 100.0]\n');

    % BREAKDOWN BY COMMANDED STEP. A zero-step episode is a STATIONARY
    % phantom: range never varies, so discriminator screen 1 falls through to
    % its "range AND amplitude both dead flat -> score 0" branch and screen 2
    % has no direction to check. Being flagged there is the ECCM working as
    % designed, not a modelling gap -- so the honest headline is the
    % non-stationary subset, reported separately rather than blended.
    deltas = linspace(-120, 120, 5);
    fprintf('\n   by commanded step:\n');
    for d = 1:5
        sel = diUsed == d;
        if ~any(sel); continue; end
        fprintf('      %+5.0f m/frame : real %5.1f%%  (n=%d)\n', ...
            deltas(d), 100*mean(isReal(sel)), nnz(sel));
    end
    moving = diUsed ~= 3;
    [mlo, mhi] = localWilson(sum(isReal(moving)), nnz(moving));
    out.realRateMoving = mean(isReal(moving));
    out.realMovingCI = [mlo mhi];
    fprintf('   NON-STATIONARY subset: real %.1f%% [%.1f, %.1f]  (n=%d)\n', ...
        100*out.realRateMoving, 100*mlo, 100*mhi, nnz(moving));
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end
