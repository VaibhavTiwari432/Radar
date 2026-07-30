function T = evalFeatureAgent(agentFile, seeds, trialsPerSeed)
%EVALFEATUREAGENT  Score the trained feature-conditioned D3QN against
%   non-learned baselines through the SAME independent judge, honestly.
%
%   T = experiments.evalFeatureAgent(agentFile, seeds, trialsPerSeed)
%       agentFile     : results\feature_agent.mat (default) from
%                       experiments.trainFeatureAgent.
%       seeds         : evaluation seeds (default 1:5 -- POA's CI bar).
%       trialsPerSeed : episodes per seed per policy (default 6).
%
%   Policies, all judged by agent.buildEnvFeatureConditioned's own
%   track.runTracker + track.discriminator terminal reward:
%       Trained     - the learned greedy D3QN policy
%       Random      - uniform action each frame
%       StaticReplay- delta=0, fixed low gain every frame (the naive DRFM)
%       Smart1/R^2  - hand-crafted physics policy: walk in, gain ~ (R0/R)^2
%                     (the strong non-learned bar the agent must match/beat)
%
%   Reports per policy: P(confirmed), P(real|confirmed), P(real overall),
%   mean episode reward. "real" = confirmed AND passed track.discriminator.

    if nargin < 1 || isempty(agentFile)
        here = fileparts(mfilename('fullpath'));
        agentFile = fullfile(fileparts(here), 'results', 'feature_agent.mat');
    end
    if nargin < 2 || isempty(seeds);         seeds = 1:5; end
    if nargin < 3 || isempty(trialsPerSeed); trialsPerSeed = 6; end

    S = load(agentFile, 'agnt');
    agnt = S.agnt;

    C = physics.Constants();
    env = agent.buildEnvFeatureConditioned(C);

    gainOptions = linspace(0.5, 4.5, 9);
    R0 = 1800;

    policies = struct( ...
        'Trained',      @(obs) localGreedy(agnt, obs), ...
        'Random',       @(obs) randi(45), ...
        'StaticReplay', @(obs) (1-1)*5 + 1, ...            % delta idx1(-120?) -> see note
        'Smart',        @(obs) localSmart(obs, gainOptions, R0));
    % StaticReplay: delta=0 (middle idx 3) + fixed low gain (idx that maps to
    % a mid gain). Action index = (gi-1)*5 + di, di in 1..5, gi in 1..9.
    staticAction = (3-1)*5 + 3;   % di=3 (delta=0), gi=3 (gain~1.5)

    names = fieldnames(policies);
    rows = cell(1, numel(names));
    fprintf('\n=== Feature-conditioned D3QN eval (independent judge) ===\n');
    for pi = 1:numel(names)
        name = names{pi};
        pf = policies.(name);
        if strcmp(name, 'StaticReplay'); pf = @(obs) staticAction; end

        confirmed = false(1, numel(seeds)*trialsPerSeed);
        realFlag  = false(1, numel(seeds)*trialsPerSeed);
        rewards   = zeros(1, numel(seeds)*trialsPerSeed);
        e = 0;
        for s = seeds
            rng(1000*s + pi);   % reproducible, distinct per policy/seed
            for t = 1:trialsPerSeed
                obs = reset(env);
                info = struct('confirmedCount',0,'eccmLabel',"");
                epReward = 0;
                for k = 1:8
                    a = pf(obs);
                    [obs, r, ~, info] = step(env, a);
                    epReward = epReward + r;
                end
                e = e + 1;
                rewards(e) = epReward;
                confirmed(e) = info.confirmedCount >= 1;
                realFlag(e)  = info.eccmLabel == "real";
            end
        end

        nConf = nnz(confirmed);
        pConf = mean(confirmed);
        if nConf>0; pRealGivenConf = mean(realFlag(confirmed)); else; pRealGivenConf = NaN; end
        pRealOverall = mean(realFlag);
        fprintf('%-13s  P(confirm)=%.2f  P(real|confirm)=%s  P(real)=%.2f  meanReward=%.3f  (n=%d)\n', ...
            name, pConf, localPct(pRealGivenConf), pRealOverall, mean(rewards), e);
        rows{pi} = table({name}, pConf, pRealGivenConf, pRealOverall, mean(rewards), ...
            'VariableNames', {'Policy','P_confirm','P_real_given_confirm','P_real','MeanReward'});
    end
    T = vertcat(rows{:});
    fprintf('\nRead: P(real) is the honest deception rate -- confirmed by trackerGNN AND\n');
    fprintf('passed track.discriminator. The learned agent must beat Random/StaticReplay\n');
    fprintf('and at least match Smart(1/R^2) to justify the D3QN over a physics heuristic.\n');
end

% ------------------------------------------------------------------------
function a = localGreedy(agnt, obs)
    act = getAction(agnt, {obs});
    a = act{1};
    if iscell(a); a = a{1}; end
    a = double(a);
end

% ------------------------------------------------------------------------
function a = localSmart(obs, gainOptions, R0)
%LOCALSMART  Closed-loop 1/R^2 heuristic: walk range in (delta idx 1 = -120 m),
%   set gain to the option nearest (R0/R)^2 so received amplitude mimics a
%   real two-way return -- the trajectory track.discriminator scores "real".
    r = max(150, obs(2)*3000);
    idealGain = (R0/r)^2;
    [~, gi] = min(abs(gainOptions - idealGain));
    di = 1;                         % delta = -120 m (closing walk)
    a = (gi-1)*5 + di;
end

% ------------------------------------------------------------------------
function s = localPct(x)
    if isnan(x); s = ' n/a '; else; s = sprintf('%.2f', x); end
end
