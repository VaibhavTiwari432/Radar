function streamManualSceneToFile(controls, outFile, opts)
%STREAMMANUALSCENETOFILE  Run a real scene through the backend, then emit
%   each frame to outFile as one NDJSON line (one JSON object per line),
%   PACED at the real radar's own frame_interval_s between emissions -- a
%   client tailing outFile sees the mission unfold at the same real-world
%   cadence the radar would actually produce looks (one look per
%   frame_interval_s), not an instant dump.
%
%   missionsim.streamManualSceneToFile(controls, outFile)
%   missionsim.streamManualSceneToFile(controls, outFile, opts)
%       controls : see missionsim.buildSceneFromControls.
%       outFile  : path to write. Truncated/recreated at the start of every
%                  call so a re-run never appends to a stale prior mission.
%       opts.paced : default true. Pause frame_interval_s between frame
%                  emissions. Set false only for fast tests.
%
%   HONEST LIMIT, stated plainly, not glossed over: the underlying CFAR/
%   tracker computation is still ONE BATCH CALL (engine.runJudge processes
%   the whole rx_frames matrix at once, as it always has in this project --
%   restructuring that into truly incremental per-frame processing is a
%   separate, larger change to a heavily-validated core function, not made
%   here). What is genuinely live here is the EMISSION pacing and
%   missionsim.buildFrameLog's own per-frame work (the growing-window ECCM
%   discriminator re-run) -- not the underlying detection numbers
%   themselves, which exist in full the moment engine.runJudge returns,
%   before this function starts writing anything. A client watching outFile
%   grow is watching a real, already-computed result unfold at the real
%   radar's own timing, not a live radar computation in progress.

    if nargin < 3; opts = struct(); end
    if ~isfield(opts, 'paced'); opts.paced = true; end

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

    fid = fopen(outFile, 'w');   % truncate/create fresh
    if fid < 0
        error('missionsim:streamManualSceneToFile:cannotOpen', 'Could not open "%s" for writing.', outFile);
    end
    fclose(fid);

    dt = S.frame_interval_s;
    missionsim.buildFrameLog(phantoms, S, feedback, C, ...
        @(f) localEmitFrame(outFile, f, dt, opts.paced));

    localAppendLine(outFile, jsonencode(struct('marker', "__end__")));
end

% ===================== file-local helpers =============================
function localEmitFrame(outFile, f, dt, paced)
    localAppendLine(outFile, jsonencode(f));
    if paced
        pause(dt);
    end
end

function localAppendLine(outFile, line)
    fid = fopen(outFile, 'a');
    fprintf(fid, '%s\n', line);
    fclose(fid);   % close, not just flush -- guarantees the bytes are on
                   % disk before the next poll from the browser can see them
end

function localDeleteIfExists(f)
    if isfile(f); delete(f); end
end
