function out = conformalValidate(csvPath, alpha, splitSeed, scoreCol)
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
%   measure it rather than quote the marginal number alone. The fix if a
%   per-arm number is needed is Mondrian (per-group) conformal: fit
%   assurance.conformalFit once per arm. Not done here -- there is no point
%   paying for it before the marginal number shows it is needed.
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

    % ---- coverage on the held-out half
    [cov, width, singleton, covered] = localScore(model, s, T.judge_real, tstIx);
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
        [c, w, ~, ~] = localScore(model, s, T.judge_real, ix);
        all_ = strcmp(T.arm, arms{a});
        g = 100*(mean(T.inline_real(all_)) - mean(T.judge_real(all_)));
        fprintf('    %-10s n=%3d  coverage %5.1f%%   mean set size %.2f   (arm twin-judge gap %+5.1f pp)\n', ...
            arms{a}, numel(ix), 100*c, w, g);
        perArm(end+1) = struct('arm', arms{a}, 'n', numel(ix), ...
            'coverage', c, 'width', w, 'gapPp', g); %#ok<AGROW>
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
function [cov, width, singleton, covered] = localScore(model, s, y, ix)
    covered = false(numel(ix), 1);
    sizes   = zeros(numel(ix), 1);
    single  = false(numel(ix), 1);
    for i = 1:numel(ix)
        r = ix(i);
        [set, unc] = assurance.conformalPredict(model, s(r));
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
