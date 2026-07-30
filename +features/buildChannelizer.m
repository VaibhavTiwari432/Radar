function pfb = buildChannelizer(M, L)
%BUILDCHANNELIZER  Precompute and cache PFB polyphase channelizer coefficients.
%
%   pfb = features.buildChannelizer(M, L) with M channels, L taps/channel
%   (default M=16, L=8, matching cognitive_engine/cogengine/features.py's
%   PolyphaseChannelizer). Returns a struct with fields M, L, E (the M x L
%   polyphase coefficient matrix).
%
%   This is the "PFB channelizer parameters ... pre-computed and cached"
%   state the mission asks agent.buildAgentWithFeatures to hold -- computed
%   ONCE and reused by every features.featureVector / featureDistance call,
%   not recomputed per call.

    if nargin < 1 || isempty(M); M = 16; end
    if nargin < 2 || isempty(L); L = 8; end

    nTaps = M * L;
    n = (0:nTaps-1)';
    h = sinc(2 * (1/M) * (n - (nTaps-1)/2)) .* hann(nTaps);
    h = h / (sum(h) + 1e-12) * M;

    pfb.M = M;
    pfb.L = L;
    pfb.E = reshape(h, L, M).';   % (M x L) polyphase matrix
end
