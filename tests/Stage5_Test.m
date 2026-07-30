classdef Stage5_Test < matlab.unittest.TestCase
%STAGE5_TEST  ECCM discriminator: the radar's counter-DRFM defences.
%              (POA Part 4, Stage 5; claim C7)
%
%   STATUS: SPEC / SCAFFOLD. Incomplete until +track/discriminator.m exists.
%
%   Intended contract:
%       [label, confidence] = track.discriminator(trackStruct, C)
%         label      : "real" | "decoy"
%         confidence : 0..1
%   Screens (POA Stage 5): kinematic plausibility, amplitude-range
%   consistency (1/R^4 real vs 1/R^2 repeater), Doppler-range-rate
%   consistency, optional learned classifier.
%
%   Claim under test: a NAIVE decoy (constant amplitude, zero Doppler) is
%   flagged; a real target passes. This is the radar that can "sometimes
%   catch you" -- the only kind worth fooling.

    methods (TestMethodSetup)
        function requireImpl(tc)
            tc.assumeTrue(localHas('track.discriminator'), ...
                'Stage 5 pending: implement +track/discriminator.m (spec in this file).');
        end
    end

    methods (Test)

        function test_flags_naive_decoy(tc)
            C = physics.Constants();
            decoy = struct('range',[2000 2000 2000 2000 2000], ...  % not moving
                           'amplitude',[1 1 1 1 1], ...             % constant (1/R^0)
                           'doppler',[0 0 0 0 0]);                  % zero Doppler
            [label, conf] = track.discriminator(decoy, C);
            tc.verifyEqual(string(label), "decoy", 'Naive decoy should be flagged.');
            tc.verifyGreaterThan(conf, 0.5);
        end

        function test_passes_real_target(tc)
            C = physics.Constants();
            R = 2000 - (0:4)*40;                       % closing target
            real = struct('range', R, ...
                          'amplitude', 1./R.^2, ...    % physical fall-off
                          'doppler', -ones(1,5)*50);   % Doppler consistent w/ closing
            [label, ~] = track.discriminator(real, C);
            tc.verifyEqual(string(label), "real", 'Physical target should pass ECCM.');
        end

    end

end

% ===================== file-local helpers =============================
function tf = localHas(name)
    tf = ~isempty(which(name));
end
