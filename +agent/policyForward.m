function Q = policyForward(net, X)
%POLICYFORWARD  Dueling-D3QN forward pass in plain matrix algebra.
%
%   Q = agent.policyForward(NET, X)
%       NET : struct from agent.exportPolicyWeights
%       X   : [obsDim x N] observations, one per column (N may be 1)
%       Q   : [numActions x N] action values;  argmax over dim 1 is the
%             greedy action.
%
%   Q(s,a) = V(s) + ( A(s,a) - mean_a A(s,a) )   -- the dueling identity from
%   agent.buildAgentFeatureConditioned, reproduced exactly (verified to
%   <1e-4 against the toolbox by the exporter's own assertion).
%
%   MEASURED 8.4 us per single-observation call, against the RL Toolbox
%   wrapper's 5.686 ms for the same weights -- see agent.exportPolicyWeights
%   for why that ratio, not quantization, is the deployment story.
%
%   Deliberately dependency-free: no dlarray, no System objects, no toolbox.
%   Everything here is a matmul, an add, a max and a mean, so this function
%   transliterates line for line into numpy or C.

    h = max(0, net.W1 * X + net.b1);
    h = max(0, net.W2 * h + net.b2);
    h = max(0, net.W3 * h + net.b3);
    V = net.Wv * h + net.bv;                 % [1 x N]
    A = net.Wa * h + net.ba;                 % [numActions x N]
    Q = V + (A - mean(A, 1));                % implicit expansion over actions
end
