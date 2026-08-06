function result = runGateA(fixtureDir)
%RUNGATEA  Blueprint Gate A: render + judge the three fixtures built by
%   generator/tests/build_gate_a_scenes.py, through the REAL independent
%   judge (+engine/runJudge.m) -- not a twin, not an assertion.
%
%   result = generator.runGateA(fixtureDir)
%       fixtureDir : directory containing gateA_genuine.mat,
%                    gateA_naive_zero_doppler.mat, gateA_cobearing_pair.mat
%                    (written by: python generator/tests/build_gate_a_scenes.py <fixtureDir>)
%       result     : struct with .genuine, .naive, .cobearing (each a
%                    feedback struct from engine.runJudge) and .allPass
%
%   Gate A (Blueprint Part 7): a genuine-consistent phantom must be
%   CONFIRMED and labelled 'real'; a phantom with range motion but no
%   Doppler (the classic pull-off signature, Blueprint 2.3) must be
%   flagged; two independently-consistent phantoms rendered through the
%   same aperture (Blueprint 2.4 -- this generator has no per-phantom
%   angle parameter) must both be flagged co-bearing.
%
%   Caught and fixed by this exact test, first run: generator/
%   physics_projection.py's phase sign was the Blueprint's own illustrative
%   convention, which is the OPPOSITE of +engine/runJudge.m's actual
%   f_d=-2*Rdot/lambda. The genuine case scored 'decoy' until that was
%   found and fixed -- see physics_projection.py's phase_progression_rad
%   docstring for the derivation.

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);

    result = struct();

    genPre = fullfile(fixtureDir, 'gateA_genuine.mat');
    genJudge = fullfile(fixtureDir, 'gateA_genuine_judge.mat');
    generator.render(genPre, genJudge);
    result.genuine = engine.runJudge(genJudge);
    okGenuine = result.genuine.confirmed_tracks >= 1 && strcmp(result.genuine.eccm_label, 'real');

    naivePre = fullfile(fixtureDir, 'gateA_naive_zero_doppler.mat');
    naiveJudge = fullfile(fixtureDir, 'gateA_naive_judge.mat');
    generator.render(naivePre, naiveJudge);
    result.naive = engine.runJudge(naiveJudge);
    okNaive = result.naive.confirmed_tracks >= 1 && ~strcmp(result.naive.eccm_label, 'real');

    coPre = fullfile(fixtureDir, 'gateA_cobearing_pair.mat');
    coJudge = fullfile(fixtureDir, 'gateA_cobearing_judge.mat');
    generator.render(coPre, coJudge);
    result.cobearing = engine.runJudge(coJudge);
    okCobearing = result.cobearing.confirmed_tracks >= 2 && result.cobearing.cobearing_flagged;

    result.allPass = okGenuine && okNaive && okCobearing;

    fprintf('(a) genuine_consistent : confirmed=%d label=%-6s %s\n', ...
        result.genuine.confirmed_tracks, result.genuine.eccm_label, tern(okGenuine));
    fprintf('(b) naive_zero_doppler : confirmed=%d label=%-6s %s\n', ...
        result.naive.confirmed_tracks, result.naive.eccm_label, tern(okNaive));
    fprintf('(c) cobearing_pair     : confirmed=%d cobearing=%d %s\n', ...
        result.cobearing.confirmed_tracks, result.cobearing.cobearing_flagged, tern(okCobearing));
    fprintf('GATE A: %s\n', tern(result.allPass));
end

function s = tern(ok)
    if ok; s = 'PASS'; else; s = 'FAIL'; end
end
