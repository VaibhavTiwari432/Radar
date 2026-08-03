function out = simplexAB(csvPath, smartArm, alpha, splitSeed, scoreCol)
%SIMPLEXAB  Does the Simplex guard actually buy anything? A/B the guarded
%   controller against always-smart and always-fallback, on the judge.
%
%   out = experiments.simplexAB(csvPath, smartArm, alpha, splitSeed, scoreCol)
%       scoreCol : which belief the guard switches on. Default
%                  'inline_s_amp', the amplitude screen's own score. The
%                  combined 'inline_score' is (s_amp + 1)/2 -- an affine map
%                  into [0.5, 1.0] that makes "the judge says real" impossible
%                  to exclude from any prediction set, which is what made the
%                  guard a near-constant function at a 94% fallback rate. Pass
%                  'inline_score' to reproduce that. See
%                  experiments.conformalValidate's header.
%       smartArm : 'stats' (default) or 'shaped' -- the trained D3QN whose
%                  plans the guard is deciding whether to trust. The fallback
%                  is always 'structural', the untrained CV-coherent
%                  generator, which is the arm that already beats both
%                  (19.0% vs 2.0%/4.0% real against the judge, measured in
%                  results/calibration_data.csv, 100 episodes per arm).
%                  NOT the 76.0%/56.0%/27.0% in results/t4_gap.log and
%                  results/t6.log -- untracked pre-Tier-0/1 artefacts,
%                  superseded by commit 6121e7ae. The structure-beats-
%                  learning ORDERING survives the correction; the absolute
%                  rates do not, and they move by a factor of four.
%
%   NO NEW ROLLOUTS. Every number here comes from the calibration log
%   experiments.calibrationLog already produced, which holds each arm's own
%   inline belief and the independent judge's verdict on the SAME cube.
%   Re-running the arms to A/B them would draw different noise and confound
%   the guard's effect with the draw.
%
%   HOW THE PAIRING WORKS, AND WHAT IT IS NOT. The guarded controller's
%   outcome on a test episode is the smart arm's judge verdict when the
%   guard trusts it, and the structural arm's verdict at the same
%   (seed, episode) index when it does not. The two arms are separate
%   environments with separate noise draws, so this is NOT a
%   counterfactual on one identical received signal -- it is the guarded
%   POLICY's outcome distribution against the always-smart and
%   always-fallback distributions. Stated because the difference matters:
%   a per-episode "would this exact cube have survived" claim is not
%   available from this design and is not made.
%
%   THE HONEST LIMIT ON WHEN THE BELIEF EXISTS. The inline score the guard
%   switches on is computed from the completed 8-frame track, so in this
%   measurement the guard decides with information a real-time guard would
%   not have until after it had already emitted. What this therefore
%   measures is the CEILING of an episode-level guard, not a deployable
%   one. The deployable version switches MID-episode on the partial-track
%   score both environments' localPotential already computes every frame;
%   that needs a policy swap inside the environment and is the follow-on,
%   deliberately not built here before this number says whether it is worth
%   building.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 1 || isempty(csvPath)
        csvPath = fullfile(root, 'results', 'calibration_data.csv');
    end
    if nargin < 2 || isempty(smartArm);  smartArm = 'stats'; end
    if nargin < 3 || isempty(alpha);     alpha = 0.1;        end
    if nargin < 4 || isempty(splitSeed); splitSeed = 7;      end
    if nargin < 5 || isempty(scoreCol);  scoreCol = 'inline_s_amp'; end
    fallbackArm = 'structural';

    T = readtable(csvPath);
    S = T(strcmp(T.arm, smartArm), :);
    F = T(strcmp(T.arm, fallbackArm), :);
    if isempty(S); error('experiments:simplexAB:noArm', 'no rows for arm %s', smartArm); end

    % Fallback lookup by (seed, episode)
    fbKey = F.seed * 1e6 + F.episode;

    rng(splitSeed);
    n = height(S);
    perm  = randperm(n);
    nCal  = floor(n/2);
    model = assurance.conformalFit(S.(scoreCol)(perm(1:nCal)), ...
                                    S.judge_real(perm(1:nCal)), alpha);
    tstIx = perm(nCal+1:end);

    nT = numel(tstIx);
    smartOut = nan(nT,1); fbOut = nan(nT,1); guardOut = nan(nT,1);
    usedSmart = false(nT,1); reasons = strings(nT,1);
    for i = 1:nT
        r = tstIx(i);
        [useSmart, reason] = assurance.simplexGuard(model, S.(scoreCol)(r));
        usedSmart(i) = useSmart; reasons(i) = reason;
        smartOut(i) = S.judge_real(r);
        j = find(fbKey == S.seed(r)*1e6 + S.episode(r), 1);
        if isempty(j)
            % No paired fallback episode -- do not invent one. Excluded from
            % the guarded column and reported in the printed count.
            fbOut(i) = NaN;
        else
            fbOut(i) = F.judge_real(j);
        end
        if useSmart; guardOut(i) = smartOut(i); else; guardOut(i) = fbOut(i); end
    end

    ok = ~isnan(guardOut);
    pSmart = mean(smartOut(ok)); pFb = mean(fbOut(ok)); pGuard = mean(guardOut(ok));
    fallbackRate = mean(~usedSmart);

    fprintf('simplexAB: smart = %s, fallback = %s, n_test = %d (%d pairable), predictor %s\n', ...
        smartArm, fallbackArm, nT, nnz(ok), scoreCol);
    fprintf('  conformal qhat = %.4f at %.0f%% nominal coverage\n\n', model.qhat, 100*(1-alpha));
    fprintf('  always-smart     judge real %5.1f%%\n', 100*pSmart);
    fprintf('  always-fallback  judge real %5.1f%%\n', 100*pFb);
    fprintf('  GUARDED          judge real %5.1f%%   (fell back on %5.1f%% of episodes)\n', ...
        100*pGuard, 100*fallbackRate);

    % The acceptance test: on the episodes the guard FLAGGED, did dropping to
    % the fallback actually do at least as well as trusting the smart plan?
    flagged = ok & ~usedSmart;
    if nnz(flagged) == 0
        fprintf('\n  guard never fired -- acceptance test not applicable\n');
        winRate = NaN;
    else
        winRate = mean(fbOut(flagged) >= smartOut(flagged));
        fprintf(['\n  ACCEPTANCE (flagged episodes only, n=%d):\n' ...
                 '    fallback >= smart in %5.1f%% of them   -> %s\n'], ...
            nnz(flagged), 100*winRate, ternary(winRate >= 0.80, 'PASS', 'FAIL'));
    end

    fprintf('\n  guard decisions:\n');
    for rs = unique(reasons)'
        fprintf('    %-20s %3d (%5.1f%%)\n', rs, nnz(reasons==rs), 100*mean(reasons==rs));
    end

    out = struct('smartArm', smartArm, 'fallbackArm', fallbackArm, ...
        'alpha', alpha, 'splitSeed', splitSeed, 'scoreCol', scoreCol, 'model', model, 'nTest', nT, ...
        'pSmart', pSmart, 'pFallback', pFb, 'pGuarded', pGuard, ...
        'fallbackRate', fallbackRate, 'flaggedWinRate', winRate, ...
        'usedSmart', usedSmart, 'reasons', reasons, ...
        'smartOut', smartOut, 'fbOut', fbOut, 'guardOut', guardOut);

    f = fullfile(root, 'results', ['simplex_ab_' smartArm '.mat']);
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s\n', f);
end

function s = ternary(c, a, b)
    if c; s = a; else; s = b; end
end
