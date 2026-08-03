function d = trackerDefaults()
%TRACKERDEFAULTS  The judge's tracker operating point, declared ONCE.
%
%   d = track.trackerDefaults()
%
%   Every historical value this project has used, in a single struct that
%   both track.runTracker (which applies them) and engine.runJudge (which
%   needs to know the gate it ran under, to rebuild each track's own hit
%   history) read from. Before this existed, runJudge carried its own
%   literal copy `ASSIGNMENT_GATE_M = 200` -- which went stale the moment a
%   caller swept the gate, silently logging hits against a threshold the
%   tracker was not using.
%
%   These are the JUDGE's numbers. Nothing on the adversary/twin side of
%   CLAUDE.md Rule 2 may set them: engine.runJudge takes overrides only as
%   explicit name-value arguments from its MATLAB caller, never from the
%   exported .mat (which the twin writes).
%
%   AssignmentThreshold widened from trackerGNN's default [30 inf] -- see
%   +track/runTracker.m's header for the measurement behind 200.

    d = struct( ...
        'AssignmentThreshold',   [200 inf], ...
        'ConfirmationThreshold', [3 5], ...      % POA Stage 3, claims C5/C6
        'DeletionThreshold',     [5 5], ...
        'FilterModel',           'cv', ...
        'TrackerType',           'gnn');
end
