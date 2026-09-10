function state = reactivePolicy(state, fb, varargin)
%REACTIVEPOLICY  The radar's between-block answer to a track that barely passed.
%
%   state = radar.reactivePolicy(state, fb, 'NextFrame', k, 'Name', value, ...)
%
%   RL v2 Step 2. PURE: (radar state, judge scalars) -> next radar state. It
%   lives judge-side so the generator only ever meets the radar through what it
%   radiates (Rule 2); generator/decision code must never put `state` into an
%   agent's observation.
%
%   state  struct
%       screens      cellstr  EccmScreens in force now
%       confirm      [M N]    ConfirmationThreshold in force now
%       agile_from   scalar   first frame the chirp alternates on; 0 = never
%       n_reactions  scalar   reactions spent so far
%       last         char     most recent reaction ('' = none yet)
%   fb     generator.judgeSummary scalars; reads min_real_confidence and
%          any_rate_fail.
%
%   Name-value
%       'NextFrame'  REQUIRED. First frame of the NEXT block. Agility can only
%                    change the future: echoes already stored were received
%                    under the old chirp.
%       'Margin'     0.3. Trigger when a track the radar calls REAL has
%                    discriminator confidence |score-0.5|*2 below this -- it
%                    passed, but barely (+track/discriminator.m:595-599).
%                    ASSUMED doctrine, not measured.
%       'Reactions'  {'screen','agility','confirm'}. Reaction k uses entry k
%                    (cyclically); an exhausted one falls through to the next.
%       'Screens'    {'rangerate','residual','maneuver'}, appended in order.
%
%   Also triggers on any_rate_fail: the range-rate magnitude check (reported
%   beside the ECCM score, not in it) disagreeing is itself a reason to look
%   harder.
%
%   WHAT A JAMMER CAN SEE: agility (the chirp it intercepts changes). WHAT IT
%   CANNOT: a new screen or a stricter confirmation rule. That asymmetry is
%   what would give a sequential learner something to infer (RL v2, Step 3).
%
%   The harness re-judges the whole prefix each block, so a new screen or
%   confirmation rule re-scores the stored track history; agility acts only
%   from NextFrame on. Dwell length cannot react here: pulses per frame are
%   fixed for the whole cube (+engine/runJudge.m:1062).

    p = inputParser;
    p.addParameter('NextFrame', [], @(x) isscalar(x) && x >= 1);
    p.addParameter('Margin', 0.3, @(x) isscalar(x) && x > 0 && x <= 1);
    p.addParameter('Reactions', {'screen', 'agility', 'confirm'}, @iscellstr);
    p.addParameter('Screens', {'rangerate', 'residual', 'maneuver'}, @iscellstr);
    p.parse(varargin{:});
    o = p.Results;
    if isempty(o.NextFrame)
        error('radar:reactivePolicy:NextFrame', 'NextFrame is required');
    end

    conf = double(fb.min_real_confidence);
    suspicious = (isfinite(conf) && conf < o.Margin) || logical(fb.any_rate_fail);
    if ~suspicious
        return;
    end

    screens = reshape(cellstr(state.screens), 1, []);
    unused = setdiff(o.Screens, screens, 'stable');
    k = double(state.n_reactions);
    n = numel(o.Reactions);
    order = [o.Reactions(mod(k, n) + 1:end), o.Reactions(1:mod(k, n))];
    for r = order
        switch r{1}
            case 'screen'
                if isempty(unused); continue; end
                state.screens = [screens, unused(1)];
            case 'agility'
                if state.agile_from > 0; continue; end
                state.agile_from = o.NextFrame;
            case 'confirm'
                if state.confirm(1) >= 4; continue; end
                state.confirm = [4 5];
        end
        state.n_reactions = k + 1;
        state.last = r{1};
        return;
    end
    % Every reaction exhausted: the radar has nothing left to escalate.
end
