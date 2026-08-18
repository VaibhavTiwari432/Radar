classdef test_generator_screen_ablation < matlab.unittest.TestCase
%TEST_GENERATOR_SCREEN_ABLATION  Regression cover for claim F4, and a
%   standing assertion that screen 2b stays inert (audit finding H2).
%
%   F4: "each discriminator screen catches EXACTLY its own violation and is
%   blind to the other's." Measured by generator.screenAblation -- which,
%   until now, had no test. This is the last of the five uncovered
%   +generator/ entry points found by the 10 Aug 2026 audit.
%
%   THE ARMS each violate exactly one physical law, which is the only way
%   to attribute a flag to a screen:
%       genuine         consistent phantom -- the FALSE-ALARM control
%       flat_amplitude  amplitude held flat -> screen 1 alone should catch
%       zero_doppler    phase held at zero  -> screen 2 alone should catch
%       cobearing       two phantoms, one aperture -> runJudge's own screen
%       maneuvering     per-frame acceleration flutter -> screen 2b's only arm
%
%   WHY N=2 SEEDS AND NOT THE PUBLISHED 5. The sweep is 7 masks x 5 arms x
%   seeds render+judge calls. Every claim asserted below sits at 0.00 or
%   1.00 -- an orthogonality structure, not a marginal rate -- so a second
%   seed catches a break at a fraction of the runtime.
%
%   DELIBERATELY NOT ASSERTED: F5's 0.80 cell (the 3-screen default catching
%   the flat-amplitude repeater 4 times in 5 where amplitude-alone catches
%   it 5 times in 5). That number cannot even be expressed at N=2, and
%   pinning it here would either flap or force the seed count up for one
%   cell. It stays generator.screenAblation's own result at N=5.

    properties
        FixtureDir
        R
    end

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'generator.tests.build_gate_a_scenes not importable from this MATLAB''s Python environment (pyenv).');
        end

        function buildAndAblate(tc)
            tc.FixtureDir = tempname;
            mkdir(tc.FixtureDir);
            mod = py.importlib.import_module('generator.tests.build_gate_a_scenes');
            py.importlib.reload(mod);
            mod.build_genuine_consistent(fullfile(tc.FixtureDir, 'gateA_genuine.mat'));
            mod.build_naive_zero_doppler(fullfile(tc.FixtureDir, 'gateA_naive_zero_doppler.mat'));
            mod.build_cobearing_pair(fullfile(tc.FixtureDir, 'gateA_cobearing_pair.mat'));
            mod.build_flat_amplitude(fullfile(tc.FixtureDir, 'gateA_flat_amplitude.mat'));
            mod.build_maneuvering(fullfile(tc.FixtureDir, 'gateA_maneuvering.mat'));
            tc.R = generator.screenAblation(tc.FixtureDir, 'NumSeeds', 2);
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

        function test_F4_each_screen_catches_only_its_own_violation(tc)
            % The orthogonality claim, all four corners. A screen that fires
            % on the other arm's violation is not attributing anything.
            tc.verifyEqual(tc.cell('amplitude only', 'flat_amplitude'), 1, ...
                'The amplitude screen must catch a flat-amplitude repeater.');
            tc.verifyEqual(tc.cell('amplitude only', 'zero_doppler'), 0, ...
                'The amplitude screen must be BLIND to a phase violation -- its amplitude law is satisfied.');
            tc.verifyEqual(tc.cell('doppler only', 'zero_doppler'), 1, ...
                'The Doppler screen must catch a flat-phase pull-off.');
            tc.verifyEqual(tc.cell('doppler only', 'flat_amplitude'), 0, ...
                'The Doppler screen must be BLIND to an amplitude violation -- its phase tracks range correctly.');
        end

        function test_F4_genuine_arm_is_never_flagged_by_a_real_mask(tc)
            % The false-alarm control. Any mask that condemns this arm is
            % accusing a real target, which makes every other cell in its
            % row uninterpretable.
            for m = {'amplitude only', 'doppler only', 'DEFAULT (a+d+micro)', ...
                     '+residual', 'DEFAULT, IMM tracker', '+maneuver (IMM)'}
                tc.verifyEqual(tc.cell(m{1}, 'genuine'), 0, ...
                    sprintf('mask ''%s'' flagged the GENUINE arm -- that is a false accusation, not a screen.', m{1}));
            end
        end

        function test_no_screens_means_suspicious_not_free_pass(tc)
            % The floor row, and it is not vacuous: with every screen off
            % discriminator.m scores an empty screen set 0.5, and `> 0.5` is
            % false, so every confirmed track is labelled decoy. This is the
            % file's own "nothing here proves this is real should lean
            % suspicious" rule -- including for the genuine arm.
            for a = {'genuine', 'flat_amplitude', 'zero_doppler', 'cobearing', 'maneuvering'}
                tc.verifyEqual(tc.cell('none (floor)', a{1}), 1, ...
                    sprintf('arm ''%s'': with no screens enabled the label must default to decoy, not real.', a{1}));
            end
        end

        function test_H2_maneuver_screen_is_inert_and_harmless(tc)
            % Audit finding H2, asserted so it cannot silently change in
            % EITHER direction.
            %
            % HARMLESS (the fix): screen 2b was converted from an averaged
            % vote to a veto because as a vote it scored ~1.0 on every
            % non-manoeuvring phantom and averaged condemning screens back
            % up -- dropping flat_amplitude and zero_doppler to 0.00. Adding
            % it must now change nothing.
            %
            % INERT (the finding): it also catches nothing, including on the
            % manoeuvring arm built for it. The tracker measures range only
            % at 46.84 m quantisation and the scene's velocity alternation
            % is under one bin, so the IMM's dominant mode never switches.
            % If this ever starts flagging, the screen has become real and
            % H2 needs rewriting -- which is exactly why it is asserted.
            for a = {'genuine', 'flat_amplitude', 'zero_doppler', 'cobearing', 'maneuvering'}
                tc.verifyEqual(tc.cell('+maneuver (IMM)', a{1}), ...
                               tc.cell('DEFAULT, IMM tracker', a{1}), ...
                    sprintf(['arm ''%s'': the +maneuver row must match its ' ...
                             'same-tracker control exactly. A difference means ' ...
                             'screen 2b started doing something -- good or bad, ' ...
                             'it invalidates H2 and must be re-measured.'], a{1}));
            end
            tc.verifyEqual(tc.cell('+maneuver (IMM)', 'maneuvering'), 0, ...
                'H2: the veto does not fire even on the flutter arm. See +track/discriminator.m for the three reasons.');
        end

    end

    methods (Access = private)
        function p = cell(tc, maskName, armName)
            t = tc.R.table;
            hit = t(strcmp({t.mask}, maskName) & strcmp({t.arm}, armName));
            tc.assertNumElements(hit, 1, ...
                sprintf('no ablation cell for mask ''%s'' / arm ''%s''', maskName, armName));
            p = hit.pFlagged;
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
