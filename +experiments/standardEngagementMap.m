function out = standardEngagementMap(varargin)
%STANDARDENGAGEMENTMAP  The map: real positions, fake positions, and the misses.
%
%   out = experiments.standardEngagementMap()
%   out = experiments.standardEngagementMap('Engagement', 'hidden-drone')
%
%   Renders the FROZEN engagement defined in generator/engagement.py, runs the
%   real judge, runs track.emitterAttribution, and writes
%
%       results/figures/standard_engagement_map.png
%       results/figures/standard_engagement_map_data.csv
%
%   -- the picture and its numbers together, which is this repo's existing
%   convention (+experiments/reportFigures.m).
%
%   WHAT THE MAP ANSWERS. Where is every signal the radar received, in
%   coordinates? Which of those positions are real objects and which were
%   fabricated? And -- the part that is usually left out -- which fakes did
%   the radar FAIL to identify?
%
%   THE SCENARIO IS NOT CHOSEN HERE. generator/engagement.py owns it and
%   validates it against every bound this radar imposes (blind range, R_ua,
%   v_ua, CFAR train+guard separation, causality, monopulse sector) before
%   anything is rendered. That validation runs on every call: this project has
%   twice published numbers from scenes that quietly breached one of those
%   bounds, and a map is exactly the artefact that would launder such a scene
%   into looking authoritative.
%
%   RULE 2 THROUGHOUT. The drone's true track is returned to THIS function by
%   tests/renderPhantomScene.m and is never written into the .mat the judge
%   reads. Every estimated quantity comes out of complex samples.

    p = inputParser;
    p.addParameter('Engagement', 'standard', @(s) ischar(s) || isstring(s));
    p.addParameter('Seed', 21, @isscalar);
    p.addParameter('OutDir', fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                                       'results', 'figures'), @(s) ischar(s) || isstring(s));
    p.addParameter('Visible', false, @islogical);
    p.parse(varargin{:});
    o = p.Results;

    % ---- the frozen scenario, read from its ONE definition ----------------
    name = char(o.Engagement);
    switch name
        case 'standard';     eng = py.generator.engagement.STANDARD_ENGAGEMENT;
        case 'hidden-drone'; eng = py.generator.engagement.HIDDEN_DRONE_ENGAGEMENT;
        otherwise
            error('standardEngagementMap:unknownEngagement', ...
                  'unknown engagement ''%s''', name);
    end
    margins = eng.validate();      % raises rather than rendering an illegal scene

    ranges = cellfun(@double, cell(eng.phantom_ranges_m));
    rate   = double(eng.phantom_rate_mps);
    nFrames = double(eng.num_frames);
    droneP0 = cellfun(@double, cell(eng.drone_position0_m));
    droneV  = cellfun(@double, cell(eng.drone_velocity_mps));
    skinOn  = logical(eng.include_platform_skin_return);

    % ---- render, judge, attribute -----------------------------------------
    rng(o.Seed, 'twister');
    [matPath, truth] = renderPhantomScene(ranges, rate, ...
        'NumFrames', nFrames, ...
        'MotherRangeM', norm(droneP0), ...
        'MotherVelocityMps', droneV, ...
        'IncludePlatformSkinReturn', skinOn, ...
        'PlatformRcs', double(eng.platform_rcs_m2), ...
        'Tag', ['engmap_' name]);
    fb = engine.runJudge(matPath);
    [verdict, diag] = track.emitterAttribution(fb);

    nT = double(fb.confirmed_tracks);
    nFake = nnz(verdict == "radiated-fake");
    nUnk  = nnz(verdict == "undetermined");

    % ---- THE ACCOUNTING THAT MATTERS: how many fakes got away -------------
    % Counting only the verdicts flatters the result. In the hidden-drone
    % case the drone has no skin return, so the NEAREST PHANTOM becomes the
    % nearest member of the shared-rate group and is returned
    % "source-or-real" -- correctly, since causality cannot exclude it and the
    % real emitter is invisible. That is a fake the radar did not identify,
    % and a summary reporting "0 undetermined" would hide it.
    %
    % Measured against truth, which this function has and the judge does not:
    % how many phantoms were rendered, versus how many were named fake.
    nPhantomsTrue = size(truth.range_m, 1);
    if isfinite(truth.platform_row); nPhantomsTrue = nPhantomsTrue - 1; end
    nMissed = nPhantomsTrue - nFake;

    % ---- the numbers, written before the picture --------------------------
    % Deliberately in this order: the CSV is the evidence and the PNG is a
    % rendering of it, so a figure can never exist without its data.
    outDir = char(o.OutDir);
    if ~isfolder(outDir); mkdir(outDir); end
    stem = fullfile(outDir, sprintf('%s_engagement_map', strrep(name, '-', '_')));
    localWriteCsv([stem '_data.csv'], fb, verdict, diag, truth);

    % ---- the picture ------------------------------------------------------
    vis = 'off'; if o.Visible; vis = 'on'; end
    f = figure('Color', 'w', 'Position', [100 100 1180 620], 'Visible', vis);
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % LEFT: the plan view. Cross-range is exaggerated relative to down-range
    % by three orders of magnitude here (tens of metres against thousands), so
    % the axes are deliberately NOT equal -- an equal-axis plot of this
    % geometry is a horizontal line and shows nothing. Said on the axis label
    % rather than left for the reader to misread.
    ax1 = nexttile(tl);
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');
    plot(ax1, 0, 0, 'kp', 'MarkerSize', 16, 'MarkerFaceColor', 'k');
    text(ax1, 0, 0, '  radar', 'FontWeight', 'bold', 'VerticalAlignment', 'top');

    pTrue = truth.mother_position_xyz_m;
    plot(ax1, pTrue(1,:), pTrue(2,:), 'k--', 'LineWidth', 1.6);
    plot(ax1, pTrue(1,1), pTrue(2,1), 'ko', 'MarkerSize', 8, 'LineWidth', 1.4);

    cols = struct('fake', [0.85 0.16 0.16], 'real', [0.10 0.45 0.85], ...
                  'unknown', [0.95 0.62 0.05]);
    % Each track is labelled inline at its own last position rather than in a
    % legend: a legend would need a stable entry order across engagements with
    % different track counts, and the verdict is what the reader is looking
    % for anyway.
    for i = 1:nT
        P = fb.track_position_xyz_m{i};
        switch verdict(i)
            case "radiated-fake";  c = cols.fake;    mk = 'x'; lw = 1.8;
            case "source-or-real"; c = cols.real;    mk = 'o'; lw = 2.0;
            otherwise;             c = cols.unknown; mk = 's'; lw = 2.4;
        end
        plot(ax1, P(1,:), P(2,:), '-', 'Color', c, 'LineWidth', lw, 'Marker', mk, ...
             'MarkerSize', 5);
        text(ax1, P(1,end), P(2,end), sprintf('  %s', verdict(i)), ...
             'Color', c, 'FontSize', 8);
    end
    xlabel(ax1, 'down-range x [m]');
    ylabel(ax1, 'cross-range y [m]   (NOTE: axes are not equal)');
    title(ax1, sprintf('%s engagement -- what the radar received', name));
    localLightAxes(ax1);      % after the labels exist, or title() overrides it

    % RIGHT: the comparison that produces the verdicts. One shared angular
    % rate across every claimed range is the signature; plotting implied cross
    % speed against range makes it a straight line through the origin whose
    % slope IS that rate.
    ax2 = nexttile(tl);
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');
    R = [diag.mean_range_m]; V = [diag.implied_cross_speed_mps];
    for i = 1:nT
        switch verdict(i)
            case "radiated-fake";  c = cols.fake;    mk = 'x';
            case "source-or-real"; c = cols.real;    mk = 'o';
            otherwise;             c = cols.unknown; mk = 's';
        end
        plot(ax2, R(i), V(i), mk, 'Color', c, 'MarkerSize', 11, 'LineWidth', 2);
    end
    omTrue = localTrueOmega(truth);
    rr = [0, max(R(isfinite(R))) * 1.05];
    plot(ax2, rr, omTrue * rr, 'k--', 'LineWidth', 1.2);
    text(ax2, rr(2), omTrue*rr(2), sprintf('  drone''s own \\omega = %.3f mrad/s', ...
         omTrue*1e3), 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
    xlabel(ax2, 'claimed range [m]');
    ylabel(ax2, 'implied cross-range speed R\cdot\omega [m/s]');
    title(ax2, 'one aperture => one angular rate, whatever range is claimed');
    localLightAxes(ax2);

    subtitle = sprintf(['%d phantoms transmitted | %d confirmed | %d named fake ' ...
        '| \\bf%d NOT IDENTIFIED\\rm  \\bullet  emitter fix: %s'], ...
        nPhantomsTrue, nT, nFake, nMissed, fb.emitter_fix);
    if skinOn
        posErr = min(vecnorm(fb.emitter_position_xyz_m - pTrue, 2, 1));
        subtitle = sprintf('%s, %.1f m from the real drone', subtitle, posErr);
    else
        subtitle = sprintf(['%s (bearing + causality BOUND only: no skin ' ...
            'return, so range is not observable)'], subtitle);
    end
    title(tl, subtitle, 'FontWeight', 'normal', 'Color', 'k');

    png = [stem '.png'];
    exportgraphics(f, png, 'Resolution', 200, 'BackgroundColor', 'w');
    if ~o.Visible; close(f); end

    fprintf('\n%s engagement\n', name);
    fprintf('  %d phantoms transmitted, %d tracks confirmed\n', nPhantomsTrue, nT);
    fprintf('  named fake: %d   undetermined: %d   NOT IDENTIFIED: %d\n', ...
            nFake, nUnk, nMissed);
    fprintf('  emitter fix: %s at %.1f m, bearing %+.4f deg\n', ...
            fb.emitter_fix, fb.emitter_range_max_m, rad2deg(fb.emitter_az_rad));
    fprintf('  wrote %s\n  wrote %s\n', png, [stem '_data.csv']);

    out = struct('feedback', fb, 'truth', truth, 'verdict', verdict, ...
                 'diag', diag, 'margins', margins, 'png', png, ...
                 'csv', [stem '_data.csv'], 'n_fake', nFake, ...
                 'n_undetermined', nUnk, 'n_phantoms_true', nPhantomsTrue, ...
                 'n_missed', nMissed);
end


function localWriteCsv(path, fb, verdict, diag, truth)
%LOCALWRITECSV  One row per track per frame, plus the drone's truth columns.
%   Long format rather than one row per track: a per-frame position series is
%   the thing being claimed, and flattening it into columns would make the
%   file unreadable at any other track count.
    rows = table();
    for i = 1:double(fb.confirmed_tracks)
        P = fb.track_position_xyz_m{i};
        t = double(fb.track_time_s{i}(:));
        K = numel(t);
        r = table(repmat(i, K, 1), t, P(1,:)', P(2,:)', P(3,:)', ...
                  double(fb.track_range_m{i}(:)), ...
                  double(fb.track_azimuth_rad{i}(:)), ...
                  repmat(diag(i).omega_rad_s, K, 1), ...
                  repmat(diag(i).sigma_omega_rad_s, K, 1), ...
                  repmat(diag(i).implied_cross_speed_mps, K, 1), ...
                  repmat(diag(i).group, K, 1), ...
                  repmat(diag(i).bearing_screen_score, K, 1), ...
                  repmat(string(verdict(i)), K, 1), ...
                  repmat(string(fb.track_label{i}), K, 1), ...
            'VariableNames', {'track', 't_s', 'x_m', 'y_m', 'z_m', 'range_m', ...
                              'azimuth_rad', 'omega_rad_s', 'sigma_omega_rad_s', ...
                              'implied_cross_mps', 'group', 'bearing_screen', ...
                              'attribution', 'eccm_label'});
        rows = [rows; r]; %#ok<AGROW>
    end
    % The drone's truth as track 0, so the comparison lives in one file rather
    % than needing a second one joined by hand.
    pT = truth.mother_position_xyz_m;
    tT = truth.times_s(:);
    KT = numel(tT);
    nanc = nan(KT, 1);
    truthRows = table(zeros(KT,1), tT, pT(1,:)', pT(2,:)', pT(3,:)', ...
        truth.mother_range_m(:), truth.source_azimuth_rad(:), ...
        nanc, nanc, nanc, nanc, nanc, ...
        repmat("TRUTH-drone", KT, 1), repmat("", KT, 1), ...
        'VariableNames', rows.Properties.VariableNames);
    writetable([truthRows; rows], path);
end


function localLightAxes(ax)
%LOCALLIGHTAXES  Force a light axes regardless of the session's theme.
%   Recent MATLAB releases default to a dark theme, which exports an
%   unreadable figure onto this project's white-background convention: black
%   axes interior with the black truth track drawn on top of it, invisible.
%   Set explicitly rather than left to whatever theme the runner happens to
%   have -- a figure that renders differently per machine is not evidence.
    set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
            'GridColor', [0.15 0.15 0.15], 'GridAlpha', 0.15);
    % Titles and labels carry their own colour under a dark theme and stay
    % light grey on white unless set too.
    set([ax.Title, ax.XLabel, ax.YLabel], 'Color', 'k');
end


function w = localTrueOmega(truth)
%LOCALTRUEOMEGA  The drone's own angular rate, LS slope of its rendered
%   bearing series -- the same estimator the judge fits on its side, so the
%   two numbers are comparable rather than merely close.
    pf = polyfit(truth.times_s(:), truth.source_azimuth_rad(:), 1);
    w = pf(1);
end
