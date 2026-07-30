function fv = featureVector(iq, pfb)
%FEATUREVECTOR  54-D hardware-realizable feature vector (16 PFB channels x
%   {power,peak,kurtosis} + 6 global time-domain features).
%
%   fv = features.featureVector(iq, pfb), pfb from features.buildChannelizer
%   (built fresh with defaults if omitted). Direct MATLAB port of
%   cognitive_engine/cogengine/features.py's feature_vector.

    if nargin < 2 || isempty(pfb)
        pfb = features.buildChannelizer();
    end
    Y = features.channelize(pfb, iq);
    mag = abs(Y);
    power = mean(mag.^2, 2);
    peak = max(mag, [], 2);
    cen = mag - mean(mag, 2);
    v = mean(cen.^2, 2) + 1e-12;
    kurt = mean(cen.^4, 2) ./ (v.^2);
    chan = reshape([power, peak, kurt].', [], 1);   % 48

    iq = iq(:);
    env = abs(iq);
    phD = diff(unwrap(angle(iq)));
    glob = [mean(env); std(env); mean(env.^2); ...
             max(env)/(mean(env)+1e-10); mean(phD); std(phD)];  % 6

    fv = [chan; glob];   % 54
end
