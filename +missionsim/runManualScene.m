function frameLog = runManualScene(controls)
%RUNMANUALSCENE  End-to-end: left-panel controls -> real scene -> real
%   judge -> frame log. The function app.onRunManualScenePressed calls;
%   split out so it's independently testable without a live uifigure.
%
%   frameLog = missionsim.runManualScene(controls)
%       controls : see missionsim.buildSceneFromControls (n, amplitudeProfile,
%                  phaseProfile).
%       frameLog : missionsim.buildFrameLog's own output -- a {1 x
%                  numFrames} cell of schema-valid frame structs.

    phantoms = missionsim.buildSceneFromControls(controls);
    C = physics.Constants();
    radarState = engine.sceneContract().radarState;

    scene = struct('phantoms', phantoms, 'maneuver', "swarm", ...
                    'eirp_budget_dbw', 20.0, 't0_s', 0.0, 'duration_s', 8.0);
    scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
    rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
    twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
    renderRng = py.numpy.random.default_rng(int64(20261166));   % this project's own mission seed

    tmpMat = [tempname(), '.mat'];
    cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
    py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rsPy, twinConfig, renderRng, tmpMat);

    feedback = engine.runJudge(tmpMat);
    S = load(tmpMat);
    frameLog = missionsim.buildFrameLog(phantoms, S, feedback, C);
end

% ===================== file-local helpers =============================
function localDeleteIfExists(f)
    if isfile(f); delete(f); end
end
