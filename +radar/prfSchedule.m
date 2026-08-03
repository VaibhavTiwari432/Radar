function [priS, timesS] = prfSchedule(nPulses, prfHz, jitterFrac, rs)
%PRFSCHEDULE  A staggered pulse-repetition-interval sequence (Tier 2.2).
%
%   [priS, timesS] = radar.prfSchedule(nPulses, prfHz, jitterFrac, rs)
%       jitterFrac : peak fractional deviation of each PRI from nominal.
%                    0 -> constant PRI (this project's historical radar).
%       rs         : RandStream, for a reproducible schedule
%       priS       : [nPulses x 1] the PRI BEFORE each pulse [s]
%       timesS     : [nPulses x 1] transmit time of each pulse [s], t(1) = 0
%
%   WHY. A constant PRI is the second thing a DRFM repeater wants after a
%   constant waveform: it makes the next pulse's ARRIVAL TIME predictable, so
%   a repeater can schedule its retransmission open-loop. Real anti-DRFM
%   radars stagger the PRI for exactly this reason -- +radar/agileWaveform.m's
%   own header names PRF stagger as such a technique and does not implement
%   it. This does.
%
%   THE STAGGER IS THE RADAR'S SECRET, exactly like the sweep schedule: the
%   radar knows `timesS` and can compensate for it; a repeater does not, and
%   must fall back on the NOMINAL PRI. That asymmetry is the whole mechanism,
%   and it is why this returns the times rather than hiding them inside a
%   renderer.
%
%   BOUND ON jitterFrac, DERIVED. The receive window is one nominal PRI long
%   (400 samples at fs = 3.2 MHz and PRF = 8 kHz, C.pri_samples). A PRI
%   shorter than nominal by more than the window would eclipse the previous
%   pulse's own listening time, so the useful range is jitterFrac < ~0.5;
%   values above that are refused rather than silently producing an
%   unphysical schedule.

    assert(isscalar(jitterFrac) && jitterFrac >= 0 && jitterFrac < 0.5, ...
        'radar:prfSchedule:badJitter', ...
        ['jitterFrac must be in [0, 0.5): a deviation of half a PRI or more ' ...
         'eclipses the previous pulse''s receive window. Got %g.'], jitterFrac);

    priNom = 1 / prfHz;
    if jitterFrac == 0
        priS = repmat(priNom, nPulses, 1);
    else
        if nargin < 4 || isempty(rs)
            u = rand(nPulses, 1) - 0.5;
        else
            u = rand(rs, nPulses, 1) - 0.5;
        end
        % Symmetric about nominal, so the MEAN PRF is unchanged and the
        % stagger costs no average revisit rate -- only predictability.
        priS = priNom * (1 + 2 * jitterFrac * u);
    end

    % t(1) = 0; pulse p leaves priS(p) after pulse p-1.
    timesS = [0; cumsum(priS(1:end-1))];
end
