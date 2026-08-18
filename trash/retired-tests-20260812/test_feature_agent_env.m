classdef test_feature_agent_env < matlab.unittest.TestCase
%TEST_FEATURE_AGENT_ENV  Contract for the feature-conditioned D3QN env
%   (+agent/buildEnvFeatureConditioned.m): the 54-D PFB feature vector is a
%   LIVE part of the observation, and the independent-judge reward still
%   rewards a physically self-consistent (gain~1/R^2) trajectory over a
%   static replay through that richer state.

    methods (TestClassSetup)
        function assumeArchivedDependencyPresent(tc)
            % 7 Aug 2026 archive: every scene in this file is built by
            % agent.buildEnvFeatureConditioned, which no longer exists. Report Incomplete --
            % this project's own honest "not built yet" outcome, the same
            % one DataIntegration_Test uses for an absent dataset -- rather
            % than erroring. 63 errored methods made a real regression
            % invisible; a skip keeps the suite usable as an instrument.
            % NOT a fix: rewire to generator.render to genuinely re-enable.
            tc.assumeTrue(archivedDepsPresent({'agent.buildEnvFeatureConditioned'}), ...
                'agent.buildEnvFeatureConditioned was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
        end
    end

    methods (Test)

        function test_environment_validates(tc)
            C = physics.Constants();
            env = agent.buildEnvFeatureConditioned(C);
            validateEnvironment(env);          % throws -> Failed if malformed
            tc.verifyTrue(true);
        end

        function test_observation_is_57d_with_live_features(tc)
            C = physics.Constants();
            env = agent.buildEnvFeatureConditioned(C);
            obsInfo = getObservationInfo(env);
            tc.verifyEqual(obsInfo.Dimension(1), 57, ...
                'Observation must be 3 kinematic + 54 PFB features = 57-D.');
            tc.verifyEqual(numel(getActionInfo(env).Elements), 45, ...
                'Action space is still the 45 (5 delta x 9 gain) DRFM actions.');

            rng(7);
            obs0 = reset(env);
            tc.verifyEqual(numel(obs0), 57);
            tc.verifyEqual(obs0(4:end), zeros(54,1), ...
                'Reset carries no echo yet -> feature block must be zero.');

            [obs1, ~, ~, ~] = step(env, 23);   % any mid-space action
            featBlock = obs1(4:end);
            tc.verifyEqual(numel(featBlock), 54);
            tc.verifyGreaterThan(nnz(abs(featBlock) > 1e-6), 0, ...
                'After a step the 54-D feature block must be populated from the echo.');
            tc.verifyTrue(all(featBlock >= -1 & featBlock <= 1), ...
                'tanh-normalized feature block must stay within [-1,1].');
        end

        function test_smart_trajectory_beats_static(tc)
            % Same behavioral claim as Stage6_Test, now through the 57-D
            % feature-conditioned env: a range-walk with gain tracking 1/R^2
            % (self-consistent Doppler comes free) scores strictly above a
            % static replay -- proof the tracker+ECCM reward is live, not the
            % features (features only perceive; Rule 2).
            C = physics.Constants();
            deltaOptionsM = linspace(-120, 120, 5);
            gainOptions   = linspace(0.5, 4.5, 9);

            rng(11);
            env = agent.buildEnvFeatureConditioned(C);
            reset(env);
            deltaIdx = 1; R0 = 1800; delta = deltaOptionsM(deltaIdx);
            smartTotal = 0;
            for k = 0:7
                Rk = R0 + delta*k;
                idealGain = 1.0 * (R0/Rk)^2;
                [~, gi] = min(abs(gainOptions - idealGain));
                a = (gi-1)*5 + deltaIdx;
                [~, r] = step(env, a);
                smartTotal = smartTotal + r;
            end

            rng(11);
            env2 = agent.buildEnvFeatureConditioned(C);
            reset(env2);
            staticTotal = 0;
            for k = 0:7
                a = (1-1)*5 + 3;   % delta=0, fixed low gain
                [~, r] = step(env2, a);
                staticTotal = staticTotal + r;
            end

            tc.verifyGreaterThan(smartTotal, staticTotal, sprintf( ...
                'Smart 1/R^2 trajectory (%.2f) should beat static replay (%.2f).', ...
                smartTotal, staticTotal));
        end

    end
end
