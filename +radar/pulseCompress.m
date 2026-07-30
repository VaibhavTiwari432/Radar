function [power, y, mf] = pulseCompress(rx, waveform)
%PULSECOMPRESS  Matched-filter (pulse compression) of a received pulse.
%
%   [power, y, mf] = radar.pulseCompress(RX, WAVEFORM) correlates the
%   received fast-time samples RX (column vector) with a matched copy of the
%   transmitted WAVEFORM (a phased.* waveform System object), returning:
%       power - |y|.^2, the range-power profile fed to radar.cfarDetect
%       y     - complex matched-filter output, DELAY-COMPENSATED so that a
%               target whose echo starts at rx(k+1) produces its
%               pulse-compression peak at power(k+1) (row k+1 <-> range
%               k*C.range_per_sample, matching radar.rangeDoppler's axis
%               convention).
%       mf    - the phased.MatchedFilter (returned for reuse)
%
%   phased.MatchedFilter is a causal FIR filter: correlating a pulse that
%   starts at sample k produces its peak at k + numel(coeff) - 1, not at k
%   (see e.g. MathWorks' "Simulating a Monostatic Radar" example). We shift
%   the output left by that fixed group delay and zero-pad the tail so
%   absolute range recovery (Stage 4, claim C3) is correct, not just
%   relative energy concentration (Stage 1).
%
%   INDEPENDENT radar block (CLAUDE.md Rule 2). Ref: POA Part 4 Stage 1-2.

    rx = rx(:);
    N = numel(rx);
    coeff = getMatchedFilter(waveform);       % matched coefficients for this waveform
    mf = phased.MatchedFilter('Coefficients', coeff);
    yRaw = mf(rx);

    delay = numel(coeff) - 1;
    if delay > 0 && delay < N
        y = [yRaw(delay+1:end); complex(zeros(delay,1))];
    else
        y = yRaw;
    end
    power = abs(y).^2;
end
