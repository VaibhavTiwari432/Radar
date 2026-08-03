function out = conformalValidate(csvPath, alpha, splitSeed, scoreCol, groupCol)
%CONFORMALVALIDATE  Does the Assurance Layer's coverage claim actually hold?
%
%   out = experiments.conformalValidate(csvPath, alpha, splitSeed)
%       csvPath   : experiments.calibrationLog's output. Default
%                   results/calibration_data.csv
%       alpha     : miscoverage level. Default 0.1 (90% nominal coverage)
%       splitSeed : calibration/test split seed. Default 7
%       scoreCol  : which belief to conformalise. Default 'inline_s_amp',
%                   the AMPLITUDE screen's own score.
%
%   WHY THE DEFAULT IS THE PER-SCREEN SCORE AND NOT THE COMBINED ONE.
%   Measured, not assumed: `inline_s_dop` is 1.0 in every logged episode, so
%   the discriminator's combined score is exactly (s_amp + 1)/2 -- an affine
%   map of the informative variable into [0.5, 1.0]. That compression does
%   not merely lose information, it structurally disables the predictor: with
%   every score >= 0.5, the nonconformity of "the judge says real" is
%   1 - x <= 0.5, which is below any qhat the calibration produces, so "real"
%   can NEVER be excluded from a prediction set and the sets cannot be
%   singletons. That is the whole of the 1.81-of-2 mean set size and the 94%
%   Simplex fallback rate reported against the combined score. Pass
%   'inline_score' to reproduce those.
%
%   THE TEST THAT CAN FAIL. assurance.conformalFit PROMISES that its
%   prediction sets contain the judge's real verdict at least (1-alpha) of
%   the time. That promise is worthless unless it is checked on data the
%   threshold was not fitted on, so the log is split in half at random:
%   conformal threshold from one half, coverage measured on the other. If
%   empirical coverage lands below nominal outside its Wilson interval, the
%   interval is a lie and this prints FAIL. Nothing here tunes anything to
%   make it pass.
%
%   PER-ARM COVERAGE IS REPORTED SEPARATELY AND IS EXPECTED TO BE WORSE.
%   Split conformal guarantees MARGINAL coverage -- averaged over the whole
%   calibration distribution. The three arms have materially different
%   twin-judge gaps (+16.0 / +7.0 / +5.0 pp, measured in
%   results/calibration_data.csv -- NOT the +24.0/+21.0/+44.0 pp in
%   results/t4_gap.log and results/t6.log, which are untracked pre-Tier-0/1
%   artefacts superseded by commit 6121e7ae), so a pooled threshold will
%   over-cover the easy arm and
%   under-cover the hard one while still being marginally valid. That is a
%   property of marginal conformal, not a bug, and the honest response is to
%   measure it rather than quote the marginal number alone.
%
%   MONDRIAN (PER-GROUP) CONFORMAL IS THE FIX, AND IT IS NOW WIRED IN:
%   pass groupCol (e.g. 'arm') to fit assurance.conformalFit once per group
%   and score each held-out row against its OWN group's threshold. Default ''
%   keeps the marginal behaviour, so every previously published number
%   reproduces unchanged.
%
%   WHY IT WAS DEFERRED, AND WHY THE DEFERRAL NO LONGER HOLDS. This header
%   previously said Mondrian was not wired in because "which grouping is
%   correct at deployment depends on what the engine knows about its own arm
%   at emission time, and that is a design question this measurement does not
%   settle." That question has an answer: the ARM IS NOT A LATENT PROPERTY THE
%   ENGINE MUST INFER -- it is the generator the engine itself chose to run
%   (structural CV-coherent, or which trained policy). It is known at emission
%   time by construction, so conditioning on it is legitimate rather than
%   cheating. Two groupings that would NOT be legitimate, for contrast: the
%   observer (the engine is never told which radar it faces -- that is the
%   whole point of experiments.exchangeability) and the judge's own verdict
%   (the label being predicted).
%
%   WHAT FORCED IT. experiments.exchangeability measured the structural arm
%   under-covering at 78.0% AT THE NOMINAL OBSERVER, before any shift, while
%   the pooled number read 90.3%. The dominant coverage defect in this layer
%   is per-ARM, not per-observer, and observer pooling does not touch it.
%
%   EPISTEMIC vs ALEATORIC. Law of total variance over regime cells: within
%   a cell (same arm, same commanded velocity and RCS) the only thing that
%   differs between episodes is the noise draw, so the within-cell Bernoulli
%   variance is ALEATORIC -- irreducible, no amount of modelling removes it.
%   The between-cell variance is EPISTEMIC: outcome spread the engine could
%   in principle predict from what it already knows about the regime it is
%   in. A high epistemic fraction means "gather data / condition on regime";
%   a high aleatoric fraction means "accept the variance". Only the
%   structural arm has commanded (vel, rcs) recorded per episode -- the
%   trained agents pick a fresh action every frame, so there is no single
%   regime label for the episode and they are excluded from this
%   decomposition rather than being given a fabricated one.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 1 || isempty(csvPath)
        csvPath = fullfile(root, 'results', 'calibration_data.csv');
    end
    if nargin < 2 || isempty(alpha);     alpha = 0.1;   end
    if nargin < 3 || isempty(splitSeed); splitSeed = 7; end
    if nargin < 4 || isempty(scoreCol); scoreCol = 'inline_s_amp'; end
    if nargin < 5 || isempty(groupCol); groupCol = ''; end   % '' = marginal

    T = readtable(csvPath);
    if ~ismember(scoreCol, T.Properties.VariableNames)
        error('experiments:conformalValidate:noColumn', ...
              '%s has no column %s -- re-run experiments.calibrationLog to add the per-screen scores.', csvPath, scoreCol);
    end
    s = T.(scoreCol);
    n = height(T);
    fprintf('conformalValidate: %d rows from %s\n', n, csvPath);
    fprintf('  nominal coverage %.0f%%, split seed %d, predictor %s\n\n', ...
        100*(1-alpha), splitSeed, scoreCol);

    rng(splitSeed);
    perm  = randperm(n);
    nCal  = floor(n/2);
    calIx = perm(1:nCal);
    tstIx = perm(nCal+1:end);

    model = assurance.conformalFit(s(calIx), T.judge_real(calIx), alpha);
    fprintf('  fitted on %d calibration points, qhat = %.4f%s\n', ...
        model.n, model.qhat, ternary(model.saturated, '  (SATURATED: n too small to exclude anything)', ''));

    % ---- Mondrian: one threshold per group, each row scored against its own.
    % A group with no calibration rows falls back to the pooled model rather
    % than erroring -- and says so, because a silent fallback would report
    % marginal coverage under a Mondrian label.
    groups = {}; models = {};
    if ~isempty(groupCol)
        if ~ismember(groupCol, T.Properties.VariableNames)
            error('experiments:conformalValidate:noGroupColumn', ...
                  '%s has no column %s to group by.', csvPath, groupCol);
        end
        groups = unique(T.(groupCol), 'stable');
        fprintf('\n  MONDRIAN by %s -- one threshold per group:\n', groupCol);
        for g = 1:numel(groups)
            gi = calIx(strcmp(T.(groupCol)(calIx), groups{g}));
            if isempty(gi)
                models{g} = model; %#ok<AGROW>
                fprintf('    %-12s no calibration rows -- POOLED qhat %.4f used\n', groups{g}, model.qhat);
            else
                models{g} = assurance.conformalFit(s(gi), T.judge_real(gi), alpha); %#ok<AGROW>
                fprintf('    %-12s n=%3d  qhat %.4f%s\n', groups{g}, models{g}.n, models{g}.qhat, ...
                    ternary(models{g}.saturated, '  (SATURATED)', ''));
            end
        end
        model = struct('groupCol', groupCol, 'groups', {groups}, 'models', {models}, ...
                       'pooled', model, 'qhat', NaN, 'n', numel(calIx), 'saturated', false);
    end

    % ---- coverage on the held-out half
    [cov, width, singleton, covered] = localScore(model, s, T.judge_real, tstIx, T, groupCol);
    [lo, hi] = localWilson(round(cov*numel(tstIx)), numel(tstIx));
    pass = hi >= (1 - alpha);        % nominal inside the interval's reach
    fprintf('\n  HELD-OUT (n=%d):  coverage %5.1f%% [%.1f, %.1f]   mean set size %.2f   singleton %5.1f%%   -> %s\n', ...
        numel(tstIx), 100*cov, 100*lo, 100*hi, width, 100*singleton, ternary(pass, 'PASS', 'FAIL'));

    % ---- per-arm, expected to be worse; see header
    arms = unique(T.arm);
    fprintf('\n  per-arm coverage (marginal threshold, NOT per-arm calibrated):\n');
    perArm = struct('arm', {}, 'n', {}, 'coverage', {}, 'width', {}, 'gapPp', {});
    for a = 1:numel(arms)
        ix = tstIx(strcmp(T.arm(tstIx), arms{a}));
        if isempty(ix); continue; end
        [c, w, ~, ~] = localScore(model, s, T.judge_real, ix, T, groupCol);
        all_ = strcmp(T.arm, arms{a});
        g = 100*(mean(T.inline_real(all_)) - mean(T.judge_real(all_)));
        fprintf('    %-10s n=%3d  coverage %5.1f%%   mean set size %.2f   (arm twin-judge gap %+5.1f pp)\n', ...
            arms{a}, numel(ix), 100*c, w, g);
        perArm(end+1) = struct('arm', arms{a}, 'n', numel(ix), ...
            'coverage', c, 'width', w, 'gapPp', g); %#ok<AGROW>
    end

    % ---- DISCRIMINATIVE POWER. Coverage and set size say how the conformal
    % wrapper behaves; NEITHER says whether the underlying score carries
    % information about the judge. It has to be asked separately, because at a
    % low base rate a predictor with no information at all still yields narrow
    % sets and high coverage -- it emits the majority label and is usually
    % right. AUC 0.5 means no information; the always-say-NOT-REAL accuracy
    % beside it is what a singleton set is actually worth on this data.
    fprintf('\n  discriminative power of %s (AUC 0.5 = no information):\n', scoreCol);
    aucAll = localAuc(s(~isnan(s)), T.judge_real(~isnan(s)));
    perAuc = struct('arm', {}, 'auc', {}, 'baseRate', {}, 'majorityAcc', {});
    for a = 1:numel(arms)
        m = strcmp(T.arm, arms{a}) & ~isnan(s);
        u = localAuc(s(m), T.judge_real(m));
        br = mean(T.judge_real(m));
        fprintf('    %-10s AUC %.3f   base rate judge_real %5.1f%%   always-NOT-REAL accuracy %5.1f%%\n', ...
            arms{a}, u, 100*br, 100*(1-br));
        perAuc(end+1) = struct('arm', arms{a}, 'auc', u, 'baseRate', br, ...
                               'majorityAcc', 1-br); %#ok<AGROW>
    end
    brAll = mean(T.judge_real(~isnan(s)));
    fprintf('    %-10s AUC %.3f   base rate judge_real %5.1f%%   always-NOT-REAL accuracy %5.1f%%\n', ...
        'POOLED', aucAll, 100*brAll, 100*(1-brAll));
    if aucAll < 0.60
        fprintf(['    -> WEAK. Narrow sets here are the BASE RATE, not information.\n' ...
                 '       Do not read a high singleton rate as predictive capability.\n']);
    end

    % ---- epistemic / aleatoric, structural arm only (see header)
    st = strcmp(T.arm, 'structural') & ~isnan(T.vel_mps);
    [cellIds, ~] = findgroups(T.vel_mps(st), T.rcs_dbsm(st));
    y = T.judge_real(st);
    pAll = mean(y);
    totalVar = pAll * (1 - pAll);
    aleatoric = 0; nCells = max(cellIds);
    for c = 1:nCells
        yc = y(cellIds == c);
        if isempty(yc); continue; end
        pc = mean(yc);
        aleatoric = aleatoric + (numel(yc)/numel(y)) * pc * (1 - pc);
    end
    epistemic = max(0, totalVar - aleatoric);
    fprintf(['\n  uncertainty split (structural arm, %d episodes over %d (vel,rcs) cells):\n' ...
             '    total Bernoulli variance %.4f  =  aleatoric %.4f (%.0f%%)  +  epistemic %.4f (%.0f%%)\n'], ...
        nnz(st), nCells, totalVar, aleatoric, 100*aleatoric/max(totalVar,eps), ...
        epistemic, 100*epistemic/max(totalVar,eps));

    out = struct('n', n, 'alpha', alpha, 'splitSeed', splitSeed, 'scoreCol', scoreCol, 'model', model, ...
        'coverage', cov, 'coverageCI', [lo hi], 'meanSetSize', width, ...
        'singletonRate', singleton, 'pass', pass, 'perArm', perArm, ...
        'totalVar', totalVar, 'aleatoric', aleatoric, 'epistemic', epistemic, ...
        'covered', covered);

    f = fullfile(root, 'results', 'conformal_validation.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s\n', f);
