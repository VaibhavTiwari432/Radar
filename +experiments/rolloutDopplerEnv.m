function d = rolloutDopplerEnv(env, policy, nEpisodes, seed)
%ROLLOUTDOPPLERENV  Run a fixed policy on agent.buildEnvDoppler and collect
%   the behavioural diagnostics the reward curve alone cannot show.
%
%   d = experiments.rolloutDopplerEnv(env, policy, nEpisodes, seed)
%       policy : an rl agent object, or 'random', or 'truthful' (the
%                hand-built reference policy: hold a range walk, command the
%                matching velocity, step the gain down once ~1/R^2).
%
%   WHY THESE METRICS. A reward curve says how well the agent did; it does
%   not say WHAT it learned. The three that matter here map one-to-one onto
%   the two ECCM screens the agent has to beat:
%
%     velConsistency  fraction of frames where the COMMANDED radial velocity
%                     has the same sign as the ACHIEVED range step. With
%                     dt = 1 s the range walk IS a range rate, so this is a
%                     direct read of kinematic truthfulness -- "trajectory
%                     consistency". A repeater that walks its false range
%                     without matching Doppler is exactly the naive DRFM the
%                     screen exists to catch.
%     ampSlope        fitted d log(amplitude) / d log(range) per episode.
%                     The physical value for a real monostatic return is -2
%                     (amplitude ~ sqrt(power) ~ 1/R^2). This is the
%                     quantity screen 1 scores, reported as a distribution
%                     rather than as a pass/fail so the failure MODE is
%                     visible (too flat vs over-ramped).
%     realRate        fraction of episodes the INDEPENDENT ECCM labelled
%                     "real". The actual objective.
%
%   Everything here is measured off the env's own `logged` struct -- this
%   function computes no physics and re-judges nothing.

    if nargin < 3 || isempty(nEpisodes); nEpisodes = 200; end
    if nargin < 4 || isempty(seed);      seed = 0;        end
    rng(seed);

    isRandom   = ischar(policy) || isstring(policy);
    mode = "agent";
    if isRandom; mode = string(policy); end

    % Action count comes from the ENV, not a constant. It was hardcoded to
    % 125 (5 deltas x 5 gains x 5 velocities), which is right for
    % agent.buildEnvDoppler and silently wrong for any other env --
    % agent.buildEnvEntity has 25, and a random draw of 125 indexed straight
    % off the end of its action grid. Unchanged for the Doppler env, so the
    % recorded arms are unaffected (same count, same RNG draws).
    ai = getActionInfo(env);
    nA = numel(ai.Elements);
    rewards   = zeros(nEpisodes, 1);
    realFlag  = false(nEpisodes, 1);
    confFlag  = false(nEpisodes, 1);
    ampSlope  = nan(nEpisodes, 1);
    velCons   = nan(nEpisodes, 1);
    detRate   = nan(nEpisodes, 1);
    labels    = strings(nEpisodes, 1);

    % Reference policy: coherent +120 m/frame walk, matching +120 m/s
    % velocity, one gain step down at the midpoint (verified to score
    % "real" -- see the schedule sweep in the commit that added this file).
    truthfulGain = [4 4 4 4 3 3 3 3];

    for e = 1:nEpisodes
        obs = reset(env);
        tot = 0; lg = [];
        for k = 1:8
            switch mode
                case "random"
                    a = randi(nA);
                case "truthful"
                    a = sub2ind([5 5 5], 5, truthfulGain(k), 5);
                otherwise
                    a = getAction(policy, {obs});
                    if iscell(a); a = a{1}; end
                    a = double(a);
            end
            [obs, r, ~, lg] = step(env, a);
            tot = tot + r;
        end
        rewards(e)  = tot;
        labels(e)   = lg.eccmLabel;
        realFlag(e) = (lg.eccmLabel == "real");
        confFlag(e) = lg.confirmedCount >= 1;
        detRate(e)  = mean(lg.detectedHist);

        % trajectory consistency: sign(commanded velocity) vs sign(achieved
        % range step). Frames with a zero step are excluded -- there is no
        % direction to be consistent WITH, so counting them either way would
        % be an artefact of the clamp, not of the policy.
        moving = abs(lg.cmdRangeStep) > 1e-9;
        if any(moving)
            velCons(e) = mean(sign(lg.cmdVelHist(moving)) == sign(lg.cmdRangeStep(moving)));
        end

        m = ~isnan(lg.rangeHist) & ~isnan(lg.ampHist);
        Rr = lg.rangeHist(m); Aa = lg.ampHist(m);
        if nnz(m) >= 2 && range(Rr) > 1e-9 && all(Aa > 0)
            pf = polyfit(log(Rr), log(Aa), 1);
            ampSlope(e) = pf(1);
        end
    end

    d = struct();
    d.mode           = mode;
    d.nEpisodes      = nEpisodes;
    d.rewards        = rewards;
    d.labels         = labels;
    d.meanReward     = mean(rewards);
    d.realRate       = mean(realFlag);
    d.confirmRate    = mean(confFlag);
    d.detectRate     = mean(detRate, 'omitnan');
    d.velConsistency = mean(velCons, 'omitnan');
    d.velConsPerEp   = velCons;
    d.ampSlope       = ampSlope;
    d.medianAmpSlope = median(ampSlope, 'omitnan');
    % Wilson 95% CI on realRate -- the project's own convention in
    % BENCHMARK_RESULTS.md, and the right interval for a proportion near 0 or 1.
    [d.realLo, d.realHi] = localWilson(sum(realFlag), nEpisodes);
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;     % 95%
    p = k / n;
    den = 1 + z^2/n;
    c   = p + z^2/(2*n);
    hw  = z * sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c - hw)/den; hi = (c + hw)/den;
end
