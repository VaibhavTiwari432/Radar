function T = runBenchmark(opts)
%RUNBENCHMARK  Deception benchmark & honest trade-off table.
%              (POA Part 4, Stage 7; claim C10)
%
%   T = experiments.runBenchmark(opts)
%       opts.quick (logical, default false) - shrink seeds/trials/training
%                  for a fast CI run. Still >=5 seeds per condition (POA
%                  requires this for confidence intervals).
%
%   Drives agent.buildEnv's actual multi-step (F=8 frames) engagement
%   directly via reset/step -- the SAME environment agent.buildAgent trains
%   against, not a re-derived copy -- under three action-selection
%   policies:
%       Random     - uniformly random action every frame
%       BruteForce - per-seed exhaustive search over the 45 actions,
%                    repeated EVERY frame (the best "constant" policy;
%                    brute-forcing full 45^8 per-frame sequences isn't
%                    tractable, so this is brute force's natural ceiling)
%       DQN        - agent.buildAgent, trained briefly, greedy per frame,
%                    conditioned on the (frame, range, detected) observation
%                    -- the one policy that CAN vary gain with range
%
%   Each row is one (Condition, Seed) pair, averaged over several
%   evaluation episodes:
%       Condition, Seed, P_detected, P_false_track_confirmed,
%       MeanFalseTrackLifetime, P_rejected_by_ECCM, MeanEIRP
%
%   P_rejected_by_ECCM is read from agent.buildEnv's own terminal
%   diagnostics (info.eccmLabel), which come from track.discriminator on
%   the episode's actual range/amplitude/Doppler history -- so a policy
%   only avoids ECCM rejection by producing a trajectory that is actually
%   kinematically and amplitude-consistent, not by construction.
%
%   Drives agent.buildEnvWithFeatures (feature-matched synthesis, the SOLE
%   active tx_template path -- CLAUDE.md's "Directory Map & Status"), not
%   the original agent.buildEnv, which is kept only as the verbatim-replay
%   fallback target for agent.buildEnvWithFeatures's internal confidence
%   gate (+features/synthesizeTxPulse.m), not as a selectable benchmark mode.

    if nargin < 1 || isempty(opts); opts = struct(); end
    if ~isfield(opts, 'quick'); opts.quick = false; end

    C = physics.Constants();
    [env, degradedEvent] = agent.buildEnvWithFeatures(C);
    if isempty(degradedEvent)
        fprintf('runBenchmark: feature-matched synthesis gate OK (no fallback).\n');
    else
        fprintf(['runBenchmark: feature-matched synthesis DEGRADED to verbatim replay ' ...
            '(reason=%s, confidence=%.4f) -- benchmark below reflects the fallback, not the matched replica.\n'], ...
            degradedEvent.reason, degradedEvent.confidence);
    end
    actInfo = getActionInfo(env);
    numAct = numel(actInfo.Elements);
    F = 8;

    seeds = 1:5;
    if opts.quick
        trialsPerEval = 3;
        dqnEpisodes   = 25;
        searchTrials  = 1;
    else
        trialsPerEval = 20;
        dqnEpisodes   = 300;
        searchTrials  = 5;
    end

    rows = cell(1, numel(seeds)*3);
    r = 0;
    for s = seeds
        rng(s);
        r = r+1;
        rows{r} = localEvalCondition('Random', s, env, @(obs) randi(numAct), trialsPerEval, F);

        rng(s);
        bestAction = localBruteForceSearch(env, numAct, searchTrials, F);
        r = r+1;
        rows{r} = localEvalCondition('BruteForce', s, env, @(obs) bestAction, trialsPerEval, F);

        rng(s);
        agnt = agent.buildAgent(env);
        localTrainQuick(agnt, env, dqnEpisodes, F);
        r = r+1;
        rows{r} = localEvalCondition('DQN', s, env, @(obs) localGreedyAction(agnt, obs), trialsPerEval, F);
    end

    T = vertcat(rows{:});
end

% ------------------------------------------------------------------------
function bestAction = localBruteForceSearch(env, numAct, searchTrials, F)
%LOCALBRUTEFORCESEARCH  Best-of-45 constant (same action every frame) policy.
    scores = zeros(1, numAct);
    for a = 1:numAct
        for t = 1:searchTrials
            reset(env);
            info = struct('confirmedCount', 0, 'eccmLabel', "");
            for k = 1:F
                [~, ~, ~, info] = step(env, a);
            end
            scores(a) = scores(a) + double(info.confirmedCount >= 1) + double(info.eccmLabel == "real");
        end
    end
    [~, bestAction] = max(scores);
end

% ------------------------------------------------------------------------
function localTrainQuick(agnt, env, numEpisodes, F)
%LOCALTRAINQUICK  Brief training run, no plots/console spam.
    trainOpts = rlTrainingOptions( ...
        'MaxEpisodes',          numEpisodes, ...
        'MaxStepsPerEpisode',   F, ...
        'Verbose',              false, ...
        'Plots',                'none', ...
        'StopTrainingCriteria', 'EpisodeCount', ...
        'StopTrainingValue',    numEpisodes);
    train(agnt, env, trainOpts);
end

% ------------------------------------------------------------------------
function a = localGreedyAction(agnt, obs)
    act = getAction(agnt, {obs});
    a = act{1};
end

% ------------------------------------------------------------------------
function row = localEvalCondition(condition, seed, env, policyFcn, trialsPerEval, F)
%LOCALEVALCONDITION  Run trialsPerEval full episodes under policyFcn(obs)
%                     and reduce to one benchmark-table row.
    gainOptions = linspace(0.5, 4.5, 9);

    confirmedFlags = false(1, trialsPerEval);
    lifetimes      = [];
    rejectedFlags  = [];
    detectedFrames = [];
    gainsUsed      = [];

    for t = 1:trialsPerEval
        obs = reset(env);
        info = struct('confirmedCount', 0, 'eccmLabel', "", 'detectedHist', false(1,F));
        for k = 1:F
            a = policyFcn(obs);
            gi = floor((a-1) / 5) + 1;
            gainsUsed(end+1) = gainOptions(gi); %#ok<AGROW>
            [obs, ~, ~, info] = step(env, a);
            detectedFrames(end+1) = obs(3); %#ok<AGROW>
        end

        if info.confirmedCount >= 1
            confirmedFlags(t) = true;
            lifetimes(end+1) = sum(info.detectedHist); %#ok<AGROW>
            if info.eccmLabel == "decoy"
                rejectedFlags(end+1) = true; %#ok<AGROW>
            elseif info.eccmLabel == "real"
                rejectedFlags(end+1) = false; %#ok<AGROW>
            end
            % "unscreened" (too few valid points) contributes to neither --
            % honestly excluded rather than silently counted as a pass.
        end
    end

    P_detected = mean(detectedFrames);
    P_false_track_confirmed = mean(confirmedFlags);
    if isempty(lifetimes); MeanFalseTrackLifetime = NaN; else; MeanFalseTrackLifetime = mean(lifetimes); end
    if isempty(rejectedFlags); P_rejected_by_ECCM = NaN; else; P_rejected_by_ECCM = mean(rejectedFlags); end
    MeanEIRP = mean(gainsUsed.^2);

    row = table({condition}, seed, P_detected, P_false_track_confirmed, ...
                 MeanFalseTrackLifetime, P_rejected_by_ECCM, MeanEIRP, ...
                 'VariableNames', {'Condition','Seed','P_detected', ...
                    'P_false_track_confirmed','MeanFalseTrackLifetime', ...
                    'P_rejected_by_ECCM','MeanEIRP'});
end
