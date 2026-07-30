function outFiles = plotAgilityPredictability(matFile, outDir)
%PLOTAGILITYPREDICTABILITY  Figures for the sweep-schedule prediction study.
%
%   TWO PANELS, and the second one is the answer:
%     A  realised prediction accuracy vs the Bayes ceiling max(p, 1-p).
%        Shows the empirical predictor is already optimal -- there is no
%        headroom for a bigger model to claim.
%     B  deception rate for predict / oracle / stale, with Wilson 95% CIs.
%        Shows what prediction is WORTH, which is the question that matters.
%
%   THE RESULT, stated here because a reader should not have to infer it:
%   for a 2-state (up/down sweep) schedule with persistence p, the
%   Bayes-optimal predictor of the next symbol IS "repeat the last symbol"
%   whenever p > 0.5. A predictive repeater and a naive stale repeater are
%   therefore THE SAME STRATEGY over that whole range, and the measured
%   curves sit on top of each other. At p = 0.5 both collapse to chance
%   together, because an i.i.d. source is unpredictable by proof.
%
%   So on this radar there is no regime where a learned frequency predictor
%   beats the trivial baseline. Making prediction meaningful needs a LARGER
%   HOP SET with exploitable structure (an m-sequence / LFSR over K
%   frequencies, where "repeat last" is worthless but the generator state is
%   learnable) -- not a bigger network against two frequencies.

    if nargin < 1 || isempty(matFile)
        here = fileparts(mfilename('fullpath'));
        matFile = fullfile(fileparts(here), 'results', 'agility_predictability.mat');
    end
    if nargin < 2 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results', 'figures');
    end
    if ~isfolder(outDir); mkdir(outDir); end
    S = load(matFile);

    % Same CVD-validated palette as plotDopplerStudy.
    COL.predict = [0.00 0.45 0.70];
    COL.oracle  = [0.00 0.62 0.45];
    COL.stale   = [0.90 0.62 0.00];
    GREY = [0.45 0.45 0.45];

    p = S.persistences(:);
    n = S.nSeeds;

    f = figure('Position', [80 80 1240 500], 'Color', 'w');
    try; f.Theme = 'light'; catch; end   %#ok<TRYNC>  R2025a theme; pinned below anyway
    tl = tiledlayout(f, 1, 2, 'TileSpacing','compact', 'Padding','compact');
    title(tl, 'Can a DRFM repeater predict an agile radar''s next sweep?', ...
        'FontWeight','bold','FontSize',13, 'Color', [0.1 0.1 0.1]);

    % ---------- A: accuracy vs Bayes ceiling ------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    plot(ax, p, 100*S.bayesCeiling, '--', 'Color', GREY, 'LineWidth', 2, ...
        'DisplayName', 'Bayes ceiling  max(p, 1-p)');
    plot(ax, p, 100*S.predAccuracy, '-o', 'Color', COL.predict, 'LineWidth', 2, ...
        'MarkerSize', 7, 'MarkerFaceColor', COL.predict, 'MarkerEdgeColor','w', ...
        'DisplayName', 'order-1 empirical predictor');
    % Reference lines carry no identity -- kept out of the legend, or they
    % arrive as "data1" and drown the two series that matter.
    yline(ax, 50, ':', 'chance', 'Color', GREY, 'FontSize', 8, 'HandleVisibility','off');
    xlabel(ax, 'schedule persistence  p = P(next sweep == current)');
    ylabel(ax, 'next-sweep prediction accuracy  [%]');
    title(ax, 'A. The predictor is already at the ceiling');
    legend(ax, 'Location','northwest', 'Box','off', 'FontSize', 8, ...
        'TextColor', [0.2 0.2 0.2]);
    ylim(ax, [40 108]); xlim(ax, [min(p)-0.02 max(p)+0.02]);
    experiments.lightAxes(ax);
    text(ax, 0.505, 45.5, sprintf(['i.i.d. source: H(X_{n+1} | history) = 1 bit\n' ...
        '-> 50%% is a proof, not a tuning failure']), 'FontSize', 8, 'Color', GREY);

    % ---------- B: what prediction is worth -------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    cols  = [COL.predict; COL.oracle; COL.stale];
    names = {'predictive repeater','oracle (knows schedule)','stale (replay last frame)'};
    dx = [-0.013 0 0.013];      % small x-offset so overlapping CIs stay readable
    for m = 1:3
        k = S.deceived(:, m);
        [lo, hi] = localWilson(k, n);
        for i = 1:numel(p)
            plot(ax, [p(i) p(i)]+dx(m), 100*[lo(i) hi(i)], '-', ...
                'Color', [cols(m,:) 0.5], 'LineWidth', 2, 'HandleVisibility','off');
        end
        plot(ax, p+dx(m), 100*k/n, '-o', 'Color', cols(m,:), 'LineWidth', 2, ...
            'MarkerSize', 7, 'MarkerFaceColor', cols(m,:), 'MarkerEdgeColor','w', ...
            'DisplayName', names{m});
    end
    xlabel(ax, 'schedule persistence  p');
    ylabel(ax, sprintf('deception rate  [%%, n=%d, Wilson 95%% CI]', n));
    title(ax, 'B. Prediction buys nothing over stale replay');
    legend(ax, 'Location','south', 'Box','off', 'FontSize', 8, ...
        'TextColor', [0.2 0.2 0.2], 'NumColumns', 1);
    ylim(ax, [-5 125]); xlim(ax, [min(p)-0.035 max(p)+0.035]);
    experiments.lightAxes(ax);
    text(ax, 0.5, 118, 'predict and stale coincide for p > 0.5 - they are the same rule', ...
        'FontSize', 8, 'Color', GREY);

    outFiles = {};
    png = fullfile(outDir, 'agility_predictability.png');
    exportgraphics(f, png, 'Resolution', 150);
    outFiles{end+1} = png;
    fprintf('plotAgilityPredictability: wrote %s\n', png);
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
%LOCALWILSON  Wilson score interval -- the project's convention for a
%   proportion (BENCHMARK_RESULTS.md). Correct near 0 and 1 where the normal
%   approximation is not, which is exactly where these counts sit.
    z = 1.959963984540054;
    ph = k(:) / n;
    den = 1 + z^2/n;
    c   = ph + z^2/(2*n);
    hw  = z * sqrt(ph.*(1-ph)/n + z^2/(4*n^2));
    lo = (c - hw)./den; hi = (c + hw)./den;
end