end

% ------------------------------------------------------------------------
function [cov, width, singleton, covered] = localScore(model, s, y, ix, T, groupCol)
%LOCALSCORE  Coverage and mean set size. Under Mondrian each row is scored
%   against ITS OWN group's threshold -- scoring a row against a pooled qhat
%   while calling the result Mondrian would report the defect it is meant to
%   fix.
    mondrian = nargin >= 6 && ~isempty(groupCol);
    covered = false(numel(ix), 1);
    sizes   = zeros(numel(ix), 1);
    single  = false(numel(ix), 1);
    for i = 1:numel(ix)
        r = ix(i);
        m = model;
        if mondrian
            g = find(strcmp(model.groups, T.(groupCol){r}), 1);
            if isempty(g); m = model.pooled; else; m = model.models{g}; end
        end
        [set, unc] = assurance.conformalPredict(m, s(r));
        if y(r) ~= 0
            covered(i) = set(2);       % judge said real; is "real" in the set?
        else
            covered(i) = set(1);       % judge said not real; is "not real" in it?
        end
        sizes(i)   = nnz(set);
        single(i)  = ~unc;
    end
    cov = mean(covered); width = mean(sizes); singleton = mean(single);
end

% ------------------------------------------------------------------------
function u = localAuc(s, y)
%LOCALAUC  Probability a randomly chosen judge-real episode scores above a
%   randomly chosen judge-decoy one. Ties count half, which matters here
%   because this project's screen scores are heavily tied at 0 and 0.5.
    pos = s(y ~= 0); neg = s(y == 0);
    if isempty(pos) || isempty(neg); u = NaN; return; end
    w = 0;
    for i = 1:numel(pos)
        w = w + sum(pos(i) > neg) + 0.5*sum(pos(i) == neg);
    end
    u = w / (numel(pos) * numel(neg));
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
