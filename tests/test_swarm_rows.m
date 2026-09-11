classdef test_swarm_rows < matlab.unittest.TestCase
%TEST_SWARM_ROWS  The two new row layouts of experiments.skinBacktrackCheck.
%
%   1. M drones x K phantoms: a backtrack to a SIBLING phantom counts as tied
%      to the right drone (ownerOf / interleaving). Fails if siblings are
%      mis-owned or counted as someone else's.
%   2. The moving-mother platform path: the builder appends the skin row LAST;
%      the remap must hand the drone back as row 1 and the phantom as row 2.
%      Fails if the remap, the centring or the MotherTrack cross-check breaks.
%   One seed each, detectable 1 m^2 drones, 2400 m clear of CFAR masking.

    methods (Test)
        function test_siblings_are_tied_to_their_own_drone(tc)
            r = experiments.skinBacktrackCheck('N', 2, 'K', 2, 'GapM', 2400, ...
                'PlatformRcs', 1, 'NumSeeds', 1, 'Arms', "swarm");
            tc.verifyGreaterThanOrEqual(r.k, 3, 'most of the 4 phantoms should be backtracked');
            tc.verifyEqual(r.toOwnDrone, r.k, 'a phantom was tied to the wrong drone');
        end

        function test_a_moving_mother_maps_back_to_drone_one(tc)
            r = experiments.skinBacktrackCheck('N', 1, 'K', 1, 'DroneStartM', 4000, ...
                'GapM', 2400, 'SpreadDeg', 1, 'DroneVelocityMps', [0 35], ...
                'PlatformRcs', 1, 'NumSeeds', 1, 'Arms', "swarm");
            tc.verifyEqual(r.skinDetected, 1, 'the moving drone''s skin echo was not matched');
            tc.verifyEqual([r.k, r.toOwnDrone], [1, 1], 'the phantom was not tied to its drone');
        end
    end
end
