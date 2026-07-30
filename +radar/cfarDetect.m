function [detIdx, detMask, cfar] = cfarDetect(power, varargin)
%CFARDETECT  Constant-false-alarm-rate detection over a power vector.
%
%   [detIdx, detMask, cfar] = radar.cfarDetect(POWER) runs a cell-averaging
%   CFAR detector across the real, non-negative column vector POWER (e.g.
%   |matched-filter output|.^2) and returns:
%       detIdx  - indices of cells declared "target"
%       detMask - logical vector, true where a detection was declared
%       cfar    - the configured phased.CFARDetector (returned for reuse)
%
%   Name-value options (all have physically sensible defaults):
%       'Pfa'            probability of false alarm      (default 1e-4)
%       'NumTraining'    training cells (each side)      (default 20)
%       'NumGuard'       guard cells (each side)         (default 4)
%       'Method'         'CA'|'GOCA'|'SOCA'|'OS'         (default 'CA')
%
%   The detector is created here from MathWorks' phased.CFARDetector — this
%   is the INDEPENDENT radar judge (CLAUDE.md Rule 2). +synth must never call
%   this to grade itself; only +radar / +track consume it.
%
%   Cells within (NumTraining+NumGuard) of either edge cannot be tested
%   (no room for a full training window) and are never flagged.
%
%   Ref: POA Part 4 Stage 1; phased.CFARDetector docs.

    p = inputParser;
    addParameter(p, 'Pfa',         1e-4, @(x)isscalar(x)&&x>0&&x<1);
    addParameter(p, 'NumTraining', 20,   @(x)isscalar(x)&&x>=1);
    addParameter(p, 'NumGuard',    4,    @(x)isscalar(x)&&x>=0);
    addParameter(p, 'Method',      'CA', @(s)ischar(s)||isstring(s));
    parse(p, varargin{:});
    o = p.Results;

    power = double(power(:));                 % force real column
    assert(all(power >= 0), 'radar:cfarDetect:negativePower', ...
        'CFAR input must be non-negative power (got a negative value).');

    cfar = phased.CFARDetector( ...
        'Method',                char(o.Method), ...
        'NumTrainingCells',      2*o.NumTraining, ...   % total, both sides
        'NumGuardCells',         2*o.NumGuard, ...      % total, both sides
        'ProbabilityFalseAlarm', o.Pfa, ...
        'ThresholdFactor',       'Auto', ...
        'ThresholdOutputPort',   false);

    margin = o.NumTraining + o.NumGuard;
    N = numel(power);
    detMask = false(N,1);

    if N > 2*margin
        cut = (margin+1):(N-margin);          % testable cells-under-test
        d = cfar(power, cut);                 % logical over cut
        detMask(cut) = logical(d(:));
    end
    detIdx = find(detMask);
end
