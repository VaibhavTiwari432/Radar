function s = runJudgeJson(matFile, includeFrameLog)
%RUNJUDGEJSON  engine.runJudge, returned as a JSON string.
%
%   s = engine.runJudgeJson(matFile)
%   s = engine.runJudgeJson(matFile, includeFrameLog)
%
%   WHY THIS WRAPPER EXISTS. MATLAB Engine for Python can only marshal a
%   SCALAR struct back to Python. engine.runJudge's feedback contains
%   frame_log, a cell of struct ARRAYS (one entry per track per frame), so the
%   direct call succeeds at 1 confirmed track and fails at 3 with
%   "only a scalar struct can be returned from MATLAB" -- a bug that hides
%   until a multi-phantom scene is judged, which is exactly the interesting
%   case. Verified: N=1 marshalled fine, N=3 raised.
%
%   Going through jsonencode instead uses the seam this project already
%   validates in both directions (+engine/sceneStructToJson.m,
%   web/src/lib/frameLog.js) rather than adding a second, type-fragile one.
%
%   KNOWN jsonencode GOTCHA, already documented in CLAUDE.md and guarded on
%   the consuming side: a ONE-element struct array collapses to a bare JSON
%   object instead of a 1-element array. Python's server/attribute.py and the
%   client's asList() both normalise for it. Do not "fix" it here -- the
%   frozen fixtures depend on the current shape.
%
%   frame_log is EXCLUDED by default: it is the largest field by far and the
%   console does not consume it yet. It is what a fourth phantom state
%   ("detected but never confirmed") would need, so pass true when that is
%   built rather than inventing the state without evidence.

    if nargin < 2 || isempty(includeFrameLog); includeFrameLog = false; end

    fb = engine.runJudge(matFile);

    if ~includeFrameLog && isfield(fb, 'frame_log')
        fb = rmfield(fb, 'frame_log');
    end

    s = jsonencode(fb);
end
