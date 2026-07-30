function outFiles = plotDopplerStudy(outDir)
%PLOTDOPPLERSTUDY  Figures + a markdown results table for the Doppler-axis
%   study. Reads results/*.mat; computes no physics of its own.
%
%   outFiles = experiments.plotDopplerStudy(outDir)
%
%   SIX PANELS, one question each:
%     A  P(ECCM says "real") vs episode -- the only axis on which the legacy
%        and the new arms are comparable (see the note on reward scales).
%     B  reward-value structure: what the learner actually had to climb
%     C  the mechanism: screen-2 failure rate vs policy coherence
%     D  trajectory consistency (commanded Doppler vs achieved range walk)
%     E  amplitude-range slope against the physical -2
%     F  real-rate with Wilson 95% CIs -- headroom, with uncertainty
%
%   WHY NOT ONE REWARD CURVE FOR ALL THREE ARMS. The legacy environment and
%   this one have DIFFERENT reward functions (legacy max 2.4, new max 3.0,
%   different terminal ladders). Plotting them on a shared reward axis would
%   imply a comparison that does not exist. They ARE comparable on the
%   OUTCOME -- did the independent ECCM call the phantom real -- so that is
%   the shared axis, recovered per episode from each arm's own reward via
%   its own "real" value. The thresholds are stated in the legend, not hidden.

    if nargin < 1 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results', 'figures');
    end
    if ~isfolder(outDir); mkdir(outDir); end
    root = fileparts(fileparts(mfilename('fullpath')));

    % Okabe-Ito derived, CVD-validated (deutan worst adjacent dE 11.0,
    % normal 24.2) -- see the dataviz validator run in this change's notes.
    COL.legacy   = [0.00 0.45 0.70];   % #0072B2 blue
    COL.noshape  = [0.90 0.62 0.00];   % #E69F00 orange
    COL.shaped   = [0.00 0.62 0.45];   % #009E73 green
    COL.truthful = [0.84 0.37 0.00];   % #D55E00 vermillion
    GREY = [0.45 0.45 0.45];

    arms = {};
    L = localTryLoad(fullfile(root,'results','feature_agent.mat'));
    if ~isempty(L)
        arms{end+1} = struct('name','legacy (no Doppler axis)', 'R', L.episodeReward(:), ...
            'realAt', 2.4, 'tol', 0.05, 'col', COL.legacy, 'diag', []);
    end
    S = localTryLoad(fullfile(root,'results','doppler_agent_shaped.mat'));
    if ~isempty(S)
        arms{end+1} = struct('name','Doppler axis + shaping', 'R', S.episodeReward(:), ...
            'realAt', 3.0, 'tol', 0.20, 'col', COL.shaped, 'diag', S.diagGreedy);
    end
    N = localTryLoad(fullfile(root,'results','doppler_agent_noshape.mat'));
    if ~isempty(N)
        arms{end+1} = struct('name','Doppler axis, no shaping', 'R', N.episodeReward(:), ...
            'realAt', 3.0, 'tol', 0.20, 'col', COL.noshape, 'diag', N.diagGreedy);
    end
    assert(~isempty(arms), 'plotDopplerStudy:noResults', ...
        'No results/*.mat found -- run experiments.runDopplerStudy first.');

    f = figure('Position', [60 60 1560 920], 'Color', 'w');
    try; f.Theme = 'light'; catch; end   %#ok<TRYNC>
    tl = tiledlayout(f, 2, 3, 'TileSpacing','compact', 'Padding','compact');
    title(tl, 'D3QN vs the ECCM: what a measured Doppler axis changes', ...
        'FontWeight','bold','FontSize',14, 'Color', [0.1 0.1 0.1]);

    % ---------- A: P(real) vs episode -------------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    W = 50;
    for i = 1:numel(arms)
        a = arms{i};
        isReal = abs(a.R - a.realAt) <= a.tol;
        p = movmean(double(isReal), W, 'Endpoints','shrink');
        plot(ax, 1:numel(p), 100*p, 'LineWidth', 2, 'Color', a.col, 'DisplayName', a.name);
        text(ax, numel(p), 100*p(end), sprintf('  %.0f%%', 100*p(end)), ...
            'Color', a.col, 'FontSize', 9, 'VerticalAlignment','middle');
    end
    xlabel(ax,'training episode'); ylabel(ax,'P(ECCM verdict = "real")  [%]');
    title(ax, sprintf('A. Deception success, rolling %d episodes', W));
    legend(ax,'Location','northwest','Box','off','FontSize',8,'TextColor',[0.2 0.2 0.2]);
    ylim(ax,[0 108]); experiments.lightAxes(ax);

    % ---------- B: reward-value structure ---------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    for i = 1:numel(arms)
        a = arms{i};
        u = unique(round(a.R,2));
        cnt = arrayfun(@(v) sum(round(a.R,2)==v), u);
        bar(ax, u, 100*cnt/numel(a.R), 0.5, 'FaceColor', a.col, ...
            'EdgeColor','none', 'FaceAlpha', 0.7, 'DisplayName', a.name);
    end
    xlabel(ax,'episode reward'); ylabel(ax,'share of episodes  [%]');
    title(ax,'B. Reward structure the learner had to climb');
    legend(ax,'Location','northeast','Box','off','FontSize',8,'TextColor',[0.2 0.2 0.2]);
    experiments.lightAxes(ax);

    % ---------- C: the mechanism ------------------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    coh = localCoherenceSweep();
    b = bar(ax, [coh.legacyFail(:) coh.measuredFail(:)]*100, 'EdgeColor','none');
    b(1).FaceColor = COL.legacy; b(2).FaceColor = COL.shaped;
    b(1).DisplayName = 'legacy: diff(range) as Doppler';
    b(2).DisplayName = 'measured Doppler axis';
    ax.XTick = 1:numel(coh.labels); ax.XTickLabel = coh.labels;
    ax.XTickLabelRotation = 18;
    ylabel(ax,'screen-2 failure rate  [%]');
    title(ax,'C. Mechanism: can the Doppler screen fail?');
    legend(ax,'Location','northwest','Box','off','FontSize',8,'TextColor',[0.2 0.2 0.2]);
    ylim(ax, [0 max(6, 1.35*100*max([coh.legacyFail(:); coh.measuredFail(:)]))]);
    for i = 1:numel(coh.labels)
        text(ax, i-0.15, coh.legacyFail(i)*100, sprintf(' %.1f%%', coh.legacyFail(i)*100), ...
            'FontSize',8,'HorizontalAlignment','center','VerticalAlignment','bottom', ...
            'Color',COL.legacy);
        text(ax, i+0.15, coh.measuredFail(i)*100, sprintf(' %.1f%%', coh.measuredFail(i)*100), ...
            'FontSize',8,'HorizontalAlignment','center','VerticalAlignment','bottom', ...
            'Color',COL.shaped);
    end
    experiments.lightAxes(ax);

    % ---------- D: trajectory consistency ---------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    [names, vals, cols] = localDiagSeries(arms, 'velConsistency', COL);
    localDotPlot(ax, names, 100*vals, cols);
    xline(ax, 40, '--', 'chance', 'Color', GREY, 'FontSize', 8, ...
        'HandleVisibility','off', 'LabelVerticalAlignment','bottom');
    xlabel(ax,'trajectory consistency  [% of moving frames]');
    title(ax,'D. Does commanded Doppler match the range walk?');
    xlim(ax,[0 118]); experiments.lightAxes(ax);

    % ---------- E: amplitude-range slope ----------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    lg = {};
    for i = 1:numel(arms)
        a = arms{i};
        if isempty(a.diag) || ~isfield(a.diag,'ampSlope'); continue; end
        s = a.diag.ampSlope(~isnan(a.diag.ampSlope));
        if isempty(s); continue; end
        histogram(ax, s, 'BinWidth', 0.5, 'Normalization','probability', ...
            'FaceColor', a.col, 'EdgeColor','none', 'FaceAlpha', 0.6, ...
            'DisplayName', a.name);
        lg{end+1} = a.name; %#ok<AGROW>
    end
    xline(ax, -2, '-', 'physical 1/R^2', 'Color', [0.15 0.15 0.15], ...
        'LineWidth', 1.5, 'FontSize', 8, 'LabelVerticalAlignment','bottom', ...
        'HandleVisibility','off');
    xline(ax, -4, ':', 'screen pass band', 'Color', GREY, 'FontSize', 8, 'HandleVisibility','off');
    xline(ax,  0, ':', '', 'Color', GREY, 'HandleVisibility','off');
    xlabel(ax,'fitted d log(amplitude) / d log(range)'); ylabel(ax,'share of episodes');
    title(ax,'E. Amplitude law vs the physical value');
    if ~isempty(lg)
        legend(ax,'Location','northwest','Box','off','FontSize',8,'TextColor',[0.2 0.2 0.2]);
    end
    xlim(ax,[-8 6]); experiments.lightAxes(ax);

    % ---------- F: real-rate with Wilson CIs ------------------------
    ax = nexttile(tl); hold(ax,'on'); grid(ax,'on');
    [rn, rv, rlo, rhi, rc] = localRealRates(arms, COL);
    for i = 1:numel(rn)
        plot(ax, [100*rlo(i) 100*rhi(i)], [i i], '-', 'Color', rc(i,:), 'LineWidth', 2.5);
        plot(ax, 100*rv(i), i, 'o', 'MarkerSize', 9, 'MarkerFaceColor', rc(i,:), ...
            'MarkerEdgeColor','w', 'LineWidth', 1.2);
        text(ax, 100*rhi(i)+2, i, sprintf('%.1f%%', 100*rv(i)), 'FontSize', 9, ...
            'VerticalAlignment','middle', 'Color', rc(i,:));
    end
    ax.YTick = 1:numel(rn); ax.YTickLabel = rn; ylim(ax,[0.4 numel(rn)+0.6]);
    xlim(ax,[0 122]); xlabel(ax,'episodes labelled "real" by the ECCM  [%, Wilson 95% CI]');
    title(ax,'F. Headroom: random -> learned -> reference');
    experiments.lightAxes(ax);

    outFiles = {};
    pngPath = fullfile(outDir, 'doppler_study.png');
    exportgraphics(f, pngPath, 'Resolution', 150);
    outFiles{end+1} = pngPath;
    fprintf('plotDopplerStudy: wrote %s\n', pngPath);

    mdPath = localWriteMarkdown(outDir, arms, coh);
    outFiles{end+1} = mdPath;
    fprintf('plotDopplerStudy: wrote %s\n', mdPath);
end

% ========================================================================
function s = localTryLoad(p)
    s = [];
    if isfile(p); s = load(p); end
end

% ------------------------------------------------------------------------
function coh = localCoherenceSweep()
%LOCALCOHERENCESWEEP  The measured mechanism behind panel C.
%   For each policy-coherence regime, how often can each construction's
%   screen 2 actually FAIL? The legacy column is the diff(range) construction
%   from buildEnvFeatureConditioned; the measured column is a real range-rate
%   whose sign is set independently of the range walk (a phantom that does
%   not bother to match Doppler), which is the case the screen exists to
%   catch. Pure arithmetic on the screen's own predicate -- no simulation.
    C = physics.Constants();
    rng(7);
    deltaOptions = linspace(-120,120,5);
    velOptions   = linspace(-120,120,5);
    F = 8; R0 = 1800; dt = 1.0; q = C.range_per_sample; nT = 6000;
    coh.labels = {'incoherent','1 direction flip','coherent'};
    coh.legacyFail = zeros(1,3); coh.measuredFail = zeros(1,3);
    for m = 1:3
        lf = 0; mf = 0; nL = 0; nM = 0;
        for t = 1:nT
            switch m
                case 1, d = deltaOptions(randi(5,1,F));
                case 2, d0 = deltaOptions(randi(5)); d = repmat(d0,1,F);
                        d(randi(F)) = deltaOptions(randi(5));
                otherwise, d = repmat(deltaOptions(randi(5)),1,F);
            end
            r = R0; R = zeros(1,F);
            for k = 1:F
                r = min(2950, max(150, r + d(k)));
                R(k) = round(r/q)*q;
            end
            if range(R) < 1e-9; continue; end
            % legacy: Doppler manufactured from the range history
            dd = diff(R)/dt; D = [dd(1), dd];
            if abs(mean(diff(R)))>1e-9 && abs(mean(D))>1e-9
                nL = nL + 1;
                if sign(mean(diff(R))) ~= sign(mean(D)); lf = lf + 1; end
            end
            % measured: an INDEPENDENT commanded velocity, as the new env has
            Dm = repmat(velOptions(randi(5)), 1, F);
            if abs(mean(diff(R)))>1e-9 && abs(mean(Dm))>1e-9
                nM = nM + 1;
                if sign(mean(diff(R))) ~= sign(mean(Dm)); mf = mf + 1; end
            end
        end
        coh.legacyFail(m)   = lf / max(1,nL);
        coh.measuredFail(m) = mf / max(1,nM);
    end
end

% ------------------------------------------------------------------------
function [names, vals, cols] = localDiagSeries(arms, field, COL)
    names = {}; vals = []; cols = [];
    for i = 1:numel(arms)
        a = arms{i};
        if isempty(a.diag) || ~isfield(a.diag, field); continue; end
        names{end+1} = a.name; %#ok<AGROW>
        vals(end+1)  = a.diag.(field); %#ok<AGROW>
        cols(end+1,:) = a.col; %#ok<AGROW>
    end
    ref = localReference();
    if ~isempty(ref)
        names{end+1} = 'truthful reference policy';
        vals(end+1)  = ref.velConsistency;
        cols(end+1,:) = COL.truthful;
    end
end

% ------------------------------------------------------------------------
function localDotPlot(ax, names, vals, cols)
    for i = 1:numel(vals)
        plot(ax, [0 vals(i)], [i i], '-', 'Color', [cols(i,:) 0.35], 'LineWidth', 2);
        plot(ax, vals(i), i, 'o', 'MarkerSize', 9, 'MarkerFaceColor', cols(i,:), ...
            'MarkerEdgeColor','w', 'LineWidth', 1.2);
        text(ax, vals(i)+2, i, sprintf('%.0f%%', vals(i)), 'FontSize', 9, ...
            'VerticalAlignment','middle', 'Color', cols(i,:));
    end
    ax.YTick = 1:numel(names); ax.YTickLabel = names; ylim(ax,[0.4 numel(names)+0.6]);
end

% ------------------------------------------------------------------------
function [names, v, lo, hi, cols] = localRealRates(arms, COL)
    names = {}; v = []; lo = []; hi = []; cols = [];
    ref = localReference();
    if ~isempty(ref) && isfield(ref,'randomRealRate')
        names{end+1} = 'random policy';
        v(end+1) = ref.randomRealRate; lo(end+1) = ref.randomLo; hi(end+1) = ref.randomHi;
        cols(end+1,:) = [0.45 0.45 0.45];
    end
    for i = 1:numel(arms)
        a = arms{i};
        if isempty(a.diag); continue; end
        names{end+1} = a.name; %#ok<AGROW>
        v(end+1) = a.diag.realRate; lo(end+1) = a.diag.realLo; hi(end+1) = a.diag.realHi; %#ok<AGROW>
        cols(end+1,:) = a.col; %#ok<AGROW>
    end
    if ~isempty(ref)
        names{end+1} = 'truthful reference';
        v(end+1) = ref.realRate; lo(end+1) = ref.realLo; hi(end+1) = ref.realHi;
        cols(end+1,:) = COL.truthful;
    end
end

% ------------------------------------------------------------------------
function ref = localReference()
%LOCALREFERENCE  Cached random + truthful baselines on the new env. These
%   are cheap (no training) but not free, so they are computed once per
%   MATLAB session rather than per panel.
    persistent cached
    if ~isempty(cached); ref = cached; return; end
    ref = [];
    try
        C = physics.Constants();
        env = agent.buildEnvDoppler(C);
        dT = experiments.rolloutDopplerEnv(env, 'truthful', 120, 41);
        dR = experiments.rolloutDopplerEnv(env, 'random',   120, 42);
        ref = struct('realRate', dT.realRate, 'realLo', dT.realLo, 'realHi', dT.realHi, ...
            'velConsistency', dT.velConsistency, 'ampSlope', dT.ampSlope, ...
            'randomRealRate', dR.realRate, 'randomLo', dR.realLo, 'randomHi', dR.realHi, ...
            'randomVelCons', dR.velConsistency);
        cached = ref;
    catch ME
        warning('plotDopplerStudy:noReference', 'reference rollouts failed: %s', ME.message);
    end
end

% ------------------------------------------------------------------------
function mdPath = localWriteMarkdown(outDir, arms, coh)
%LOCALWRITEMARKDOWN  The same numbers as a table. The palette validator
%   raised a contrast WARN on one categorical slot, which obligates a
%   non-colour route to the values -- this is it.
    mdPath = fullfile(outDir, 'doppler_study.md');
    fid = fopen(mdPath, 'w');
    c = onCleanup(@() fclose(fid));
    fprintf(fid, '# Doppler-axis study — results\n\n');
    fprintf(fid, 'Generated %s by `experiments.plotDopplerStudy`.\n\n', ...
        datestr(now, 'yyyy-mm-dd HH:MM')); %#ok<TNOW1,DATST>

    fprintf(fid, '## Training arms\n\n');
    fprintf(fid, '| arm | episodes | mean reward | P(real) first 25%% | P(real) last 25%% | trend/ep |\n');
    fprintf(fid, '|---|---|---|---|---|---|\n');
    for i = 1:numel(arms)
        a = arms{i}; R = a.R; n = numel(R); b = max(1,floor(n/4));
        isReal = abs(R - a.realAt) <= a.tol;
        p = polyfit((1:n)', R, 1);
        fprintf(fid, '| %s | %d | %.3f | %.1f%% | %.1f%% | %+.2e |\n', a.name, n, mean(R), ...
            100*mean(isReal(1:b)), 100*mean(isReal(end-b+1:end)), p(1));
    end

    fprintf(fid, '\n## Greedy-policy diagnostics (200-episode rollout)\n\n');
    fprintf(fid, '| arm | P(real) [95%% CI] | confirmed | trajectory consistency | median amp slope |\n');
    fprintf(fid, '|---|---|---|---|---|\n');
    for i = 1:numel(arms)
        a = arms{i};
        if isempty(a.diag); continue; end
        d = a.diag;
        fprintf(fid, '| %s | %.1f%% [%.1f, %.1f] | %.1f%% | %.1f%% | %+.2f |\n', a.name, ...
            100*d.realRate, 100*d.realLo, 100*d.realHi, 100*d.confirmRate, ...
            100*d.velConsistency, d.medianAmpSlope);
    end

    ref = localReference();
    if ~isempty(ref)
        fprintf(fid, '| random policy (baseline) | %.1f%% [%.1f, %.1f] | — | %.1f%% | — |\n', ...
            100*ref.randomRealRate, 100*ref.randomLo, 100*ref.randomHi, 100*ref.randomVelCons);
        fprintf(fid, '| truthful reference policy | %.1f%% [%.1f, %.1f] | — | %.1f%% | — |\n', ...
            100*ref.realRate, 100*ref.realLo, 100*ref.realHi, 100*ref.velConsistency);
    end

    fprintf(fid, '\n## Mechanism: screen-2 failure rate by policy coherence\n\n');
    fprintf(fid, 'Can the Doppler screen punish the agent at all?\n\n');
    fprintf(fid, '| policy coherence | legacy `diff(range)` | measured Doppler |\n');
    fprintf(fid, '|---|---|---|\n');
    for i = 1:numel(coh.labels)
        fprintf(fid, '| %s | %.2f%% | %.2f%% |\n', coh.labels{i}, ...
            100*coh.legacyFail(i), 100*coh.measuredFail(i));
    end
    fprintf(fid, ['\nA coherent policy — what a converged agent produces — fails the legacy ' ...
        'screen **0%% of the time**. Half the ECCM verdict became a free pass exactly as ' ...
        'training converged.\n']);
end
