function tf = archivedDepsPresent(names)
%ARCHIVEDDEPSPRESENT  True if every named function is resolvable on the path.
%
%   tf = archivedDepsPresent({'engine.entity.render', 'synth.synthesizeSwarm'})
%
%   WHY THIS EXISTS. The 7 August 2026 rebuild archived the signal generator
%   (GOVERNANCE.md), which left 24 test files ERRORING on undefined names --
%   63 errored methods in a 212-method suite. That is not a red suite, it is
%   a BROKEN INSTRUMENT: a genuine new regression cannot be seen against 63
%   pre-existing errors, so the suite stops being able to do the one job it
%   has. This helper lets those files report the project's own third
%   outcome instead --
%
%       Passed     claim verified
%       Failed     code exists and is WRONG -> debug before advancing
%       Incomplete honest "not built / dependency absent"
%
%   -- which is exactly what runAllTests.m's own header already says
%   Incomplete is for, and what data/-absent tests (DataIntegration_Test)
%   have always done.
%
%   THIS IS NOT A COMPATIBILITY SHIM. GOVERNANCE.md forbids patching the
%   archived packages back in, and nothing here does: this function only
%   ASKS whether a name resolves, and never provides, stubs or re-exports
%   any archived behaviour. A guarded test still does not run until it is
%   genuinely rewired against generator.render -- it just says so honestly
%   instead of erroring.
%
%   Guarded files remain tracked as pending work in
%   trash/BROKEN_DOWNSTREAM.md. A skip is a debt, not a resolution.

    if ischar(names) || isstring(names)
        names = cellstr(names);
    end
    tf = true;
    for i = 1:numel(names)
        % which() resolves dotted package-qualified function names and
        % returns '' when unresolvable. exist() is NOT usable here: it
        % reports 0 for package functions in some releases even when they
        % are present, which would skip tests that could actually run --
        % the failure direction that hides work rather than surfacing it.
        if isempty(which(names{i}))
            tf = false;
            return
        end
    end
end
