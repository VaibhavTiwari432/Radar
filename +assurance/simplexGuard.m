function [useSmart, reason] = simplexGuard(model, smartScore)
%SIMPLEXGUARD  Decide whether to trust the high-performance controller or
%   drop to the verified-safe one, using calibrated confidence rather than
%   the smart controller's own opinion of itself.
%
%   [useSmart, reason] = assurance.simplexGuard(model, smartScore)
%       model      : from assurance.conformalFit
%       smartScore : the smart controller's inline ECCM screen score for the
%                    emission under consideration
%       useSmart   : true to emit the smart plan, false to fall back
%       reason     : one of 'confident-real', 'confident-not-real',
%                    'ambiguous', 'out-of-distribution', 'no-belief'
%
%   THE RULE. Emit the smart plan only when its conformal prediction set is
%   the singleton {judge says real}. Every other set -- the other singleton,
%   both labels, the empty set, or no belief at all -- falls back.
%
%   WHY THE SINGLETON AND NOT A THRESHOLD ON THE SCORE. A raw score
%   threshold is a number someone tuned; the singleton condition is a
%   statement with a coverage guarantee behind it (assurance.conformalFit).
%   The threshold moves on its own when the calibration data says the
%   engine's belief has become less trustworthy, which is the entire point
%   of putting a Simplex architecture around an unverified controller.
%
%   WHAT THIS DOES NOT CLAIM. Black-box Simplex is proven safe when the
%   fallback is VERIFIED. This project's fallback (the structural CV-coherent
%   generator) is not verified in that sense -- it is measured, at 19.0%
%   real against the judge (results/calibration_data.csv, 100 episodes)
%   versus the learned agent's 2.0%. So the guarantee here is empirical
%   ("the floor is the measured
%   fallback rate"), not a proof, and experiments.simplexAB is what measures
%   whether the floor actually holds.

    [set, uncertain] = assurance.conformalPredict(model, smartScore);
    useSmart = isequal(set, [false true]);
    if useSmart
        reason = 'confident-real';
    elseif isequal(set, [true false])
        reason = 'confident-not-real';
    elseif isnan(smartScore)
        reason = 'no-belief';
    elseif ~any(set)
        reason = 'out-of-distribution';
    elseif uncertain
        reason = 'ambiguous';
    else
        reason = 'ambiguous';
    end
end
