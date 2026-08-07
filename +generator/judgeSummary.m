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
end
