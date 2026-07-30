function outFile = trainDopplerAgent(episodes, seed, shaping, tag, envOpts)
%TRAINDOPPLERAGENT  Train the feature-conditioned D3QN against the
%   Doppler-capable environment (agent.buildEnvDoppler) and save the reward
%   curve plus a greedy-policy diagnostic sweep.
%
%   outFile = experiments.trainDopplerAgent(episodes, seed, shaping, tag)
%       episodes : training episodes (default 1200). The roadmap asked for
%                  "significantly past the current 300-episode budget"; 300
%                  was never the binding constraint (see below), but this
%                  removes the objection either way.
%       seed     : RNG seed (default 1)
%       shaping  : potential-based reward shaping on/off (default true).
%                  The OFF arm is the control for the claim that shaping is
%                  what propagates the terminal signal.
%       tag      : filename suffix, so arms do not overwrite each other.
%
%   WHY A NEW TRAINER RATHER THAN A BIGGER episodes= ON THE OLD ONE.
%   results/feature_agent.mat is a 300-episode run whose reward takes only
%   four values (0.4 / 1.35 / 1.4 / 2.4) and whose quartile means go
%   1.347 -> 1.465 -> 1.387 -> 1.227. The trend is NEGATIVE (-5.5e-4 per
%   episode): the greedy policy scores worse than the exploratory one. A
%   learner starved of episodes plateaus; it does not invert. The signal it
%   was climbing was half-constant by construction -- see
%   agent.buildEnvDoppler's header and tests/test_doppler_screen_coherence.m.
%   Running the same environment for 1200 episodes would buy 4x more of the
%   same non-gradient.
%
%   Saves results/doppler_agent_<tag>.mat with the trained agent, the
%   per-episode reward curve, the greedy diagnostic sweep, and the env spec
%   (so the configuration is reported, not remembered).

    if nargin < 1 || isempty(episodes); episodes = 1200;   end
    if nargin < 2 || isempty(seed);     seed     = 1;      end
    if nargin < 3 || isempty(shaping);  shaping  = true;   end
    if nargin < 4 || isempty(tag)
        if shaping; tag = 'shaped'; else; tag = 'noshape'; end
    end

    if nargin < 5 || isempty(envOpts); envOpts = struct(); end
    % Extra env switches (POA Phase 3: .project for T1, .useFeatures for T2)
    % ride through here rather than being hardcoded, so an arm is fully
    % described by its arguments and the saved spec.
    envOpts.shaping = shaping;

    C = physics.Constants();
    rng(seed);
    [env, degradedEvent, spec] = agent.buildEnvDoppler(C, [], envOpts);
    if isempty(degradedEvent)
        fprintf('trainDopplerAgent[%s]: feature-matched tx gate OK (no fallback).\n', tag);
    else
        fprintf('trainDopplerAgent[%s]: tx DEGRADED to verbatim (reason=%s, conf=%.4f).\n', ...
            tag, degradedEvent.reason, degradedEvent.confidence);
    end
    fprintf('trainDopplerAgent[%s]: %d actions, obs %d, %d pulses/dwell, Doppler bin %.1f m/s\n', ...
        tag, spec.numActions, spec.obsDim, spec.numPulses, spec.dopplerBinMps);

    agnt = agent.buildAgentFeatureConditioned(env);

    % EXPLORATION IS RESCALED TO THE ACTION SPACE, not left at the builder's
    % default. buildAgentFeatureConditioned's EpsilonDecay = 5e-3 was tuned
    % for a 45-action space: with 8 steps/episode it anneals to EpsilonMin by
    % roughly episode 99. This env has 125 actions (2.8x), so the same decay
    % would end exploration after each action had been tried ~6 times on
    % average -- and a DQN that stops exploring before it has seen the space
    % converges to whatever it happened to sample first. Decaying at 1e-3
    % puts the anneal at ~episode 490, keeping the exploratory phase in
    % proportion. Overridden here rather than in the builder so the legacy
    % 45-action agent keeps the settings its published run used.
    agnt.AgentOptions.EpsilonGreedyExploration.EpsilonDecay = 1e-3;

    trainOpts = rlTrainingOptions( ...
        'MaxEpisodes',          episodes, ...
        'MaxStepsPerEpisode',   spec.framesPerEpisode, ...
        'Verbose',              false, ...
        'Plots',                'none', ...
        'StopTrainingCriteria', 'EpisodeCount', ...
        'StopTrainingValue',    episodes);

    t0 = tic;
    stats = train(agnt, env, trainOpts);
    trainSecs = toc(t0);

    R = stats.EpisodeReward(:);
    n = numel(R); b = max(1, floor(n/4));
    qm = [mean(R(1:b)) mean(R(b+1:2*b)) mean(R(2*b+1:3*b)) mean(R(3*b+1:end))];
    p = polyfit((1:n)', R, 1);
    fprintf(['trainDopplerAgent[%s]: %d ep in %.1f s | quartile means ' ...
        '%.3f %.3f %.3f %.3f | trend %+.2e/ep\n'], tag, n, trainSecs, qm, p(1));

    % ---- greedy diagnostic sweep -------------------------------------
    % train() does not expose the env's `logged` per episode, so the
    % behavioural metrics come from an explicit greedy rollout afterwards.
    % This is also the honest place to measure them: they describe the
    % POLICY, not the exploration noise mixed into the training curve.
    diagGreedy = experiments.rolloutDopplerEnv(env, agnt,   200, seed + 1000);
    diagRandom = experiments.rolloutDopplerEnv(env, 'random', 200, seed + 2000);

    fprintf('  greedy : real %.1f%% | confirmed %.1f%% | vel-consistent %.1f%% | mean R %.3f\n', ...
        100*diagGreedy.realRate, 100*diagGreedy.confirmRate, ...
        100*diagGreedy.velConsistency, diagGreedy.meanReward);
    fprintf('  random : real %.1f%% | confirmed %.1f%% | vel-consistent %.1f%% | mean R %.3f\n', ...
        100*diagRandom.realRate, 100*diagRandom.confirmRate, ...
        100*diagRandom.velConsistency, diagRandom.meanReward);

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    resultsDir = fullfile(root, 'results');
    if ~isfolder(resultsDir); mkdir(resultsDir); end
    outFile = fullfile(resultsDir, sprintf('doppler_agent_%s.mat', tag));
    episodeReward = R; %#ok<NASGU>
    save(outFile, 'agnt', 'episodeReward', 'episodes', 'seed', 'shaping', ...
        'spec', 'diagGreedy', 'diagRandom', 'trainSecs');
    fprintf('trainDopplerAgent[%s]: saved -> %s\n', tag, outFile);
end
