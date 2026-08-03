function [set, uncertain] = conformalPredict(model, score)
%CONFORMALPREDICT  Turn one belief into a prediction set over the judge's
%   possible verdicts, at the coverage assurance.conformalFit was fitted for.
%
%   [set, uncertain] = assurance.conformalPredict(model, score)
%       model     : from assurance.conformalFit
%       score     : the engine's inline ECCM screen score in [0,1] for the
%                   emission it is about to make
%       set       : logical [1x2], set(1) = "judge says NOT real" is in the
%                   set, set(2) = "judge says real" is in the set
%       uncertain : true when the set is not a singleton -- i.e. the engine
%                   cannot commit to what the judge will do at this coverage
%                   level. This is the Simplex guard's trigger.
%
%   FOUR OUTCOMES, AND THE EMPTY ONE MATTERS.
%       {real}        confident the judge will be fooled
%       {not real}    confident it will not
%       {real, not}   genuinely ambiguous -- too near the boundary to call
%       {}            NEITHER label is plausible under the calibration set.
%                     In a binary problem an empty set cannot mean "no
%                     answer"; it means this score is unlike anything in
%                     calibration, which is exactly the exchangeability
%                     violation the coverage guarantee is conditional on.
%                     Reported as uncertain, deliberately NOT as a confident
%                     verdict -- a distribution-shift alarm, not a decision.
%
%   A NaN score (an unscreened episode: fewer than 2 usable frames, so the
%   discriminator never ran) is uncertain by construction. There is no
%   belief to be confident about.

    if isnan(score)
        set = [true true]; uncertain = true; return;
    end
    score = double(score);
    % Include a label iff its nonconformity is within the calibrated
    % threshold: s(y=1) = 1-score, s(y=0) = score.
    set = [score <= model.qhat, (1 - score) <= model.qhat];
    uncertain = (nnz(set) ~= 1);
end
