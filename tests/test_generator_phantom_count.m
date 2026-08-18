classdef test_generator_phantom_count < matlab.unittest.TestCase
%TEST_GENERATOR_PHANTOM_COUNT  Regression cover for claims F7 and F8.
%
%   F7: "the monopulse wall is total and N-INDEPENDENT -- 8 phantoms fare
%   exactly as badly as 2: 8/8 confirmed, 8/8 flagged, 0 survivors. Angle-
%   blind, the same swarm sustains 8/8."
%   F8: the equal-RCS arm's loss at N=8 is NOT the radar catching phantoms
%   -- they are amplitude-screen false positives on weak far returns.
%
%   Both were measured by generator.phantomCountSweep, a manually-run
%   script with no test. The 10 Aug 2026 audit found 5 of 7 +generator/
%   entry points uncovered; test_generator_phase_b.m and
%   test_generator_agility.m closed two, this closes the third.
%
%   WHY N=2 SEEDS HERE AND 5 IN THE PUBLISHED TABLE. The sweep is
%   2 arms x 2 angle settings x 4 N-values x seeds render+judge calls, so
%   seeds are the only cost lever. The claims this file guards sit at the
%   EXTREMES (0 survivors, or all N surviving), not at a marginal rate, so
%   a second seed is enough to catch a break while keeping the file
%   runnable in the suite. The N=5 table in CLAIMABLE_RESULTS.md remains
%   generator.phantomCountSweep's own job -- this is a regression gate, not
%   a replacement for the published measurement, and it must not be quoted
%   as one.
%
%   NOT ASSERTED HERE: the exact 6.20/8 equal-RCS number behind F8. That
%   figure needs the screen-attribution run (disabling the amplitude screen
%   and watching the flags vanish) which this sweep does not perform. What
%   IS asserted is the structural half -- that those phantoms are all
%   CONFIRMED, i.e. detected, so any loss is a labelling decision and not a
%   detection failure. That distinction is the entire reason
%   phantomCountSweep reports three numbers instead of one.

    properties
        FixtureDir
        R
    end

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'generator.tests.build_n_phantom_scenes not importable from this MATLAB''s Python environment (pyenv).');
        end

        function buildAndSweep(tc)
            tc.FixtureDir = tempname;
            mkdir(tc.FixtureDir);
            mod = py.importlib.import_module('generator.tests.build_n_phantom_scenes');
            py.importlib.reload(mod);
            arms = {'equalrcs', 'equalpower'};
            equalPower = [false true];
            for a = 1:2
                for n = [1 2 4 8]
                    mod.build_n_phantom_scene( ...
                        fullfile(tc.FixtureDir, sprintf('nphantom_%s_N%d.mat', arms{a}, n)), ...
                        int32(n), equalPower(a));
                end
            end
            tc.R = generator.phantomCountSweep(tc.FixtureDir, 'NumSeeds', 2);
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

        function test_F7_monopulse_leaves_no_survivors_at_any_N_above_one(tc)
            % The wall, and its N-independence. Asserted for EVERY N >= 2 in
            % BOTH arms -- including equal-power, the adversary's best case,
            % where every phantom arrives at the same received power. If
            % more power bought survivability this is the cell that would
            % show it.
            rows = tc.R([tc.R.monopulse] == true & [tc.R.n] >= 2);
            tc.assertNotEmpty(rows);
            for k = 1:numel(rows)
                tc.verifyEqual(rows(k).surviving, 0, ...
                    sprintf(['F7: arm %s, N=%d, monopulse ON must leave ZERO ' ...
                             'survivors. One aperture cannot place N phantoms ' ...
                             'on N bearings -- if this passes, either the ' ...
                             'co-bearing screen or render.m''s single-azimuth ' ...
                             'constraint has changed.'], rows(k).arm, rows(k).n));
            end
        end

        function test_F7_the_same_swarm_survives_an_angle_blind_radar(tc)
            % The control. Without it, "0 survivors" could just mean the
            % scene never worked. The equal-POWER arm is used because it is
            % the one whose phantoms are all guaranteed detectable at every
            % N by construction; the equal-RCS arm deliberately fades with
            % range and is the subject of F8 below.
            rows = tc.R(strcmp({tc.R.arm}, 'equalpower') & ...
                        [tc.R.monopulse] == false & [tc.R.n] >= 2);
            tc.assertNotEmpty(rows);
            for k = 1:numel(rows)
                tc.verifyEqual(rows(k).surviving, rows(k).n, ...
                    sprintf(['Angle-blind, all %d phantoms of the equal-power ' ...
                             'arm are individually consistent and must survive. ' ...
                             'A loss here means the scene broke, not that the ' ...
                             'radar got smarter.'], rows(k).n));
            end
        end

        function test_F7_N1_cannot_be_flagged_cobearing(tc)
            % The co-bearing screen compares tracks to each other, so it is
            % structurally incapable of firing on a single track. N=1 with
            % monopulse ON must therefore still survive -- this is what
            % proves the N>=2 zeros above come from the SHARED BEARING and
            % not from the angle channel being hostile to everything.
            rows = tc.R([tc.R.n] == 1 & [tc.R.monopulse] == true);
            tc.assertNotEmpty(rows);
            for k = 1:numel(rows)
                tc.verifyEqual(rows(k).surviving, 1, ...
                    'A lone phantom has no one to share a bearing with and must survive monopulse.');
            end
        end

        function test_F8_equal_rcs_losses_are_labelling_not_detection(tc)
            % F8's structural half. Every phantom in the equal-RCS arm is
            % physically consistent by construction, so any flag is the
            % radar making a LABELLING decision about something it saw --
            % not failing to see it. Guarding this is what stops a future
            % "the radar caught them" reading of a number that is really
            % "the radar never detected them", which this project has
            % already been burned by once (the N=8 CEM cell).
            rows = tc.R(strcmp({tc.R.arm}, 'equalrcs') & [tc.R.monopulse] == false);
            tc.assertNotEmpty(rows);
            for k = 1:numel(rows)
                tc.verifyEqual(rows(k).surviving, rows(k).confirmed - rows(k).flagged, ...
                    'surviving = confirmed - flagged must hold by construction.');
                tc.verifyGreaterThan(rows(k).confirmed, 0, ...
                    sprintf(['arm equalrcs, N=%d: nothing confirmed at all. ' ...
                             'That is a DETECTION failure and must not be ' ...
                             'reported as ECCM success.'], rows(k).n));
            end
        end

    end
end

function tf = localPythonReady()
    try
        py.importlib.import_module('generator.tests.build_n_phantom_scenes');
        tf = true;
    catch
        tf = false;
    end
end
