function startup()
%STARTUP  Put the project on the MATLAB path.
%
%   Run this once at the start of a MATLAB session (from the project root):
%       >> startup
%
%   Adds the project root (so the package folders +physics, +data, +radar,
%   +synth, +track, +agent resolve) plus tests/ and experiments/.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, 'tests'));
    fprintf('[radar-sim] paths added from: %s\n', here);

    % Same job, other language: put the project root on MATLAB's EMBEDDED
    % Python path too, so `py.importlib.import_module('cogengine')` resolves.
    % MATLAB's embedded interpreter does NOT inherit the current folder the
    % way `python script.py` does, so without this every Python-driven test
    % (test_four_phantom_swarm, test_missionsim_*, test_tradeoff_sweep, ...)
    % silently filters itself to Incomplete with "cogengine not importable
    % from this MATLAB's Python environment (pyenv)" on a machine where
    % cogengine is in fact perfectly importable. Fixed here, once, rather
    % than in each test's own localPythonReady().
    try
        if count(py.sys.path, here) == 0
            insert(py.sys.path, int32(0), here);
        end
        fprintf('[radar-sim] cogengine importable from pyenv (%s)\n', pyenv().Version);
    catch ME
        % No usable Python on this machine -- MATLAB-only work is
        % unaffected, and the tests' own assumption filters still report
        % Incomplete honestly rather than Failed.
        fprintf('[radar-sim] no usable pyenv (%s); Python-driven tests will report Incomplete\n', ...
            ME.identifier);
    end

    fprintf('[radar-sim] next: runAllTests(''Stage0'')\n');
end
