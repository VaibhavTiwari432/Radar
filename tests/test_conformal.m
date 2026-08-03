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
