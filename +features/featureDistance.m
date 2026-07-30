function d = featureDistance(iqA, iqB, pfb)
%FEATUREDISTANCE  Relative L2 distance in 54-D PFB feature space -- the
%   realism metric. Small = the synthesized echo looks (to a feature-based
%   ECCM) like the real one.
%
%   d = features.featureDistance(iqA, iqB, pfb), pfb from
%   features.buildChannelizer (built fresh with defaults if omitted).
%   Direct MATLAB port of cognitive_engine/cogengine/features.py's
%   feature_distance.

    if nargin < 3 || isempty(pfb)
        pfb = features.buildChannelizer();
    end
    fa = features.featureVector(iqA, pfb);
    fb = features.featureVector(iqB, pfb);
    d = norm(fa - fb) / (norm(fa) + norm(fb) + 1e-12);
end
