function frameLog = buildFrameLog(scenePhantoms, S, feedback, C, onFrame)
%BUILDFRAMELOG  Assemble a Mission Simulator frame log (MISSION_SIMULATOR_
%   UI_SPEC.md Section 8's schema) from a REAL, already-run judge result --
%   the bridge between the existing, validated backend
%   (cogengine.matlab_judge.export_scene_for_judge -> engine.runJudge) and
%   the UI. Every frame produced here is validated against
%   missionsim.validateFrame before being returned -- a frame this
%   function builds that fails its own schema is a bug, caught immediately.
%
%   frameLog = missionsim.buildFrameLog(scenePhantoms, S, feedback, C)
%   frameLog = missionsim.buildFrameLog(scenePhantoms, S, feedback, C, onFrame)
%       scenePhantoms : struct array, ground truth (as passed to
%                       cogengine.matlab_judge.export_scene_for_judge --
%                       range_m, radial_vel_mps per phantom at t0).
%       S             : the .mat struct engine.runJudge itself loaded
%                       (fs, pulse_width_s, bandwidth_hz, prf_hz, cfar_pfa,
%                       cfar_num_training, cfar_num_guard, frame_interval_s).
%       feedback      : engine.runJudge's return value -- MUST include
%                       frame_log/track_range_m/track_label etc. (added
%                       this session specifically so this bridge is
%                       possible; see +engine/runJudge.m's own comment).
%       C             : physics.Constants().
%       onFrame       : OPTIONAL function handle, called as onFrame(f) once
%                       per frame, immediately after that frame is built and
%                       validated, in loop order. Added so a caller (see
%                       missionsim.streamManualSceneToFile) can emit each
%                       frame as it's assembled instead of waiting for the
%                       whole log -- the detection/tracking NUMBERS were
%                       already computed by the batch judge call above this
%                       function's caller; what onFrame exposes live is this
%                       function's own per-frame work (the growing-window
%                       ECCM re-derivation), one frame at a time. Default: none.
%       frameLog      : {1 x numFrames} cell of frame structs, each valid
%                       against missionsim.validateFrame.
%
%   HONEST GAP, not papered over: this project's actual radar physics is
%   1D (range + radial velocity only -- Phantom never had a bearing/
%   azimuth/3D-position field anywhere in this codebase, Phase 1 through
%   Task 5). The UI spec's middle panel assumes full 3D scenario geometry.
%   Resolved the same way AI_Cognitive_Engine_Detailed_Design.md's own
%   "Honest Limits" section already does: "one mother drone -> all
%   phantoms share its instantaneous bearing" -- positions here place every
%   phantom along ONE fixed, ASSUMED bearing (local +X) at its real range;
%   bearing/altitude are tagged ASSUMED, never DERIVED or MEASURED, because
%   they are not something this simulation has ever computed.

    if nargin < 5
        onFrame = [];
    end

    numFrames = feedback.num_frames;
    dt = S.frame_interval_s;
    n = numel(scenePhantoms);

    % ---- Radar identity block, computed ONCE (frozen at run start, R1) ----
    fs = double(S.fs);
    pri_s = 1 / double(S.prf_hz);
    rangeCellM = C.c / (2 * fs);
    unambigRangeM = C.c * pri_s / 2;
    identity = struct( ...
        'fs',            struct('value', fs, 'unit', 'Hz', 'provenance', 'DERIVED'), ...
        'priUs',         struct('value', pri_s * 1e6, 'unit', 'us', 'provenance', 'DERIVED'), ...
        'rangeCellM',    struct('value', rangeCellM, 'unit', 'm', 'provenance', 'DERIVED'), ...
        'unambigRangeM', struct('value', unambigRangeM, 'unit', 'm', 'provenance', 'DERIVED'));

    % ---- Per-frame ground truth (this project's own kinematic convention:
    % range advances linearly by radial_vel_mps*dt each frame, identical to
    % cogengine.radar_twin.advance_phantom / matlab_judge.export_scene_for_
    % judge's Python-side advance) ----
    truthRangeAtFrame = zeros(n, numFrames);
    for p = 1:n
        truthRangeAtFrame(p, :) = scenePhantoms(p).range_m + scenePhantoms(p).radial_vel_mps * (0:numFrames-1) * dt;
    end

    % ---- Live, per-frame ECCM verdict: re-run track.discriminator on each
    % track's OWN hit history truncated to "up through frame k" (accumulated
    % below from +engine/runJudge.m's per-frame hitRange/hitAmp, added this
    % session specifically for this), not just the final verdict
    % engine.runJudge already computed once at the end -- Section 5.5's
    % "live numbers, not just pass/fail" taken literally. Reuses the exact
    % same discriminator +track/discriminator.m already calls; this does
    % not reimplement ECCM, it re-invokes it with a growing window. ----
    rangeHistByID = containers.Map('KeyType', 'double', 'ValueType', 'any');
    ampHistByID   = containers.Map('KeyType', 'double', 'ValueType', 'any');
    timeHistByID  = containers.Map('KeyType', 'double', 'ValueType', 'any');

    frameLog = cell(1, numFrames);
    seenIDs = [];

    for k = 1:numFrames
        f = struct();
        f.frame = k;
        f.t = (k - 1) * dt;
        f.phase = localDerivePhase(feedback.frame_log, k);

        % ---- synth (ground truth phantoms as the mother drone's OWN state) ----
        phantomsOut = struct('id', {}, 'range', {}, 'radialVelMps', {});
        for p = 1:n
            phantomsOut(p) = struct( ...
                'id', sprintf('P%d', p), ...
                'range', struct('value', truthRangeAtFrame(p, k), 'unit', 'm', 'provenance', 'DERIVED'), ...
                'radialVelMps', scenePhantoms(p).radial_vel_mps);
        end
        f.synth.phantoms = phantomsOut;

        % ---- truth (shared geometry: bearing/altitude ASSUMED, see header) ----
        truthPhantoms = struct('id', {}, 'pos', {});
        for p = 1:n
            truthPhantoms(p) = struct('id', sprintf('P%d', p), ...
                'pos', [truthRangeAtFrame(p, k), 0, 0]);   % bearing=0, altitude=0: ASSUMED (header)
        end
        f.truth.phantoms = truthPhantoms;

        % ---- radar.identity (same every frame, frozen at run start) ----
        f.radar.identity = identity;

        % ---- radar.detection ----
        tk = feedback.frame_log{k};
        % The JUDGE's own detector settings, read from the judge's own
        % declaration -- NOT from the exported .mat, which the adversary
        % writes and which no longer carries them at all (Phase A1).
        cfarD = radar.cfarDefaults();
        f.radar.detection.cfarType = cfarD.Method;
        f.radar.detection.designPfa = struct('value', cfarD.Pfa, 'provenance', 'ASSUMED');
        f.radar.detection.detectionsThisFrame = numel(unique([tk.trackId]));

        % ---- radar.tracker (this project's ACTUAL configured values,
        % +track/runTracker.m -- never the spec's illustrative defaults) ----
        trkD = track.trackerDefaults();   % same single source the tracker uses
        f.radar.tracker.filter = 'KalmanCV';
        f.radar.tracker.confirmMofN = trkD.ConfirmationThreshold;
        f.radar.tracker.deleteMofN = trkD.DeletionThreshold;

        % ---- radar.tracks: 5-state lifecycle + live ECCM ----
        tracksOut = struct('id', {}, 'state', {}, 'ageFrames', {}, 'hits', {}, ...
            'misses', {}, 'eccmVerdict', {}, 'rangeEst', {}, ...
            'ampRangeSlopeDbDecade', {}, 'dopplerResidualMps', {});
        currentIDs = [tk.trackId];
        seenIDs = union(seenIDs, currentIDs);
        % union()'s output orientation is NOT guaranteed row -- with an
        % empty LHS it returns a COLUMN, and `for id = col` iterates ONCE
        % with id bound to the WHOLE column (MATLAB for-loops iterate
        % columns, not elements) instead of once per ID. Verified this
        % directly: caused "logical indices...outside of the array bounds"
        % a few lines below, id silently became a 4-element vector. Force
        % row orientation explicitly, don't rely on union()'s default.
        for id = seenIDs(:)'
            if ismember(id, currentIDs)
                tt = tk([tk.trackId] == id);
                if ~tt.isConfirmed
                    state = 'TENTATIVE';
                elseif tt.missStreak > 0
                    state = 'COASTING';
                else
                    state = 'CONFIRMED';
                end
                misses = tt.missStreak;
                hits = tt.hits;
                % double(), not the raw uint32 trackerGNN's Age property
                % carries: a JSON export/re-import round-trip always
                % produces double (JSON has no int/float distinction) --
                % coercing here, not patching every downstream comparison,
                % is the same root-cause fix this project already applied
                % once for the identical issue class (cogengine/schema.py's
                % __post_init__ coercion, CLAUDE.md's build-order step 6).
                age = double(tt.age);
                rangeEst = tt.rangeEst;

                % Accumulate this track's OWN hit history for the live
                % discriminator call below.
                if tt.hitThisFrame
                    if ~isKey(rangeHistByID, id)
                        rangeHistByID(id) = zeros(0,1); ampHistByID(id) = zeros(0,1); timeHistByID(id) = zeros(0,1);
                    end
                    rangeHistByID(id) = [rangeHistByID(id); tt.hitRange];
                    ampHistByID(id)   = [ampHistByID(id);   tt.hitAmp];
                    timeHistByID(id)  = [timeHistByID(id);  f.t];
                end
            else
                state = 'DELETED';
                misses = NaN; hits = NaN; age = NaN; rangeEst = NaN;
            end

            % Live ECCM: the SAME track.discriminator +engine/runJudge.m's
            % own final verdict uses, called here with the growing
            % history-so-far -- a real, re-runnable verdict per frame, not
            % an interpolation or a guess at what it'll end up being.
            verdict = 'UNSCREENED';
            ampSlope = NaN; dopplerResidual = NaN;
            if isKey(rangeHistByID, id) && numel(rangeHistByID(id)) >= 2
                rSeq = rangeHistByID(id); aSeq = ampHistByID(id); tSeq = timeHistByID(id);
                dSeq = diff(rSeq) ./ diff(tSeq); dSeq = [dSeq(1); dSeq];
                trackHist = struct('range', rSeq, 'amplitude', aSeq, 'doppler', dSeq);
                [lbl, ~] = track.discriminator(trackHist, C);
                verdict = upper(char(lbl));
                % Section 5.5's live gauges -- SAME history, informational
                % only, never the verdict itself (that's track.discriminator
                % above, the sole authority per CLAUDE.md's Golden Rule).
                sc = missionsim.computeEccmScreens(trackHist);
                ampSlope = sc.amplitudeRangeSlopeDbDecade;
                dopplerResidual = sc.dopplerResidualMps;
            end

            tracksOut(end+1) = struct('id', sprintf('T%02d', id), 'state', state, ...
                'ageFrames', age, 'hits', hits, 'misses', misses, ...
                'eccmVerdict', verdict, 'rangeEst', rangeEst, ...
                'ampRangeSlopeDbDecade', ampSlope, 'dopplerResidualMps', dopplerResidual); %#ok<AGROW>
        end
        f.radar.tracks = tracksOut;

        % ---- radar.scoreboard (Section 5.6): final-run aggregate, same
        % every frame -- engine.runJudge computes it once, end of run, not
        % incrementally; a genuine, documented simplification, not hidden. ----
        f.radar.scoreboard.confirmedFalseTracks = struct('value', feedback.confirmed_tracks, 'provenance', 'MEASURED');
        f.radar.scoreboard.deceptionRate = struct( ...
            'value', localSafeDiv(feedback.false_tracks_surviving, max(1, numel(scenePhantoms))), ...
            'provenance', 'MEASURED');

        [valid, errors] = missionsim.validateFrame(f);
        if ~valid
            error('missionsim:buildFrameLog:invalidFrame', ...
                'buildFrameLog produced a frame (k=%d) that fails its own schema:\n%s', ...
                k, strjoin(errors, sprintf('\n')));
        end
        frameLog{k} = f;
        if ~isempty(onFrame)
            onFrame(f);
        end
    end
end

% ===================== file-local helpers =============================
function phase = localDerivePhase(frameLogHistory, k)
%LOCALDERIVEPHASE  Section 4.2's phase state machine, adapted to what this
%   project's judge run actually models (a fixed-duration dwell against an
%   already-transmitting swarm, not a full ingress-to-egress mission) --
%   DECEPTION_HOLDING's own definition (">=2 confirmed tracks alive
%   simultaneously") is used VERBATIM, unchanged, since it's directly
%   computable from real state; INGRESS/ACQUISITION are approximated from
%   how many frames have elapsed and whether anything has confirmed yet
%   (this project's scenes don't model a mother drone flying in from
%   outside detection range -- transmission starts at frame 1).
    tk = frameLogHistory{k};
    confirmedCount = 0;
    if ~isempty(tk)
        confirmedCount = sum([tk.isConfirmed]);
    end
    if confirmedCount >= 2
        phase = 'DECEPTION_HOLDING';
    elseif confirmedCount >= 1
        phase = 'ENGINE_ACTIVE';
    elseif k <= 3
        phase = 'ACQUISITION';
    else
        phase = 'INGRESS';
    end
end

function r = localSafeDiv(a, b)
    if b == 0; r = 0; else; r = a / b; end
end
