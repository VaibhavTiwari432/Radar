function [confirmed, history, modeProbHistory] = runTracker(detsPerFrame, times, C, varargin) %#ok<INUSD>
%RUNTRACKER  Run trackerGNN over a sequence of per-frame detections.
%
%   confirmed = track.runTracker(detsPerFrame, times, C)
%   [confirmed, history] = track.runTracker(detsPerFrame, times, C)
%   [confirmed, history, modeProbHistory] = track.runTracker(detsPerFrame, times, C)
%       detsPerFrame : {1 x F} cell array of objectDetection arrays, one
%                      cell per frame (a cell may be empty -- no detections
%                      that frame; may hold MULTIPLE detections in one
%                      frame for simultaneous targets).
%       times        : [1 x F] frame timestamps [s]. Informational: each
%                      objectDetection already carries its own .Time, which
%                      is what trackerGNN actually keys off.
%       C            : physics.Constants() (not used directly; kept so the
%                      call signature matches the rest of the project).
%
%       confirmed    : struct array of the tracks whose IsConfirmed flag is
%                      true at the end of the run (fields incl. TrackID,
%                      Age, State, ...).
%       history      : {1 x F} cell array, ALL tracks trackerGNN returned
%                      at that frame (confirmed or not yet), so a caller
%                      tracking multiple simultaneous targets can rebuild
%                      each TrackID's own per-frame range/amplitude series
%                      (needed to run track.discriminator per track, not
%                      just once globally). Second output, additive --
%                      existing single-output callers (Stage3_Test.m)
%                      are unaffected.
%       modeProbHistory : {1 x F} cell array, parallel to history. Each
%                      cell is a containers.Map (TrackID -> [1 x nModels]
%                      IMM model-probability row, via
%                      getTrackFilterProperties). Only populated when
%                      'FilterModel' is 'imm' -- for cv/ca every cell is an
%                      empty containers.Map, so a caller can tell "no IMM
%                      this run" apart from "IMM but this track had no
%                      hits yet" (an empty Map vs. a missing key). Third
%                      output, additive -- existing 1- and 2-output
%                      callers are unaffected. This is what
%                      +engine/runJudge.m threads into
%                      track.discriminator's new manoeuvre-plausibility
%                      screen (see that file's .modeProbSeq assembly).
%
%   ONLY SOURCE of the deception/success metric (CLAUDE.md Rule 2): +synth
%   must never call this to grade itself. Uses trackerGNN with
%   ConfirmationThreshold [3 5] (POA Stage 3, claims C5/C6) -- a track needs
%   3 hits in the last 5 updates to confirm. trackerGNN is MathWorks' own
%   multi-target tracker -- it already assigns/gates multiple simultaneous
%   detections to distinct tracks; nothing about THIS function was
%   single-target-only, only its callers used to hand it one detection/frame.

    % AssignmentThreshold widened from the default [30 inf]: this project's
    % scenarios include closing/opening rates up to ~120 m/s (Stage 6's
    % DRFM range-walk). At the 1 Hz revisit cadence used throughout, the
    % FIRST hit-to-hit residual for such a target (~60-120 m) is gated out
    % by the default threshold before the filter has any velocity estimate
    % to predict from (verified interactively: default gate loses the
    % track every time; 200 confirms it by frame 3, matching the slow
    % Stage 3 scenarios' behavior, and still rejects Stage 3's
    % noise-only clutter, which sits thousands of metres apart).
    % ---- sweepable operating point (added for the benchmark suite) -------
    % DEFAULTS ARE THE HISTORICAL VALUES, so every existing caller
    % (Stage3_Test, engine.runJudge, the fixture batch runners, +agent/*)
    % behaves exactly as before. Only a caller that explicitly passes a
    % different operating point gets a different radar -- which is the whole
    % point of a threshold sweep: the adversary's difficulty must be a
    % stated parameter, not a hardcoded constant nobody can vary.
    %
    %   'AssignmentThreshold'   default [200 inf]  (gate, metres)
    %   'ConfirmationThreshold' default [3 5]      (M-of-N)
    %   'DeletionThreshold'     default [5 5]
    %   'FilterModel'  'cv' (default) | 'imm' | 'ca'
    %       cv  -> initcvekf, MathWorks' constant-velocity EKF (historical)
    %       imm -> initekfimm, an interacting-multiple-model bank
    %              (CV/CA/CT). A maneuver-aware tracker: the honest test of
    %              whether a deception exploits a SINGLE-model weakness.
    %       ca  -> initcaekf, constant acceleration
    %   'TrackerType'  'gnn' (default) | 'jpda'
    %       jpda -> trackerJPDA, multi-hypothesis association. Tests whether
    %               association ambiguity catches what a single-hypothesis
    %               assignment misses.
    d = track.trackerDefaults();   % the ONE declaration of these values
    p = inputParser;
    addParameter(p, 'AssignmentThreshold',   d.AssignmentThreshold);
    addParameter(p, 'ConfirmationThreshold', d.ConfirmationThreshold);
    addParameter(p, 'DeletionThreshold',     d.DeletionThreshold);
    addParameter(p, 'FilterModel',           d.FilterModel);
    addParameter(p, 'TrackerType',           d.TrackerType);
    parse(p, varargin{:});
    o = p.Results;

    switch lower(char(o.FilterModel))
        case 'cv';  filtFcn = @initcvekf;
        case 'imm'; filtFcn = @initekfimm;
        case 'ca';  filtFcn = @initcaekf;
        otherwise
            error('track:runTracker:badFilter', ...
                'FilterModel must be cv|imm|ca, got ''%s''', char(o.FilterModel));
    end

    switch lower(char(o.TrackerType))
        case 'gnn'
            tracker = trackerGNN('ConfirmationThreshold', o.ConfirmationThreshold, ...
                                  'DeletionThreshold',     o.DeletionThreshold, ...
                                  'AssignmentThreshold',   o.AssignmentThreshold, ...
                                  'FilterInitializationFcn', filtFcn);
        case 'jpda'
            % trackerJPDA's confirmation/deletion are event-based
            % (probability thresholds), not the M-of-N pair trackerGNN
            % takes, so the M-of-N is passed through its History logic.
            tracker = trackerJPDA('TrackLogic', 'History', ...
                                  'ConfirmationThreshold', o.ConfirmationThreshold, ...
                                  'DeletionThreshold',     o.DeletionThreshold, ...
                                  'AssignmentThreshold',   o.AssignmentThreshold, ...
                                  'FilterInitializationFcn', filtFcn);
        otherwise
            error('track:runTracker:badTracker', ...
                'TrackerType must be gnn|jpda, got ''%s''', char(o.TrackerType));
    end

    isImm = strcmpi(char(o.FilterModel), 'imm');

    tracks = objectTrack.empty(0,1);
    history = cell(1, numel(detsPerFrame));
    modeProbHistory = cell(1, numel(detsPerFrame));
    for k = 1:numel(detsPerFrame)
        dets = detsPerFrame{k};
        if isempty(dets)
            % objectDetection.empty, NOT [] -- once trackerGNN locks on the
            % objectDetection input type, a plain double [] throws
            % "changing the data type on input 1" (verified interactively).
            if isLocked(tracker)
                tracks = tracker(objectDetection.empty, times(k));
            end
        else
            tracks = tracker(dets, times(k));
        end
        history{k} = tracks;

        % IMM mode probabilities, THIS frame, THIS live tracker -- must be
        % read now, not reconstructed afterward: the tracker only ever
        % holds its CURRENT per-track filter state (verified interactively,
        % see track.getFilterState's header), so a mode-probability
        % TIME SERIES only exists if snapshotted here, frame by frame.
        mpMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
        if isImm
            for t = 1:numel(tracks)
                id = tracks(t).TrackID;
                mp = getTrackFilterProperties(tracker, id, 'ModelProbabilities');
                mpMap(id) = mp{1}(:)';
            end
        end
        modeProbHistory{k} = mpMap;
    end

    if isempty(tracks)
        confirmed = tracks;
    else
        confirmed = tracks([tracks.IsConfirmed]);
    end
end
