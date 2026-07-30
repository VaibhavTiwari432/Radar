classdef test_missionsim_left_panel < matlab.unittest.TestCase
%TEST_MISSIONSIM_LEFT_PANEL  Mission Simulator build order Step 8: left
%   panel controls wired.
%
%   Acceptance criterion (verbatim): "Setting N=4 in MANUAL produces
%   exactly 4 phantoms in the frame log. In D3QN mode, controls are
%   disabled and mirror the agent's action."

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_manual_N4_produces_exactly_4_phantoms(tc)
            controls.n = 4; controls.amplitudeProfile = 'uniform'; controls.phaseProfile = 'random';
            frameLog = missionsim.runManualScene(controls);

            tc.verifyGreaterThan(numel(frameLog), 0);
            for k = 1:numel(frameLog)
                tc.verifyEqual(numel(frameLog{k}.synth.phantoms), 4, ...
                    sprintf('Frame %d should carry exactly 4 phantoms.', k));
                tc.verifyEqual(numel(frameLog{k}.truth.phantoms), 4);
            end
        end

        function test_manual_N_varies_phantom_count_exactly(tc)
            for n = [1, 2, 5]
                controls.n = n; controls.amplitudeProfile = 'uniform'; controls.phaseProfile = 'random';
                phantoms = missionsim.buildSceneFromControls(controls);
                tc.verifyEqual(numel(phantoms), n, sprintf('N=%d should produce exactly %d phantoms.', n, n));
                totalPowerW = sum([phantoms.amp_scale]) / 3.0 * 60.0;
                tc.verifyLessThan(abs(totalPowerW - 60.0), 1e-6, ...
                    'Total allocated power should sum to exactly the 60W shared budget regardless of N.');
            end
        end

        function test_n_out_of_range_errors(tc)
            controls.n = 6; controls.amplitudeProfile = 'uniform'; controls.phaseProfile = 'random';
            tc.verifyError(@() missionsim.buildSceneFromControls(controls), ...
                'missionsim:buildSceneFromControls:nOutOfRange');
        end

        function test_d3qn_mode_locks_controls_and_mirrors_action(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            tc.verifyEqual(char(app.PhantomCountSlider.Enable), 'on', ...
                'Controls should start editable in OFF/MANUAL mode.');

            app.onEngineModeChanged('D3QN');
            tc.verifyEqual(char(app.PhantomCountSlider.Enable), 'off');
            tc.verifyEqual(char(app.AmplitudeProfileDropdown.Enable), 'off');
            tc.verifyEqual(char(app.PhaseProfileDropdown.Enable), 'off');

            % Controls must MIRROR the agent's action, not just lock.
            tc.verifyEqual(app.PhantomCountSlider.Value, app.D3QNAction.n);
            tc.verifyEqual(app.AmplitudeProfileDropdown.Value, app.D3QNAction.amplitudeProfile);
            tc.verifyEqual(app.PhaseProfileDropdown.Value, app.D3QNAction.phaseProfile);

            app.onEngineModeChanged('MANUAL');
            tc.verifyEqual(char(app.PhantomCountSlider.Enable), 'on', ...
                'Controls should re-enable when leaving D3QN mode.');
        end

        function test_run_button_produces_frame_with_correct_phantom_count(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            app.PhantomCountSlider.Value = 2;
            app.AmplitudeProfileDropdown.Value = 'uniform';
            app.PhaseProfileDropdown.Value = 'random';

            app.onRunManualScenePressed();

            tc.verifyEqual(numel(app.CurrentFrame.synth.phantoms), 2);
            tc.verifyFalse(app.Running, 'Running should return to false once the scene finishes.');
            tc.verifyTrue(contains(app.LastSceneResultLabel.Text, 'N=2'));
        end

    end

end

% ===================== file-local helpers =============================
function tf = localPythonReady()
    try
        py.importlib.import_module('cogengine');
        tf = true;
    catch
        tf = false;
    end
end
