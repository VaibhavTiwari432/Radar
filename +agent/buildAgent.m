function agnt = buildAgent(env)
%BUILDAGENT  Dueling Double-DQN (D3QN) agent for the DRFM action space.
%
%   agnt = agent.buildAgent(env)
%
%   "Double": rlDQNAgentOptions UseDoubleDQN=true (decouples action
%   selection from action evaluation to reduce Q-value overestimation).
%   "Dueling": the Q-network splits a shared trunk into a scalar
%   state-value stream V(s) and a per-action advantage stream A(s,a),
%   recombined as
%       Q(s,a) = V(s) + (A(s,a) - mean_a A(s,a))
%   the standard dueling identity (Wang et al. 2016) that stabilizes
%   learning when many actions have similar value -- exactly this
%   project's 45-action DRFM space, where large swaths of (delay,gain)
%   combinations are equivalent (see Stage6_Test reward map: reward
%   depends only on whether the fake range clears the CFAR guard margin,
%   not on gain).
%
%   Ref: POA Part 5 (RL agent, in depth), Stage 6, claim C9.

    obsInfo = getObservationInfo(env);
    actInfo = getActionInfo(env);
    numObs  = obsInfo.Dimension(1);
    numAct  = numel(actInfo.Elements);

    trunk = [
        featureInputLayer(numObs, 'Name', 'state')
        fullyConnectedLayer(24,   'Name', 'fc1')
        reluLayer(                'Name', 'relu1')
        fullyConnectedLayer(24,  'Name', 'fc2')
        reluLayer(                'Name', 'relu2')
    ];
    valueHead = fullyConnectedLayer(1,      'Name', 'fcValue');
    advHead   = fullyConnectedLayer(numAct, 'Name', 'fcAdvantage');
    combine   = functionLayer(@localDuelingCombine, 'Name', 'dueling', ...
                    'Formattable', true, 'NumInputs', 2, ...
                    'InputNames', {'in1','in2'});

    net = layerGraph(trunk);
    net = addLayers(net, valueHead);
    net = addLayers(net, advHead);
    net = addLayers(net, combine);
    net = connectLayers(net, 'relu2',       'fcValue');
    net = connectLayers(net, 'relu2',       'fcAdvantage');
    net = connectLayers(net, 'fcValue',     'dueling/in1');
    net = connectLayers(net, 'fcAdvantage', 'dueling/in2');

    dlnet  = dlnetwork(net);
    critic = rlVectorQValueFunction(dlnet, obsInfo, actInfo);

    agentOpts = rlDQNAgentOptions( ...
        'UseDoubleDQN',       true, ...
        'TargetSmoothFactor', 1e-3, ...
        'MiniBatchSize',      8);
    % ponytail: MiniBatchSize=8, not the rlDQNAgentOptions default of 64 --
    % this is a single-observation 45-action bandit trained for as few as
    % ~20 episodes in experiments.runBenchmark's quick mode, and a bigger
    % minibatch than the whole training run means zero gradient updates
    % ever fire (verified: default 32 gave a frozen, untrained agent).

    agnt = rlDQNAgent(critic, agentOpts);
end

% ------------------------------------------------------------------------
function q = localDuelingCombine(v, a)
    q = v + (a - mean(a, 1));
end
