function out = exchangeability(csvPath, alpha, splitSeed, scoreCol)
%EXCHANGEABILITY  Does conformal coverage survive a radar the calibration set
%   never saw? The Assurance Layer's own first follow-up, run.
%
%   out = experiments.exchangeability(csvPath, alpha, splitSeed, scoreCol)
%       csvPath : a MULTI-OBSERVER calibration set, i.e. the output of
%                 experiments.calibrationLog(..., observers) with more than
%                 one row in `observers`. Default
%                 results/calibration_observers.csv
%
%   THE CLAIM UNDER TEST, AND WHY IT IS NOT A FORMALITY. Split conformal's
%   coverage guarantee is conditional on EXCHANGEABILITY between the
%   calibration set and what is met at deployment. ASSURANCE_LAYER_RESULTS.md
%   states that as a limit and names the violation:
%   experiments.observerSweep measured CFAR NumTraining 20 -> 32 costing the
%   judge's real rate 23.0% -> 8.0% (Wilson intervals DISJOINT) while the
%   engine's inline belief did not move at all -- the label distribution
%   shifts underneath a frozen score distribution, which is precisely the
%   condition the guarantee needs. Until this file ran, no coverage number in
%   that document was licensed for a radar whose training length is unknown.
%
%   TWO REGIMES, ONE MODEL CLASS, AND THE PREDICTION IS WRITTEN DOWN FIRST.
%
%     A  SHIFTED   fit qhat on the NOMINAL observer only, measure coverage on
%                  each other observer. This is the deployment situation the
%                  limit describes: calibrated on one radar, met by another.
%     B  POOLED    fit on a random half of ALL observer rows, measure on the
%                  other half. Exchangeability holds BY CONSTRUCTION here,
%                  because the split is random over the pooled set, so this is
%                  the repair the limit proposes ("re-collect the calibration
%                  set across the observer distribution").
%
%   PREDICTION, RECORDED BEFORE THE RUN so it can be wrong: A under-covers on
%   the observer whose real rate falls (fewer `real` verdicts than the
%   nominal-fitted qhat was calibrated for), B lands at or above nominal.
%   THE COMPETING OUTCOME, equally recorded: A does NOT under-cover, because
%   the amplitude score and the judge's verdict move TOGETHER under a
%   NumTraining change -- see ROOT CAUSE HYPOTHESIS below.
%
%   %% THE VERDICT RULE -- LOCKED BEFORE THE DATA, COMMITTED BEFORE THE RUN
%
%   A_coverage is the WORST held-out coverage over the non-nominal observers
%   under the nominal-fitted qhat. The nominal observer is excluded from it
%   because qhat was fitted on those rows: it is training coverage, printed
%   for reference and marked as such, never decisive.
%
%       if     A_coverage < 0.85    UNDER-COVERS: conformal limit binds;
%                                   recommend POOLED
%       elseif A_coverage <= 0.95   VALID: limit is real but not binding in
%                                   this regime
%       elseif A_coverage <= 1.0    OVER-COVERS: both methods meet target;
%                                   report trade-off
%       else                        AMBIGUOUS: manual review required
%
%   TWO DEVIATIONS FROM THE RULE AS HANDED TO ME, BOTH DELIBERATE AND BOTH
%   STATED BEFORE THE RUN rather than discovered afterwards:
%
%   (1) THE `else` BRANCH IS DEAD CODE AS SPECIFIED. `<0.85`, `[0.85,0.95]`
%       and `>0.95` are exhaustive over the reals, so AMBIGUOUS could never
%       fire and the rule would have no defined behaviour for the one case
%       that genuinely is ambiguous: an observer with NO held-out rows, whose
%       coverage is NaN, not a number to compare. The branch is bound to that
%       case, which makes it reachable and makes it mean something. A NaN
%       cannot silently fall into VALID.
%   (2) THE SLOP BAND IN THE BRIEF (+/-3 pp, 83-93%) CONTRADICTS ITS OWN
%       THRESHOLDS (85 / 95). The thresholds are implemented, because they
%       are what the decision tree is written in; the band is not, because
%       implementing both would need a precedence rule nobody stated. Flagged
%       here so the discrepancy is on the record and not resolved by whoever
%       reads the output first.
%
%   COVERAGE IS REPORTED WITH MEAN SET SIZE, ALWAYS, AND THE REASON IS THAT
%   COVERAGE ALONE IS NOT INTERPRETABLE. The set {real, not-real} covers
%   every outcome by construction, so a predictor that always returns the
%   whole outcome space scores 100% coverage and answers nothing. An
%   OVER-COVERS verdict at set size 2.00 is a vacuous predictor, not a pass.
%   Set size does NOT enter the verdict -- the rule is locked -- but it is
%   printed on the same line so no verdict can be quoted without it.
%
%   The per-observer Wilson intervals are also printed. They are the
%   sample-size-aware version of the same question (experiments.
%   conformalValidate's own rule: FAIL if the interval's upper bound cannot
%   reach nominal) and at n ~ 75 per observer a bare point estimate is noisy.
%   They are diagnostic here, NOT decisive: the locked tree above is what
%   decides, and it decides on the point estimate.
%
%   %% ROOT CAUSE HYPOTHESIS
%
%   OBSERVATION: at NumTraining 32 the judge's real rate falls 23.0% -> 8.0%
%   (experiments.observerSweep, n=100, Wilson intervals disjoint) while the
%   engine's inline belief does not move at all.
%
%   MECHANISM:
%     1. NumTraining sets the CA-CFAR TRAINING WINDOW, and the near-range
%        blind zone is NumTraining+NumGuard cells wide, so 20 -> 32 widens it
%        by 12 cells ~ 562 m. (NOT the tracker's gate width -- that is
%        AssignmentThreshold, swept separately at 100 and 400 m and measured
%        bit-identical. Attributing this to gate width would name a knob the
%        sweep already exonerated.)
%     2. A target walking near that edge loses detections, so the track has
%        fewer usable frames: 6.00 -> 4.12 on the episodes that flip
%        (experiments.cliffRootCause, pre-registered and RUN).
%     3. Screen 1 fits log(amplitude) against log(range) over those frames,
%        so a shorter lever arm destabilises the slope: -1.374 -> -11.798
%        against a physical -2, std 6.181 -> 19.299.
%     4. The conformal predictor's variable IS that screen's own score
%        (inline_s_amp). So the score is computed from the very quantity the
%        shift destabilises.
%
%   IMPLICATION -- what each outcome would mean, stated before either is seen:
%     - Score TRACKS the slope  -> A_coverage stays >= 0.85. The predictor
%       sees the shift in its own input, so its nonconformity moves with the
%       outcome and the calibration stays honest. The exchangeability limit is
%       REAL IN MECHANISM BUT DOES NOT BIND on this grid.
%     - Score is BLIND to the slope -> A_coverage falls below 0.85. The label
%       distribution moved while the score distribution did not, which is
%       exactly the violation. The limit BINDS and pooling is required.
%
%   This experiment measures which is true. Note the asymmetry that makes it
%   worth running: the two outcomes are not "pass" and "fail" -- one says the
%   documented limit is weaker than feared, the other says every coverage
%   number in ASSURANCE_LAYER_RESULTS.md needs an observer caveat.
%
%   WHAT THIS DOES NOT MEASURE. Coverage is about the BELIEF, not the
%   deception: a prediction set that reliably contains "the judge will flag
%   this" is perfectly covered and completely unfavourable. The observer grid
%   is also one-at-a-time (observerSweep's grid), so an interaction between
%   two mis-assumed knobs is out of scope.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 1 || isempty(csvPath)
        csvPath = fullfile(root, 'results', 'calibration_observers.csv');
    end
    if nargin < 2 || isempty(alpha);     alpha = 0.1;   end
    if nargin < 3 || isempty(splitSeed); splitSeed = 7; end
    if nargin < 4 || isempty(scoreCol);  scoreCol = 'inline_s_amp'; end

    T = readtable(csvPath);
    if ~ismember('observer', T.Properties.VariableNames)
        error('experiments:exchangeability:noObserverColumn', ...
              ['%s has no `observer` column. Collect one with\n' ...
               '  experiments.calibrationLog(nEp, seeds, csv, observers)\n' ...
               'passing an Nx2 {name, runJudge args} cell.'], csvPath);
    end
    obsNames = unique(T.observer, 'stable');
    if numel(obsNames) < 2
        error('experiments:exchangeability:singleObserver', ...
              '%s holds only observer "%s" -- there is no shift to measure.', ...
              csvPath, obsNames{1});
    end
    s = T.(scoreCol);
    y = T.judge_real;

    fprintf('exchangeability: %d rows, %d observers, predictor %s, nominal coverage %.0f%%\n\n', ...
        height(T), numel(obsNames), scoreCol, 100*(1-alpha));

    % ---- the shift itself, before any conformal: does the label distribution
    % actually move while the score distribution does not? If it does not,
    % nothing below is testing anything.
    fprintf('  %-24s %8s %10s %12s %12s\n', 'observer', 'n', 'judge real', 'mean score', 'inline real');
    perObs = struct('name', {}, 'n', {}, 'judgeReal', {}, 'meanScore', {}, ...
                    'inlineReal', {}, 'coverageShifted', {}, 'ciShifted', {}, ...
                    'widthShifted', {}, 'passShifted', {});
    for i = 1:numel(obsNames)
        m = strcmp(T.observer, obsNames{i});
        fprintf('  %-24s %8d %9.1f%% %12.4f %11.1f%%\n', obsNames{i}, nnz(m), ...
            100*mean(y(m)), mean(s(m), 'omitnan'), 100*mean(T.inline_real(m)));
        perObs(i) = struct('name', obsNames{i}, 'n', nnz(m), ...
            'judgeReal', mean(y(m)), 'meanScore', mean(s(m), 'omitnan'), ...
            'inlineReal', mean(T.inline_real(m)), 'coverageShifted', NaN, ...
            'ciShifted', [NaN NaN], 'widthShifted', NaN, 'passShifted', false);
    end

    % ---- regime A: calibrated on nominal, met by every other observer
    nomIx = find(strcmp(T.observer, obsNames{1}));
    mdlNom = assurance.conformalFit(s(nomIx), y(nomIx), alpha);
    fprintf(['\n  A SHIFTED -- qhat fitted on observer "%s" alone ' ...
             '(n=%d, qhat=%.4f), applied to each observer:\n'], ...
        obsNames{1}, mdlNom.n, mdlNom.qhat);
    worstA = NaN; worstName = ''; widthAtWorst = NaN; failA = {};
    for i = 1:numel(obsNames)
        ix = find(strcmp(T.observer, obsNames{i}));
        [cov, width] = localCoverage(mdlNom, s, y, ix);
        [lo, hi] = localWilson(round(cov*numel(ix)), numel(ix));
        pass = hi >= (1 - alpha);        % Wilson: diagnostic, NOT the verdict
        note = '';
        if i == 1; note = '  <- fitted here, TRAINING coverage, not decisive'; end
        fprintf('    %-24s coverage %5.1f%% [%4.1f, %5.1f]   set size %.2f   -> %s%s\n', ...
            obsNames{i}, 100*cov, 100*lo, 100*hi, width, ternary(pass, 'PASS', 'FAIL'), note);
        perObs(i).coverageShifted = cov;
        perObs(i).ciShifted = [lo hi];
        perObs(i).widthShifted = width;
        perObs(i).passShifted = pass;
        if i > 1 && (isnan(worstA) || cov < worstA)
            worstA = cov; worstName = obsNames{i}; widthAtWorst = width;
        end
        if i > 1 && ~pass; failA{end+1} = obsNames{i}; end %#ok<AGROW>
    end

    % ---- regime B: pooled across observers, random split, exchangeable by
    % construction. This is the repair, measured rather than asserted.
    rng(splitSeed);
    n = height(T);
    perm = randperm(n);
    calIx = perm(1:floor(n/2));
    tstIx = perm(floor(n/2)+1:end);
    mdlPool = assurance.conformalFit(s(calIx), y(calIx), alpha);
    [covB, widthB] = localCoverage(mdlPool, s, y, tstIx);
    [loB, hiB] = localWilson(round(covB*numel(tstIx)), numel(tstIx));
    passB = hiB >= (1 - alpha);
    fprintf(['\n  B POOLED  -- qhat fitted on a random half of ALL observers ' ...
             '(n=%d, qhat=%.4f):\n'], mdlPool.n, mdlPool.qhat);
    fprintf('    %-24s coverage %5.1f%% [%4.1f, %5.1f]   set size %.2f   -> %s\n', ...
        'held-out half', 100*covB, 100*loB, 100*hiB, widthB, ternary(passB, 'PASS', 'FAIL'));
    for i = 2:numel(obsNames)
        ix = tstIx(strcmp(T.observer(tstIx), obsNames{i}));
        if isempty(ix); continue; end
        [c, w] = localCoverage(mdlPool, s, y, ix);
        fprintf('      of which %-16s n=%3d  coverage %5.1f%%   set size %.2f\n', ...
            obsNames{i}, numel(ix), 100*c, w);
    end

    % ---- VERDICT. The rule is the one locked in this file's header and
    % committed before the data existed. It decides on A_coverage = the WORST
    % held-out non-nominal coverage, on the point estimate, and on nothing
    % else. Set size is printed beside it because coverage alone is not
    % interpretable, but it does not enter the branch.
    if isnan(worstA)
        verdict = 'AMBIGUOUS: manual review required';
        detail  = 'no held-out non-nominal rows -- A_coverage is undefined, not a number to compare';
    elseif worstA < 0.85
        verdict = 'UNDER-COVERS: conformal limit binds; recommend POOLED';
        detail  = sprintf(['the label distribution moved while the score distribution ' ...
                  'did not.\n           Every coverage number in ' ...
                  'ASSURANCE_LAYER_RESULTS.md needs an observer caveat;\n' ...
                  '           regime B (pooled) measured %.1f%% and is the repair.'], 100*covB);
    elseif worstA <= 0.95
        verdict = 'VALID: limit is real but not binding in this regime';
        detail  = ['the predictor sees the shift in its own input, so the ' ...
                   'calibration stays honest.'];
    elseif worstA <= 1.0
        verdict = 'OVER-COVERS: both methods meet target; report trade-off';
        detail  = ['check the set size before quoting this -- the whole outcome ' ...
                   'space covers 100%.'];
    else
        verdict = 'AMBIGUOUS: manual review required';
        detail  = 'A_coverage outside [0,1] -- impossible, indicates a defect above';
    end
    fprintf('\n  A_coverage = %.1f%% (worst non-nominal: %s, set size %.2f)\n', ...
        100*worstA, ternary(isempty(worstName), '<none>', worstName), widthAtWorst);
    fprintf('  VERDICT: %s\n           %s\n', verdict, detail);
    if ~isempty(failA)
        fprintf(['           (Wilson diagnostic, not the verdict: %d of %d non-nominal ' ...
                 'observers\n            cannot reach nominal -- %s)\n'], ...
            numel(failA), numel(obsNames)-1, strjoin(failA, ', '));
    end
    fprintf('  MECHANISM: %s\n', ternary(~isnan(worstA) && worstA < 0.85, ...
        'score was BLIND to the slope shift -- the limit binds.', ...
        'score TRACKED the slope shift -- real in mechanism, not binding here.'));

    out = struct('csvPath', csvPath, 'alpha', alpha, 'splitSeed', splitSeed, ...
        'scoreCol', scoreCol, 'observers', {obsNames'}, 'perObserver', perObs, ...
        'qhatNominal', mdlNom.qhat, 'qhatPooled', mdlPool.qhat, ...
        'aCoverage', worstA, 'aCoverageObserver', worstName, ...
        'aCoverageSetSize', widthAtWorst, 'verdict', verdict, ...
        'worstShiftedCoverage', worstA, 'shiftedFailures', {failA}, ...
        'pooledCoverage', covB, 'pooledCI', [loB hiB], ...
        'pooledSetSize', widthB, 'pooledPass', passB);
    f = fullfile(root, 'results', 'exchangeability.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s\n', f);
end

% ------------------------------------------------------------------------
function [cov, width] = localCoverage(model, s, y, ix)
%LOCALCOVERAGE  Fraction of rows whose prediction set contains the judge's
%   actual verdict, and the mean set size that bought it. Coverage without
%   set size is not interpretable -- the whole outcome space always covers.
    covered = false(numel(ix), 1);
    sizes   = zeros(numel(ix), 1);
    for i = 1:numel(ix)
        r = ix(i);
        set = assurance.conformalPredict(model, s(r));
        if y(r) ~= 0; covered(i) = set(2); else; covered(i) = set(1); end
        sizes(i) = nnz(set);
    end
    cov = mean(covered); width = mean(sizes);
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end

% ------------------------------------------------------------------------
function s = ternary(c, a, b)
    if c; s = a; else; s = b; end
end

%% INTERPRETATION -- FILLED IN AFTER RESULTS, NOTHING ABOVE THIS LINE MAY MOVE
%
%   A_coverage        = [pending]
%   worst observer    = [pending]
%   mean set size     = [pending]
%   Verdict           = [pending -- read off the locked tree, not chosen]
%   Regime B (pooled) = [pending]
%
%   Mechanism confirmation:
%     [pending. Inferred from A_coverage against the 0.85 threshold ONLY:
%      >= 0.85 means the amplitude score TRACKED the NumTraining-driven slope
%      shift, so the exchangeability limit is real in mechanism but does not
%      bind on this grid;  < 0.85 means the score was BLIND to it and the
%      limit binds. There is no third reading available -- if the data
%      suggests one, it belongs in a NEW section below, not in a revision of
%      the rule above.]
%
%   Anything learned that the locked rule could not express goes here, under
%   its own heading, as a limitation of the rule. The rule itself is a
%   commitment made before the data and does not get amended to fit it.
