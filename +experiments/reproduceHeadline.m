function S = reproduceHeadline(T)
%REPRODUCEHEADLINE  Compute and save the project's headline claim + CI.
%                    (POA Part 4, Stage 8; reproducibility)
%
%   S = experiments.reproduceHeadline() runs experiments.runBenchmark in
%   quick mode and derives the headline from its BruteForce rows.
%   S = experiments.reproduceHeadline(T) reuses an already-computed
%   benchmark table (skips re-running the experiment).
%
%   Headline claim: NET evasion rate of a naive DRFM replay against the
%   FULL chain -- raw tracker confirmation AND the Stage 5 ECCM screen --
%   using the best-found (BruteForce) action per seed. A confirmed track
%   that the ECCM then flags does NOT count as a deception success; that
%   is the honest point of Stage 5/7 (see Stage7 quick run: BruteForce
%   confirms 100% of the time, but track.discriminator catches all of it,
%   since a fixed-delay/fixed-gain/zero-Doppler replay is exactly the
%   "naive decoy" signature it's built to catch).
%
%   S.value = mean net evasion rate across seeds
%   S.ci    = [lower upper] 95% CI (normal approximation, n = seeds)
%
%   Saved to results/headline.mat so Stage8_Test can verify a fresh run
%   reproduces the claim within its own CI.

    if nargin < 1 || isempty(T)
        T = experiments.runBenchmark(struct('quick', true));
    end

    bf = T(strcmp(T.Condition, 'BruteForce'), :);
    assert(height(bf) >= 5, 'reproduceHeadline:tooFewSeeds', ...
        'Need >=5 BruteForce seeds to report a headline CI.');

    evasion = 1 - bf.P_rejected_by_ECCM;   % confirmed AND not caught by ECCM
    evasion(isnan(evasion)) = 0;           % never confirmed -> 0% evasion, not undefined

    n = numel(evasion);
    S.value = mean(evasion);
    se = std(evasion) / sqrt(n);
    S.ci = [max(0, S.value - 1.96*se), min(1, S.value + 1.96*se)];
    S.n = n;
    S.description = ['Net evasion rate (confirmed track AND labeled "real", not ' ...
        '"decoy", by track.discriminator) of the best-found CONSTANT per-frame ' ...
        'action (BruteForce), N=' num2str(n) ' seeds. A constant action cannot ' ...
        'vary gain with its own range walk the way DQN''s adaptive policy can, ' ...
        'so this is a lower bound on what the richer action space allows, not ' ...
        'the whole space''s ceiling.'];

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    resultsDir = fullfile(root, 'results');
    if ~isfolder(resultsDir); mkdir(resultsDir); end
    save(fullfile(resultsDir, 'headline.mat'), '-struct', 'S');
end
