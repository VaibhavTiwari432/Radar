function [screens, confirm, agileFrom, nReactions, last] = reactiveStep( ...
        screens, confirm, agileFrom, nReactions, minRealConf, anyRateFail, nextFrame)
%REACTIVESTEP  Scalar/array-in, scalar/array-out wrapper over radar.reactivePolicy.
%
%   [screens, confirm, agileFrom, nReactions, last] = radar.reactiveStep( ...
%       screens, confirm, agileFrom, nReactions, minRealConf, anyRateFail, nextFrame)
%
%   WHY THIS EXISTS. reactivePolicy takes and returns a struct, and MATLAB
%   Engine API for Python cannot pass a Python dict IN as a struct at all. This
%   wrapper takes only the field values (a cellstr, a vector, scalars) and
%   returns them as separate outputs, every one of which the engine converts --
%   the same interop constraint +generator/judgeSummary.m documents on the way
%   OUT. The reaction LOGIC lives in one place (reactivePolicy); this only
%   marshals. generator/decision/env_seq.py holds the state between blocks and
%   is the only Python caller.

    state = struct('screens', {cellstr(screens)}, 'confirm', double(confirm), ...
                   'agile_from', double(agileFrom), ...
                   'n_reactions', double(nReactions), 'last', '');
    fb = struct('min_real_confidence', double(minRealConf), ...
                'any_rate_fail', logical(anyRateFail));
    s = radar.reactivePolicy(state, fb, 'NextFrame', double(nextFrame));
    screens = s.screens;
    confirm = s.confirm;
    agileFrom = s.agile_from;
    nReactions = s.n_reactions;
    last = s.last;
end
