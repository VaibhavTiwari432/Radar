function summary = judgeSummary(judgeMatPath, varargin)
%JUDGESUMMARY  Thin generator-side wrapper around engine.runJudge, returning
%   ONLY scalar/simple fields.
%
%   summary = generator.judgeSummary(judgeMatPath, 'Name', value, ...)
%   Same name-value arguments as engine.runJudge.
%
%   WHY THIS EXISTS. MATLAB Engine API for Python can only auto-convert a
%   struct to a Python dict when it (and every struct nested inside it, at
%   every level) is SCALAR (1x1) -- "only a scalar struct can be returned
%   from MATLAB". engine.runJudge's feedback.frame_log is a
%   {1 x numFrames} cell where each cell holds a STRUCT ARRAY, one element
%   per simultaneous track that frame -- scalar only when a frame happens
%   to have at most one track. generator/decision/train.py's training run
%   crashed on this exactly once a multi-track frame occurred by chance
%   (~episode 75-100 of a 150-episode run, not on the first call), which is
%   why this was found only once the run had been going for a while, not by
%   inspection.
%
%   This is an INTEROP limitation of the Python bridge, not a judge defect
%   -- engine.runJudge's own return value is correct and unchanged for
%   every MATLAB-side caller (+experiments/*, tests/*). Fixed here, on the
%   generator side, rather than by trimming what the judge returns (Rule 2:
%   the judge's output shape is not the generator's to dictate).

    fb = engine.runJudge(judgeMatPath, varargin{:});

    summary = struct();
    summary.confirmed_tracks = fb.confirmed_tracks;
    summary.false_tracks_surviving = fb.false_tracks_surviving;
    summary.flagged_decoys = fb.flagged_decoys;
    summary.eccm_label = char(fb.eccm_label);
    if fb.confirmed_tracks > 0
        summary.track_label = strjoin(cellstr(fb.track_label), ',');
    else
        summary.track_label = '';
    end

    % RL v2 reactive radar (+radar/reactivePolicy.m) triggers. Scalars, because
    % the bridge cannot return anything else (see the header). NaN when there is
    % no confirmed real track to be suspicious of -- distinct from a real track
    % that passed with low confidence, which is the trigger.
    labels = cellstr(fb.track_label);
    isReal = strcmp(labels, 'real');
    if any(isReal)
        summary.min_real_confidence = min(fb.track_confidence(isReal));
    else
        summary.min_real_confidence = NaN;
    end
    % The range-rate magnitude check (reported beside the ECCM score, not folded
    % in) disagreeing on ANY confirmed track. false when the field is absent
    % (legacy 2-D path) or empty.
    if isfield(fb, 'track_rate_pass') && ~isempty(fb.track_rate_pass)
        summary.any_rate_fail = any(~fb.track_rate_pass);
    else
        summary.any_rate_fail = false;
    end
end
