function tests = test_conformal
%TEST_CONFORMAL  The Assurance Layer's coverage guarantee, on synthetic data
%   where the right answer is known independently of this project's radar.
%
%   These are deliberately NOT radar tests. assurance.conformalFit's claim is
%   a distribution-free statistical one -- "the set contains the truth at
%   least (1-alpha) of the time for exchangeable data" -- so it must be
%   falsifiable without a judge run. If the coverage property only held on
%   this project's own calibration log, it would be a coincidence, not a
%   guarantee. The radar-data version of this check is
%   experiments.conformalValidate.
    tests = functiontests(localfunctions);
end

function test_coverage_holds_on_exchangeable_data(tc)
    % Ground truth drawn as Bernoulli(score) -- the score IS the true
    % probability here, so a well-behaved method must cover at 1-alpha, and
    % a method that forgot the finite-sample (n+1) correction undercovers.
    rng(11);
    alpha = 0.1; n = 400;
    s = rand(n, 1);
    y = rand(n, 1) < s;
    model = assurance.conformalFit(s(1:200), y(1:200), alpha);

    covered = false(200, 1);
    for i = 201:400
        set = assurance.conformalPredict(model, s(i));
        if y(i); covered(i-200) = set(2); else; covered(i-200) = set(1); end
    end
    cov = mean(covered);
    % Wilson upper bound at n=200 is ~+4 pp, so 1-alpha must be reachable.
    tc.verifyGreaterThanOrEqual(cov, 1 - alpha - 0.05, ...
        sprintf('coverage %.3f is below nominal %.2f by more than sampling error', cov, 1-alpha));
end

function test_a_perfect_score_gives_singleton_sets(tc)
    % When belief and outcome agree exactly, every nonconformity score is 0,
    % so qhat is 0 and each set collapses to the one correct label. This is
    % the "engine knows itself" limit -- if it did not produce singletons the
    % predictor could never be confident about anything.
    rng(12);
    n = 200;
    s = [zeros(n/2,1); ones(n/2,1)];
    y = s > 0.5;
    model = assurance.conformalFit(s, y, 0.1);
    [set1, unc1] = assurance.conformalPredict(model, 1.0);
    [set0, unc0] = assurance.conformalPredict(model, 0.0);
    tc.verifyEqual(set1, [false true],  'score 1.0 should give {real} alone');
    tc.verifyEqual(set0, [true false],  'score 0.0 should give {not real} alone');
    tc.verifyFalse(unc1); tc.verifyFalse(unc0);
end

function test_an_uninformative_score_never_commits(tc)
    % A score of 0.5 on every episode with a coin-flip outcome: the belief
    % carries no information, so the honest prediction set is BOTH labels.
    % A predictor that returned a singleton here would be manufacturing
    % confidence out of nothing, which is the failure this layer exists to
    % prevent.
    rng(13);
    n = 200;
    s = 0.5 * ones(n, 1);
    y = rand(n, 1) < 0.5;
    model = assurance.conformalFit(s, y, 0.1);
    [set, unc] = assurance.conformalPredict(model, 0.5);
    tc.verifyEqual(nnz(set), 2, 'an uninformative belief must not yield a singleton');
    tc.verifyTrue(unc);
end

function test_nan_score_is_uncertain(tc)
    % An unscreened episode (fewer than 2 usable frames) has no belief at
    % all. It must not silently inherit whatever the last score was.
    model = assurance.conformalFit([0.2; 0.8], [0; 1], 0.1);
    [set, unc] = assurance.conformalPredict(model, NaN);
    tc.verifyEqual(nnz(set), 2);
    tc.verifyTrue(unc);
end

function test_small_n_saturates_rather_than_undercovering(tc)
    % With n=5 and alpha=0.1, ceil((n+1)*0.9) = 6 > 5: there is not enough
    % calibration data to exclude ANY label at 90%. The correct behaviour is
    % qhat = Inf (always both labels), not a quietly optimistic finite
    % threshold. This is the guard against a confident-looking assurance
    % layer built on a handful of points.
    model = assurance.conformalFit(rand(5,1), rand(5,1) > 0.5, 0.1);
    tc.verifyTrue(model.saturated);
    tc.verifyEqual(model.qhat, Inf);
    tc.verifyEqual(nnz(assurance.conformalPredict(model, 0.99)), 2);
end

function test_mondrian_cannot_repair_a_confidently_wrong_group(tc)
    % Locks the measured result behind experiments.conformalValidate's
    % groupCol path (ASSURANCE_LAYER_RESULTS.md section 6): per-group fitting
    % does NOT repair a group whose belief is MAXIMALLY wrong more often than
    % alpha. It only makes that group abstain.
    %
    % Nonconformity is 1-score when the judge says real and score when it does
    % not, so 1.0 means the belief was maximally wrong -- score 0.0 on a track
    % the judge called real. The structural arm does that on 12.0% of
    % episodes, so at alpha=0.1 the calibrated quantile lands ON 1.0 and every
    % prediction set becomes the whole outcome space. That is arithmetic, not
    % tuning, and this test exists so that nobody "fixes" it by clamping qhat
    % below 1.0 -- which would silently break the coverage guarantee rather
    % than reveal that the belief is the problem.
    n = 100;
    bad  = [ones(12,1); zeros(88,1)] ~= 0;      % 12% maximally wrong
    sBad = [zeros(12,1); 0.95*ones(88,1)];      % score 0.0 while judge=real
    yBad = [true(12,1);  true(88,1)];
    mBad = assurance.conformalFit(sBad, yBad, 0.1);
    tc.verifyEqual(mBad.qhat, 1.0, 'AbsTol', 1e-12, ...
        '12% maximally-wrong at alpha=0.1 must drive qhat to 1.0');
    tc.verifyFalse(mBad.saturated, 'this is not the small-n case -- n is ample');
    tc.verifyEqual(nnz(assurance.conformalPredict(mBad, 0.5)), 2, ...
        'a qhat of 1.0 must yield the whole outcome space -- coverage bought by abstention');

    % Same alpha, same n, a group that is merely imperfect rather than
    % confidently wrong: Mondrian works there, so the failure above is a
    % property of the BELIEF and not of the method.
    sOk = [0.30*ones(12,1); 0.95*ones(88,1)];
    mOk = assurance.conformalFit(sOk, yBad, 0.1);
    tc.verifyLessThan(mOk.qhat, 1.0);
    tc.verifyEqual(nnz(assurance.conformalPredict(mOk, 0.95)), 1, ...
        'a well-behaved group must still commit');
    tc.verifyGreaterThan(mBad.qhat, mOk.qhat);
    assert(numel(bad) == n);   % the 12% figure is the point; keep it visible
end
