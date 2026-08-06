function scene = decideScene(radarState)
%DECIDESCENE  The integration seam: MATLAB pipeline -> cognitive engine -> Scene.
%
%   scene = engine.decideScene(radarState) returns a Scene struct (see
%   scene_contract.m) that the MATLAB renderer + INDEPENDENT judge consume.
%
%   Two supported paths (design doc Part 6). Pick one; both honour the same
%   RadarState/Scene data contract so the Python brain stays swappable.
%
%   IMPORTANT: the engine plans against its own radar TWIN. Keep the twin
%   separate from THIS pipeline's judge (phased.CFARDetector + trackerGNN);
%   the gap between them is the honest result to report.

    method = "pyenv";   % "onnx" | "pyenv" | "matlab"

    switch method
        % --- Path A: run a Python-trained policy via ONNX (no live Python) -----
        case "onnx"
            persistent net
            if isempty(net)
                net = importNetworkFromONNX("policy.onnx");  % Deep Learning Toolbox
            end
            obs = [radarState.prf_hz; radarState.carrier_hz; ...
                   radarState.n_pulses; radarState.doubt_cue];
            params = predict(net, dlarray(single(obs), "CB"));
            scene  = engine.decodeSceneParams(extractdata(params), radarState);

        % --- Path B: call the live Python cognitive engine (CEM/MPC) ----------
        case "pyenv"
            % Requires: pyenv configured; cogengine on the Python path.
            py.importlib.import_module("cogengine");
            rs = py.cogengine.schema.RadarState( ...
                    pyargs("prf_hz", radarState.prf_hz, ...
                           "carrier_hz", radarState.carrier_hz, ...
                           "n_pulses", int64(radarState.n_pulses)));
            twin  = py.cogengine.radar_twin.RadarTwin(rs);
            tup   = py.cogengine.planner_cem.cem_plan(rs, twin, pyargs("n_phantoms", int64(4)));
            scene = engine.pySceneToStruct(tup{1});   % Scene.to_dict -> struct

        % --- Path C: pure-MATLAB CEM (no Python at all, for the demo) ---------
        case "matlab"
            scene = engine.cemPlanMatlab(radarState);   % reimplement Part 5.2 in MATLAB
    end
end
