function Y = channelize(pfb, x)
%CHANNELIZE  Run x through the cached PFB channelizer.
%
%   Y = features.channelize(pfb, x), pfb from features.buildChannelizer.
%   Returns Y, an (M x T) complex matrix (M channels x T time blocks),
%   the same structure as cognitive_engine's PolyphaseChannelizer.process.

    x = x(:);
    T = floor(numel(x) / pfb.M);
    xb = reshape(x(1:T*pfb.M), pfb.M, T);
    filt = zeros(pfb.M, T);
    for m = 1:pfb.M
        c = conv(xb(m, :), pfb.E(m, :));
        filt(m, :) = c(1:T);
    end
    Y = fft(filt, [], 1);
end
