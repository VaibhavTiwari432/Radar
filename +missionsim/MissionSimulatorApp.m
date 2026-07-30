classdef MissionSimulatorApp < handle
    %MISSIONSIMULATORAPP  The three-panel Mission Simulator shell
    %   (MISSION_SIMULATOR_UI_SPEC.md Section 1-5, build order Section 9
    %   Step 1). Programmatic uifigure/uigridlayout (not an App Designer
    %   .mlapp -- .mlapp is a binary/zip format not amenable to text-based
    %   editing and code review; uifigure gets the same component set with
    %   plain, diffable, testable .m source).
    %
    %   LEFT   = Synthesizer World, the only editable region (Section 3).
    %   MIDDLE = 3D Scenario, read-only, shared geometry (Section 4).
    %   RIGHT  = Radar Truth, read-only DURING a run; its own Setup-mode
    %            controls (CFAR type, filter type, thresholds) are only
    %            editable before a run starts (R1, Section 1) -- enforced
    %            here structurally via Enable state driven by app.Running,
    %            not by convention.
    %
    %   app = missionsim.MissionSimulatorApp() builds and shows the shell.
    %   app.loadFrame(frameOrJson) validates (missionsim.validateFrame)
    %       and renders a frame -- Step 1's own acceptance criterion:
    %       "Renders a hand-written frame JSON correctly."
    %   app.setRunning(tf) is R1's structural enforcement point.

    properties
        Fig
        Running (1,1) logical = false
        CurrentFrame = struct()
        PhysConstants               % physics.Constants(), cached once (no free params)
        RangeRingRadii = struct('unambigRangeM', NaN, 'recordCeilingM', NaN)

        % ---- LEFT panel (Section 3.1 Mission Control subset -- Step 1's
        % shell scope; the rest of Section 3 is Step 8's job) ----
        RunPauseButton
        StepFrameButton
        ResetButton
        ScenarioPresetDropdown
        ControlResultLabel
        LastControlResult = struct()

        % ---- LEFT panel (Section 3.2 Hallucination Engine -- Step 8) ----
        EngineModeDropdown
        PhantomCountSlider
        PhantomCountValueLabel
        AmplitudeProfileDropdown
        PhaseProfileDropdown
        DopplerSeparationSlider
        CarrierAssumedLabel
        RunManualSceneButton
        LastSceneResultLabel
        D3QNAction = struct('n', 3, 'amplitudeProfile', 'uniform', 'phaseProfile', 'random')

        % ---- LEFT panel (Section 3.3 Platform & RF Budget -- Step 9) ----
        PeakEirpCapField
        AvgEirpCapField
        BudgetBarLabel
        BlockedTransmissionLog = struct('frame', {}, 'reason', {})

        % ---- MIDDLE panel (Section 4) ----
        PhaseBannerLabel
        SceneAxes

        % ---- RIGHT panel: Setup-mode controls, LOCKED while Running (R1) ----
        CfarTypeDropdown
        DesignPfaField
        FilterTypeDropdown
        ConfirmThresholdField

        % ---- RIGHT panel: live readouts (Section 5.1/5.6), always read-only ----
        FsLabel
        PriLabel
        RangeCellLabel
        UnambigRangeLabel
        ConfirmedFalseTracksLabel
        DeceptionRateLabel
        TrackTable
        TrackMarkerOpacities   % containers.Map, initialized fresh per-instance in the constructor (handle-class gotcha)
    end

    properties (Constant)
        % This project's ACTUAL configured value (+track/runTracker.m),
        % never the spec's illustrative [6 6] default -- Section 7's
        % "3/6 misses to deletion" counter uses the real threshold.
        DELETION_THRESHOLD_MISSES = 5
    end

    methods
        function app = MissionSimulatorApp()
            app.PhysConstants = physics.Constants();
            app.TrackMarkerOpacities = containers.Map('KeyType', 'char', 'ValueType', 'double');
            app.Fig = uifigure('Name', 'Mission Simulator', 'Position', [100 100 1400 820]);
            root = uigridlayout(app.Fig, [1 3]);
            root.ColumnWidth = {'1x', '2x', '1x'};
            root.Padding = [8 8 8 8];

            leftPanel   = uipanel(root, 'Title', 'SYNTHESIZER WORLD  (editable)');
            middlePanel = uipanel(root, 'Title', '3D SCENARIO  (read-only, shared)');
            rightPanel  = uipanel(root, 'Title', 'RADAR TRUTH  (read-only during a run)');

            app.buildLeftPanel(leftPanel);
            app.buildMiddlePanel(middlePanel);
            app.buildRightPanel(rightPanel);

            app.setRunning(false);
        end

        function buildLeftPanel(app, parent)
            g = uigridlayout(parent, [15 2]);
            g.RowHeight = [repmat({'fit'}, 1, 14), {'1x'}];
            g.Scrollable = 'on';

            app.RunPauseButton = uibutton(g, 'Text', 'Run', ...
                'ButtonPushedFcn', @(~, ~) app.onRunPausePressed());
            app.RunPauseButton.Layout.Row = 1; app.RunPauseButton.Layout.Column = 1;

            app.StepFrameButton = uibutton(g, 'Text', 'Step frame');
            app.StepFrameButton.Layout.Row = 1; app.StepFrameButton.Layout.Column = 2;

            app.ResetButton = uibutton(g, 'Text', 'Reset', ...
                'ButtonPushedFcn', @(~, ~) app.onResetPressed());
            app.ResetButton.Layout.Row = 2; app.ResetButton.Layout.Column = 1;

            uilabel(g, 'Text', 'Scenario preset');
            app.ScenarioPresetDropdown = uidropdown(g, ...
                'Items', {'Ingress', 'C1: Noise only', 'C2: Single real target', 'Custom'}, ...
                'ValueChangedFcn', @(src, ~) app.onScenarioPresetChanged(src.Value));
            app.ScenarioPresetDropdown.Layout.Row = 3; app.ScenarioPresetDropdown.Layout.Column = 2;

            app.ControlResultLabel = uilabel(g, 'Text', '', 'WordWrap', 'on');
            app.ControlResultLabel.Layout.Row = 4; app.ControlResultLabel.Layout.Column = [1 2];

            % ---- 3.2 Hallucination Engine ----
            uilabel(g, 'Text', 'Engine mode', 'FontWeight', 'bold');
            app.EngineModeDropdown = uidropdown(g, 'Items', {'OFF', 'MANUAL', 'D3QN'}, ...
                'ValueChangedFcn', @(src, ~) app.onEngineModeChanged(src.Value));
            app.EngineModeDropdown.Layout.Row = 5; app.EngineModeDropdown.Layout.Column = 2;

            uilabel(g, 'Text', 'Phantom count');
            app.PhantomCountSlider = uislider(g, 'Limits', [1 5], 'Value', 3, ...
                'MajorTicks', 1:5, 'MinorTicks', [], ...
                'ValueChangedFcn', @(src, ~) app.onPhantomCountChanged(round(src.Value)));
            app.PhantomCountSlider.Layout.Row = 6; app.PhantomCountSlider.Layout.Column = 2;
            app.PhantomCountValueLabel = uilabel(g, 'Text', 'N=3', 'HorizontalAlignment', 'right');
            app.PhantomCountValueLabel.Layout.Row = 6; app.PhantomCountValueLabel.Layout.Column = 1;

            uilabel(g, 'Text', 'Amplitude profile');
            app.AmplitudeProfileDropdown = uidropdown(g, 'Items', {'uniform', 'decaying', 'random'});
            app.AmplitudeProfileDropdown.Layout.Row = 7; app.AmplitudeProfileDropdown.Layout.Column = 2;

            uilabel(g, 'Text', 'Phase profile');
            app.PhaseProfileDropdown = uidropdown(g, 'Items', {'random', 'coherent', 'staggered'});
            app.PhaseProfileDropdown.Layout.Row = 8; app.PhaseProfileDropdown.Layout.Column = 2;

            uilabel(g, 'Text', 'Doppler separation');
            app.DopplerSeparationSlider = uislider(g, 'Limits', [0 500], 'Value', 120);
            app.DopplerSeparationSlider.Layout.Row = 9; app.DopplerSeparationSlider.Layout.Column = 2;
            % Carrier is ASSUMED (RadChar is baseband -- data/README.md's
            % own note), read from this project's own already-established
            % assumed value (engine.sceneContract().radarState.carrier_hz),
            % never a typed "10.0 GHz" string.
            assumedCarrierHz = engine.sceneContract().radarState.carrier_hz;
            app.CarrierAssumedLabel = uilabel(g, ...
                'Text', sprintf('carrier assumed: %.1f GHz', assumedCarrierHz / 1e9), ...
                'FontColor', [0.6 0.4 0]);
            app.CarrierAssumedLabel.Layout.Row = 10; app.CarrierAssumedLabel.Layout.Column = [1 2];

            % ---- 3.3 Platform & RF Budget (Step 9: EIRP enforcement) ----
            uilabel(g, 'Text', 'Average EIRP cap (W)');
            app.AvgEirpCapField = uieditfield(g, 'numeric', 'Value', 60, 'Limits', [0.1 Inf]);
            app.AvgEirpCapField.Layout.Row = 11; app.AvgEirpCapField.Layout.Column = 2;

            uilabel(g, 'Text', 'Peak EIRP cap (W)');
            app.PeakEirpCapField = uieditfield(g, 'numeric', 'Value', 200, 'Limits', [0.1 Inf]);
            app.PeakEirpCapField.Layout.Row = 12; app.PeakEirpCapField.Layout.Column = 2;

            app.BudgetBarLabel = uilabel(g, 'Text', '', 'FontColor', [0 0.6 0]);
            app.BudgetBarLabel.Layout.Row = 13; app.BudgetBarLabel.Layout.Column = [1 2];

            app.RunManualSceneButton = uibutton(g, 'Text', 'Run scene through real judge', ...
                'ButtonPushedFcn', @(~, ~) app.onRunManualScenePressed());
            app.RunManualSceneButton.Layout.Row = 14; app.RunManualSceneButton.Layout.Column = [1 2];
            app.LastSceneResultLabel = uilabel(g, 'Text', '', 'WordWrap', 'on');
            app.LastSceneResultLabel.Layout.Row = 15; app.LastSceneResultLabel.Layout.Column = [1 2];
        end

        function onPhantomCountChanged(app, n)
            app.PhantomCountValueLabel.Text = sprintf('N=%d', n);
        end

        function onEngineModeChanged(app, mode)
            %ONENGINEMODECHANGED  Section 3.2's critical interaction:
            %   "when Engine mode = D3QN, the N slider, amplitude, and
            %   phase controls grey out and become live readouts of the
            %   agent's chosen action." HONEST GAP: this project has no
            %   trained D3QN policy validated end-to-end (Stage 6/7 are the
            %   RL training stages; a real training run is its own,
            %   separate undertaking, not done as part of this UI build).
            %   "The agent's action" here is therefore a documented
            %   PLACEHOLDER action generator (missionsim.pickD3qnAction),
            %   not real trained-policy inference -- the STRUCTURAL
            %   behavior (controls lock, mirror SOME action) is what this
            %   step's acceptance criterion actually tests, and is real.
            isD3qn = strcmp(mode, 'D3QN');
            lockState = matlab.lang.OnOffSwitchState(~isD3qn);
            app.PhantomCountSlider.Enable = lockState;
            app.AmplitudeProfileDropdown.Enable = lockState;
            app.PhaseProfileDropdown.Enable = lockState;
            if isD3qn
                app.D3QNAction = missionsim.pickD3qnAction();
                app.PhantomCountSlider.Value = app.D3QNAction.n;
                app.PhantomCountValueLabel.Text = sprintf('N=%d (agent)', app.D3QNAction.n);
                app.AmplitudeProfileDropdown.Value = app.D3QNAction.amplitudeProfile;
                app.PhaseProfileDropdown.Value = app.D3QNAction.phaseProfile;
            end
        end

        function onRunManualScenePressed(app)
            %ONRUNMANUALSCENEPRESSED  Step 8's own acceptance criterion:
            %   "Setting N=4 in MANUAL produces exactly 4 phantoms in the
            %   frame log." Runs the ACTUAL judge pipeline end to end
            %   (missionsim.buildSceneFromControls -> the real
            %   cogengine.matlab_judge.export_scene_for_judge ->
            %   engine.runJudge -> missionsim.buildFrameLog -> loadFrame),
            %   not a mock. Step 9's EIRP budget check (below) runs FIRST,
            %   before any transmission -- "a configuration exceeding
            %   200 W peak blocks transmission for that frame."
            controls.n = round(app.PhantomCountSlider.Value);
            controls.amplitudeProfile = app.AmplitudeProfileDropdown.Value;
            controls.phaseProfile = app.PhaseProfileDropdown.Value;

            avgCapW = app.AvgEirpCapField.Value;
            peakCapW = app.PeakEirpCapField.Value;

            phantoms = missionsim.buildSceneFromControls(controls, avgCapW);
            perPhantomW = [phantoms.amp_scale] / 3.0 * 60.0;   % power_w_to_amp_scale's inverse (fixed 3.0/60W anchor)
            totalW = sum(perPhantomW);
            peakUsedW = max(perPhantomW);

            utilizationPct = 100 * peakUsedW / peakCapW;
            if utilizationPct >= 100
                app.BudgetBarLabel.FontColor = [0.8 0 0];
            elseif utilizationPct >= 85
                app.BudgetBarLabel.FontColor = [0.8 0.5 0];
            else
                app.BudgetBarLabel.FontColor = [0 0.6 0];
            end
            app.BudgetBarLabel.Text = sprintf('EIRP: peak %.1f/%.0f W (%.0f%%), total %.1f W', ...
                peakUsedW, peakCapW, utilizationPct, totalW);

            if peakUsedW > peakCapW
                % R1-style hard block (Section 3.3: "breach must block
                % transmission for that frame rather than merely colouring
                % red -- a constraint the UI lets you exceed is not a
                % constraint"). Logged, not silently refused.
                app.BlockedTransmissionLog(end+1) = struct('frame', numel(app.BlockedTransmissionLog)+1, ...
                    'reason', sprintf('peak %.1fW exceeds %.0fW cap', peakUsedW, peakCapW));
                app.LastSceneResultLabel.Text = sprintf( ...
                    'BLOCKED: peak %.1fW exceeds %.0fW cap -- transmission refused, not sent to the judge.', ...
                    peakUsedW, peakCapW);
                return;
            end

            app.LastSceneResultLabel.Text = sprintf('Running N=%d scene through the real judge...', controls.n);
            drawnow;
            app.setRunning(true);
            try
                frameLog = missionsim.runManualScene(controls);
                app.setRunning(false);
                app.LastSceneResultLabel.Text = sprintf('Done: %d frames, N=%d phantoms.', ...
                    numel(frameLog), controls.n);
                app.loadFrame(frameLog{end});
            catch e
                app.setRunning(false);
                app.LastSceneResultLabel.Text = ['Error: ', e.message];
                rethrow(e);
            end
        end

        function onScenarioPresetChanged(app, value)
            %ONSCENARIOPRESETCHANGED  Section 3.5: "Press C1 in front of a
            %   jury: the radar sees noise and confirms nothing. Press C2:
            %   it confirms one real track." -- runs the REAL judge, not a
            %   canned demo string.
            if startsWith(value, 'C1')
                preset = 'C1';
            elseif startsWith(value, 'C2')
                preset = 'C2';
            else
                app.ControlResultLabel.Text = '';
                return;
            end
            app.ControlResultLabel.Text = sprintf('Running %s against the real judge...', preset);
            drawnow;
            result = missionsim.runControlScenario(preset);
            app.LastControlResult = result;
            if strcmp(preset, 'C1')
                app.ControlResultLabel.Text = sprintf( ...
                    '%s: measured Pfa=%.3g vs design %.3g (%.1f%% error, need <20%%) -- %s', ...
                    result.label, result.measuredPfa, result.designPfa, result.relErrPct, ...
                    localPassFailStr(result.pass));
            else
                app.ControlResultLabel.Text = sprintf( ...
                    '%s: confirmed=%d, range err=%.1fm, label=%s -- %s', ...
                    result.label, result.confirmedTracks, result.rangeErrM, result.eccmLabel, ...
                    localPassFailStr(result.pass));
            end
        end

        function buildMiddlePanel(app, parent)
            g = uigridlayout(parent, [2 1]);
            g.RowHeight = {'fit', '1x'};

            app.PhaseBannerLabel = uilabel(g, 'Text', 'PHASE — (no frame loaded)', ...
                'FontWeight', 'bold', 'FontSize', 14, 'HorizontalAlignment', 'center');

            app.SceneAxes = uiaxes(g);
            title(app.SceneAxes, '3D Scenario (Step 3 fills this in)');
        end

        function buildRightPanel(app, parent)
            g = uigridlayout(parent, [12 2]);
            g.RowHeight = repmat({'fit'}, 1, 11); g.RowHeight{end+1} = '1x';

            % ---- 5.1 Radar Identity (always read-only readouts) ----
            uilabel(g, 'Text', 'fs', 'FontWeight', 'bold');
            app.FsLabel = uilabel(g, 'Text', '—');
            uilabel(g, 'Text', 'PRI', 'FontWeight', 'bold');
            app.PriLabel = uilabel(g, 'Text', '—');
            uilabel(g, 'Text', 'Range cell', 'FontWeight', 'bold');
            app.RangeCellLabel = uilabel(g, 'Text', '—');
            uilabel(g, 'Text', 'Unambig. range', 'FontWeight', 'bold');
            app.UnambigRangeLabel = uilabel(g, 'Text', '—');

            % ---- 5.3 Setup-mode controls: LOCKED while Running (R1) ----
            uilabel(g, 'Text', 'CFAR type (setup only)', 'FontWeight', 'bold');
            app.CfarTypeDropdown = uidropdown(g, 'Items', {'CA', 'OS'});
            uilabel(g, 'Text', 'Design Pfa (setup only)', 'FontWeight', 'bold');
            app.DesignPfaField = uieditfield(g, 'numeric', 'Value', 1e-4);
            uilabel(g, 'Text', 'Filter type (setup only)', 'FontWeight', 'bold');
            app.FilterTypeDropdown = uidropdown(g, 'Items', {'KalmanCV', 'IMM'});
            uilabel(g, 'Text', 'Confirm M-of-N (setup only)', 'FontWeight', 'bold');
            app.ConfirmThresholdField = uieditfield(g, 'text', 'Value', '[3 5]');

            % ---- 5.6 Scoreboard (always read-only) ----
            uilabel(g, 'Text', 'Confirmed false tracks', 'FontWeight', 'bold');
            app.ConfirmedFalseTracksLabel = uilabel(g, 'Text', '—');
            uilabel(g, 'Text', 'Deception rate', 'FontWeight', 'bold');
            app.DeceptionRateLabel = uilabel(g, 'Text', '—');

            % ---- 5.4 Track table: "what the radar holds" (Section 9 Step 5/6) ----
            app.TrackTable = uitable(g, ...
                'ColumnName', {'ID', 'State', 'Age', 'Hits', 'Misses', 'ECCM', ...
                                'Amp-range slope (dB/dec)', 'Doppler resid. (m/s)'}, ...
                'ColumnWidth', repmat({'auto'}, 1, 8));
            app.TrackTable.Layout.Row = 12; app.TrackTable.Layout.Column = [1 2];
        end

        function onRunPausePressed(app)
            app.setRunning(~app.Running);
        end

        function onResetPressed(app)
            app.setRunning(false);
        end

        function setRunning(app, tf)
            %SETRUNNING  R1's structural enforcement point (Section 1):
            %   "No right-panel control is editable while a run is in
            %   progress." Setup-mode controls are disabled the moment
            %   Running goes true, full stop -- not "by convention".
            app.Running = logical(tf);
            lockState = matlab.lang.OnOffSwitchState(~app.Running);
            app.CfarTypeDropdown.Enable = lockState;
            app.DesignPfaField.Enable = lockState;
            app.FilterTypeDropdown.Enable = lockState;
            app.ConfirmThresholdField.Enable = lockState;
            if app.Running
                app.RunPauseButton.Text = 'Pause';
            else
                app.RunPauseButton.Text = 'Run';
            end
        end

        function loadFrame(app, frame)
            %LOADFRAME  Step 1's own acceptance criterion: "Renders a
            %   hand-written frame JSON correctly." Validates against the
            %   schema (missionsim.validateFrame) before rendering anything
            %   -- an invalid frame must not silently render partial state.
            if ischar(frame) || isstring(frame)
                frame = jsondecode(char(frame));
            end
            [valid, errors] = missionsim.validateFrame(frame);
            if ~valid
                error('missionsim:invalidFrame', 'Frame failed schema validation:\n%s', ...
                    strjoin(errors, sprintf('\n')));
            end
            app.CurrentFrame = frame;
            app.renderCurrentFrame();
        end

        function renderCurrentFrame(app)
            f = app.CurrentFrame;
            if isfield(f, 'phase')
                app.PhaseBannerLabel.Text = ['PHASE — ', char(f.phase)];
            end
            if isfield(f, 'radar') && isfield(f.radar, 'identity')
                idn = f.radar.identity;
                app.FsLabel.Text = localFmtValue(idn, 'fs', 'Hz');
                app.PriLabel.Text = localFmtValue(idn, 'priUs', 'us');
                app.RangeCellLabel.Text = localFmtValue(idn, 'rangeCellM', 'm');
                app.UnambigRangeLabel.Text = localFmtValue(idn, 'unambigRangeM', 'm');
            end
            if isfield(f, 'radar') && isfield(f.radar, 'scoreboard')
                sb = f.radar.scoreboard;
                app.ConfirmedFalseTracksLabel.Text = localFmtValue(sb, 'confirmedFalseTracks', '');
                app.DeceptionRateLabel.Text = localFmtValue(sb, 'deceptionRate', '');
            end
            app.renderTrackTable();   % computes TrackMarkerOpacities, must run before renderScene3D
            app.renderScene3D();
        end

        function renderTrackTable(app)
            %RENDERTRACKTABLE  Section 5.4, "what the radar holds" -- Step
            %   5/6's own state-machine rendering (TENTATIVE/CONFIRMED/
            %   COASTING/DELETED), driven entirely by
            %   missionsim.buildFrameLog's already-real hit/miss counts,
            %   not re-derived here.
            f = app.CurrentFrame;
            if ~isfield(f, 'radar') || ~isfield(f.radar, 'tracks') || isempty(f.radar.tracks)
                app.TrackTable.Data = cell(0, 8);
                return;
            end
            tr = f.radar.tracks;
            n = numel(tr);
            data = cell(n, 8);
            newOpacities = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for i = 1:n
                % uitable.Data cells must be numeric/logical/char --
                % rejects MATLAB string scalars outright (verified: a
                % hand-built frame using "T01" instead of 'T01' crashed
                % here). The frame schema's own worked example (Section 8)
                % uses double-quoted strings throughout, so this function
                % must accept either, not assume buildFrameLog's own
                % char-producing convention is the only valid input.
                id = char(tr(i).id);
                state = char(tr(i).state);
                data{i,1} = id;
                data{i,2} = state;
                data{i,3} = tr(i).ageFrames;
                data{i,4} = tr(i).hits;
                if strcmp(state, 'COASTING')
                    % Section 7's own language: "3/6 misses to deletion" --
                    % this project's REAL deletion threshold is 5, not the
                    % spec's illustrative 6 (+track/runTracker.m).
                    data{i,5} = sprintf('%d/%d to deletion', tr(i).misses, app.DELETION_THRESHOLD_MISSES);
                else
                    data{i,5} = tr(i).misses;
                end
                data{i,6} = char(tr(i).eccmVerdict);
                % Section 5.5 live gauges -- defensive isfield check: older/
                % hand-built frames (Steps 1/3/4/6's own tests) don't carry
                % these fields, and this function must not error on them.
                if isfield(tr(i), 'ampRangeSlopeDbDecade')
                    data{i,7} = tr(i).ampRangeSlopeDbDecade;
                    data{i,8} = tr(i).dopplerResidualMps;
                else
                    data{i,7} = NaN;
                    data{i,8} = NaN;
                end

                % Opacity decays monotonically with consecutive misses,
                % floor 0 at the deletion threshold -- Step 6's own
                % acceptance criterion, computed here (used by
                % renderScene3D) so table and 3D view can never disagree.
                switch state
                    case 'CONFIRMED'
                        op = 1.0;
                    case 'COASTING'
                        op = max(0, 1 - tr(i).misses / app.DELETION_THRESHOLD_MISSES);
                    case 'TENTATIVE'
                        op = 0.4;
                    otherwise
                        op = 0;
                end
                newOpacities(id) = op;
            end
            app.TrackTable.Data = data;
            app.TrackMarkerOpacities = newOpacities;
        end

        function renderScene3D(app)
            %RENDERSCENE3D  Build order Step 3: middle-panel 3D view +
            %   derived range rings. Acceptance criterion (verbatim):
            %   "Range rings match c*PRI/2 and 512*c/(2*fs) to within 1 m.
            %   No literal km constant appears in source." Both radii are
            %   computed here from physics.Constants() (c, Nsamples) and
            %   the CURRENT frame's own already-derived rangeCellM/priUs --
            %   never a typed km value.
            %
            %   HONEST GAP (missionsim.buildFrameLog's own header repeats
            %   this): this project's backend has never modeled the mother
            %   drone's own 3D trajectory/altitude/RCS as a separately
            %   tracked object -- only phantom ranges exist. This view
            %   therefore renders the radar site + phantoms + derived range
            %   rings; it does not render an invented mother-drone icon
            %   with telemetry no backend run ever produced.
            f = app.CurrentFrame;
            ax = app.SceneAxes;
            cla(ax);
            hold(ax, 'on');

            C = app.PhysConstants;
            if isfield(f, 'radar') && isfield(f.radar, 'identity') ...
                    && isfield(f.radar.identity, 'unambigRangeM')
                unambigM = f.radar.identity.unambigRangeM.value;
            else
                unambigM = C.c * (C.PRI_min + C.PRI_max) / 2 / 2;  % fallback: no frame loaded yet
            end
            recordCeilingM = C.range_window;   % ALREADY 512*c/(2*fs), physics.Constants.m's own derivation
            app.RangeRingRadii.unambigRangeM = unambigM;
            app.RangeRingRadii.recordCeilingM = recordCeilingM;

            theta = linspace(0, 2*pi, 200);
            plot(ax, unambigM * cos(theta), unambigM * sin(theta), 'b--', 'DisplayName', 'Unambiguous range');
            plot(ax, recordCeilingM * cos(theta), recordCeilingM * sin(theta), 'r:', 'DisplayName', 'Record ceiling (512 samples)');

            plot(ax, 0, 0, 'k^', 'MarkerSize', 12, 'MarkerFaceColor', 'k', 'DisplayName', 'Radar site');

            if isfield(f, 'truth') && isfield(f.truth, 'phantoms') && ~isempty(f.truth.phantoms)
                % Each .pos is built as a 1x3 ROW ([range 0 0]), but
                % jsondecode has no way to preserve that after a JSON
                % round-trip (missionsim.exportFrameLog/importFrameLog) --
                % a JSON array [x,y,z] decodes to a 3x1 COLUMN by default,
                % with no orientation metadata to recover it from.
                % Verified directly: an export/re-import round-trip turned
                % vertcat(...) into a 9x1 instead of Nx3, and pos(:,2)
                % errored ("Index...exceeds array bounds"). Normalize each
                % phantom's pos to a row before stacking, regardless of
                % which orientation it arrived in.
                posRows = arrayfun(@(p) reshape(p.pos, 1, 3), f.truth.phantoms, 'UniformOutput', false);
                pos = vertcat(posRows{:});
                plot(ax, pos(:,1), pos(:,2), 'o', 'MarkerSize', 8, 'MarkerFaceColor', [0.6 0.6 0.6], ...
                    'DisplayName', 'Phantoms (assumed shared bearing)');
            end

            % ---- Step 6: track lifecycle rendering -- opacity encodes
            % state, matching TrackMarkerOpacities (renderTrackTable, so
            % table and 3D view can never disagree with each other). ----
            if isfield(f, 'radar') && isfield(f.radar, 'tracks')
                for i = 1:numel(f.radar.tracks)
                    t = f.radar.tracks(i);
                    tid = char(t.id); tstate = char(t.state);   % Map keys/switch need char, not string (see renderTrackTable)
                    if strcmp(tstate, 'DELETED') || ~isKey(app.TrackMarkerOpacities, tid)
                        continue;   % Section 7: DELETED tracks drop off, not rendered
                    end
                    op = app.TrackMarkerOpacities(tid);
                    switch tstate
                        case 'CONFIRMED'; col = [0 0.6 0]; mk = 's';
                        case 'COASTING';  col = [0.9 0.6 0]; mk = 's';
                        otherwise;        col = [0.5 0.5 0.5]; mk = 'd';  % TENTATIVE
                    end
                    % scatter(), not plot(): plain Line objects here don't
                    % support MarkerFaceAlpha/MarkerEdgeAlpha (verified --
                    % errored with "Unrecognized property"); Scatter
                    % objects document and support both.
                    h = scatter(ax, t.rangeEst, 0, 100, col, mk, 'filled', ...
                        'DisplayName', sprintf('%s (%s)', tid, tstate));
                    h.MarkerFaceAlpha = max(0.05, op);
                    h.MarkerEdgeAlpha = max(0.05, op);
                end
            end

            hold(ax, 'off');
            axis(ax, 'equal');
            legend(ax, 'Location', 'northoutside', 'NumColumns', 2);
            title(ax, sprintf('3D Scenario (range rings: %.0f m / %.0f m)', unambigM, recordCeilingM));
        end

        function delete(app)
            if ~isempty(app.Fig) && isvalid(app.Fig)
                close(app.Fig);
            end
        end
    end
end

% ===================== file-local helpers =============================
function s = localPassFailStr(tf)
    if tf; s = 'PASS'; else; s = 'FAIL'; end
end

function s = localFmtValue(container, fieldName, unit)
%LOCALFMTVALUE  Render a {value, unit, provenance}-wrapped field (or a
%   plain scalar) as "value unit [PROVENANCE]" / "value unit", falling
%   back to an em dash if the field is absent -- never errors on a
%   partially-populated frame.
    if ~isfield(container, fieldName)
        s = '—';
        return;
    end
    v = container.(fieldName);
    if isstruct(v) && isfield(v, 'value')
        if isfield(v, 'provenance')
            s = sprintf('%.6g %s [%s]', v.value, unit, char(v.provenance));
        else
            s = sprintf('%.6g %s', v.value, unit);
        end
    else
        s = sprintf('%.6g %s', v, unit);
    end
end
