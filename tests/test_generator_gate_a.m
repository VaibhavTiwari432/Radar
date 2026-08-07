classdef test_generator_gate_a < matlab.unittest.TestCase
%TEST_GENERATOR_GATE_A  Blueprint Gate A, as a re-runnable unittest so it
%   is covered by runAllTests() and not only by the standalone
%   generator.runGateA driver.
%
%   Gate A (Virtual Entity Engine Scientific Blueprint, Part 7): before any
%   feasibility mapping (Phase B) or agent (Phase C) is credible, the
%   rebuilt generator must produce scenes the REAL independent judge
%   (+engine/runJudge.m) classifies correctly in both directions --
%
%     (a) a physically consistent phantom, built through the ONLY path an
%         agent action can take (generator.physics_projection.project_action)
%         -> CONFIRMED and labelled 'real'
%     (b) a phantom whose range walks but whose phase is held flat (the
%         classic RGPO/pull-off signature, Blueprint 2.3), built by
%         deliberately BYPASSING project_action since that path cannot
%         structurally produce it -> flagged, NOT 'real'
%     (c) two independently-consistent phantoms rendered through ONE
%         aperture (Blueprint 2.4 -- +generator/render.m has no
%         per-phantom azimuth argument, so any multi-phantom scene IS
%         co-bearing) -> both flagged by the co-bearing screen
%
%   A screen that never fires, or always fires, is broken; (a) vs (b)/(c)
%   is what distinguishes those cases from a working instrument.
%
%   FOUND BY THIS TEST, first time it was run end to end:
%   generator/physics_projection.py's phase_progression_rad used the
%   Blueprint's own illustrative sign (+4*pi/lambda * dR), which is the
%   OPPOSITE of this project's actual convention -- +engine/runJudge.m
%   recovers range-rate as Rdot = -lambda*f_d/2 ("Negative = closing"),
%   which requires phi = -4*pi*R/lambda. Case (a) scored 'decoy' until
%   that was fixed. That is the whole point of gating on an independent
%   judge rather than on the generator's own opinion of its output.

    properties
        FixtureDir
    end

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'generator.tests.build_gate_a_scenes not importable from this MATLAB''s Python environment (pyenv).');
        end

        function buildFixtures(tc)
            tc.FixtureDir = tempname;
            mkdir(tc.FixtureDir);
            mod = py.importlib.import_module('generator.tests.build_gate_a_scenes');
            py.importlib.reload(mod);
            mod.build_genuine_consistent(fullfile(tc.FixtureDir, 'gateA_genuine.mat'));
            mod.build_naive_zero_doppler(fullfile(tc.FixtureDir, 'gateA_naive_zero_doppler.mat'));
            mod.build_cobearing_pair(fullfile(tc.FixtureDir, 'gateA_cobearing_pair.mat'));
        end
    end

    methods (TestClassTeardown)
        function cleanFixtures(tc)
            if ~isempty(tc.FixtureDir) && isfolder(tc.FixtureDir)
                rmdir(tc.FixtureDir, 's');
            end
        end
    end

    methods (Test)

        function test_consistent_phantom_is_confirmed_as_real(tc)
            % Deterministic noise draw so a marginal seed cannot make this
            % test flap; the physics being asserted does not depend on
            % which draw, and a flapping gate is worse than no gate.
            rng(1, 'twister');
            judgeMat = fullfile(tc.FixtureDir, 'genuine_judge.mat');
            generator.render(fullfile(tc.FixtureDir, 'gateA_genuine.mat'), judgeMat);
            fb = engine.runJudge(judgeMat);

            tc.verifyGreaterThanOrEqual(fb.confirmed_tracks, 1, ...
                'A physically consistent phantom should be detected and confirmed.');
            tc.verifyEqual(fb.eccm_label, 'real', ...
                'A phantom built through project_action satisfies 2.1-2.3 and should not be flagged.');
            % The Doppler screen must actually have been in play -- a 'real'
            % label from a 2-D export (screen self-disabled) would be a much
            % weaker claim, and runJudge reports which path ran precisely so
            % no caller can quote a label without knowing that.
            tc.verifyEqual(fb.doppler_source, 'measured');
        end

        function test_zero_doppler_pull_off_phantom_is_flagged(tc)
            rng(1, 'twister');
            judgeMat = fullfile(tc.FixtureDir, 'naive_judge.mat');
            generator.render(fullfile(tc.FixtureDir, 'gateA_naive_zero_doppler.mat'), judgeMat);
            fb = engine.runJudge(judgeMat);

            % It should still be DETECTED (it is a real signal with real
            % power) -- the claim is about the LABEL, not detectability.
            tc.verifyGreaterThanOrEqual(fb.confirmed_tracks, 1, ...
                'The spoof carries real power and should still be detected.');
            tc.verifyNotEqual(fb.eccm_label, 'real', ...
                'Range walking with flat phase is the pull-off signature and must be flagged.');
        end

        function test_two_phantoms_from_one_aperture_are_flagged_cobearing(tc)
            rng(1, 'twister');
            judgeMat = fullfile(tc.FixtureDir, 'cobearing_judge.mat');
            generator.render(fullfile(tc.FixtureDir, 'gateA_cobearing_pair.mat'), judgeMat);
            fb = engine.runJudge(judgeMat);

            tc.verifyGreaterThanOrEqual(fb.confirmed_tracks, 2, ...
                'Both phantoms are individually consistent and should confirm.');
            tc.verifyTrue(fb.cobearing_flagged, ...
                'Two tracks sharing one bearing is the single-source signature (Blueprint 2.4).');
            tc.verifyTrue(all(strcmp(fb.track_label, 'decoy')), ...
                'The co-bearing screen condemns the GROUP -- every co-bearing track, not just one.');
        end

        function test_angle_blind_radar_does_not_flag_the_same_pair(tc)
            % The control that makes the test above meaningful: the SAME
            % two phantoms, judged by a radar with no difference channel,
            % must NOT be flagged co-bearing -- otherwise the screen might
            % be firing on something other than the shared bearing.
            rng(1, 'twister');
            judgeMat = fullfile(tc.FixtureDir, 'cobearing_noangle_judge.mat');
            generator.render(fullfile(tc.FixtureDir, 'gateA_cobearing_pair.mat'), judgeMat, ...
                'IncludeAngleChannel', false);
            fb = engine.runJudge(judgeMat);

            tc.verifyEqual(fb.angle_source, 'none');
            tc.verifyFalse(fb.cobearing_flagged, ...
                'A radar with no angle channel cannot detect a shared bearing.');
        end

    end
end

function tf = localPythonReady()
    try
        py.importlib.import_module('generator.tests.build_gate_a_scenes');
        tf = true;
    catch
        tf = false;
    end
end
