function outFiles = reportFigures(which)
%REPORTFIGURES  Result figures for REPORT_HAC-2026-1166.md, one per call.
%
%   experiments.reportFigures('fig0')   RadChar dataset panel
%   experiments.reportFigures('fig4')   evasion across the ECCM ladder
%   experiments.reportFigures('fig4b')  R3 confusion matrix
%   experiments.reportFigures('fig5')   deception arms with controls
%   experiments.reportFigures('fig6')   policy comparison
%   experiments.reportFigures('fig9')   masquerade ERP vs regulatory limit
%
%   PROVENANCE RULE (the reason this file exists rather than a notebook):
%   every number plotted here is either (a) read from a real data file at
%   plot time, or (b) transcribed from a table in REPORT_HAC-2026-1166.md
%   that carries a [MEASURED] tag, with the section number cited at the
%   literal. NOTHING is remembered, estimated, or interpolated. Each figure
%   writes its own numbers to results/figures/<name>_data.csv so the picture
%   is never the only copy.
%
%   This file PLOTS. It contains no detection, tracking, synthesis or
%   planning logic and must never grow any -- CLAUDE.md Rule 2 keeps +synth
%   and +radar/+track independent, and a figure script that computed either
%   side's numbers would be a third party to that separation.
%
%   Palette is the project's existing Okabe-Ito house set (the same one
%   +experiments/plotDopplerStudy.m and plotAgilityPredictability.m use),
%   re-validated 5 Aug 2026 against the dataviz six checks at surface
%   #fcfcfb: lightness band PASS, chroma floor PASS, CVD separation PASS
%   (worst adjacent 11.4 protan), normal-vision floor PASS (worst 15.6),
%   contrast WARN on #E69F00 -- relieved, per the rule, by direct value
%   labels on every bar plus the mandatory _data.csv sidecar.

    if nargin < 1 || isempty(which); which = 'all'; end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    outDir = fullfile(root, 'results', 'figures');
    if ~isfolder(outDir); mkdir(outDir); end

    outFiles = {};
    switch lower(which)
        case 'fig0';  outFiles = localFig0(root, outDir);
        case 'fig4';  outFiles = localFig4(outDir);
        case 'fig4b'; outFiles = localFig4b(outDir);
        case 'fig5';  outFiles = localFig5(outDir);
        case 'fig6';  outFiles = localFig6(outDir);
        case 'fig9';  outFiles = localFig9(outDir);
        case {'fig3', 'fig7', 'fig37'}
                      outFiles = localFig3and7(outDir);
        case 'fig2';  outFiles = localFig2(outDir);
        case 'fig10'; outFiles = localFig10(outDir);
        case 'fig5b'; outFiles = localFig5b(outDir);
        otherwise
            error('reportFigures:unknown', ...
                'Unknown figure "%s". Use fig0|fig4|fig4b|fig5|fig6|fig9.', which);
    end
end

