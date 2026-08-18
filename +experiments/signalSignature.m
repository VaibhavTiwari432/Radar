function out = signalSignature(varargin)
%SIGNALSIGNATURE  Positions in, (amplitude, frequency, delay) out, and what
%   the radar does with them.
%
%   out = experiments.signalSignature()
%   out = experiments.signalSignature('Offsets', [2200 0 0; 3800 400 0])
%
%   THE QUESTION. Specify phantoms as relative positions P1, P2 ... from the
%   drone. What signal signature does that produce, and where does the radar
%   put them?
%
%   THE THREE PRIMITIVES ARE ALL THERE IS. +generator/render.m consumes
%   exactly three per-phantom, per-sample series and nothing else:
%
%       phantom_range_m    -> TIME DELAY      tau = 2R/c
%       phantom_phase_rad  -> FREQUENCY       f_d = (1/2pi) dphi/dt
%       phantom_amplitude  -> AMPLITUDE       A
%
%   A 3D position maps onto them completely -- for the RADIAL part of the
%   geometry:
%
%       R    = |P_m + dP|              -> tau
%       Rdot = u . V                   -> f_d = -2*Rdot/lambda
%       A    = k*sqrt(sigma) / R^2
%
%   THE RADAR THIS IS BUILT FOR IS SINGLE-APERTURE. It has one receive
%   channel: no monopulse, no difference channel, no bearing measurement at
%   all. It knows each target's RANGE, RANGE-RATE and AMPLITUDE and nothing
%   else. That is the default here ('SingleAperture', true); pass false to
%   engage the two-aperture monopulse radar the published Phase B wall was
%   measured on.
%
%   WHY THAT CHANGES THE ANSWER COMPLETELY. Against monopulse, a phantom's
%   inherited bearing is a contradiction the radar can see, and
%   +experiments/phaseControllability.m measures why it cannot be fixed: the
%   transmitted phase cancels identically in Delta/Sigma. Remove the second
%   aperture and there is no bearing to contradict -- the requested
%   cross-range offset becomes UNFALSIFIABLE rather than wrong. The radar
%   still places detections on boresight, but by convention, not measurement:
%   a target at range R could be anywhere on the sphere of that radius.
%
%   AND EVERYTHING IT CAN STILL CHECK IS CONSISTENT BY CONSTRUCTION.
%   generator/physics_projection.py derives amplitude and phase from the SAME
%   range trajectory the delay comes from, so the amplitude-vs-range law and
%   the Doppler/range-rate sign -- the two screens this radar actually runs --
%   cannot disagree with the delay. Measured on the default scene: three
%   position-authored phantoms, all labelled `real`.
%
%   Same scene with the difference channel on: all three `decoy`, co-bearing
%   flagged. The two configurations are one argument apart and the contrast is
%   the point.

    p = inputParser;
    % Default scene: one phantom ON the drone's bearing (residual 0, the
    % control) and two progressively further off it, so the table shows the
    % residual growing from nothing rather than only at one value.
    p.addParameter('Offsets', [2200 0 0; 3800 200 0; 5400 600 0], ...
                   @(x) size(x,2) == 3);
    p.addParameter('OffsetVelocities', [], @(x) isempty(x) || size(x,2) == 3);
    % SINGLE APERTURE BY DEFAULT (16 Aug 2026). The radar measures range,
    % range-rate and amplitude, and has no difference channel -- so it has no
    % bearing at all. That is the configuration this pipeline is built for:
    % with no angle measurement there is nothing for a phantom's inherited
    % bearing to contradict, and every quantity the radar CAN measure is
    % derived from one range trajectory and therefore self-consistent.
    % Pass false to engage the two-aperture monopulse radar instead, which is
    % what the published Phase B wall was measured on.
    p.addParameter('SingleAperture', true, @islogical);
    p.addParameter('DroneRangeM', 1400, @isscalar);
    p.addParameter('DroneVelocityMps', [0 3 0], @(x) numel(x) == 3);
    p.addParameter('NumFrames', 8, @isscalar);
    p.addParameter('Seed', 17, @isscalar);
    p.addParameter('OutDir', fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                                       'results', 'figures'), @(s) ischar(s) || isstring(s));
    p.parse(varargin{:});
    o = p.Results;

    offs = o.Offsets;
    vels = o.OffsetVelocities;
    if isempty(vels); vels = repmat([-50 0 0], size(offs,1), 1); end
    C = physics.Constants();

    rng(o.Seed, 'twister');
    [matPath, truth] = renderPhantomScene([], [], ...
        'PhantomOffsets', offs, 'PhantomOffsetVelocities', vels, ...
        'NumFrames', o.NumFrames, 'MotherRangeM', o.DroneRangeM, ...
        'MotherVelocityMps', o.DroneVelocityMps, ...
        'IncludeAngleChannel', ~o.SingleAperture, 'Tag', 'signature');
    fb = engine.runJudge(matPath);

    % ---- what was written on the wire ------------------------------------
    % Read back out of the pre-render plan, which IS the signature -- not
    % recomputed here, which would be a second copy of the derivation.
    plan = load(fullfile(tempdir, 'signature_plan.mat'));
    nPh = size(offs, 1);

    fprintf('\n=== THE SIGNAL SIGNATURE (what leaves the drone) ===\n');
    fprintf('drone at %.0f m, velocity (%.1f, %.1f, %.1f) m/s\n\n', ...
            o.DroneRangeM, o.DroneVelocityMps);
    fprintf('%4s %26s %12s %12s %12s\n', 'ph', 'requested offset dP [m]', ...
            'delay us', 'f_d Hz', 'amplitude');
    tauUs = nan(nPh,1); fdHz = nan(nPh,1); ampV = nan(nPh,1);
    for i = 1:nPh
        R = plan.phantom_range_m(i, :);
        tauUs(i) = 2*R(1)/C.c * 1e6;
        % Frequency IS the slow-time phase derivative -- taken from the phase
        % series the renderer will actually transmit, not from the range.
        phi = plan.phantom_phase_rad(i, :);
        dt = C.PRI;
        fdHz(i) = mean(diff(phi)) / (2*pi*dt);
        ampV(i) = plan.phantom_amplitude(i, 1);
        fprintf('%4d %26s %12.3f %12.1f %12.4f\n', i, ...
                sprintf('(%.0f, %.0f, %.0f)', offs(i,1), offs(i,2), offs(i,3)), ...
                tauUs(i), fdHz(i), ampV(i));
    end

    % ---- where it was asked to be, and where it landed --------------------
    if o.SingleAperture
        fprintf(['\n=== POSITION: REQUESTED vs WHERE THE RADAR *ASSUMES* IT IS ===\n' ...
                 '    (no difference channel, so the second column is boresight by\n' ...
                 '     CONVENTION, not by measurement -- see the note below)\n']);
    else
        fprintf('\n=== POSITION: REQUESTED vs WHERE THE RADAR PUT IT ===\n');
    end
    fprintf('%4s %22s %22s %12s %10s\n', 'ph', 'requested [m]', ...
            'radar assumed [m]', 'residual m', 'range err');
    resid = nan(nPh,1); rangeErr = nan(nPh,1); matched = nan(nPh,1);
    frameOf = nan(nPh,1);
    for i = 1:nPh
        % Associate the measured track by nearest predicted range -- the
        % phantoms are >1124.2 m apart (CFAR train+guard), so this is
        % unambiguous.
        predR = norm(squeeze(truth.predicted_measured_position_m(i, :, 1)));
        [~, k] = min(abs(cellfun(@(r) r(1), fb.track_range_m) - predR));
        matched(i) = k;

        % COMPARE AT THE SAME INSTANT. A track's first hit is rarely frame 1 --
        % confirmation needs M of N, so it typically starts at t = 2 s, by
        % which point a -50 m/s phantom has closed 100 m. Comparing the
        % track's first measurement against truth's first frame charges the
        % geometry for that, and an earlier version of this function did
        % exactly that and reported a ~90 m "range error" that was purely the
        % time offset.
        t1 = fb.track_time_s{k}(1);
        [~, fIdx] = min(abs(truth.times_s - t1));
        frameOf(i) = fIdx;

        req = squeeze(truth.requested_position_m(i, :, fIdx))';
        P = fb.track_position_xyz_m{k};
        meas = P(:, 1);
        resid(i) = norm(req - meas);
        rangeErr(i) = abs(norm(req) - norm(meas));
        fprintf('%4d %22s %22s %12.1f %10.1f\n', i, ...
                sprintf('(%.0f, %.0f, %.0f)', req), ...
                sprintf('(%.0f, %.0f, %.0f)', meas), resid(i), rangeErr(i));
    end

    % ---- what the radar RECONSTRUCTS from those three numbers -------------
    % This is the whole chain closing: position -> (A, f, tau) on the wire ->
    % the radar's own estimate of (R, Rdot, sigma), measured from complex
    % samples with no knowledge of any of the above.
    fprintf('\n=== WHAT THE RADAR RECONSTRUCTS ===\n');
    fprintf('%4s %10s %10s %12s %12s %10s\n', 'ph', 'R true', 'R meas', ...
            'Rdot true', 'Rdot meas', 'label');
    rdotErr = nan(nPh,1);
    for i = 1:nPh
        k = matched(i); fI = frameOf(i);
        Rtrue = norm(squeeze(truth.requested_position_m(i, :, fI)));
        Rmeas = fb.track_range_m{k}(1);
        % True range-rate from the position track: the radial projection of
        % the claimed velocity, which is the only part the frequency
        % primitive carries.
        fI2 = min(fI + 1, numel(truth.times_s));
        dtT = truth.times_s(fI2) - truth.times_s(fI);
        if dtT > 0
            RdotTrue = (norm(squeeze(truth.requested_position_m(i, :, fI2))) - Rtrue) / dtT;
        else
            RdotTrue = NaN;
        end
        RdotMeas = mean(fb.track_range_rate_mps{k});
        rdotErr(i) = abs(RdotMeas - RdotTrue);
        fprintf('%4d %10.1f %10.1f %12.2f %12.2f %10s\n', i, Rtrue, Rmeas, ...
                RdotTrue, RdotMeas, fb.track_label{k});
    end

    if o.SingleAperture
        fprintf('\n  SINGLE APERTURE: this radar has NO difference channel, so it\n');
        fprintf('  measures no bearing at all (angle_source = ''%s''). It knows\n', ...
                fb.angle_source);
        fprintf('  each target''s RANGE, RANGE-RATE and AMPLITUDE and nothing else.\n');
        fprintf('\n  THE CONSEQUENCE FOR THE CROSS-RANGE COLUMN ABOVE: it is not\n');
        fprintf('  WRONG, it is UNFALSIFIABLE. The radar places every detection on\n');
        fprintf('  boresight because that is its only convention, not because it\n');
        fprintf('  measured anything -- a target at this range could be anywhere on\n');
        fprintf('  the sphere of that radius. The requested cross-range offset is\n');
        fprintf('  therefore neither honoured nor contradicted.\n');
        fprintf('\n  AND EVERY QUANTITY IT CAN CHECK IS CONSISTENT BY CONSTRUCTION.\n');
        fprintf('  generator/physics_projection.py derives amplitude and phase from\n');
        fprintf('  the SAME range trajectory the delay comes from, so the amplitude\n');
        fprintf('  law and the Doppler/range-rate sign -- the two screens this\n');
        fprintf('  radar actually runs -- cannot disagree with it.\n');
        fprintf('  Labels: %s\n', strjoin(fb.track_label, ', '));
    else
        fprintf('\n  TWO APERTURES: bearing is measured, and every phantom carries\n');
        fprintf('  the drone''s, not its own.\n');
        fprintf('\n%4s %14s %14s %14s\n', 'ph', 'req bearing', 'drone bearing', 'measured');
        for i = 1:nPh
            hits = fb.track_time_s{matched(i)};
            idx = arrayfun(@(tt) find(abs(truth.times_s - tt) < 1e-9, 1), hits);
            fprintf('%4d %11.4f deg %11.4f deg %11.4f deg\n', i, ...
                rad2deg(mean(truth.requested_bearing_rad(i, idx))), ...
                rad2deg(mean(truth.source_azimuth_rad(idx))), ...
                rad2deg(mean(fb.track_azimuth_rad{matched(i)}, 'omitnan')));
        end
    end

    % ---- is the prediction right? -----------------------------------------
    predErr = nan(nPh,1);
    fprintf('\n=== IS THE PREDICTION RIGHT? ===\n');
    if o.SingleAperture
        % With no angle measured there is no position to predict -- only the
        % RANGE is observable, so that is the only thing it is meaningful to
        % check. Comparing a predicted (x, y, z) against a detection the radar
        % placed on boresight by convention would be scoring the convention.
        for i = 1:nPh
            Rtrue = norm(squeeze(truth.requested_position_m(i, :, frameOf(i))));
            predErr(i) = abs(fb.track_range_m{matched(i)}(1) - Rtrue);
        end
        fprintf('  Single aperture: RANGE is the only observable, so range is\n');
        fprintf('  the only thing to check. |R_measured - |P_requested||: %s m\n', ...
                mat2str(round(predErr', 1)));
    else
        % generator/geometry.py says the radar will place each phantom at
        % R*u_drone. Falsifiable against the real judge, so check it.
        for i = 1:nPh
            pred = squeeze(truth.predicted_measured_position_m(i, :, frameOf(i)))';
            P = fb.track_position_xyz_m{matched(i)};
            predErr(i) = norm(pred - P(:, 1));
        end
        fprintf('  geometry.py predicts R*u_drone; distance from that to the\n');
        fprintf('  judge''s own measured position: %s m\n', ...
                mat2str(round(predErr', 1)));
    end
    fprintf('  (one range cell = %.1f m, so agreement at the instrument''s\n', ...
            C.range_per_sample);
    fprintf('   own resolution)\n');

    out = struct('offsets_m', offs, 'delay_us', tauUs, 'doppler_hz', fdHz, ...
                 'amplitude', ampV, 'residual_m', resid, ...
                 'range_error_m', rangeErr, 'prediction_error_m', predErr, ...
                 'feedback', fb, 'truth', truth, 'matched_track', matched, ...
                 'single_aperture', o.SingleAperture, 'rdot_error_mps', rdotErr, ...
                 'labels', {fb.track_label});

    % ---- figure + csv, the repo's convention ------------------------------
    outDir = char(o.OutDir);
    if ~isfolder(outDir); mkdir(outDir); end
    stem = fullfile(outDir, 'signal_signature');
    writetable(table((1:nPh)', offs(:,1), offs(:,2), offs(:,3), tauUs, fdHz, ampV, ...
                     resid, rangeErr, predErr, ...
        'VariableNames', {'phantom','dx_m','dy_m','dz_m','delay_us','doppler_hz', ...
                          'amplitude','residual_m','range_error_m','prediction_error_m'}), ...
        [stem '_data.csv']);

    f = figure('Color','w','Position',[100 100 1150 520],'Visible','off');
    tl = tiledlayout(f, 1, 2, 'TileSpacing','compact','Padding','compact');

    ax1 = nexttile(tl); hold(ax1,'on'); grid(ax1,'on'); box(ax1,'on');
    plot(ax1, 0, 0, 'kp', 'MarkerSize', 14, 'MarkerFaceColor','k');
    pm = truth.mother_position_xyz_m;
    plot(ax1, pm(1,:), pm(2,:), 'k--', 'LineWidth', 1.4);
    for i = 1:nPh
        req = squeeze(truth.requested_position_m(i, :, frameOf(i)));
        P = fb.track_position_xyz_m{matched(i)};
        plot(ax1, req(1), req(2), 'o', 'Color', [0.10 0.45 0.85], ...
             'MarkerSize', 10, 'LineWidth', 2);
        plot(ax1, P(1,1), P(2,1), 'x', 'Color', [0.85 0.16 0.16], ...
             'MarkerSize', 12, 'LineWidth', 2);
        plot(ax1, [req(1) P(1,1)], [req(2) P(2,1)], ':', ...
             'Color', [0.5 0.5 0.5], 'LineWidth', 1.2);
        text(ax1, req(1), req(2), sprintf('  P%d', i), 'FontSize', 9);
    end
    xlabel(ax1, 'down-range x [m]');
    ylabel(ax1, 'cross-range y [m]   (axes are not equal)');
    if o.SingleAperture
        title(ax1, 'o requested    x where the radar ASSUMES it is');
    else
        title(ax1, 'o requested    x where the radar measured it');
    end
    localLightAxes(ax1);

    ax2 = nexttile(tl); hold(ax2,'on'); grid(ax2,'on'); box(ax2,'on');
    bar(ax2, [rangeErr, resid]);
    set(ax2, 'XTick', 1:nPh);
    xlabel(ax2, 'phantom');
    ylabel(ax2, 'error [m]');
    legend(ax2, {'range error', 'total displacement'}, 'Location', 'northwest');
    if o.SingleAperture
        title(ax2, 'range is measured; cross-range never is');
    else
        title(ax2, 'the range is honoured; the bearing is not');
    end
    localLightAxes(ax2);

    if o.SingleAperture
        cap = sprintf(['SINGLE APERTURE: range exact to within a %.1f m cell; ' ...
            'cross-range unmeasured, so %.0f m of displacement costs nothing -- ' ...
            'all %d labelled %s'], C.range_per_sample, max(resid), nPh, ...
            strjoin(unique(fb.track_label), '/'));
    else
        cap = sprintf(['TWO APERTURES: same phantoms, bearing now measured -- ' ...
            'all %d labelled %s'], nPh, strjoin(unique(fb.track_label), '/'));
    end
    title(tl, cap, 'FontWeight', 'normal', 'Color', 'k');
    exportgraphics(f, [stem '.png'], 'Resolution', 200, 'BackgroundColor', 'w');
    close(f);
    fprintf('\n  wrote %s\n  wrote %s\n', [stem '.png'], [stem '_data.csv']);
    out.png = [stem '.png'];
    out.csv = [stem '_data.csv'];
end


function localLightAxes(ax)
%LOCALLIGHTAXES  Force a light axes regardless of the session's theme, so the
%   exported figure matches this project's white-background convention on any
%   machine. Same reason +experiments/standardEngagementMap.m does it.
    set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
            'GridColor', [0.15 0.15 0.15], 'GridAlpha', 0.15);
    set([ax.Title, ax.XLabel, ax.YLabel], 'Color', 'k');
end
