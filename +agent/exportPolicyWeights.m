function outFile = exportPolicyWeights(agnt, outFile)
%EXPORTPOLICYWEIGHTS  Strip a trained D3QN down to plain matrices plus a
%   dependency-free forward pass, for edge deployment.
%
%   outFile = agent.exportPolicyWeights(agnt, outFile)
%       agnt : a trained rlDQNAgent (agent.buildAgentFeatureConditioned's
%              dueling architecture: trunk fc1-fc2-fc3 + value/advantage heads)
%
%   WHY THIS EXISTS INSTEAD OF QUANTIZATION -- MEASURED, on this machine,
%   with the 45-action net and the CPU already loaded by a training run:
%
%       getValue() through the RL Toolbox wrapper   5.686 ms   (mean, n=2000)
%       the same weights, plain matrix multiplies   0.0084 ms  (mean, n=20000)
%       ------------------------------------------------------------------
%       wrapper overhead                            680x the arithmetic
%
%   The network is 34,816 MACs and 137 KB of FP32. It is not what costs
%   2 ms; the dlarray/cell/System-object machinery around it is, by a factor
%   of 680. So:
%
%     * The "<2 ms decision" target is met by this path with ~238x margin
%       (8.4 us against a 2000 us budget), with NO quantization at all.
%     * INT8 would take 137 KB to 34 KB and speed up 34,816 MACs that
%       already complete in microseconds. On a drone payload the RF front
%       end and the DRFM memory dominate power by orders of magnitude; a
%       137 KB MLP is not the battery problem, and shrinking it 4x does not
%       become one. (It is also not currently executable here --
%       `dlquantizer` / the Model Quantization Library is not installed.)
%
%   Quantization becomes worth measuring if the policy network grows by
%   orders of magnitude, or if the target part has no FPU. Neither is true
%   of a 3-layer 35k-parameter MLP on any edge TPU or SoC that could host a
%   DRFM in the first place. Revisit with a measurement, not an assumption.
%
%   The saved .mat holds ONLY double matrices -- no MATLAB objects, no
%   toolbox dependency -- so it loads in numpy/C/ONNX tooling as-is.
%   agent.policyForward implements the matching forward pass.

    if nargin < 2 || isempty(outFile)
        here = fileparts(mfilename('fullpath'));
        outFile = fullfile(fileparts(here), 'results', 'policy_weights.mat');
    end

    p = getLearnableParameters(getCritic(agnt));
    assert(numel(p) == 10, 'agent:exportPolicyWeights:arch', ...
        ['Expected the 10-tensor dueling architecture (fc1,fc2,fc3,value,advantage ' ...
         'weights+biases); got %d tensors. Update this exporter if the trunk changed.'], ...
        numel(p));

    W = cell(1, numel(p));
    for i = 1:numel(p); W{i} = double(extractdata(p{i})); end

    net = struct('W1', W{1}, 'b1', W{2}, 'W2', W{3}, 'b2', W{4}, ...
                 'W3', W{5}, 'b3', W{6}, 'Wv', W{7}, 'bv', W{8}, ...
                 'Wa', W{9}, 'ba', W{10});
    net.obsDim     = size(W{1}, 2);
    net.numActions = size(W{9}, 1);
    net.numParams  = sum(cellfun(@numel, W));
    net.bytesFP32  = net.numParams * 4;

    % Numerical proof that the stripped path reproduces the toolbox path.
    % An exporter that silently transposed a weight would otherwise ship a
    % different policy that still looks like a policy.
    rng(0);
    X = rand(net.obsDim, 32);
    qRef = zeros(net.numActions, 32);
    critic = getCritic(agnt);
    for i = 1:32
        qRef(:, i) = double(extractdata(getValue(critic, {X(:, i)})));
    end
    qOwn = agent.policyForward(net, X);
    err = max(abs(qRef(:) - qOwn(:)));
    assert(err < 1e-4, 'agent:exportPolicyWeights:mismatch', ...
        'stripped forward pass differs from the toolbox by %.3e', err);
    net.maxAbsErrVsToolbox = err;

    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d); mkdir(d); end
    save(outFile, '-struct', 'net');
    fprintf(['exportPolicyWeights: %d params (%.1f KB FP32), %d actions, ' ...
             'max|dQ| vs toolbox %.2e -> %s\n'], ...
        net.numParams, net.bytesFP32/1024, net.numActions, err, outFile);
end
