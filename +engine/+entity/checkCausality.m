function [ok, reason] = checkCausality(phantomRangeM, jammerRangeM, mode, radarIsAgile)
%CHECKCAUSALITY  Can a repeater at jammerRangeM physically put a phantom at
%                phantomRangeM? (RADAR_REALISM_AUDIT.md 1.3)
%
%   [ok, reason] = engine.entity.checkCausality(phantomRangeM, jammerRangeM)
%   [ok, reason] = engine.entity.checkCausality(..., mode, radarIsAgile)
%
%       mode          'repeat' (default) | 'predictive'
%       radarIsAgile  logical, default false. Only consulted for 'predictive'.
%
%   THE PHYSICS, which this project modelled for a long time by not modelling
%   it at all. A DRFM repeater works by receiving the radar's pulse, storing
%   it, and retransmitting it after a delay. Delay is non-negative, so the
%   phantom's apparent range is
%
%       R_phantom = R_jammer + c*tau/2 ,  tau >= 0   =>   R_phantom >= R_jammer
%
%   A repeater CANNOT put a false target closer to the radar than itself. To
%   do that it would have to transmit before the pulse it is copying has
%   arrived -- i.e. PREDICT the next pulse. That is a real technique
%   (predictive repeat-back / pre-emptive jamming), and it is available
%   exactly when the radar is predictable: fixed PRF, fixed waveform. It is
%   NOT available against an agile radar, which is why the two improvements
%   are coupled and why 'predictive' here refuses when radarIsAgile is true.
%
%   Why this matters for everything this project has published: the canonical
%   scene puts a phantom at 1800 m closing to 1380 m, and the "mother drone"
%   has a power budget (cogengine/planner_cem.py) but NO POSITION anywhere in
%   the codebase. So every phantom placed closer than the jammer has been
%   free, and it is not free.
%
%   Returns ok=false plus a human-readable reason rather than throwing --
%   callers decide whether an impossible phantom is an error (engine.entity.
%   render) or a logged statistic (a planner exploring the action space).

    if nargin < 3 || isempty(mode); mode = 'repeat'; end
    if nargin < 4 || isempty(radarIsAgile); radarIsAgile = false; end

    ok = true; reason = '';

    if isempty(jammerRangeM) || ~isfinite(jammerRangeM)
        % No jammer modelled -> nothing to check. Honest, not silent: the
        % caller gets a reason string saying the check did not run.
        reason = 'unenforced: no jammer range supplied';
        return;
    end

    assert(isscalar(phantomRangeM) && phantomRangeM > 0, ...
        'engine:entity:badPhantomRange', 'phantomRangeM must be a positive scalar');
    assert(isscalar(jammerRangeM) && jammerRangeM > 0, ...
        'engine:entity:badJammerRange', 'jammerRangeM must be a positive scalar');

    switch lower(char(mode))
        case 'repeat'
            if phantomRangeM < jammerRangeM
                ok = false;
                reason = sprintf(['repeat-back cannot place a phantom at %.1f m: ' ...
                    'the jammer is at %.1f m, and a stored-and-delayed pulse can only ' ...
                    'appear FARTHER away (delay >= 0). Needs mode=''predictive''.'], ...
                    phantomRangeM, jammerRangeM);
            end

        case 'predictive'
            if radarIsAgile
                ok = false;
                reason = sprintf(['predictive repeat-back is not available against an ' ...
                    'AGILE radar: placing a phantom at %.1f m (inside the jammer at ' ...
                    '%.1f m) requires transmitting a copy of a pulse that has not ' ...
                    'arrived yet, which requires knowing what that pulse will be.'], ...
                    phantomRangeM, jammerRangeM);
            end

        otherwise
            error('engine:entity:badMode', ...
                'mode must be ''repeat'' or ''predictive'', got ''%s''', char(mode));
    end
end
