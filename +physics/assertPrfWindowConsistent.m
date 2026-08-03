function info = assertPrfWindowConsistent(prfHz, fastTimeSamples, varargin)
%ASSERTPRFWINDOWCONSISTENT  A radar cannot listen for longer than its PRI.
%
%   info = physics.assertPrfWindowConsistent(prfHz, fastTimeSamples)
%   info = physics.assertPrfWindowConsistent(..., 'Mode', 'warn'|'error'|'silent')
%
%   Returns a struct describing the radar's actual range/Doppler ambiguity
%   envelope, and (by default) WARNS if the receive window is longer than one
%   PRI -- the condition under which every range beyond R_ua in that window
%   is physically a folded return being read as if it were not.
%
%   Default mode is 'warn', not 'error': this project's own established
%   configuration (50 kHz PRF, 400-sample window) VIOLATES the check, and
%   turning that into a hard error would stop 15 existing test files rather
%   than inform them. The point is to make the contradiction visible and
%   impossible to reintroduce silently, not to halt work that predates it.
%
%   See physics.apparentRange's header for the full argument.

    p = inputParser;
    addParameter(p, 'Mode', 'warn', @(s) any(strcmpi(s, {'warn','error','silent'})));
    parse(p, varargin{:});
    mode = lower(p.Results.Mode);

    C = physics.Constants();
    priSamples = C.fs / prfHz;

    info.prf_hz               = prfHz;
    info.pri_s                = 1 / prfHz;
    info.pri_samples          = priSamples;
    info.fast_time_samples    = fastTimeSamples;
    info.unambiguous_range_m  = C.c / (2 * prfHz);
    info.window_span_m        = fastTimeSamples * C.range_per_sample;
    info.window_pri_ratio     = fastTimeSamples / priSamples;
    % PRF the receive window would imply if IT were the honest one.
    info.implied_prf_hz       = C.fs / fastTimeSamples;
    info.consistent           = (fastTimeSamples <= priSamples);

    if info.consistent || strcmp(mode, 'silent'); return; end

    msg = sprintf(['receive window is %.2f PRIs long: %d samples (%.0f m) at ' ...
        'PRF %.0f Hz, whose PRI is only %.0f samples (R_ua %.0f m). Ranges ' ...
        'beyond %.0f m in this window are folded returns being read as ' ...
        'unambiguous. The window implies PRF %.0f Hz instead.'], ...
        info.window_pri_ratio, fastTimeSamples, info.window_span_m, prfHz, ...
        priSamples, info.unambiguous_range_m, info.unambiguous_range_m, ...
        info.implied_prf_hz);

    if strcmp(mode, 'error')
        error('physics:assertPrfWindowConsistent:windowExceedsPri', '%s', msg);
    else
        warning('physics:assertPrfWindowConsistent:windowExceedsPri', '%s', msg);
    end
end
