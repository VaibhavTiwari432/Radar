function model = conformalFit(scores, outcomes, alpha)
%CONFORMALFIT  Split-conformal calibration of the engine's own belief against
%   the independent judge's verdict.
%
%   model = assurance.conformalFit(scores, outcomes, alpha)
%       scores   : [n x 1] the engine's inline ECCM screen score in [0,1]
%                  (experiments.calibrationLog's inline_score) -- its BELIEF
%                  that the judge will call this track real.
%       outcomes : [n x 1] logical/0-1, what engine.runJudge ACTUALLY did
%                  (calibrationLog's judge_real). The ground truth.
%       alpha    : miscoverage level; 0.1 gives 90% coverage. Default 0.1.
%
%   WHAT THE GUARANTEE IS. For an exchangeable calibration/test split, the
%   set returned by assurance.conformalPredict contains the judge's true
%   verdict with probability >= 1-alpha. That is a distribution-free,
%   finite-sample statement: it does NOT assume the score is a calibrated
%   probability, does not assume a model class, and does not assume the
%   twin-judge gap is small.
%
%   WHY NO MODEL IS FITTED. The obvious construction is to fit a logistic
%   regression of judge_real on inline_score and conformalise its output.
%   That step is unnecessary here and would be a second thing to validate:
%   conformal prediction repairs an arbitrarily miscalibrated score, so the
%   score is used AS the probability estimate. A badly-behaved score does
%   not break the coverage guarantee -- it makes the prediction sets WIDER,
%   which is the correct and visible failure mode. Interval width is
%   therefore the quality metric and coverage is the correctness metric, and
%   they are reported separately (experiments.conformalValidate).
%
%   THIS IS THE ADVERSARY'S SELF-KNOWLEDGE, NOT THE JUDGE'S (CLAUDE.md
%   Rule 2). +assurance/ never calls +radar/, +track/ or +engine/runJudge;
%   it only ever consumes a log of what that judge already decided, after
%   the fact. Nothing here can reach back and change what the judge does.

    if nargin < 3 || isempty(alpha); alpha = 0.1; end
    scores   = double(scores(:));
    outcomes = double(outcomes(:)) ~= 0;
    if numel(scores) ~= numel(outcomes)
        error('assurance:conformalFit:sizeMismatch', ...
              'scores (%d) and outcomes (%d) must be the same length.', ...
              numel(scores), numel(outcomes));
    end
    keep = ~isnan(scores);           % unscreened episodes carry no score
    scores = scores(keep); outcomes = outcomes(keep);
    n = numel(scores);
    if n < 1
        error('assurance:conformalFit:empty', 'No scored calibration points.');
    end
    if alpha <= 0 || alpha >= 1
        error('assurance:conformalFit:alpha', 'alpha must be in (0,1).');
    end

    % Least-ambiguous-set nonconformity: how badly the belief missed the
    % outcome that actually happened. s = 1 - phat(y_true).
    s = zeros(n, 1);
    s( outcomes) = 1 - scores( outcomes);
    s(~outcomes) =     scores(~outcomes);

    % The finite-sample quantile: the ceil((n+1)*(1-alpha))-th smallest, NOT
    % quantile(s, 1-alpha). The +1 is what makes the coverage guarantee hold
    % for finite n rather than asymptotically; dropping it undercovers, most
    % visibly at the small n a calibration run like this actually has.
    k = ceil((n + 1) * (1 - alpha));
    ss = sort(s);
    if k > n
        qhat = Inf;                  % too few points to exclude anything
    else
        qhat = ss(k);
    end

    model = struct('qhat', qhat, 'alpha', alpha, 'n', n, ...
                   'k', k, 'scores', s, 'saturated', k > n);
end
