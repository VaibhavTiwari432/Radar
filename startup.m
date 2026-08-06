function startup()
%STARTUP  Put the project on the MATLAB path.
%
%   Run this once at the start of a MATLAB session (from the project root):
%       >> startup
%
%   Adds the project root (so the package folders +physics, +data, +radar,
%   +track, +generator, +engine resolve) plus tests/ and experiments/.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, 'tests'));
    fprintf('[radar-sim] paths added from: %s\n', here);

    % Same job, other language: put the project root on MATLAB's EMBEDDED
    % Python path too, so `py.importlib.import_module('generator')` /
    % `('common')` resolve. MATLAB's embedded interpreter does NOT inherit
    % the current folder the way `python script.py` does, so without this
    % any Python-driven MATLAB test silently filters itself to Incomplete
    % on a machine where the package is in fact perfectly importable.
    % NOTE (7 Aug 2026): this used to import 'cogengine', archived to
    % trash/legacy-generator-20260807/ along with the rest of the old
    % generator -- the packages this now enables are common/ and generator/.
    try
        if count(py.sys.path, here) == 0
            insert(py.sys.path, int32(0), here);
        end
        fprintf('[radar-sim] generator/common importable from pyenv (%s)\n', pyenv().Version);
    catch ME
        % No usable Python on this machine -- MATLAB-only work is
        % unaffected, and the tests' own assumption filters still report
        % Incomplete honestly rather than Failed.
        fprintf('[radar-sim] no usable pyenv (%s); Python-driven tests will report Incomplete\n', ...
            ME.identifier);
    end

    fprintf('[radar-sim] next: runAllTests(''Stage0'')\n');
end
