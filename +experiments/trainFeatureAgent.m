function outFile = trainFeatureAgent(episodes, seed)
%TRAINFEATUREAGENT  Train the feature-conditioned D3QN for real and save it.
%
%   outFile = experiments.trainFeatureAgent(episodes, seed)
%       episodes : training episodes (default 400). Each episode is F=8
%                  frames against agent.buildEnvFeatureConditioned's
%                  independent-judge reward.
%       seed     : RNG seed (default 1) for reproducibility.
%       outFile  : path to the saved results\feature_agent.mat holding the
%                  trained agent and its per-episode reward curve.
%
%   This is the "actually train it" step the project never ran (see
%   +missionsim/pickD3qnAction.m's honest gap). Reward comes ONLY from
%   track.runTracker + track.discriminator (Rule 2); the 54-D features
%   condition the policy's perception, not its reward.

    if nargin < 1 || isempty(episodes); episodes = 400; end
    if nargin < 2 || isempty(seed);     seed = 1;      end

    C = physics.Constants();
    rng(seed);
    [env, degradedEvent] = agent.buildEnvFeatureConditioned(C);
    if isempty(degradedEvent)
        fprintf('trainFeatureAgent: feature-matched tx gate OK (no fallback).\n');
    else
        fprintf('trainFeatureAgent: tx DEGRADED to verbatim (reason=%s, conf=%.4f).\n', ...
            degradedEvent.reason, degradedEvent.confidence);
    end

    agnt = agent.buildAgentFeatureConditioned(env);

    trainOpts = rlTrainingOptions( ...
        'MaxEpisodes',          episodes, ...
        'MaxStepsPerEpisode',   8, ...
        'Verbose',              false, ...
        'Plots',                'none', ...
        'StopTrainingCriteria', 'EpisodeCount', ...
        'StopTrainingValue',    episodes);

    t0 = tic;
    stats = train(agnt, env, trainOpts);
    trainSecs = toc(t0);

    R = stats.EpisodeReward(:);
    nEarly = min(50, numel(R));
    early = mean(R(1:nEarly));
    late  = mean(R(max(1,end-nEarly+1):end));
    fprintf(['trainFeatureAgent: %d episodes in %.1fs | mean reward first %d = %.3f, ' ...
        'last %d = %.3f (delta %+.3f)\n'], episodes, trainSecs, nEarly, early, nEarly, late, late-early);

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    resultsDir = fullfile(root, 'results');
    if ~isfolder(resultsDir); mkdir(resultsDir); end
    outFile = fullfile(resultsDir, 'feature_agent.mat');
    episodeReward = R; %#ok<NASGU>
    save(outFile, 'agnt', 'episodeReward', 'episodes', 'seed');
    fprintf('trainFeatureAgent: saved -> %s\n', outFile);
end
