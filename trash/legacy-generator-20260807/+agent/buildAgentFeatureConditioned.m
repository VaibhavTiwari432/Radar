function agnt = buildAgentFeatureConditioned(env)
%BUILDAGENTFEATURECONDITIONED  Dueling Double-DQN sized for the 57-D
%   feature-conditioned observation from agent.buildEnvFeatureConditioned.
%
%   agnt = agent.buildAgentFeatureConditioned(env)
%
%   Same dueling Double-DQN identity as agent.buildAgent
%       Q(s,a) = V(s) + (A(s,a) - mean_a A(s,a))
%   but a deeper trunk (128->128->64) because the state is now the 3 kinematic
%   scalars PLUS the 54-D PFB feature fingerprint of the current echo -- a
%   24-wide trunk (agent.buildAgent, tuned for a 3-D bandit) cannot absorb
%   that. Exploration/replay are set explicitly here rather than left at
%   rlDQNAgentOptions defaults, since this agent is meant to be trained for
%   real (hundreds of episodes), not the ~20-episode smoke run buildAgent
%   was tuned for.
%
%   Pairs with agent.buildEnvFeatureConditioned(C).

    obsInfo = getObservationInfo(env);
    actInfo = getActionInfo(env);
    numObs  = obsInfo.Dimension(1);
    numAct  = numel(actInfo.Elements);

    trunk = [
        featureInputLayer(numObs, 'Name', 'state')
        fullyConnectedLayer(128, 'Name', 'fc1')
        reluLayer(               'Name', 'relu1')
        fullyConnectedLayer(128, 'Name', 'fc2')
        reluLayer(               'Name', 'relu2')
        fullyConnectedLayer(64,  'Name', 'fc3')
        reluLayer(               'Name', 'relu3')
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
    net = connectLayers(net, 'relu3',       'fcValue');
    net = connectLayers(net, 'relu3',       'fcAdvantage');
    net = connectLayers(net, 'fcValue',     'dueling/in1');
    net = connectLayers(net, 'fcAdvantage', 'dueling/in2');

    dlnet  = dlnetwork(net);
    critic = rlVectorQValueFunction(dlnet, obsInfo, actInfo);

    agentOpts = rlDQNAgentOptions( ...
        'UseDoubleDQN',                true, ...
        'TargetSmoothFactor',          1e-3, ...
        'ExperienceBufferLength',      1e4, ...
        'MiniBatchSize',               64, ...
        'DiscountFactor',              0.99);
    % Epsilon-greedy: start fully exploratory, decay slowly enough that a
    % few-hundred-episode run (F=8 steps each) still spends most of its early
    % life exploring the 45-action space before annealing to near-greedy.
    agentOpts.EpsilonGreedyExploration.Epsilon            = 1.0;
    agentOpts.EpsilonGreedyExploration.EpsilonDecay       = 5e-3;
    agentOpts.EpsilonGreedyExploration.EpsilonMin         = 0.02;
    agentOpts.CriticOptimizerOptions.LearnRate            = 1e-3;
    agentOpts.CriticOptimizerOptions.GradientThreshold    = 1;

    agnt = rlDQNAgent(critic, agentOpts);
end

% ------------------------------------------------------------------------
function q = localDuelingCombine(v, a)
    q = v + (a - mean(a, 1));
end
