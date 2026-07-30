classdef Stage0_Test < matlab.unittest.TestCase
%STAGE0_TEST  Verify the toolchain: MATLAB + the five required toolboxes.
%
%   STATUS: RUNNABLE NOW. This is the "does the agentic loop reach a real
%   MATLAB with the right toolboxes" check (POA Part 4, Stage 0). No radar
%   logic yet.
%
%   Run:  runAllTests('Stage0')
%   Pass: all green means MATLAB, Signal Processing, Phased Array, Sensor
%         Fusion & Tracking, Reinforcement Learning, and Deep Learning are
%         installed, licensed, and callable through Claude Code.

    methods (TestClassSetup)
        function addProjectPath(~)
            here = fileparts(mfilename('fullpath'));
            addpath(fileparts(here));   % project root (parent of tests/)
        end
    end

    methods (Test)

        function test_basic_arithmetic(tc)
            tc.verifyEqual(2+3, 5, 'Base MATLAB arithmetic failed.');
        end

        function test_vector_ops(tc)
            tc.verifyEqual(sum(1:5), 15, 'Vector sum failed.');
        end

        function test_signal_processing_toolbox(tc)
            tc.verifyConstructs(@() hamming(8), 'Signal Processing Toolbox');
        end

        function test_phased_array_toolbox(tc)
            tc.verifyConstructs(@() phased.CFARDetector(), ...
                'Phased Array System Toolbox (phased.CFARDetector)');
            tc.verifyConstructs(@() phased.LinearFMWaveform(), ...
                'Phased Array System Toolbox (phased.LinearFMWaveform)');
        end

        function test_tracking_toolbox(tc)
            tc.verifyConstructs(@() trackerGNN('ConfirmationThreshold',[3 5]), ...
                'Sensor Fusion and Tracking Toolbox (trackerGNN)');
        end

        function test_reinforcement_learning_toolbox(tc)
            tc.verifyConstructs(@() rlFiniteSetSpec(1:45), ...
                'Reinforcement Learning Toolbox (rlFiniteSetSpec)');
            tc.verifyConstructs(@() rlDQNAgentOptions('UseDoubleDQN',true), ...
                'Reinforcement Learning Toolbox (rlDQNAgentOptions)');
        end

        function test_deep_learning_toolbox(tc)
            tc.verifyConstructs(@() featureInputLayer(4), ...
                'Deep Learning Toolbox (featureInputLayer)');
        end

        function test_physics_constants_load(tc)
            % Project code is on the path and derivations are self-consistent.
            C = physics.Constants();
            tc.verifyGreaterThan(C.range_per_sample, 0);
            tc.verifyEqual(C.range_per_sample, C.c/(2*C.fs), 'AbsTol', 1e-9, ...
                'physics.Constants range_per_sample is not c/(2*fs).');
        end

    end

    methods (Access = private)
        function verifyConstructs(tc, fh, label)
            % Try to construct an object; verify it succeeds and is non-empty.
            ok = true; msg = '';
            try
                obj = fh();
                ok = ~isempty(obj);
            catch e
                ok = false; msg = e.message;
            end
            tc.verifyTrue(ok, sprintf('%s not available/constructible. %s', label, msg));
        end
    end

end