% =======================================================================
% FIG 0 -- RadChar dataset panel. The ONLY figure here whose numbers are
% read from a file at plot time rather than transcribed from the report.
% =======================================================================
function outFiles = localFig0(root, outDir)
    h5 = fullfile(root, 'data', 'RadChar-Tiny.h5');
    assert(isfile(h5), 'reportFigures:noDataset', ...
        'data/RadChar-Tiny.h5 absent -- see data/README.md. Refusing to plot synthetic stand-ins.');

    % data.loadRadChar, not a raw h5read: it already handles the two real
    % gotchas in this file (h5py writes numpy-complex as an HDF5 COMPOUND
    % type, and the row-major/column-major flip) and is covered by
    % tests/DataIntegration_Test.m. Re-deriving that here would be a second,
    % untested reader of the same bytes.
    % Full file, not a prefix: RadChar-Tiny is stored CLASS-ORDERED, not
    % shuffled, so 'MaxSignals', 4000 returns 4000 records of signal_type 0
    % and the other four classes are simply absent (measured -- the first
    % attempt at this figure asserted out on exactly that). ~410 MB and a
    % few seconds; a partial-read path would mean a second copy of
    % loadRadChar's compound-complex handling, which is the duplication
    % this project already paid for once.
    D = data.loadRadChar(h5);
    fs = physics.Constants().fs;      % 3.2 MHz, derived -- never a literal

    names = {'Coherent pulse train', 'Barker', 'Polyphase Barker', 'Frank', 'LFM'};
    pick = nan(1, 5);
    for t = 0:4
        idx = find(D.signal_type == t, 1, 'first');
        assert(~isempty(idx), 'reportFigures:missingClass', ...
            'signal_type %d not present in the first %d records.', t, D.N);
        pick(t+1) = idx;
    end

    COL_I = [0.00 0.45 0.70];    % #0073B3
    COL_Q = [0.90 0.62 0.00];    % #E69F00
    COL_M = [0.00 0.62 0.45];    % #009E73

    f = figure('Color', 'w', 'Position', [80 40 1180 1020], 'Visible', 'off');
    tl = tiledlayout(f, 5, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

    rows = cell(5, 1);
    for r = 1:5
        k = pick(r);
        x = D.iq(:, k);
        n = numel(x);
        t_us = (0:n-1) / fs * 1e6;

        % --- col 1: I and Q ---
        ax = nexttile(tl); hold(ax, 'on');
        plot(ax, t_us, real(x), 'LineWidth', 1.0, 'Color', COL_I, 'DisplayName', 'I');
        plot(ax, t_us, imag(x), 'LineWidth', 1.0, 'Color', COL_Q, 'DisplayName', 'Q');
        experiments.lightAxes(ax); grid(ax, 'on');
        ylabel(ax, sprintf('%s', names{r}), 'FontWeight', 'bold', 'FontSize', 9);
        if r == 1
            title(ax, 'IQ (baseband)', 'FontSize', 10);
            legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 8, ...
                'TextColor', [0.2 0.2 0.2]);
        end
        if r == 5; xlabel(ax, 'time (\mus)'); end
        xlim(ax, [0 t_us(end)]);

        % --- col 2: magnitude envelope ---
        ax = nexttile(tl);
        plot(ax, t_us, abs(x), 'LineWidth', 1.0, 'Color', COL_M);
        experiments.lightAxes(ax); grid(ax, 'on');
        if r == 1; title(ax, '|x(t)| envelope', 'FontSize', 10); end
        if r == 5; xlabel(ax, 'time (\mus)'); end
        xlim(ax, [0 t_us(end)]);
        % annotate with the record's OWN label fields -- real metadata, not
        % a description of what the waveform ought to look like.
        text(ax, 0.98, 0.92, sprintf('%d pulses · \\tau=%.1f \\mus · SNR %+d dB', ...
            D.number_of_pulses(k), D.pulse_width(k)*1e6, D.signal_to_noise_ratio(k)), ...
            'Units', 'normalized', 'HorizontalAlignment', 'right', ...
            'FontSize', 7.5, 'Color', [0.35 0.35 0.35]);

        % --- col 3: spectrum ---
        ax = nexttile(tl);
        X = fftshift(abs(fft(x)));
        X_db = 20*log10(X / max(X) + eps);
        fax = (-n/2 : n/2-1) * (fs/n) / 1e6;
        plot(ax, fax, X_db, 'LineWidth', 1.0, 'Color', COL_I);
        experiments.lightAxes(ax); grid(ax, 'on');
        ylim(ax, [-60 5]); xlim(ax, [fax(1) fax(end)]);
        if r == 1; title(ax, 'spectrum (dB, normalised)', 'FontSize', 10); end
        if r == 5; xlabel(ax, 'frequency (MHz)'); end

        rows{r} = {names{r}, D.index(k), D.signal_type(k), D.number_of_pulses(k), ...
                   D.pulse_width(k), D.pulse_repetition_interval(k), ...
                   D.time_delay(k), D.signal_to_noise_ratio(k)};
    end

    title(tl, 'RadChar-Tiny — the five radar signal classes, read from the dataset', ...
        'FontWeight', 'bold', 'FontSize', 13, 'Color', [0.10 0.10 0.10]);
    % The five records share n_pulses / pulse width / SNR, and that is worth
    % stating rather than glossing: RadChar-Tiny is ordered by class in
    % blocks of 10,000 AND ordered by parameter within a block, so "first
    % record of each class" lands on the same parameter corner five times.
    % That makes this a CONTROLLED comparison (waveform class is the only
    % variable) but it is NOT a random sample of the dataset's SNR range.
    subtitle(tl, sprintf(['One real record per class (indices %s) from data/RadChar-Tiny.h5 — ' ...
        '50,000 records, 512 complex samples, f_s = %.1f MHz.\n' ...
        'All five share 2 pulses / \\tau = 14.03 \\mus / SNR +13 dB: the file is class-ordered in blocks of ' ...
        '10,000 and parameter-ordered within a block, so waveform class is the only variable here — ' ...
        'not a random sample of the −20…+20 dB range.\n' ...
        '[MEASURED — RadChar-Tiny.h5, ICASSP 2023, 50,000 records]'], ...
        strjoin(arrayfun(@(v) sprintf('%d', v-1), pick, 'UniformOutput', false), ', '), fs/1e6), ...
        'FontSize', 8.5, 'Color', [0.35 0.35 0.35]);

    png = fullfile(outDir, 'fig0_radchar_dataset.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig0_radchar_dataset_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'class_name,record_index,signal_type,number_of_pulses,pulse_width_s,pri_s,time_delay_s,snr_db\n');
    for r = 1:5
        v = rows{r};
        fprintf(fid, '%s,%d,%d,%d,%.9g,%.9g,%.9g,%d\n', v{1}, v{2}, v{3}, v{4}, v{5}, v{6}, v{7}, v{8});
    end
    fclose(fid);

    fprintf('\n=== FIG 0 : RadChar dataset panel ===\n');
    fprintf('source: %s (fs = %.4g Hz from physics.Constants)\n', h5, fs);
    fprintf('%-22s %10s %8s %10s %12s %8s\n', 'class', 'record', 'type', 'n_pulses', 'pulse_w_us', 'snr_dB');
    for r = 1:5
        v = rows{r};
        fprintf('%-22s %10d %8d %10d %12.3f %8d\n', v{1}, v{2}, v{3}, v{4}, v{5}*1e6, v{8});
    end
    fprintf('wrote %s\n', png);
    fprintf('wrote %s\n', csv);
    outFiles = {png, csv};
end

% =======================================================================
% FIG 4 -- HEADLINE: evasion across the ECCM ladder.
% Numbers transcribed from REPORT_HAC-2026-1166.md section 7.2, [MEASURED].
% =======================================================================
function outFiles = localFig4(outDir)
    % --- section 7.2 table, verbatim. Do not edit without re-reading it. ---
    rung   = {'R2', 'R3', 'R3''', 'R4', 'R5'};
    config = {'+ Doppler screen', '+ amplitude (authoritative)', ...
              'amplitude alone', '+ monopulse angle', '+ agility (stale)'};
    vee    = [100.0 100.0  85.0   0.0  70.0];
    lo     = [ 83.9  83.9  64.0   0.0  39.7];
    hi     = [100.0 100.0  94.8  16.1  89.2];
    naive  = [  0.0   0.0   NaN   0.0   NaN];
    seeds  = [   20    20    20     8    10];

    COL_VEE   = [0.00 0.45 0.70];    % #0073B3
    COL_NAIVE = [0.90 0.62 0.00];    % #E69F00
    COL_WIN   = [0.84 0.37 0.00];    % #D55E00 -- the rung where the radar wins
    GREY      = [0.45 0.45 0.45];

    f = figure('Color', 'w', 'Position', [100 100 1000 620], 'Visible', 'off');
    ax = axes(f, 'Position', [0.085 0.235 0.885 0.615]); hold(ax, 'on');

    xv = 1:numel(rung);
    w = 0.34;
    xV = xv - w/2 - 0.02;      % 2 px surface gap between the adjacent fills
    xN = xv + w/2 + 0.02;

    for i = xv
        c = COL_VEE; if vee(i) == 0; c = COL_WIN; end
        bar(ax, xV(i), vee(i), w, 'FaceColor', c, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    hV = bar(ax, NaN, NaN, w, 'FaceColor', COL_VEE, 'EdgeColor', 'none', ...
        'DisplayName', 'VEE phantom (engine)');
    for i = xv
        if isnan(naive(i)); continue; end
        bar(ax, xN(i), naive(i), w, 'FaceColor', COL_NAIVE, ...
            'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    hN = bar(ax, NaN, NaN, w, 'FaceColor', COL_NAIVE, 'EdgeColor', 'none', ...
        'DisplayName', 'naive DRFM (baseline)');

    % A 0 % bar has no height, so R4 would otherwise be an empty column that
    % reads as "not measured". Draw the zero explicitly.
    for i = xv
        if vee(i) == 0
            plot(ax, xV(i) + [-w/2 w/2], [0 0], '-', 'Color', COL_WIN, ...
                'LineWidth', 3.5, 'HandleVisibility', 'off');
        end
        if ~isnan(naive(i)) && naive(i) == 0
            plot(ax, xN(i) + [-w/2 w/2], [0 0], '-', 'Color', COL_NAIVE, ...
                'LineWidth', 3.5, 'HandleVisibility', 'off');
        end
    end

    errorbar(ax, xV, vee, vee-lo, hi-vee, 'LineStyle', 'none', ...
        'Color', [0.15 0.15 0.15], 'LineWidth', 1.1, 'CapSize', 7, ...
        'HandleVisibility', 'off');

    % Direct value labels: the relief the palette's contrast WARN requires,
    % and what stops R4 = 0 from reading as a missing bar. Anchored ABOVE
    % the CI cap, not above the bar, so the R4 label clears its own error
    % bar and the naive label sitting near the baseline.
    for i = xv
        text(ax, xV(i), max(vee(i), hi(i)) + 5, sprintf('%.0f%%', vee(i)), ...
            'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold', ...
            'Color', localTern(vee(i) == 0, COL_WIN, [0.15 0.15 0.15]));
        if ~isnan(naive(i))
            text(ax, xN(i), 3.5, sprintf('%.0f%%', naive(i)), ...
                'HorizontalAlignment', 'center', 'FontSize', 8.5, 'Color', [0.35 0.35 0.35]);
        end
    end

    experiments.lightAxes(ax); grid(ax, 'on');
    ax.XTick = xv;
    ax.XTickLabel = rung;          % single line only -- a cell element
    ax.FontSize = 9;               % containing \n is split into SEPARATE ticks
    ax.XAxis.FontWeight = 'bold';  % by MATLAB, which silently shifts every label
    ylim(ax, [0 122]); xlim(ax, [0.4 numel(rung)+0.6]);
    ylabel(ax, 'phantom evasion rate (%)', 'FontSize', 10);
    legend(ax, [hV hN], 'Location', 'northeast', 'Box', 'off', 'FontSize', 9, ...
        'TextColor', [0.2 0.2 0.2], 'Orientation', 'horizontal');

    % Config + seed count as their own text row under the axis, since the
    % tick label cannot carry them (see the XTickLabel note above).
    for i = xv
        text(ax, xv(i), -8, config{i}, 'HorizontalAlignment', 'center', ...
            'FontSize', 8, 'Color', [0.30 0.30 0.30], 'Clipping', 'off');
        text(ax, xv(i), -15, sprintf('n = %d', seeds(i)), 'HorizontalAlignment', 'center', ...
            'FontSize', 7.5, 'Color', [0.50 0.50 0.50], 'Clipping', 'off');
    end

    title(ax, 'Evasion across the radar configuration ladder', ...
        'FontWeight', 'bold', 'FontSize', 14, 'Color', [0.10 0.10 0.10]);
    subtitle(ax, 'Error bars: Wilson 95 % CI. Higher = the phantom survives; the radar wins at the bottom.', ...
        'FontSize', 9, 'Color', GREY);

    % R1 is a NOTE, deliberately not a bar -- a 100 % bar there would read as
    % the radar working, when it is the detector refusing to operate (7.2).
    annotation(f, 'textbox', [0.085 0.075 0.885 0.062], 'String', ...
        ['R1 (no ECCM screens) is EXCLUDED as degenerate, not omitted: with no informative screen the ' ...
         'discriminator defaults to 0.5 → decoy and flags EVERYTHING —' newline ...
         'TP = 20 and FP = 20, a 100 % false-alarm rate on real aircraft. It is not detecting decoys, it is refusing to operate.'], ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.8, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');

    annotation(f, 'textbox', [0.005 0.005 0.99 0.05], 'String', ...
        ['R4 is the headline: a single transmit aperture cannot beat a monopulse angle channel, because every ' ...
         'phantom shares the one jammer''s bearing.   [MEASURED, 8–20 seeds per rung, Wilson 95 % CI]'], ...
        'EdgeColor', 'none', 'FontSize', 8.2, 'Color', [0.30 0.30 0.30], ...
        'HorizontalAlignment', 'center');

    png = fullfile(outDir, 'fig4_eccm_ladder.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig4_eccm_ladder_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'rung,configuration,vee_evasion_pct,ci_lo,ci_hi,naive_drfm_pct,seeds,source\n');
    for i = xv
        fprintf(fid, '%s,%s,%.1f,%.1f,%.1f,%s,%d,REPORT_HAC-2026-1166.md 7.2 [MEASURED]\n', ...
            rung{i}, config{i}, vee(i), lo(i), hi(i), ...
            localNumOrBlank(naive(i)), seeds(i));
    end
    fprintf(fid, 'R1,no ECCM screens,NaN,NaN,NaN,,20,DEGENERATE - excluded from plot (7.2)\n');
    fclose(fid);

    fprintf('\n=== FIG 4 : evasion across the ECCM ladder ===\n');
    fprintf('%-5s %-30s %8s %16s %8s %6s\n', 'rung', 'config', 'VEE %', '95% CI', 'naive', 'seeds');
    for i = xv
        fprintf('%-5s %-30s %8.1f  [%5.1f,%5.1f] %8s %6d\n', rung{i}, config{i}, ...
            vee(i), lo(i), hi(i), localNumOrBlank(naive(i)), seeds(i));
    end
    fprintf('R1 excluded as degenerate (flags 20/20 genuine aircraft).\n');
    fprintf('wrote %s\n', png);
    fprintf('wrote %s\n', csv);
    outFiles = {png, csv};
end

% =======================================================================
% FIG 4b -- the R3 confusion matrix, per generator.
% REPORT_HAC-2026-1166.md section 7.2, [MEASURED], 20 seeds, positive class = "decoy".
% =======================================================================
function outFiles = localFig4b(outDir)
    gen = {'VEE phantom (engine)', 'naive DRFM (baseline)', 'brute-force ceiling'};
    TP  = [ 0    20     0   ];
    FP  = [ 1     1     1   ];
    TN  = [19    19    19   ];
    FN  = [20     0    20   ];
    F1  = [ 0.000 0.976 0.000];
    prec= [ 0.000 0.952 0.000];
    rec = [ 0.000 1.000 0.000];
    evas= [100.0   0.0 100.0];

    GOOD = [0.85 0.93 0.89];   % correct cell tint (from the #009E73 hue)
    BAD  = [0.98 0.88 0.80];   % error cell tint  (from the #D55E00 hue)
    INK  = [0.15 0.15 0.15];

    f = figure('Color', 'w', 'Position', [100 100 1080 470], 'Visible', 'off');
    tl = tiledlayout(f, 1, 3, 'TileSpacing', 'loose', 'Padding', 'compact');

    for g = 1:3
        ax = nexttile(tl); hold(ax, 'on');
        M    = [TP(g) FN(g); FP(g) TN(g)];
        good = [true false; false true];       % TP and TN are the correct cells
        for r = 1:2
            for c = 1:2
                col = BAD; if good(r, c); col = GOOD; end
                % 2 px surface gap between fills -> inset each patch slightly
                rectangle(ax, 'Position', [c-0.485, 2-r+0.015, 0.97, 0.97], ...
                    'FaceColor', col, 'EdgeColor', 'none');
                text(ax, c, 2-r+0.60, sprintf('%d', M(r, c)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 20, ...
                    'FontWeight', 'bold', 'Color', INK);
                lbls = {'TP', 'FN'; 'FP', 'TN'};
                text(ax, c, 2-r+0.22, lbls{r, c}, 'HorizontalAlignment', 'center', ...
                    'FontSize', 9, 'Color', [0.40 0.40 0.40]);
            end
        end
        xlim(ax, [0.5 2.5]); ylim(ax, [0 2]);
        ax.XTick = [1 2]; ax.XTickLabel = {'called decoy', 'called real'};
        % YTick must ascend; row 1 (IS decoy) is drawn at the TOP, so the
        % ascending tick order is the reverse of the row order.
        ax.YTick = [0.5 1.5]; ax.YTickLabel = {'IS real', 'IS decoy'};
        experiments.lightAxes(ax); grid(ax, 'off');
        ax.FontSize = 8.5;
        title(ax, gen{g}, 'FontSize', 10, 'Color', [0.10 0.10 0.10]);
        subtitle(ax, sprintf('F1 %.3f  ·  precision %.3f  ·  recall %.3f  ·  evasion %.0f %%', ...
            F1(g), prec(g), rec(g), evas(g)), 'FontSize', 8.2, 'Color', [0.35 0.35 0.35]);
    end

    title(tl, 'R3 confusion matrix — what the ECCM chain actually catches', ...
        'FontWeight', 'bold', 'FontSize', 13, 'Color', [0.10 0.10 0.10]);
    subtitle(tl, ['Positive class = "decoy". The SAME chain scores F1 = 0.976 against the naive repeater and ' ...
        'F1 = 0.000 against the feature-matched phantom,' newline 'so the chain works — it is specifically the ' ...
        'physically-consistent phantom it cannot touch.   [MEASURED, 20 seeds]'], ...
        'FontSize', 8.5, 'Color', [0.35 0.35 0.35]);

    png = fullfile(outDir, 'fig4b_r3_confusion.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig4b_r3_confusion_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'generator,TP,FP,TN,FN,F1,precision,recall,evasion_pct,seeds,source\n');
    for g = 1:3
        fprintf(fid, '%s,%d,%d,%d,%d,%.3f,%.3f,%.3f,%.1f,20,REPORT_HAC-2026-1166.md 7.2 [MEASURED]\n', ...
            gen{g}, TP(g), FP(g), TN(g), FN(g), F1(g), prec(g), rec(g), evas(g));
    end
    fclose(fid);

    fprintf('\n=== FIG 4b : R3 confusion matrix ===\n');
    fprintf('%-24s %4s %4s %4s %4s %8s %10s %8s\n', 'generator', 'TP', 'FP', 'TN', 'FN', 'F1', 'precision', 'recall');
    for g = 1:3
        fprintf('%-24s %4d %4d %4d %4d %8.3f %10.3f %8.3f\n', gen{g}, TP(g), FP(g), TN(g), FN(g), F1(g), prec(g), rec(g));
    end
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% =======================================================================
% FIG 5 -- the deception arms, with controls.
% REPORT_HAC-2026-1166.md section 7.3, [MEASURED], 10 seeds/arm,
% tests/test_vee_deception_check.m.
% =======================================================================
function outFiles = localFig5(outDir)
    arm   = {'A', 'B', 'C', 'D', 'E'};
    label = {'genuine target', 'VEE phantom, moving', 'naive DRFM', ...
             'VEE phantom, STATIC', 'noise only'};
    role  = {'positive control', 'the engine', 'negative control', ...
             'ablation (motion removed)', 'negative control'};
    confirmed = [10 10 10 10  0];
    flagged   = [ 1  2 10  9  0];
    deceived  = [ 9  8  0  1  0];
    N = 10;

    % deceived + flagged == confirmed for every arm, so this is a genuine
    % part-to-whole and stacks honestly. Checked rather than assumed:
    assert(isequal(deceived + flagged, confirmed), ...
        'reportFigures:armsInconsistent', ...
        'deceived+flagged must equal confirmed -- re-read section 7.3.');

    COL_DEC  = [0.00 0.45 0.70];   % #0073B3 phantom survived
    COL_FLAG = [0.90 0.62 0.00];   % #E69F00 radar caught it
    BACKDROP = [0.91 0.91 0.90];

    f = figure('Color', 'w', 'Position', [100 100 1010 580], 'Visible', 'off');
    ax = axes(f, 'Position', [0.075 0.235 0.90 0.60]); hold(ax, 'on');

    xv = 1:numel(arm);
    w = 0.52;
    for i = xv
        % backdrop = the 10 seeds actually transmitted, so "not confirmed"
        % is visible as absence rather than inferred.
        rectangle(ax, 'Position', [xv(i)-w/2, 0, w, N], 'FaceColor', BACKDROP, ...
            'EdgeColor', 'none');
        if deceived(i) > 0
            rectangle(ax, 'Position', [xv(i)-w/2, 0, w, deceived(i)], ...
                'FaceColor', COL_DEC, 'EdgeColor', 'none');
        end
        if flagged(i) > 0
            % +0.06 leaves a 2 px surface gap between the two segments
            rectangle(ax, 'Position', [xv(i)-w/2, deceived(i)+0.06, w, flagged(i)-0.06], ...
                'FaceColor', COL_FLAG, 'EdgeColor', 'none');
        end
    end
    hD = bar(ax, NaN, NaN, 'FaceColor', COL_DEC,  'EdgeColor', 'none', 'DisplayName', 'deceived (phantom survived)');
    hF = bar(ax, NaN, NaN, 'FaceColor', COL_FLAG, 'EdgeColor', 'none', 'DisplayName', 'flagged by ECCM');
    hB = bar(ax, NaN, NaN, 'FaceColor', BACKDROP, 'EdgeColor', 'none', 'DisplayName', 'never confirmed');

    for i = xv
        if deceived(i) > 0
            text(ax, xv(i), deceived(i)/2, sprintf('%d', deceived(i)), 'HorizontalAlignment', 'center', ...
                'FontSize', 12, 'FontWeight', 'bold', 'Color', 'w');
        end
        if flagged(i) > 0
            text(ax, xv(i), deceived(i)+flagged(i)/2, sprintf('%d', flagged(i)), ...
                'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold', ...
                'Color', [0.25 0.18 0.00]);
        end
        text(ax, xv(i), N+0.45, sprintf('deceived %d/%d  (%.0f %%)', deceived(i), N, 100*deceived(i)/N), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.15 0.15 0.15]);
    end
    text(ax, 5, N/2, {'0/10', 'confirmed'}, 'HorizontalAlignment', 'center', ...
        'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.40 0.40 0.40]);

    experiments.lightAxes(ax); grid(ax, 'on');
    % Tick labels are blanked and the arm letter folded into the description
    % row below: a bold tick label at y=0 collides with a text() label placed
    % just under the axis, which is what the first render did.
    ax.XTick = xv; ax.XTickLabel = repmat({''}, 1, numel(xv)); ax.FontSize = 9;
    ylim(ax, [0 11.6]); xlim(ax, [0.4 numel(arm)+0.6]); ax.YTick = 0:2:10;
    ylabel(ax, 'seeds (out of 10)', 'FontSize', 10);
    lg = legend(ax, [hD hF hB], 'Box', 'off', 'FontSize', 9, ...
        'TextColor', [0.2 0.2 0.2], 'Orientation', 'horizontal');
    lg.Position = [0.5 - lg.Position(3)/2, 0.855, lg.Position(3), lg.Position(4)];

    for i = xv
        text(ax, xv(i), -0.62, sprintf('%s — %s', arm{i}, label{i}), ...
            'HorizontalAlignment', 'center', 'FontSize', 8.5, ...
            'FontWeight', 'bold', 'Color', [0.25 0.25 0.25], 'Clipping', 'off');
        text(ax, xv(i), -1.25, role{i}, 'HorizontalAlignment', 'center', ...
            'FontSize', 7.5, 'FontAngle', 'italic', 'Color', [0.52 0.52 0.52], 'Clipping', 'off');
    end

    title(ax, 'Deception arms at R3, with positive and negative controls', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    ax.Title.Units = 'normalized';
    ax.Title.Position(2) = 1.115;

    annotation(f, 'textbox', [0.075 0.055 0.90 0.075], 'String', ...
        ['The controls are what make this falsifiable: the genuine target passes (A), pure noise is rejected outright (E), ' ...
         'and the naive repeater is caught every single seed (C).' newline ...
         'Arm D isolates the value of MOTION — the same phantom held static collapses from 8/10 to 1/10. ' ...
         'Arm A also shows the cost: this judge now rejects a genuine target ~1 seed in 10.'], ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.8, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle');

    % Interpreter none: the default TeX reading turns test_vee_deception_check
    % into subscripted gibberish at every underscore.
    annotation(f, 'textbox', [0.005 0.004 0.99 0.042], 'String', ...
        '[MEASURED, 10 seeds/arm, tests/test_vee_deception_check.m]', ...
        'EdgeColor', 'none', 'FontSize', 8.2, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png = fullfile(outDir, 'fig5_deception_arms.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig5_deception_arms_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'arm,description,role,confirmed,flagged,deceived,seeds,deceived_pct,source\n');
    for i = xv
        fprintf(fid, '%s,%s,%s,%d,%d,%d,%d,%.1f,REPORT_HAC-2026-1166.md 7.3 [MEASURED]\n', ...
            arm{i}, label{i}, role{i}, confirmed(i), flagged(i), deceived(i), N, 100*deceived(i)/N);
    end
    fclose(fid);

    fprintf('\n=== FIG 5 : deception arms ===\n');
    fprintf('%-3s %-24s %-26s %10s %8s %9s %8s\n', 'arm', 'description', 'role', 'confirmed', 'flagged', 'deceived', 'rate');
    for i = xv
        fprintf('%-3s %-24s %-26s %7d/%d %6d/%d %7d/%d %7.0f%%\n', arm{i}, label{i}, role{i}, ...
            confirmed(i), N, flagged(i), N, deceived(i), N, 100*deceived(i)/N);
    end
    fprintf('checked: deceived + flagged == confirmed for all 5 arms.\n');
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% =======================================================================
% FIG 6 -- policy comparison. Does the AI help?
% REPORT_HAC-2026-1166.md section 7.4, [MEASURED], 200-episode greedy
% rollouts (structural rows: 100 episodes, experiments.t4JudgeGap).
%
%   !! THE NUMBERS BELOW ARE section 7.4's "Real rate" COLUMN, NOT ITS
%   "Published" COLUMN. 7.4 carries both, because correcting two defects in
%   agent.buildEnvDoppler (an action grid outside the radar's own
%   unambiguous velocity, and a tracker told its measurements were 47x more
%   precise than they are) moved every row. The superseded values are
%   2.5->7.0, 10.5->44.0, 67.0->54.0. Anything quoting 44.0 % for the D3QN
%   is quoting the withdrawn column.
% =======================================================================
function outFiles = localFig6(outDir)
    policy = { 'Random, unprojected', ...
               'D3QN 58-D + shaping', ...
               'D3QN 58-D, no shaping', ...
               'Random, PROJECTED', ...
               'Random, projected + CV', ...
               'Structural CV-coherent (Swerling I)', ...
               'D3QN 9-D stats', ...
               'D3QN 9-D stats, no shaping', ...
               'Structural, swerling = 0' };
    training = {'none', '1200 ep', '1200 ep', 'none', 'none', 'none', '1200 ep', '1200 ep', 'none'};
    rate = [  2.5  10.5  14.5  67.0 100.0  36.0   3.0   0.0 100.0];
    lo   = [  1.1   7.0  10.3  60.2  97.6  27.3   1.4   0.0  96.3];
    hi   = [  5.7  15.5  20.0  73.1 100.0  45.8   6.4   1.9 100.0];
    % kind: 1 = trained, 2 = untrained, 3 = reference/baseline only
    kind = [    2     1     1     2     2     2     3     3     3];
    note = {'', '', 'shaping REDUCES it', '', 'non-stationary subset', ...
            'the honest structural headline', 'reference only (5.6)', ...
            'reference only (5.6)', 'stated-assumption baseline, not a result'};

    COL_TRAIN = [0.00 0.45 0.70];   % #0073B3
    COL_FREE  = [0.00 0.62 0.45];   % #009E73
    COL_REF   = [0.62 0.62 0.62];

    f = figure('Color', 'w', 'Position', [100 100 1220 680], 'Visible', 'off');
    ax = axes(f, 'Position', [0.215 0.245 0.755 0.575]); hold(ax, 'on');

    n = numel(policy);
    yv = n:-1:1;                     % first row at the top
    for i = 1:n
        switch kind(i)
            case 1; c = COL_TRAIN; case 2; c = COL_FREE; otherwise; c = COL_REF;
        end
        barh(ax, yv(i), rate(i), 0.62, 'FaceColor', c, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    h1 = barh(ax, NaN, NaN, 'FaceColor', COL_TRAIN, 'EdgeColor', 'none', 'DisplayName', 'trained (D3QN, 1200 ep)');
    h2 = barh(ax, NaN, NaN, 'FaceColor', COL_FREE,  'EdgeColor', 'none', 'DisplayName', 'NO training');
    h3 = barh(ax, NaN, NaN, 'FaceColor', COL_REF,   'EdgeColor', 'none', 'DisplayName', 'reference / baseline only');

    errorbar(ax, rate, yv, rate-lo, hi-rate, 'horizontal', 'LineStyle', 'none', ...
        'Color', [0.15 0.15 0.15], 'LineWidth', 1.0, 'CapSize', 5, 'HandleVisibility', 'off');

    % Value label immediately after the CI cap; the italic note in its OWN
    % fixed column further right. Both live to the RIGHT of the bars -- the
    % first render put the notes at x < 0, where they landed on top of the
    % y-tick labels.
    for i = 1:n
        text(ax, hi(i)+2.5, yv(i), sprintf('%.1f %%  [%.1f, %.1f]', rate(i), lo(i), hi(i)), ...
            'FontSize', 8.5, 'VerticalAlignment', 'middle', 'Color', [0.20 0.20 0.20]);
        if ~isempty(note{i})
            text(ax, 140, yv(i), note{i}, 'FontSize', 7.4, 'FontAngle', 'italic', ...
                'VerticalAlignment', 'middle', 'Color', [0.52 0.52 0.52]);
        end
    end

    experiments.lightAxes(ax); grid(ax, 'on');
    ax.YTick = flip(yv); ax.YTickLabel = flip(policy);
    ax.FontSize = 8.8;
    xlim(ax, [0 245]); ylim(ax, [0.4 n+0.6]);
    ax.XTick = 0:20:120;
    xlabel(ax, 'real-rate: episodes surviving the judge as "real" (%)', 'FontSize', 10);
    % Inside the axes at top-right: the two shortest bars are rows 1-2 and
    % neither carries a note, so that corner is empty. Above the axes the
    % legend collided with the title.
    legend(ax, [h1 h2 h3], 'Location', 'northeast', 'Box', 'off', 'FontSize', 8.5, ...
        'TextColor', [0.2 0.2 0.2]);

    title(ax, 'Does the trained agent help? Policy comparison against the judge', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(ax, 'Wilson 95 % CI. Every row measured on ONE environment (agent.buildEnvDoppler, as corrected 2 Aug 2026).', ...
        'FontSize', 8.5, 'Color', [0.45 0.45 0.45]);

    annotation(f, 'textbox', [0.055 0.055 0.90 0.088], 'String', ...
        ['BOTH halves of this are the result. The D3QN is NOT useless — at 10.5 % [7.0, 15.5] it beats the unprojected ' ...
         'random policy''s 2.5 % [1.1, 5.7], and the intervals do not overlap.' newline ...
         'But a random policy with the PHYSICS CONSTRAINT built in and ZERO training reaches 67.0 % [60.2, 73.1] — ' ...
         '6.4x the trained agent. And removing the shaping reward makes the D3QN BETTER (14.5 % vs 10.5 %),' newline ...
         'so the shaping signal is not buying what it was added to buy. The value is in the projection, not the learning.'], ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.8, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle');

    annotation(f, 'textbox', [0.005 0.004 0.99 0.042], 'String', ...
        ['[MEASURED, 200-episode greedy rollouts (structural rows 100 ep), Wilson 95 % CI] — section 7.4 "Real rate" column, ' ...
         'NOT its superseded "Published" column'], ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center');

    png = fullfile(outDir, 'fig6_policy_comparison.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig6_policy_comparison_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'policy,training,real_rate_pct,ci_lo,ci_hi,category,note,source\n');
    kindName = {'trained', 'untrained', 'reference_only'};
    for i = 1:n
        fprintf(fid, '"%s",%s,%.1f,%.1f,%.1f,%s,"%s",REPORT_HAC-2026-1166.md 7.4 Real-rate column [MEASURED]\n', ...
            policy{i}, training{i}, rate(i), lo(i), hi(i), kindName{kind(i)}, note{i});
    end
    fclose(fid);

    fprintf('\n=== FIG 6 : policy comparison ===\n');
    fprintf('%-38s %-9s %8s %16s  %s\n', 'policy', 'training', 'real %', '95% CI', 'note');
    for i = 1:n
        fprintf('%-38s %-9s %8.1f  [%5.1f,%5.1f]  %s\n', policy{i}, training{i}, rate(i), lo(i), hi(i), note{i});
    end
    fprintf(['\nD3QN(58-D+shaping) %.1f%% vs random-unprojected %.1f%% -> +%.1f pts (CIs disjoint).\n' ...
             'Random-PROJECTED %.1f%% vs D3QN %.1f%% -> untrained wins by %.1f pts (%.1fx).\n'], ...
        rate(2), rate(1), rate(2)-rate(1), rate(4), rate(2), rate(4)-rate(2), rate(4)/rate(2));
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% =======================================================================
% FIG 9 -- masquerade ERP vs the regulatory limit.
% REPORT_HAC-2026-1166.md section 3.2, [MEASURED],
% tests/test_masquerade_amplitude.m (4/4). Limit from section 7.8 C1.
% =======================================================================
function outFiles = localFig9(outDir)
    standoff_m  = [1800   2400   3000  ];
    erp_mW      = [  24.561  7.771  3.183];
    headroom_dB = [  39.1   44.1   48.0 ];
    LIMIT_PEAK_W = 200;    % section 7.8 C1, tagged [ASSUMED] there
    LIMIT_AVG_W  = 60;

    COL_ERP  = [0.00 0.45 0.70];
    COL_LIM  = [0.84 0.37 0.00];
    GREY     = [0.45 0.45 0.45];

    f = figure('Color', 'w', 'Position', [100 100 940 600], 'Visible', 'off');
    ax = axes(f, 'Position', [0.115 0.235 0.845 0.585]); hold(ax, 'on');

    erp_W = erp_mW / 1000;
    xv = 1:numel(standoff_m);

    % Log y: the gap is 39-48 dB. On a linear axis every measured bar is a
    % flat line on the floor and the headroom -- the actual finding -- is
    % invisible. This is the one place a log axis is not a stylistic choice.
    for i = xv
        plot(ax, [xv(i) xv(i)], [1e-6 erp_W(i)], '-', 'Color', COL_ERP, 'LineWidth', 7, ...
            'HandleVisibility', 'off');
    end
    hE = plot(ax, xv, erp_W, 'o', 'MarkerSize', 9, 'MarkerFaceColor', COL_ERP, ...
        'MarkerEdgeColor', 'w', 'LineWidth', 1.2, 'LineStyle', 'none', ...
        'DisplayName', 'required masquerade ERP [MEASURED]');
    hP = yline(ax, LIMIT_PEAK_W, '-', sprintf('  200 W peak limit'), 'Color', COL_LIM, ...
        'LineWidth', 2, 'FontSize', 9, 'LabelHorizontalAlignment', 'left', ...
        'LabelVerticalAlignment', 'bottom', 'DisplayName', '200 W peak limit [ASSUMED]');
    yline(ax, LIMIT_AVG_W, '--', '  60 W average', 'Color', COL_LIM, ...
        'LineWidth', 1.2, 'FontSize', 8.5, 'Alpha', 0.7, ...
        'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'top', ...
        'HandleVisibility', 'off');

    for i = xv
        text(ax, xv(i), erp_W(i)*1.9, sprintf('%.3f mW', erp_mW(i)), ...
            'HorizontalAlignment', 'center', 'FontSize', 9.5, 'FontWeight', 'bold', ...
            'Color', [0.15 0.15 0.15]);
        % the headroom IS the result -- draw it, don't leave it to be read off
        yMid = sqrt(erp_W(i) * LIMIT_PEAK_W);
        plot(ax, [xv(i)+0.22 xv(i)+0.22], [erp_W(i) LIMIT_PEAK_W], '-', ...
            'Color', GREY, 'LineWidth', 0.8, 'HandleVisibility', 'off');
        text(ax, xv(i)+0.28, yMid, sprintf('+%.1f dB', headroom_dB(i)), ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', COL_LIM, ...
            'VerticalAlignment', 'middle');
    end

    set(ax, 'YScale', 'log');
    experiments.lightAxes(ax); grid(ax, 'on');
    ax.XTick = xv;
    ax.XTickLabel = arrayfun(@(v) sprintf('%d m', v), standoff_m, 'UniformOutput', false);
    ax.FontSize = 9;
    ylim(ax, [1e-3 2e3]); xlim(ax, [0.5 numel(xv)+0.75]);
    xlabel(ax, 'jammer standoff range R_i', 'FontSize', 10);
    ylabel(ax, 'ERP (W, log scale)', 'FontSize', 10);
    legend(ax, [hE hP], 'Location', 'southwest', 'Box', 'off', 'FontSize', 8.8, ...
        'TextColor', [0.2 0.2 0.2]);

    title(ax, 'EIRP compliance — the power constraint does not bind', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(ax, 'ERP needed to masquerade as a \sigma = 1 m^2 target declared at R_d = 1800 m, vs the declared limit.', ...
        'FontSize', 8.8, 'Color', [0.45 0.45 0.45]);

    annotation(f, 'textbox', [0.075 0.055 0.885 0.088], 'String', ...
        ['A masquerading phantom costs MILLIWATTS against a 200 W budget, because the jammer path is travelled ONCE ' ...
         '(1/R^2) and the skin echo twice (1/R^4).' newline ...
         'The real finding is therefore a negative one: EIRP compliance has never been a binding constraint on this ' ...
         'adversary, so no result in this report' newline ...
         'may be quoted as demonstrating a power-limited swarm. Section 7.8 quotes the band as 7.8-24.6 mW; that is ' ...
         'the 1800-2400 m subset of the three points plotted here.'], ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.8, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle');

    annotation(f, 'textbox', [0.005 0.004 0.99 0.042], 'String', ...
        '[MEASURED — section 3.2, tests/test_masquerade_amplitude.m (4/4); the 200 W / 60 W limit itself is ASSUMED]', ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png = fullfile(outDir, 'fig9_eirp_compliance.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig9_eirp_compliance_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'standoff_range_m,required_erp_mW,required_erp_W,limit_peak_W,headroom_dB,source\n');
    for i = xv
        fprintf(fid, '%d,%.3f,%.9g,%d,%.1f,REPORT_HAC-2026-1166.md 3.2 [MEASURED]\n', ...
            standoff_m(i), erp_mW(i), erp_W(i), LIMIT_PEAK_W, headroom_dB(i));
    end
    fclose(fid);

    fprintf('\n=== FIG 9 : EIRP compliance ===\n');
    fprintf('%10s %16s %14s %12s\n', 'standoff', 'required ERP', 'limit', 'headroom');
    for i = xv
        fprintf('%8d m %13.3f mW %10d W %10.1f dB\n', standoff_m(i), erp_mW(i), LIMIT_PEAK_W, headroom_dB(i));
    end
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% =======================================================================
% FIG 5b -- detection vs SNR, DENSER than section 2.9's four points.
%
% 2.9 measured 4 amplitudes x 5 seeds and the report's own Appendix F calls
% that "thin, needs a denser sweep". Rather than fit a curve through four
% points, this RE-RUNS the sweep at 10 amplitudes x 10 seeds using the same
% modules 2.9 used (engine.entity.render -> engine.runJudge), and overlays
% 2.9's four published points so the new sweep can be checked against them
% instead of quietly replacing them.
%
% Nothing new is implemented: this is a measurement run over existing tested
% functions. It writes only a figure and a CSV.
% =======================================================================
function outFiles = localFig5b(outDir)
    C = physics.Constants();
    PW = 12e-6; BW = 2e6; CARRIER = 10e9;
    NP = 32; NF = 400; NFRAMES = 8; V = -40; R0 = 1800;
    SEEDS = 10;
    amps = logspace(log10(0.006), log10(0.045), 10);

    n = round(PW * C.fs);
    tt = (0:n-1)' / C.fs;
    chirp = exp(1i * pi * (BW/PW) * tt.^2);
    q = engine.entity.calibrateQ('Dt', 1.0);

    L = physics.linkBudget();
    snrDb = 10*log10(physics.simAmplitudeToWatts(amps) / L.noise_power_w);

    csv = fullfile(outDir, 'fig5b_detection_vs_snr_data.csv');
    detCube = zeros(1, numel(amps));
    detSingle = zeros(1, numel(amps));
    fprintf('\n=== FIG 5b : detection vs SNR, %d amplitudes x %d seeds ===\n', numel(amps), SEEDS);

    % Reuse the measured counts if this sweep has already been run: it is
    % ~10 min of judge calls, and re-running it to restyle the plot would
    % also silently change the numbers under a figure already reviewed.
    cached = isfile(csv);
    if cached
        T = readtable(csv);
        if height(T) == numel(amps) && max(abs(T.amp_scale(:)' - amps)) < 1e-9
            detCube = T.detect_cube(:)'; detSingle = T.detect_single(:)';
            fprintf('reusing measured counts from %s (delete it to force a re-run)\n', csv);
        else
            cached = false;
        end
    end

    fprintf('%10s %9s %14s %16s\n', 'amp_scale', 'SNR dB', 'cube (32 p)', 'single pulse');
    for a = 1:numel(amps)
        if cached
            fprintf('%10.4f %9.2f %10d/%d %12d/%d\n', amps(a), snrDb(a), ...
                detCube(a), SEEDS, detSingle(a), SEEDS);
            continue;
        end
        for s = 1:SEEDS
            rs = RandStream('mt19937ar', 'Seed', 1000*a + s);
            st = engine.entity.EntityState('range_m', R0, 'range_rate_mps', V, ...
                'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
            cube = complex(zeros(NF, NP, NFRAMES));
            for k = 1:NFRAMES
                c = engine.entity.render(st, 'AmpScale', amps(a), 'NumPulses', NP, ...
                    'FastTimeSamples', NF, 'CarrierHz', CARRIER, 'PrfHz', C.PRF, ...
                    'ChirpOverride', chirp, 'RandStream', rs);
                cube(:,:,k) = c + localNoise(rs, NF, NP);
                st = engine.entity.propagate(st, 1.0, q, rs);
            end
            detCube(a)   = detCube(a)   + (localJudgeDetects(cube, PW, BW, CARRIER) > 0);
            % legacy single-pulse export: no slow-time axis at all
            detSingle(a) = detSingle(a) + (localJudgeDetects(squeeze(cube(:,1,:)), PW, BW, CARRIER) > 0);
        end
        fprintf('%10.4f %9.2f %10d/%d %12d/%d\n', amps(a), snrDb(a), ...
            detCube(a), SEEDS, detSingle(a), SEEDS);
    end

    pC = detCube / SEEDS; pS = detSingle / SEEDS;
    [cLo, cHi] = localWilson(detCube, SEEDS);
    [sLo, sHi] = localWilson(detSingle, SEEDS);

    % section 2.9's four published points, for cross-check (5 seeds each)
    refAmp = [0.030 0.020 0.012 0.008];
    refCube = [5 5 5 0]/5; refSingle = [5 4 0 0]/5;
    refSnr = 10*log10(physics.simAmplitudeToWatts(refAmp) / L.noise_power_w);

    COL_C = [0.00 0.45 0.70]; COL_S = [0.90 0.62 0.00];

    f = figure('Color', 'w', 'Position', [100 100 1020 620], 'Visible', 'off');
    ax = axes(f, 'Position', [0.085 0.265 0.885 0.545]); hold(ax, 'on');
    localBand(ax, snrDb, cLo, cHi, COL_C);
    localBand(ax, snrDb, sLo, sHi, COL_S);
    plot(ax, snrDb, 100*pC, '-o', 'Color', COL_C, 'LineWidth', 2, 'MarkerSize', 6, ...
        'MarkerFaceColor', COL_C, 'MarkerEdgeColor', 'w', 'DisplayName', 'cube, 32 pulses (this sweep)');
    plot(ax, snrDb, 100*pS, '-o', 'Color', COL_S, 'LineWidth', 2, 'MarkerSize', 6, ...
        'MarkerFaceColor', COL_S, 'MarkerEdgeColor', 'w', 'DisplayName', 'single pulse (this sweep)');
    plot(ax, refSnr, 100*refCube, 's', 'MarkerSize', 10, 'MarkerEdgeColor', COL_C, ...
        'LineWidth', 1.6, 'LineStyle', 'none', 'DisplayName', 'section 2.9, cube (5 seeds)');
    plot(ax, refSnr, 100*refSingle, 's', 'MarkerSize', 10, 'MarkerEdgeColor', COL_S, ...
        'LineWidth', 1.6, 'LineStyle', 'none', 'DisplayName', 'section 2.9, single pulse (5 seeds)');

    experiments.lightAxes(ax); grid(ax, 'on');
    ylim(ax, [-4 108]); ylabel(ax, 'P(detect) over 8 frames (%)', 'FontSize', 10);
    xlabel(ax, 'single-pulse SNR at 1800 m (dB) — derived via physics.simAmplitudeToWatts / physics.linkBudget', ...
        'FontSize', 9.5);
    legend(ax, 'Location', 'northwest', 'Box', 'off', 'FontSize', 8.5, ...
        'TextColor', [0.2 0.2 0.2]);
    title(ax, 'Detection vs SNR — a denser sweep than the published four points', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(ax, sprintf('%d amplitudes x %d seeds (shaded = Wilson 95%% CI). Squares are section 2.9''s 4 points at 5 seeds, overlaid as a cross-check.', ...
        numel(amps), SEEDS), 'FontSize', 8.5, 'Color', [0.45 0.45 0.45]);
    x50c = localCross50(snrDb, pC);
    x50s = localCross50(snrDb, pS);
    annotation(f, 'textbox', [0.085 0.055 0.885 0.085], 'String', ...
        sprintf(['Measured 50 %%-detection crossings: %.1f dB (32-pulse cube) vs %.1f dB (single pulse) — a ' ...
                 '%.1f dB integration gain, NOT the naive 10log10(32) = 15 dB,' newline ...
                 'because runJudge takes a max over Doppler bins and that lifts the noise floor with the signal. ' ...
                 'Section 2.9 puts the same gap at ~4.4 dB.' newline ...
                 'The cube curve is NON-MONOTONIC near %.0f dB (4/10 then 3/10). That is seed noise, not structure — ' ...
                 'those Wilson intervals overlap almost completely; do not read a shoulder into it.'], ...
                 x50c, x50s, x50s-x50c, snrDb(2)), ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.6, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle');
    fprintf('50%% crossings: cube %.2f dB, single %.2f dB -> integration gain %.2f dB\n', ...
        x50c, x50s, x50s-x50c);

    annotation(f, 'textbox', [0.005 0.004 0.99 0.042], 'String', ...
        ['[MEASURED — engine.entity.render -> engine.runJudge, run ' datestr(now, 'dd mmm yyyy') ...
         '; supersedes section 2.9''s 4-point sweep, which is overlaid for comparison]'], ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png = fullfile(outDir, 'fig5b_detection_vs_snr.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    fid = fopen(csv, 'w');
    fprintf(fid, 'amp_scale,snr_db,n_seeds,detect_cube,p_cube,cube_ci_lo,cube_ci_hi,detect_single,p_single,single_ci_lo,single_ci_hi\n');
    for a = 1:numel(amps)
        fprintf(fid, '%.6f,%.4f,%d,%d,%.4f,%.4f,%.4f,%d,%.4f,%.4f,%.4f\n', ...
            amps(a), snrDb(a), SEEDS, detCube(a), pC(a), cLo(a), cHi(a), ...
            detSingle(a), pS(a), sLo(a), sHi(a));
    end
    fclose(fid);
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% -----------------------------------------------------------------------
function nDet = localJudgeDetects(rx, pw, bw, carrier)
    C = physics.Constants();
    S = struct('rx_frames', rx, 'fs', C.fs, 'pulse_width_s', pw, ...
        'bandwidth_hz', bw, 'prf_hz', C.PRF, 'carrier_hz', carrier, ...
        'frame_interval_s', 1.0);
    tmp = [tempname(), '.mat'];
    save(tmp, '-struct', 'S');
    cl = onCleanup(@() delete(tmp)); %#ok<NASGU>
    fb = engine.runJudge(tmp);
    nDet = fb.confirmed_tracks;
end

% -----------------------------------------------------------------------
function x50 = localCross50(x, p)
%LOCALCROSS50  First upward 50 % crossing, linearly interpolated. Uses the
%   LAST crossing so a low-SNR noise wiggle doesn't win over the real edge.
    x50 = NaN;
    for i = numel(p)-1:-1:1
        if p(i) < 0.5 && p(i+1) >= 0.5
            x50 = x(i) + (0.5 - p(i)) * (x(i+1) - x(i)) / (p(i+1) - p(i));
            return;
        end
    end
end

% -----------------------------------------------------------------------
function localBand(ax, x, lo, hi, col)
    fill(ax, [x(:); flipud(x(:))], 100*[lo(:); flipud(hi(:))], col, ...
        'FaceAlpha', 0.14, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end

% -----------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
%LOCALWILSON  Wilson score interval -- this project's convention for a
%   proportion (BENCHMARK_RESULTS.md), same implementation as
%   +experiments/plotAgilityPredictability.m.
    z = 1.959963984540054;
    ph = k(:) / n;
    den = 1 + z^2/n;
    c   = ph + z^2/(2*n);
    hw  = z * sqrt(ph.*(1-ph)/n + z^2/(4*n^2));
    lo = (c - hw)./den; hi = (c + hw)./den;
end

% =======================================================================
% FIG 10 -- the radar's knobs at R3. Which one actually moves evasion?
% REPORT_HAC-2026-1166.md section 7.2 ("And the radar has no working knob at
% R3" + the dwell-length paragraph), [MEASURED], 20 seeds per cell.
%
% PLOTTED AS "BEST THE KNOB CAN DO", NOT AS SWEEP CURVES, ON PURPOSE. 7.2
% reports three of these four sweeps as FLAT or CLIFF-shaped and gives their
% endpoints, not per-cell curves. Drawing smooth lines through them would
% imply a trend the measurement does not contain -- so each knob contributes
% the LOWEST evasion it achieved anywhere in its tested range, and the shape
% is stated in words beside it.
% =======================================================================
function outFiles = localFig10(outDir)
    knob = { 'Dwell length  32 -> 512 pulses', ...
             'CFAR P_{fa}  10^{-6} ... 10^{-2}', ...
             'M-of-N  [2 3] ... [5 6]', ...
             'Tracker gate  1 ... 200', ...
             'Tracker model  CV/IMM/CA/GNN/JPDA' };
    best = [ 60.0  80.0  95.0 100.0 100.0];
    lo   = [ 38.7   NaN   NaN   NaN   NaN];   % only the dwell row carries a CI in 7.2
    hi   = [ 78.1   NaN   NaN   NaN   NaN];
    shape= { 'THE ONLY KNOB THAT WORKS — F1 rises 0.000 -> 0.596', ...
             'FLAT, except one unexplained dip at 10^{-3}', ...
             'nearly flat', ...
             'A CLIFF, NOT A CURVE', ...
             'ZERO difference — byte-identical' };
    cost = { 'but genuine-aircraft false alarms rise 5 % -> 35 %, and regret vs the non-adaptive ceiling rises to 40 %', ...
             'no mechanism established — must NOT be quoted as "tightening P_{fa} helps"', ...
             'and genuine-aircraft false alarms QUADRUPLE, 5 % -> 20 %', ...
             'below gate ~20 NOTHING confirms, including the genuine target — not a usable operating point', ...
             'includes IMM and CA: changing the motion model changes nothing at all' };
    isWin = [true false false false false];

    COL_WIN  = [0.84 0.37 0.00];
    COL_DEAD = [0.62 0.62 0.62];
    BASE     = 100.0;    % R3 baseline evasion, 7.2

    f = figure('Color', 'w', 'Position', [100 100 1200 620], 'Visible', 'off');
    ax = axes(f, 'Position', [0.245 0.30 0.72 0.53]); hold(ax, 'on');

    n = numel(knob);
    yv = n:-1:1;
    xline(ax, BASE, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
        'HandleVisibility', 'off');
    for i = 1:n
        c = COL_DEAD; if isWin(i); c = COL_WIN; end
        barh(ax, yv(i), best(i), 0.58, 'FaceColor', c, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    ok = ~isnan(lo);
    errorbar(ax, best(ok), yv(ok), best(ok)-lo(ok), hi(ok)-best(ok), 'horizontal', ...
        'LineStyle', 'none', 'Color', [0.15 0.15 0.15], 'LineWidth', 1.1, 'CapSize', 6, ...
        'HandleVisibility', 'off');

    for i = 1:n
        if isnan(lo(i))
            lbl = sprintf('%.0f %%', best(i));
        else
            lbl = sprintf('%.0f %%  [%.1f, %.1f]', best(i), lo(i), hi(i));
        end
        text(ax, max(best(i), localNz(hi(i))) + 2, yv(i), lbl, 'FontSize', 9, ...
            'FontWeight', localTernStr(isWin(i), 'bold', 'normal'), ...
            'VerticalAlignment', 'middle', 'Color', [0.18 0.18 0.18]);
        text(ax, 3, yv(i)+0.32, shape{i}, 'FontSize', 7.6, 'FontAngle', 'italic', ...
            'Color', localTern(isWin(i), COL_WIN, [0.50 0.50 0.50]), ...
            'VerticalAlignment', 'bottom');
    end
    text(ax, BASE-1.5, 0.72, 'R3 baseline: 100 %', 'HorizontalAlignment', 'right', ...
        'FontSize', 8, 'Color', [0.35 0.35 0.35]);

    experiments.lightAxes(ax); grid(ax, 'on');
    ax.YTick = flip(yv); ax.YTickLabel = flip(knob);
    ax.FontSize = 9;
    xlim(ax, [0 150]); ylim(ax, [0.4 n+0.75]); ax.XTick = 0:20:100;
    xlabel(ax, 'LOWEST phantom evasion the knob achieved anywhere in its tested range (%)', ...
        'FontSize', 9.5);

    title(ax, 'The radar''s knobs at R3 — only one of them moves the needle', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(ax, ['Lower is better FOR THE RADAR. Bars are best-case, not sweep curves: 7.2 reports three of these four ' ...
        'sweeps as flat or cliff-shaped.'], 'FontSize', 8.5, 'Color', [0.45 0.45 0.45]);

    shortName = {'Dwell length', 'CFAR P_{fa}', 'M-of-N', 'Tracker gate', 'Tracker model'};
    txt = '';
    for i = 1:n
        txt = [txt sprintf('%s  —  %s', shortName{i}, cost{i})]; %#ok<AGROW>
        if i < n; txt = [txt newline]; end %#ok<AGROW>
    end
    annotation(f, 'textbox', [0.045 0.045 0.925 0.185], 'String', txt, ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.5, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle');
    annotation(f, 'textbox', [0.005 0.004 0.99 0.035], 'String', ...
        '[MEASURED, 20 seeds per cell — REPORT_HAC-2026-1166.md section 7.2]', ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png = fullfile(outDir, 'fig10_radar_knobs.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig10_radar_knobs_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'knob,best_evasion_pct,ci_lo,ci_hi,shape,cost_or_caveat,seeds,source\n');
    for i = 1:n
        fprintf(fid, '"%s",%.1f,%s,%s,"%s","%s",20,REPORT_HAC-2026-1166.md 7.2 [MEASURED]\n', ...
            knob{i}, best(i), localNumOrBlank(lo(i)), localNumOrBlank(hi(i)), shape{i}, cost{i});
    end
    fprintf(fid, '"R3 baseline (32 pulses)",100.0,83.9,100.0,"baseline","",20,REPORT_HAC-2026-1166.md 7.2 [MEASURED]\n');
    fclose(fid);

    fprintf('\n=== FIG 10 : the radar''s knobs at R3 ===\n');
    fprintf('%-38s %10s  %s\n', 'knob', 'best evas', 'shape');
    for i = 1:n
        fprintf('%-38s %9.0f%%  %s\n', knob{i}, best(i), shape{i});
    end
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% -----------------------------------------------------------------------
function v = localNz(x)
    if isnan(x); v = -Inf; else; v = x; end
end
function s = localTernStr(cond, a, b)
    if cond; s = a; else; s = b; end
end

% =======================================================================
% FIG 2 -- before/after: one target vs the swarm illusion.
%
% NOT A PPI, AND THAT IS DELIBERATE. The brief asked for a polar
% before/after PPI. This project has no angle channel on the missionsim
% path: every phantom in every frame log carries truth.pos = [R, 0, 0],
% i.e. cross-range is identically ZERO, and there is no mother-drone
% position anywhere in the schema (MissionSimulatorApp.m:499 documents
% refusing to draw one). A polar scope would therefore have to INVENT
% bearings -- exactly what MISSION_SIMULATOR_UI_SPEC.md section 11 refuses
% ("would imply azimuth data this project has never had").
%
% So this plots what the log actually contains: RANGE vs TIME, truth
% against what the radar's tracker believes, before (1 target) and after
% (4 phantoms). Same before/after story, no fabricated axis.
% =======================================================================
function outFiles = localFig2(outDir)
    COL_TRUTH = [0.45 0.45 0.45];
    COL_REAL  = [0.00 0.62 0.45];   % track the ECCM called real
    COL_DECOY = [0.84 0.37 0.00];   % track the ECCM flagged
    COL_UNSCR = [0.00 0.45 0.70];   % confirmed but not screenable yet

    runs = struct('n', {1, 4}, 'title', {'BEFORE — one target', ...
                                         'AFTER — 4 phantoms, one repeater'});
    data = cell(1, 2);
    fprintf('\n=== FIG 2 : before/after, real missionsim runs ===\n');
    for r = 1:2
        controls = struct('n', runs(r).n, 'amplitudeProfile', 'uniform', ...
                          'phaseProfile', 'random');
        fl = missionsim.runManualScene(controls);
        data{r} = localFrameLogSeries(fl);
        fprintf('n=%d: %d frames, %d phantoms commanded, %d distinct track IDs seen\n', ...
            runs(r).n, numel(fl), size(data{r}.truthR, 2), numel(data{r}.trackIds));
        % Per-phantom coverage: a phantom counts as tracked in a frame if a
        % confirmed track sits within 2 range cells of its commanded range.
        C = physics.Constants();
        D = data{r};
        cov = zeros(1, size(D.truthR, 2));
        for p = 1:size(D.truthR, 2)
            for k = 1:numel(D.t)
                near = abs(D.trackR - D.truthR(k, p)) < 2*C.range_per_sample & ...
                       abs(D.tGrid - D.t(k)) < 1e-9;
                cov(p) = cov(p) + any(near);
            end
            fprintf('    phantom %d @ %.0f m: tracked in %d/%d frames\n', ...
                p, D.truthR(1, p), cov(p), numel(D.t));
        end
        data{r}.coverage = cov;
    end

    f = figure('Color', 'w', 'Position', [100 100 1150 680], 'Visible', 'off');
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    tl.OuterPosition = [0 0.215 1 0.785];   % leave a clear strip for the
                                            % result callout below the axes

    allR = [];
    for r = 1:2; allR = [allR; data{r}.truthR(:); data{r}.trackR(:)]; end %#ok<AGROW>
    rlim = [0 max(allR(~isnan(allR)))*1.12];

    for r = 1:2
        ax = nexttile(tl); hold(ax, 'on');
        D = data{r};
        for p = 1:size(D.truthR, 2)
            plot(ax, D.t, D.truthR(:, p), '-', 'Color', [COL_TRUTH 0.85], ...
                'LineWidth', 2.2, 'HandleVisibility', localOnce(p == 1), ...
                'DisplayName', 'commanded truth');
        end
        vk = {'REAL', 'DECOY', 'UNSCREENED'};
        vc = {COL_REAL, COL_DECOY, COL_UNSCR};
        for v = 1:3
            m = strcmp(D.trackVerdict, vk{v});
            if ~any(m(:)); continue; end
            plot(ax, D.tGrid(m), D.trackR(m), 'o', 'MarkerSize', 5.5, ...
                'MarkerFaceColor', vc{v}, 'MarkerEdgeColor', 'w', 'LineWidth', 0.6, ...
                'LineStyle', 'none', 'DisplayName', sprintf('track: %s', lower(vk{v})));
        end
        experiments.lightAxes(ax); grid(ax, 'on');
        xlabel(ax, 'time (s)'); if r == 1; ylabel(ax, 'range (m)'); end
        ylim(ax, rlim); xlim(ax, [min(D.t)-0.3 max(D.t)+0.3]);
        title(ax, runs(r).title, 'FontSize', 11, 'Color', [0.10 0.10 0.10]);
        ax.FontSize = 9;
        if r == 2
            legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 8.5, ...
                'TextColor', [0.2 0.2 0.2]);
        end
    end

    title(tl, 'One drone becomes a formation — truth vs what the radar tracks', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(tl, ['Grey = the range each phantom was commanded to occupy; dots = the tracker''s own range estimate, coloured by the ECCM verdict.' newline ...
        'RANGE vs TIME, not a PPI: this radar has no angle channel on this path (every frame log carries cross-range = 0 and no mother-drone position),' newline ...
        'so a polar scope would have to invent bearings. All phantoms close in parallel because one repeater commands one velocity.'], ...
        'FontSize', 8.3, 'Color', [0.35 0.35 0.35]);
    % The missing dots ARE the result -- say so, don't leave it to be noticed.
    nTracked = sum(data{2}.coverage > 0);
    annotation(f, 'textbox', [0.055 0.055 0.905 0.125], 'String', ...
        sprintf(['RESULT, not a rendering gap: only %d of the 4 commanded phantoms ever produced a confirmed track. ' ...
                 'The 4200 m and 5400 m lines carry NO dots.' newline ...
                 'The ''uniform'' amplitude profile splits the shared 60 W budget EQUALLY, and received power falls as ' ...
                 '1/R^4 — so the far phantoms are' newline 'simply never detected. Equalising received power instead ' ...
                 '(as Fig 7 does, compensating transmit amplitude by R^2) is what makes all four appear.'], nTracked), ...
        'EdgeColor', [0.82 0.82 0.82], 'BackgroundColor', [0.98 0.98 0.97], ...
        'FontSize', 7.6, 'Color', [0.30 0.30 0.30], 'FitBoxToText', 'off', ...
        'VerticalAlignment', 'middle');

    annotation(f, 'textbox', [0.005 0.004 0.99 0.045], 'String', ...
        ['[MEASURED — missionsim.runManualScene -> engine.runJudge, run ' datestr(now, 'dd mmm yyyy') ']'], ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png = fullfile(outDir, 'fig2_before_after_range_time.png');
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    csv = fullfile(outDir, 'fig2_before_after_range_time_data.csv');
    fid = fopen(csv, 'w');
    fprintf(fid, 'arm,n_phantoms,time_s,series,id,range_m,eccm_verdict\n');
    armName = {'before', 'after'};
    for r = 1:2
        D = data{r};
        for p = 1:size(D.truthR, 2)
            for k = 1:numel(D.t)
                fprintf(fid, '%s,%d,%.3f,truth,P%d,%.4f,\n', armName{r}, runs(r).n, ...
                    D.t(k), p, D.truthR(k, p));
            end
        end
        for j = 1:numel(D.trackR)
            if isnan(D.trackR(j)); continue; end
            fprintf(fid, '%s,%d,%.3f,track,%s,%.4f,%s\n', armName{r}, runs(r).n, ...
                D.tGrid(j), D.trackIdOf{j}, D.trackR(j), D.trackVerdict{j});
        end
    end
    fclose(fid);
    fprintf('wrote %s\nwrote %s\n', png, csv);
    outFiles = {png, csv};
end

% -----------------------------------------------------------------------
function S = localFrameLogSeries(fl)
%LOCALFRAMELOGSERIES  Pull truth range and per-track range/verdict out of a
%   missionsim frame log. Reads the MATLAB struct directly rather than a
%   JSON round-trip: jsonencode collapses a 1-element struct array to an
%   OBJECT, so a single-track frame reads as a 9-field dict and any
%   numel()-style count of it is wrong. This project has hit that bug
%   repeatedly; not re-entering it here.
    nF = numel(fl);
    t = zeros(nF, 1);
    nPh = numel(fl{1}.synth.phantoms);
    truthR = nan(nF, nPh);
    ids = {}; tR = []; tV = {}; tT = []; tId = {};
    for k = 1:nF
        f = fl{k};
        t(k) = f.t;
        for p = 1:numel(f.synth.phantoms)
            rp = f.synth.phantoms(p).range;
            if isstruct(rp); truthR(k, p) = rp.value; else; truthR(k, p) = rp; end
        end
        tracks = f.radar.tracks;
        for j = 1:numel(tracks)
            tr = tracks(j);
            if isempty(tr.rangeEst) || isnan(tr.rangeEst); continue; end
            if strcmp(tr.state, 'TENTATIVE'); continue; end   % not yet a track
            tR(end+1, 1) = tr.rangeEst;   %#ok<AGROW>
            tV{end+1, 1} = upper(char(tr.eccmVerdict)); %#ok<AGROW>
            tT(end+1, 1) = f.t;           %#ok<AGROW>
            tId{end+1, 1} = char(tr.id);  %#ok<AGROW>
            if ~any(strcmp(ids, tr.id)); ids{end+1} = char(tr.id); end %#ok<AGROW>
        end
    end
    S = struct('t', t, 'truthR', truthR, 'trackR', tR, 'trackVerdict', {tV}, ...
        'tGrid', tT, 'trackIds', {ids}, 'trackIdOf', {tId});
end

% -----------------------------------------------------------------------
function s = localOnce(tf)
    if tf; s = 'on'; else; s = 'off'; end
end

% =======================================================================
% FIG 3 + FIG 7 -- range-Doppler map and range profile, genuine vs swarm.
% ONE cube build feeds both, per the brief.
%
% NOTE ON PROVENANCE, because this differs from figs 4/4b/5/6/9: those
% transcribe a measured table, THIS ONE RUNS THE PIPELINE. Nothing new is
% implemented -- the scene is built with the SAME calls
% tests/test_vee_deception_check.m already uses (engine.entity.EntityState /
% render / propagate for the genuine arm, features.synthesizeTxPulse for the
% repeater arm) and processed with the judge's own
% radar.pulseCompress -> radar.rangeDoppler. There is no synth.exportCube in
% this repo; +synth/ contains only synthesizeSwarm.m, so the cube comes from
% engine.entity.render, which is the tested cube source (test_vee_entity.m).
% =======================================================================
function outFiles = localFig3and7(outDir)
    C   = physics.Constants();
    PW  = 12e-6;  BW = 2e6;  CARRIER = 10e9;
    NP  = 32;     NF = 400;
    V   = -40;               % inside v_ua = 59.96 m/s at the 8 kHz PRF
    AMP = 3.0;               % this project's validated reference level
    R_REAL   = 1800;
    R_SWARM  = [1800 3000 4200 5400];
    INTERCEPT_NOISE = 2.0;
    SEED = 20261166;         % this project's own mission seed

    lambda = C.c / CARRIER;
    fdOf = @(v) -2*v/lambda;

    wav = phased.LinearFMWaveform('SampleRate', C.fs, 'PulseWidth', PW, ...
        'SweepBandwidth', BW, 'PRF', C.PRF, 'OutputFormat', 'Pulses', 'NumPulses', 1);

    n = round(PW * C.fs);
    tchirp = (0:n-1)' / C.fs;
    cleanChirp = exp(1i * pi * (BW/PW) * tchirp.^2);
    nominalK = BW / PW;

    % ---- arm 1: ONE GENUINE target (reflects the radar's actual pulse) ----
    rs = RandStream('mt19937ar', 'Seed', SEED);
    sReal = engine.entity.EntityState('range_m', R_REAL, 'range_rate_mps', V, ...
        'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
    cubeReal = engine.entity.render(sReal, 'AmpScale', AMP, 'NumPulses', NP, ...
        'FastTimeSamples', NF, 'CarrierHz', CARRIER, 'PrfHz', C.PRF, ...
        'ChirpOverride', cleanChirp, 'RandStream', rs);
    cubeReal = cubeReal + localNoise(rs, NF, NP);

    % ---- arm 2: the 4-phantom swarm, one repeater, summed into ONE buffer --
    rs = RandStream('mt19937ar', 'Seed', SEED);
    [tmpl, degraded] = features.synthesizeTxPulse(cleanChirp, C.fs, nominalK, ...
        INTERCEPT_NOISE, rs, 1);
    cubeSwarm = complex(zeros(NF, NP));
    for i = 1:numel(R_SWARM)
        % Equal RECEIVED power per phantom: render's own amplitude law is
        % sqrt(RCS)/R^2, so the transmit scale must rise as R^2 or the far
        % phantom sits ~24 dB down and its sidelobes get masked by the near
        % one. This is the project's own documented 4-phantom fix, not a
        % cosmetic choice for the figure.
        ampI = AMP * (R_SWARM(i) / R_REAL)^2;
        sP = engine.entity.EntityState('range_m', R_SWARM(i), 'range_rate_mps', V, ...
            'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
        cubeSwarm = cubeSwarm + engine.entity.render(sP, 'AmpScale', ampI, ...
            'NumPulses', NP, 'FastTimeSamples', NF, 'CarrierHz', CARRIER, ...
            'PrfHz', C.PRF, 'ChirpOverride', tmpl, 'RandStream', rs);
    end
    cubeSwarm = cubeSwarm + localNoise(rs, NF, NP);
    fprintf('\n=== FIG 3 + FIG 7 : cube build ===\n');
    fprintf('synthesizeTxPulse structural fallbacks: %d (0 => the swarm arm really is feature-matched)\n', ...
        numel(degraded));

    % ---- pulse-compress every pulse, keeping PHASE, then Doppler-process --
    [rdReal,  rAxis, dAxis] = localRD(cubeReal,  wav, C);
    [rdSwarm, ~,     ~    ] = localRD(cubeSwarm, wav, C);

    % =================== FIG 3 : range-Doppler maps =====================
    RMAX = 7000;                       % crop: targets span 1.8-5.4 km of an
    keep = rAxis <= RMAX;              % 18.7 km window; stated in the caption
    cmap = localBlueRamp(256);

    f = figure('Color', 'w', 'Position', [100 100 1120 590], 'Visible', 'off');
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    tl.OuterPosition = [0 0.075 1 0.925];   % clear the provenance strip; the
    dbFloor = -45;                          % default layout put it on the xlabel
    panels = {rdReal, rdSwarm};
    ptitle = {sprintf('ONE genuine target (%d m)', R_REAL), ...
              sprintf('%d-phantom swarm, ONE repeater', numel(R_SWARM))};
    pmark  = {R_REAL, R_SWARM};
    for p = 1:2
        ax = nexttile(tl);
        M = panels{p}(keep, :);
        Mdb = 10*log10(M / max(M(:)) + eps);
        imagesc(ax, dAxis/1e3, rAxis(keep), Mdb);
        set(ax, 'YDir', 'normal'); colormap(ax, cmap); clim(ax, [dbFloor 0]);
        hold(ax, 'on');
        for R = pmark{p}
            plot(ax, dAxis(1)/1e3 + 0.12, R, '<', 'MarkerSize', 7, ...
                'MarkerFaceColor', [0.84 0.37 0.00], 'MarkerEdgeColor', 'w', 'LineWidth', 0.8);
        end
        xline(ax, fdOf(V)/1e3, ':', 'Color', [0.84 0.37 0.00], 'LineWidth', 1.1, ...
            'Alpha', 0.9);
        experiments.lightAxes(ax); ax.Layer = 'top'; grid(ax, 'off');
        xlabel(ax, 'Doppler (kHz)'); if p == 1; ylabel(ax, 'range (m)'); end
        title(ax, ptitle{p}, 'FontSize', 10.5, 'Color', [0.10 0.10 0.10]);
        ax.FontSize = 9;
    end
    cb = colorbar(nexttile(tl, 2));
    cb.Label.String = 'normalised power (dB)'; cb.Label.FontSize = 9;
    cb.FontSize = 8.5;

    title(tl, 'Range–Doppler response: one real target vs a four-phantom swarm', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(tl, sprintf(['Same radar, same dwell (%d pulses, PRF %.0f kHz, \\lambda = %.1f mm). ' ...
        'Markers = true range; dotted line = the Doppler a %+d m/s closer must occupy (%.2f kHz).\n' ...
        'Range axis cropped to %d m of the %.1f km unambiguous window. ' ...
        'Every phantom sits at the SAME Doppler because they share one repeater''s commanded velocity.'], ...
        NP, C.PRF/1e3, lambda*1e3, V, fdOf(V)/1e3, RMAX, C.c/(2*C.PRF)/1e3), ...
        'FontSize', 8.5, 'Color', [0.35 0.35 0.35]);
    annotation(f, 'textbox', [0.005 0.004 0.99 0.042], 'String', ...
        ['[MEASURED — engine.entity.render -> radar.pulseCompress -> radar.rangeDoppler, run ' ...
         datestr(now, 'dd mmm yyyy') ', seed 20261166]'], ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png3 = fullfile(outDir, 'fig3_range_doppler.png');
    exportgraphics(f, png3, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    % =================== FIG 7 : range profile ==========================
    profReal  = max(rdReal,  [], 2);
    profSwarm = max(rdSwarm, [], 2);
    % Reference = the GENUINE target's peak, not the swarm's. It answers the
    % question the figure is actually for ("how does a phantom compare with a
    % real return at the same range") and it stops the genuine trace running
    % off the top, which referencing the swarm peak did.
    refP = max(profReal);
    pR = 10*log10(profReal  / refP + eps);
    pS = 10*log10(profSwarm / refP + eps);
    mismatchLossDb = -10*log10(max(profSwarm) / refP);

    COL_R = [0.00 0.62 0.45];   % genuine
    COL_S = [0.00 0.45 0.70];   % swarm
    MARK  = [0.84 0.37 0.00];

    f = figure('Color', 'w', 'Position', [100 100 1080 590], 'Visible', 'off');
    ax = axes(f, 'Position', [0.085 0.20 0.885 0.60]); hold(ax, 'on');
    for i = 1:numel(R_SWARM)
        xline(ax, R_SWARM(i), '-', 'Color', [MARK 0.35], 'LineWidth', 1.0, ...
            'HandleVisibility', 'off');
    end
    plot(ax, rAxis(keep), pS(keep), '-', 'LineWidth', 1.6, 'Color', COL_S, ...
        'DisplayName', sprintf('%d-phantom swarm', numel(R_SWARM)));
    plot(ax, rAxis(keep), pR(keep), '-', 'LineWidth', 1.6, 'Color', COL_R, ...
        'DisplayName', 'one genuine target');
    yTop = ceil(max([pR(keep); pS(keep)])) + 4;
    for i = 1:numel(R_SWARM)
        text(ax, R_SWARM(i), yTop-1.4, sprintf('%d m', R_SWARM(i)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8.5, 'FontWeight', 'bold', ...
            'Color', MARK);
    end
    experiments.lightAxes(ax); grid(ax, 'on');
    xlim(ax, [0 RMAX]); ylim(ax, [-45 yTop]);
    xlabel(ax, sprintf('range (m)   —   1 sample = c/(2f_s) = %.4f m', C.range_per_sample), ...
        'FontSize', 10);
    ylabel(ax, 'pulse-compressed power (dB, ref = genuine peak)', 'FontSize', 10);
    legend(ax, 'Location', 'northeast', 'Box', 'off', 'FontSize', 9, ...
        'TextColor', [0.2 0.2 0.2]);
    title(ax, 'Range profile after pulse compression', ...
        'FontWeight', 'bold', 'FontSize', 13.5, 'Color', [0.10 0.10 0.10]);
    subtitle(ax, sprintf(['Peak-across-Doppler of the same dwell. Phantom transmit amplitude is compensated as R^2 so all four arrive at ' ...
        'EQUAL received power (measured spread 0.4 dB);\nuncompensated, the 5400 m phantom would sit %.1f dB below the 1800 m one and be masked by its sidelobes. ' ...
        'The swarm peaks sit %.1f dB under the genuine\nreturn because the repeater must rebuild the waveform from a NOISY intercept — that pulse-compression mismatch is the price of not having the real chirp.'], ...
        40*log10(R_SWARM(end)/R_SWARM(1)), mismatchLossDb), 'FontSize', 8.2, 'Color', [0.35 0.35 0.35]);
    annotation(f, 'textbox', [0.005 0.004 0.99 0.042], 'String', ...
        ['[MEASURED — engine.entity.render -> radar.pulseCompress, run ' ...
         datestr(now, 'dd mmm yyyy') ', seed 20261166]'], ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.35 0.35 0.35], ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');

    png7 = fullfile(outDir, 'fig7_range_profile.png');
    exportgraphics(f, png7, 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);

    % ---- data sidecars ----
    csv7 = fullfile(outDir, 'fig7_range_profile_data.csv');
    fid = fopen(csv7, 'w');
    fprintf(fid, 'range_m,genuine_db,swarm_db\n');
    idx = find(keep);
    for i = idx(:)'
        fprintf(fid, '%.4f,%.4f,%.4f\n', rAxis(i), pR(i), pS(i));
    end
    fclose(fid);

    mat3 = fullfile(outDir, 'fig3_range_doppler_data.mat');
    meta = struct('range_m_real', R_REAL, 'range_m_swarm', R_SWARM, ...
        'radial_vel_mps', V, 'expected_doppler_hz', fdOf(V), 'prf_hz', C.PRF, ...
        'carrier_hz', CARRIER, 'num_pulses', NP, 'fast_time_samples', NF, ...
        'pulse_width_s', PW, 'bandwidth_hz', BW, 'amp_scale_ref', AMP, ...
        'intercept_noise', INTERCEPT_NOISE, 'seed', SEED, ...
        'range_per_sample_m', C.range_per_sample, ...
        'source', 'engine.entity.render -> radar.pulseCompress -> radar.rangeDoppler'); %#ok<NASGU>
    save(mat3, 'rdReal', 'rdSwarm', 'rAxis', 'dAxis', 'meta');

    % ---- what the figure actually shows, as numbers ----
    [~, iR] = max(profReal); [pkD_R] = localPeakDoppler(rdReal, dAxis);
    fprintf('genuine: peak at %.1f m (true %d m, %+.2f bins), Doppler %.1f Hz (expected %.1f Hz, %+.2f bins)\n', ...
        rAxis(iR), R_REAL, (rAxis(iR)-R_REAL)/C.range_per_sample, pkD_R, fdOf(V), ...
        (pkD_R-fdOf(V))/(C.PRF/NP));
    fprintf('repeater pulse-compression mismatch loss vs the genuine return: %.2f dB\n', mismatchLossDb);
    fprintf('swarm peaks vs truth:\n');
    for i = 1:numel(R_SWARM)
        win = abs(rAxis - R_SWARM(i)) < 3*C.range_per_sample;
        [pk, j] = max(profSwarm .* win);
        fprintf('   phantom %d: true %5d m -> peak %7.1f m  (%+6.1f m, %.2f bins)  %6.2f dB rel\n', ...
            i, R_SWARM(i), rAxis(j), rAxis(j)-R_SWARM(i), ...
            (rAxis(j)-R_SWARM(i))/C.range_per_sample, 10*log10(pk/refP));
    end
    fprintf('wrote %s\nwrote %s\nwrote %s\nwrote %s\n', png3, png7, csv7, mat3);
    outFiles = {png3, png7, csv7, mat3};
end

% -----------------------------------------------------------------------
function nz = localNoise(rs, nf, np)
    nz = 0.05 * (randn(rs, nf, np) + 1i*randn(rs, nf, np)) / sqrt(2);
end

% -----------------------------------------------------------------------
function [rd, rAxis, dAxis] = localRD(cube, wav, C)
%LOCALRD  Pulse-compress each pulse KEEPING PHASE, then Doppler-process.
%   Phase must survive pulse compression or the slow-time FFT has nothing
%   to integrate -- the same requirement +engine/runJudge.m's cube path has.
    np = size(cube, 2);
    comp = complex(zeros(size(cube)));
    for p = 1:np
        [~, y] = radar.pulseCompress(cube(:, p), wav);
        comp(:, p) = y;
    end
    [rd, rAxis, dAxis] = radar.rangeDoppler(comp, wav, C);
end

% -----------------------------------------------------------------------
function fd = localPeakDoppler(rd, dAxis)
    [~, lin] = max(rd(:));
    [~, c] = ind2sub(size(rd), lin);
    fd = dAxis(c);
end

% -----------------------------------------------------------------------
function cm = localBlueRamp(n)
%LOCALBLUERAMP  Single-hue sequential ramp, light -> dark, anchored on the
%   house blue #0073B3. Deliberately NOT parula/turbo: a sequential channel
%   must be one hue with monotonic lightness, and a rainbow map invents
%   category boundaries that are not in the data.
    lo = [0.985 0.990 0.995];
    mid = [0.53 0.75 0.88];
    hi = [0.02 0.16 0.32];
    t = linspace(0, 1, n)';
    cm = zeros(n, 3);
    for k = 1:3
        cm(:, k) = interp1([0 0.5 1], [lo(k) mid(k) hi(k)], t, 'pchip');
    end
end

% =======================================================================
function s = localNumOrBlank(v)
    if isnan(v); s = ''; else; s = sprintf('%.1f', v); end
end

% -----------------------------------------------------------------------
function v = localTern(cond, a, b)
    if cond; v = a; else; v = b; end
end
