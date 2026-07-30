classdef test_missionsim_export < matlab.unittest.TestCase
%TEST_MISSIONSIM_EXPORT  Mission Simulator build order Step 10: frame log
%   export.
%
%   Acceptance criterion (verbatim): "A full run exports valid JSON;
%   re-importing reproduces identical panel state."

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_export_then_reimport_reproduces_identical_panel_state(tc)
            controls.n = 3; controls.amplitudeProfile = 'decaying'; controls.phaseProfile = 'coherent';
            frameLog = missionsim.runManualScene(controls);

            here = fileparts(mfilename('fullpath'));
            tmpJson = fullfile(here, '_tmp_export_test.json');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpJson)); %#ok<NASGU>

            missionsim.exportFrameLog(frameLog, tmpJson);
            tc.verifyTrue(isfile(tmpJson));

            reimported = missionsim.importFrameLog(tmpJson);
            tc.verifyEqual(numel(reimported), numel(frameLog));

            appOriginal = missionsim.MissionSimulatorApp();
            appReimported = missionsim.MissionSimulatorApp();
            cleanup1 = onCleanup(@() delete(appOriginal)); %#ok<NASGU>
            cleanup2 = onCleanup(@() delete(appReimported)); %#ok<NASGU>

            appOriginal.loadFrame(frameLog{end});
            appReimported.loadFrame(reimported{end});

            % "Identical panel state" -- compare every readout the two
            % apps actually show, not just the raw struct.
            tc.verifyEqual(appReimported.PhaseBannerLabel.Text, appOriginal.PhaseBannerLabel.Text);
            tc.verifyEqual(appReimported.FsLabel.Text, appOriginal.FsLabel.Text);
            tc.verifyEqual(appReimported.PriLabel.Text, appOriginal.PriLabel.Text);
            tc.verifyEqual(appReimported.RangeCellLabel.Text, appOriginal.RangeCellLabel.Text);
            tc.verifyEqual(appReimported.UnambigRangeLabel.Text, appOriginal.UnambigRangeLabel.Text);
            tc.verifyEqual(appReimported.ConfirmedFalseTracksLabel.Text, appOriginal.ConfirmedFalseTracksLabel.Text);
            tc.verifyEqual(appReimported.DeceptionRateLabel.Text, appOriginal.DeceptionRateLabel.Text);
            tc.verifyEqual(appReimported.TrackTable.Data, appOriginal.TrackTable.Data);
            tc.verifyEqual(appReimported.RangeRingRadii, appOriginal.RangeRingRadii);
        end

        function test_export_refuses_an_invalid_frame(tc)
            badFrameLog = {struct('radar', struct('identity', struct( ...
                'fs', struct('value', 3.2e6, 'unit', 'Hz'))))};  % missing provenance
            here = fileparts(mfilename('fullpath'));
            tmpJson = fullfile(here, '_tmp_export_invalid.json');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpJson)); %#ok<NASGU>

            tc.verifyError(@() missionsim.exportFrameLog(badFrameLog, tmpJson), ...
                'missionsim:exportFrameLog:invalidFrame');
            tc.verifyFalse(isfile(tmpJson), 'An invalid frame must not produce a partial export file.');
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

function localDeleteIfExists(f)
    if isfile(f); delete(f); end
end
