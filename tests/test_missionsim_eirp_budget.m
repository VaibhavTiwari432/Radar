classdef test_missionsim_eirp_budget < matlab.unittest.TestCase
%TEST_MISSIONSIM_EIRP_BUDGET  Mission Simulator build order Step 9: EIRP
%   budget enforcement.
%
%   Acceptance criterion (verbatim): "A configuration exceeding 200 W peak
%   blocks transmission for that frame; log records the block."

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_exceeding_peak_cap_blocks_and_logs(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            app.PhantomCountSlider.Value = 1;
            app.AmplitudeProfileDropdown.Value = 'uniform';
            app.PhaseProfileDropdown.Value = 'random';
            app.AvgEirpCapField.Value = 500;   % user sets average budget ABOVE the hardware peak ceiling
            app.PeakEirpCapField.Value = 200;  % hardware ceiling -- must be absolute, not a suggestion

            tc.verifyEmpty(app.BlockedTransmissionLog);

            app.onRunManualScenePressed();

            tc.verifyTrue(contains(app.LastSceneResultLabel.Text, 'BLOCKED'), ...
                'A peak-exceeding configuration must be blocked, not run.');
            tc.verifyEqual(numel(app.BlockedTransmissionLog), 1, ...
                'The block must be LOGGED (verbatim criterion), not just prevented silently.');
            tc.verifyEqual(app.CurrentFrame, struct(), ...
                'A blocked configuration must never reach the judge -- no frame should load.');
            tc.verifyFalse(app.Running, 'Running must not get stuck true after a block.');
        end

        function test_compliant_configuration_runs_normally(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            app.PhantomCountSlider.Value = 2;
            app.AmplitudeProfileDropdown.Value = 'uniform';
            app.PhaseProfileDropdown.Value = 'random';
            app.AvgEirpCapField.Value = 60;    % nominal, well within the 200W peak ceiling
            app.PeakEirpCapField.Value = 200;

            app.onRunManualScenePressed();

            tc.verifyEmpty(app.BlockedTransmissionLog, ...
                'A compliant configuration should never be blocked.');
            tc.verifyFalse(contains(app.LastSceneResultLabel.Text, 'BLOCKED'));
            tc.verifyTrue(isfield(app.CurrentFrame, 'synth'), 'A compliant run should actually reach the judge.');
        end

        function test_budget_bar_color_reflects_utilization(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            app.PhantomCountSlider.Value = 1;
            app.AmplitudeProfileDropdown.Value = 'uniform';
            app.PhaseProfileDropdown.Value = 'random';

            app.AvgEirpCapField.Value = 60; app.PeakEirpCapField.Value = 200;   % 30% utilization -> green
            app.onRunManualScenePressed();
            tc.verifyEqual(app.BudgetBarLabel.FontColor, [0 0.6 0]);

            app.AvgEirpCapField.Value = 500; app.PeakEirpCapField.Value = 200;   % breach -> red
            app.onRunManualScenePressed();
            tc.verifyEqual(app.BudgetBarLabel.FontColor, [0.8 0 0]);
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
