function Y = synthesizeSwarm(xIntercepted, action, C)
%SYNTHESIZESWARM  DRFM false-target generator: delay/phase/gain-shift an
%                 intercepted signal into one or more phantom echoes.
%
%   Y = synth.synthesizeSwarm(XINTERCEPTED, ACTION, C)
%       xIntercepted : [Nsamples x 1] complex. One receive-window's worth
%                      of the signal the swarm intercepted (e.g. the
%                      radar's own transmit waveform, placed at whatever
%                      sample offset represents its true range, padded with
%                      zeros/noise to fill the window). This function does
%                      not care where it came from or what it means.
%       action       : struct array (one element per phantom), each with
%           .delay_s   : additional range-delay to apply [s]
%           .phase_rad : constant phase offset [rad]
%           .gain      : linear amplitude scale (dimensionless)
%       C            : physics.Constants() (used only to convert delay_s to
%                      an integer sample shift via C.fs).
%
%       Y : [Nsamples x numel(action)] complex, one phantom echo per
%           column:  y_i[n] = gain_i * xIntercepted[n - tau_i] * exp(1i*phase_i)
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): this produces candidate
%   phantom signals only. Whether trackerGNN confirms a false track on them
%   is decided ENTIRELY by +radar and +track -- +synth never imports or
%   calls either package, and never checks its own success.
%
%   Ref: POA Part 4 Stage 3/6 (y_i[n] = A_i x[n-tau_i] e^{j phi_i}).

    x = xIntercepted(:);
    N = numel(x);
    numPhantoms = numel(action);
    Y = complex(zeros(N, numPhantoms));

    for i = 1:numPhantoms
        tauSamples = round(action(i).delay_s * C.fs);
        shifted = localDelaySamples(x, tauSamples);
        Y(:,i) = action(i).gain * shifted * exp(1i*action(i).phase_rad);
    end
end

% ------------------------------------------------------------------------
function y = localDelaySamples(x, tau)
%LOCALDELAYSAMPLES  Integer-sample delay of x by tau samples (zero-filled
%                    at the start; truncated at the end). tau may be <= 0.
    N = numel(x);
    y = complex(zeros(N,1));
    if tau >= 0 && tau < N
        y(tau+1:end) = x(1:N-tau);
    elseif tau < 0 && -tau < N
        y(1:N+tau) = x(1-tau:end);
    end
end
