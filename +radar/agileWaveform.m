function [wav, pulse] = agileWaveform(sweepSign, fs, pulseWidthS, prfHz, bandwidthHz)
%AGILEWAVEFORM  The radar's transmit waveform for ONE dwell of an agile
%               schedule (RADAR_REALISM_AUDIT.md 1.2).
%
%   [wav, pulse] = radar.agileWaveform(sweepSign, fs, pulseWidthS, prfHz, bandwidthHz)
%       sweepSign : +1 -> up-chirp, -1 -> down-chirp
%       wav       : the phased.LinearFMWaveform for this dwell (what the
%                   matched filter is built from)
%       pulse     : its actual complex samples, pulseWidthS*fs long
%
%   WHY THIS EXISTS. Until now this project's radar transmitted an IDENTICAL
%   LFM on every pulse of every frame, forever. That is the condition a DRFM
%   repeater most wants: yesterday's intercept is still a perfect copy of
%   today's pulse. Real anti-DRFM radars randomise what the next pulse will
%   be -- sweep reversal, PRF stagger, phase coding -- precisely so that a
%   stored copy goes stale. Sweep reversal is implemented here because it is
%   the cheapest agility that this project's existing matched filter already
%   understands, and its cost to a stale repeater is large: measured, an
%   up-chirp matched filter fed a down-chirp pulse loses **13.2 dB of peak**
%   and smears the response from 3 range bins to 30.
%
%   ALWAYS RETURN MATLAB'S OWN SAMPLES, never an analytic formula. Verified:
%   phased.LinearFMWaveform's 'Up' matches exp(+1i*pi*k*t^2) exactly
%   (correlation 1.0000), but its 'Down' does NOT match exp(-1i*pi*k*t^2)
%   (correlation 0.0201) -- it uses a different phase reference. A renderer
%   that generated its own down-chirp analytically would be transmitting a
%   waveform the judge is not actually looking for, and would report an
%   agility penalty that is really a convention mismatch.
%
%   The SCHEDULE is the radar's secret, not a shared parameter. Callers pass
%   a per-frame sign vector; +engine/runJudge.m reads it from the exported
%   .mat, and the deception side only ever learns it by intercepting.

    if sweepSign >= 0; dirStr = 'Up'; else; dirStr = 'Down'; end

    wav = phased.LinearFMWaveform('SampleRate', double(fs), ...
            'PulseWidth', double(pulseWidthS), 'PRF', double(prfHz), ...
            'SweepBandwidth', double(bandwidthHz), 'SweepDirection', dirStr);

    if nargout > 1
        p = wav();
        n = round(double(pulseWidthS) * double(fs));
        pulse = p(1:min(n, numel(p)));
    end
end
