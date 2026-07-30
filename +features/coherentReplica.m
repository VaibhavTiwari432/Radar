function x = coherentReplica(params, fs, n)
%COHERENTREPLICA  Build a matched replica FROM extracted waveform parameters.
%
%   x = features.coherentReplica(params, fs, n) returns a unit-energy
%   complex column vector of length n: for 'lfm' class, a clean chirp at
%   the estimated chirp rate; otherwise a pure carrier tone at the
%   estimated centre frequency.
%
%   Direct MATLAB port of cognitive_engine/cogengine/features.py's
%   coherent_replica. This is REPLICATE, the second of feature extraction's
%   three synthesis uses (see features.characterizeIntercept for
%   CHARACTERIZE, features.featureDistance for MEASURE REALISM). Building
%   the replica from ESTIMATED parameters (not the raw noisy intercept
%   itself) is what removes the intercept receiver's own noise from every
%   retransmission -- see +agent/buildEnvWithFeatures.m.

    if nargin < 3 || isempty(n)
        n = params.n_samples;
    end
    t = (0:n-1)' / fs;
    if strcmp(params.wclass, 'lfm')
        x = exp(1i * pi * params.chirp_rate_hz_s * t.^2);
    else
        x = exp(1i * 2 * pi * params.f0_hz * t);
    end
    x = x / sqrt(sum(abs(x).^2) + 1e-12);
end
