function results = runAllTests(varargin)
%RUNALLTESTS  Run the staged matlab.unittest suite and print a summary.
%
%   runAllTests            % run every tests/*_Test.m
%   runAllTests('Stage0')  % run one stage by name (file tests/Stage0_Test.m)
%   runAllTests('Stage1')  % ...etc
%
%   The summary separates three outcomes, which is the whole point:
%       Passed     - claim verified by executed MATLAB
%       Failed     - code exists but is WRONG -> debug before advancing
%       Incomplete - stage not implemented yet / dataset absent (assumption
%                    filters). These are honest "not done yet", not "broken".
%
%   Mirrors the MCP tool run_matlab_test_file, so Claude Code can call either.

    here = fileparts(mfilename('fullpath'));
    addpath(here); addpath(fullfile(here,'tests'));
    import matlab.unittest.TestSuite

    if nargin >= 1 && ~isempty(varargin{1})
        name = varargin{1};
        if ~endsWith(name, '_Test'); name = [name '_Test']; end
        f = fullfile(here, 'tests', [name '.m']);
        assert(isfile(f), 'runAllTests:noSuchStage', 'No test file: %s', f);
        suite = TestSuite.fromFile(f);
    else
        suite = TestSuite.fromFolder(fullfile(here,'tests'));
    end

    results = run(suite);

    passed     = nnz([results.Passed]);
    failed     = nnz([results.Failed]);
    incomplete = nnz([results.Incomplete]);
    total      = numel(results);

    fprintf('\n=====================================\n');
    fprintf(' RADAR-SIM TEST SUMMARY  (%d tests)\n', total);
    fprintf('=====================================\n');
    fprintf('  Passed:     %d\n', passed);
    fprintf('  Failed:     %d\n', failed);
    fprintf('  Incomplete: %d   (pending stage / no dataset)\n', incomplete);
    fprintf('=====================================\n');
    if failed > 0
        fprintf('  STATUS: FAILURES PRESENT -> debug before advancing.\n');
    elseif incomplete > 0
        fprintf('  STATUS: green so far; %d pending implementation.\n', incomplete);
    else
        fprintf('  STATUS: ALL GREEN.\n');
    end
    fprintf('=====================================\n\n');
end
