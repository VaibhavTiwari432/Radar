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
%
%   %% VERDICT RULE -- LOCKED BEFORE THE DATA, COMMITTED BEFORE THE RUN
%
%   Coverage target : 90% nominal (from the prior conformal fit,
%                     experiments.conformalValidate, alpha = 0.1)
%   Acceptable slop : +/- 3 pp  (83% - 93%)
%   A SHIFTED       : fit on nominal alone, measure on each observer separately
%   B POOLED        : fit on a random 50% of all observers
%
%   A_coverage is the worst held-out coverage over the non-nominal observers
%   under the nominal-fitted qhat.
%
%       if A_coverage < 85%
%           verdict = "UNDER-COVERS: conformal limit binds; recommend POOLED"
%       elseif (A_coverage >= 85%) && (A_coverage <= 95%)
%           verdict = "VALID: limit is real but not binding in this regime"
%       elseif A_coverage > 95%
%           verdict = "OVER-COVERS: both methods meet target; report trade-off"
%       else
%           verdict = "AMBIGUOUS: manual review required"
%       end
%
%   Once this is committed the verdict is uneditable, even after the data is
%   seen. Plain-English mirror of the same rule:
%   +experiments/exchangeability_verdict_rule.txt
%
%   %% ROOT CAUSE HYPOTHESIS
%
%   OBSERVATION: At NumTraining=32, judge real rate drops 23 pp (cliff in
%   observerSweep).
%
%   MECHANISM:
%     1. NumTraining controls CFAR gate width and thus which frames are usable.
%     2. Lost frames destabilize the amplitude slope.
%     3. Conformal predictor was calibrated on that slope.
%     4. If slope shifts WITH NumTraining, score may track it.
%
%   IMPLICATION:
%     - If score tracks slope -> A_coverage is robust (limit doesn't bind)
%     - If score is blind to slope -> A_coverage under-covers (limit binds)
%
%   This experiment measures which is true.
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

    % ---- VERDICT, from the rule locked in this file's header and committed
    % before the data existed. A_coverage is the worst held-out non-nominal
    % coverage. Nothing else enters the branch.
    A_coverage = worstA;
    if A_coverage < 0.85
        verdict = 'UNDER-COVERS: conformal limit binds; recommend POOLED';
    elseif (A_coverage >= 0.85) && (A_coverage <= 0.95)
        verdict = 'VALID: limit is real but not binding in this regime';
    elseif A_coverage > 0.95
        verdict = 'OVER-COVERS: both methods meet target; report trade-off';
    else
        verdict = 'AMBIGUOUS: manual review required';
    end
    fprintf('\n  A_coverage = %.1f%% (worst non-nominal: %s, set size %.2f)\n', ...
        100*A_coverage, ternary(isempty(worstName), '<none>', worstName), widthAtWorst);
    fprintf('  VERDICT: %s\n', verdict);
    fprintf('  MECHANISM: %s\n', ternary(A_coverage < 0.85, ...
        'score was BLIND to the slope shift -- the limit binds.', ...
        'score TRACKED the slope shift -- limit real in mechanism, not binding.'));
    if ~isempty(failA)
        fprintf('  (Wilson diagnostic, not the verdict: %s cannot reach nominal)\n', ...
            strjoin(failA, ', '));
    end

    % ---- POST-HOC per-arm diagnostic, ADDED AFTER THE VERDICT WAS READ.
    % It changes nothing above and decides nothing; it exists because the
    % pooled number the locked rule decides on turned out to conceal two
    % things (see LIMITATION OF THE RULE at the foot of this file): only the
    % structural arm is exposed to the shift at all, and that arm under-covers
    % at nominal before any shift. Printed here so both are re-runnable rather
    % than living in a transcript.
    arms = unique(T.arm, 'stable');
    fprintf('\n  POST-HOC per-arm (same qhat=%.4f, not part of the verdict):\n', mdlNom.qhat);
    fprintf('    %-11s %-14s %10s %10s %9s\n', 'arm', 'observer', 'judge real', 'coverage', 'set size');
    for a = 1:numel(arms)
        for i = 1:numel(obsNames)
            ix = find(strcmp(T.arm, arms{a}) & strcmp(T.observer, obsNames{i}));
            if isempty(ix); continue; end
            [c, w] = localCoverage(mdlNom, s, y, ix);
            fprintf('    %-11s %-14s %9.1f%% %9.1f%% %9.2f\n', ...
                arms{a}, obsNames{i}, 100*mean(y(ix)), 100*c, w);
        end
    end

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

%% INTERPRETATION (filled in after results)
% A_coverage = 90.3%  (worst non-nominal observer: Pfa 1e-2, set size 1.05)
% Verdict: VALID: limit is real but not binding in this regime
% Mechanism confirmation:
%   The score did NOT under-cover, so by the locked inference it TRACKED the
%   shift rather than being blind to it. The pre-registered PREDICTION (that A
%   under-covers) is REFUTED.
%
%   Full table, 1200 rows, qhat 0.6255 fitted on the nominal observer alone:
%     nominal      judge real 8.3%   coverage 90.3%   set size 1.05
%     Pfa 1e-2     judge real 8.3%   coverage 90.3%   set size 1.05
%     training 10  judge real 8.3%   coverage 90.3%   set size 1.05
%     training 32  judge real 4.7%   coverage 92.3%   set size 1.05
%     B POOLED                       coverage 90.0%   set size 1.05
%
%   The sets are SHARP (1.05 of a possible 2), so this is not the vacuous
%   case where coverage is bought by returning the whole outcome space.
%   MATLAB (+assurance/) and the independent Python reimplementation
%   (+reports/parse_exchangeability.py) agree to the digit.
%
%% LIMITATION OF THE RULE (post-hoc, added after seeing the data)
%
%   The rule above is NOT amended -- its verdict stands exactly as printed.
%   What follows is a limitation OF the rule, per the amendment policy in
%   +experiments/exchangeability_verdict_rule.txt, and it is stated because
%   the pooled number the rule decides on conceals two things.
%
%   (1) THE SHIFT ONLY EXISTS ON ONE ARM. At training 32 the structural arm's
%       judge real rate falls 19.0% -> 8.0%; `shaped` (4.0%) and `stats`
%       (2.0%) do not move at all, at any observer. Two thirds of the rows the
%       verdict averages over are therefore not exposed to the shift being
%       tested, which dilutes it.
%
%   (2) COVERAGE DID NOT HOLD BECAUSE THE SCORE TRACKED THE SHIFT. Per arm,
%       under that same qhat = 0.6255:
%
%         structural  nominal 78.0%  ...  training 32 84.0%   (set 1.12)
%         shaped      nominal 95.0%  ...  training 32 95.0%   (set 1.04)
%         stats       nominal 98.0%  ...  training 32 98.0%   (set 1.00)
%
%       The structural arm under-covers at 78.0% ALREADY AT NOMINAL, before
%       any shift -- reproducing the marginal-vs-conditional gap
%       ASSURANCE_LAYER_RESULTS.md measured at 78.8%, whose fix is Mondrian
%       (per-arm) conformal, NOT pooling over observers. And the shift makes
%       that arm's coverage BETTER, 78.0% -> 84.0%, not worse.
%
%       The reason is a third mechanism the pre-registered IMPLICATION could
%       not express: the shift does not perturb the predictor's input, it
%       moves the OUTCOME toward the label the predictor is already confident
%       about. NumTraining 32 drives judge-real down to 8.0%, so more episodes
%       land on "not real", which is the verdict this predictor calls well.
%       Coverage rose for the arithmetic reason that the easy label got more
%       common -- not because the amplitude score sensed anything.
%
%   CONSEQUENCE, stated plainly: the VALID verdict is correct as read, and it
%   is NOT evidence that the amplitude score tracks observer changes. It is
%   evidence that THIS shift happens to move outcomes in the direction the
%   predictor already favours. A shift in the opposite direction -- one that
%   raises the judge's real rate under a frozen belief -- is untested and
%   would attack the coverage from the side this grid never probes.
