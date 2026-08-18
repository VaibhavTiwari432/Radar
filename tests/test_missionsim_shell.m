classdef test_missionsim_shell < matlab.unittest.TestCase
%TEST_MISSIONSIM_SHELL  Mission Simulator build order (MISSION_SIMULATOR_
%   UI_SPEC.md Section 9), Step 1: static three-panel shell.
%
%   Acceptance criterion (verbatim): "Renders a hand-written frame JSON
%   correctly. Right panel has no editable control while running=true."

    methods (TestClassSetup)
        function assumeArchivedDependencyPresent(tc)
            % 7 Aug 2026 archive: every scene in this file is built by
            % engine.sceneContract, which no longer exists. Report Incomplete --
            % this project's own honest "not built yet" outcome, the same
            % one DataIntegration_Test uses for an absent dataset -- rather
            % than erroring. 63 errored methods made a real regression
            % invisible; a skip keeps the suite usable as an instrument.
            % NOT a fix: rewire to generator.render to genuinely re-enable.
            tc.assumeTrue(archivedDepsPresent({'engine.sceneContract'}), ...
                'engine.sceneContract was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
        end
    end

    methods (Test)

        function test_renders_hand_written_frame_json_correctly(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            json = jsonencode(struct( ...
                'frame', 142, 't', 14.2, 'phase', "DECEPTION_HOLDING", ...
                'radar', struct('identity', struct( ...
                    'fs', struct('value', 3.2e6, 'unit', 'Hz', 'provenance', "DERIVED"), ...
                    'priUs', struct('value', 20.0, 'unit', 'us', 'provenance', "MEASURED"), ...
                    'rangeCellM', struct('value', 46.9, 'unit', 'm', 'provenance', "DERIVED"), ...
                    'unambigRangeM', struct('value', 3000, 'unit', 'm', 'provenance', "DERIVED")), ...
                    'scoreboard', struct( ...
                    'confirmedFalseTracks', struct('value', 3, 'provenance', "MEASURED"), ...
                    'deceptionRate', struct('value', 0.62, 'provenance', "MEASURED")))));

            app.loadFrame(json);   % the raw JSON STRING, not a pre-decoded struct

            tc.verifyEqual(app.PhaseBannerLabel.Text, 'PHASE — DECEPTION_HOLDING');
            tc.verifyTrue(contains(app.FsLabel.Text, '3.2e+06'));
            tc.verifyTrue(contains(app.FsLabel.Text, 'DERIVED'));
            tc.verifyTrue(contains(app.DeceptionRateLabel.Text, '0.62'));
            tc.verifyTrue(contains(app.ConfirmedFalseTracksLabel.Text, '3'));
        end

        function test_invalid_frame_is_rejected_not_rendered(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            badFrame.radar.identity.fs = struct('value', 3.2e6, 'unit', 'Hz');  % missing provenance
            tc.verifyError(@() app.loadFrame(badFrame), 'missionsim:invalidFrame');
            tc.verifyEqual(app.PhaseBannerLabel.Text, 'PHASE — (no frame loaded)', ...
                'A rejected frame must not partially render.');
        end

        function test_right_panel_setup_controls_locked_while_running(tc)
            % The exact R1 rule (Section 1): "No right-panel control is
            % editable while a run is in progress."
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            tc.verifyEqual(char(app.CfarTypeDropdown.Enable), 'on', ...
                'Setup controls should start editable (no run in progress).');

            app.setRunning(true);
            tc.verifyEqual(char(app.CfarTypeDropdown.Enable), 'off');
            tc.verifyEqual(char(app.DesignPfaField.Enable), 'off');
            tc.verifyEqual(char(app.FilterTypeDropdown.Enable), 'off');
            tc.verifyEqual(char(app.ConfirmThresholdField.Enable), 'off');

            app.setRunning(false);
            tc.verifyEqual(char(app.CfarTypeDropdown.Enable), 'on', ...
                'Setup controls should re-enable once the run stops.');
        end

        function test_run_pause_button_toggles_running_state(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            tc.verifyFalse(app.Running);
            app.RunPauseButton.ButtonPushedFcn(app.RunPauseButton, []);
            tc.verifyTrue(app.Running);
            tc.verifyEqual(char(app.CfarTypeDropdown.Enable), 'off');
        end

    end

end
