classdef test_generator_phase_b < matlab.unittest.TestCase
%TEST_GENERATOR_PHASE_B  Regression cover for Phase B -- claims F2 and F3.
%
%   WHY THIS FILE EXISTS. F3 ("a 2-phantom co-bearing swarm goes P_confirm
%   1.00 -> 0.00 the instant monopulse is on") is this project's central
%   scientific result and, until now, it had NO test. It lived in
%   generator.phaseBSweep -- a manually-run script -- and a markdown table in
%   PHASE_B_RESULTS.md. The archived generator at least had test files for
%   its headline claims; the rebuild did not, so nothing would have caught a
%   regression in the one result the project leads with.
%
%   Audited 10 August 2026: 5 of 7 +generator/ entry points had no test at
%   all (phaseBSweep, screenAblation, phantomCountSweep, checkAgilityMechanism,
%   judgeSummary). This closes the most load-bearing of them.
%
%   IT DRIVES generator.phaseBSweep ITSELF, deliberately, rather than
%   reimplementing the sweep loop. A test that re-derives the measurement
%   with its own copy of the loop guards the copy, not the script that
%   produced the published numbers -- and the two would then be free to
%   drift apart silently, which is the exact failure this project has
%   already hit once (test_survivor_count_vs_n_resourced.m's hardcoded
%   "original" baseline going stale against a live re-run).
%
%   N=5 seeds, matching the published claim exactly, so this test IS the
%   claim's evidence rather than a weaker smoke check. That costs ~35
%   render+judge calls; slower than a unit test and far cheaper than the
%   300-1000 s CEM tests this suite already carries.

    properties
        FixtureDir
        Results
    end

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'generator.tests.build_phase_b_scenes not importable from this MATLAB''s Python environment (pyenv).');
        end

        function buildFixturesAndSweep(tc)
            tc.FixtureDir = tempname;
            mkdir(tc.FixtureDir);
            mod = py.importlib.import_module('generator.tests.build_phase_b_scenes');
            py.importlib.reload(mod);
            mod.build_one_phantom(fullfile(tc.FixtureDir, 'phaseB_1phantom_singlepulse.mat'), ...
                pyargs('num_pulses_per_frame', int32(1)));
            mod.build_one_phantom(fullfile(tc.FixtureDir, 'phaseB_1phantom_cube.mat'), ...
                pyargs('num_pulses_per_frame', int32(32)));
            mod.build_one_phantom_agile_radar(fullfile(tc.FixtureDir, 'phaseB_1phantom_agile.mat'), ...
                pyargs('num_pulses_per_frame', int32(32)));
            mod.build_two_phantom(fullfile(tc.FixtureDir, 'phaseB_2phantom_cube.mat'), ...
                pyargs('num_pulses_per_frame', int32(32)));

            % ONE sweep for the whole class -- both tests read the same run,
            % so the 35 render+judge calls are paid once, not twice.
            tc.Results = generator.phaseBSweep(tc.FixtureDir, 'NumSeeds', 5);
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

        function test_F3_monopulse_wall_is_total(tc)
            % THE central result. Two independently-consistent phantoms that
            % an angle-blind radar accepts are BOTH condemned the moment a
            % difference channel exists, because one aperture cannot place
            % them on two bearings (Blueprint 2.4). Geometry, not signal
            % fidelity -- which is why no amount of generator improvement
            % moves it, and why a regression here would be a big deal.
            t2 = tc.Results.table2;
            tc.assertNumElements(t2, 2, 'Table 2 must have exactly the off/on pair.');

            off = t2([t2.monopulse] == false);
            on  = t2([t2.monopulse] == true);
            tc.assertNumElements(off, 1);
            tc.assertNumElements(on, 1);

            % Angle-blind: the swarm survives. Published 1.00; asserted as a
            % floor rather than an equality so an unrelated marginal noise
            % draw cannot flap the gate, per this suite's own convention.
            tc.verifyGreaterThanOrEqual(off.pConfirm, 0.8, ...
                'Angle-blind, both phantoms are consistent and should survive.');

            % Monopulse on: TOTAL. This one IS an equality -- the claim is
            % not "mostly caught", it is that the wall admits nothing, and
            % weakening it to a threshold would let the result erode
            % silently one seed at a time.
            tc.verifyEqual(on.pConfirm, 0, ...
                'F3: monopulse must leave zero survivors, not merely fewer.');

            tc.verifyGreaterThan(off.pConfirm, on.pConfirm, ...
                'The wall is the DIFFERENCE between the two arms; both at the same value would mean the angle channel changed nothing.');
        end

        function test_F2_single_phantom_survives_every_radar_class(tc)
            % The control that makes F3 interpretable. If adding capability
            % broke a clean single phantom too, F3 would just be "the judge
            % got stricter", not "the swarm has a geometric tell". Every
            % class must still confirm one genuine-consistent phantom.
            t1 = tc.Results.table1;
            tc.assertNumElements(t1, 5, ...
                'Table 1 must cover range_only -> +Doppler -> +monopulse -> +IMM -> +agility.');

            for i = 1:numel(t1)
                tc.verifyEqual(t1(i).pConfirm, 1, ...
                    sprintf(['F2: radar class ''%s'' must confirm a single ' ...
                             'genuine-consistent phantom in every seed. ' ...
                             'A drop here means added capability is ' ...
                             'rejecting REAL targets, which is a false-alarm ' ...
                             'regression, not a stronger radar.'], t1(i).class));
            end

            % The co-bearing screen cannot fire on one track (it compares
            % tracks to each other), so 'plus_monopulse' passing here is
            % what proves F3's 0.00 comes from the SHARED BEARING and not
            % from the angle channel being hostile to everything.
            mono = t1(strcmp({t1.class}, 'plus_monopulse'));
            tc.assertNumElements(mono, 1);
            tc.verifyEqual(mono.pConfirm, 1, ...
                'Monopulse alone must not condemn a lone phantom -- otherwise F3 measures the screen, not the geometry.');
        end

    end
end

function tf = localPythonReady()
    try
        py.importlib.import_module('generator.tests.build_phase_b_scenes');
        tf = true;
    catch
        tf = false;
    end
end
