classdef test_missionsim_controls < matlab.unittest.TestCase
%TEST_MISSIONSIM_CONTROLS  Mission Simulator build order Step 4: detection
%   layer + controls C1/C2.
%
%   Acceptance criterion (verbatim): "C1: noise-only run over >=1e5 cells
%   gives measured P_fa within 20% of design. C2: single real target
%   confirms a track at the correct range bin."

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_C1_noise_only_measured_pfa_within_20pct(tc)
            result = missionsim.runControlScenario('C1');
            fprintf('C1: testableCells=%d measuredPfa=%.4g designPfa=%.4g relErr=%.1f%%\n', ...
                result.testableCells, result.measuredPfa, result.designPfa, result.relErrPct);

            tc.verifyGreaterThanOrEqual(result.testableCells, 1e5 - 100, ...
                'C1 must run over >=1e5 cells (verbatim acceptance criterion).');
            tc.verifyLessThan(result.relErrPct, 20, ...
                'Measured Pfa should be within 20% of design.');
            tc.verifyEqual(result.confirmedTracks, 0, ...
                'Noise-only must confirm nothing (Section 3.5''s own headline claim).');
            tc.verifyTrue(result.pass);
        end

        function test_C2_single_real_target_confirms_at_correct_range(tc)
            result = missionsim.runControlScenario('C2');
            fprintf('C2: confirmed=%d trueFinalRangeM=%.1f rangeErrM=%.1f eccmLabel=%s\n', ...
                result.confirmedTracks, result.trueFinalRangeM, result.rangeErrM, result.eccmLabel);

            tc.verifyTrue(result.confirmed, 'A single, consistent real target must confirm a track.');
            tc.verifyTrue(result.atCorrectBin, ...
                sprintf('Confirmed track range (err=%.1fm) should be within ~2 CFAR bins of the true final range.', ...
                    result.rangeErrM));
            tc.verifyEqual(result.eccmLabel, 'real');
            tc.verifyTrue(result.pass);
        end

        function test_unknown_preset_errors(tc)
            tc.verifyError(@() missionsim.runControlScenario('C3'), ...
                'missionsim:runControlScenario:unknownPreset');
        end

        function test_dropdown_wires_to_real_c1_run(tc)
            % Section 3.5's UI-level promise: selecting the preset in the
            % ACTUAL app runs the real scenario, not a canned string.
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            app.onScenarioPresetChanged('C1: Noise only');

            tc.verifyEqual(app.LastControlResult.preset, 'C1');
            tc.verifyEqual(app.LastControlResult.confirmedTracks, 0);
            tc.verifyTrue(contains(app.ControlResultLabel.Text, 'PASS'), ...
                app.ControlResultLabel.Text);
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
