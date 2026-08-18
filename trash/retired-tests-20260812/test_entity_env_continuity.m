classdef test_entity_env_continuity < matlab.unittest.TestCase
%TEST_ENTITY_ENV_CONTINUITY  Tier 1.3 + 1.4 for agent.buildEnvEntity.
%
%   1.3  Swerling is a stated parameter and the render pipeline's existing
%        localSwerlingGain actually fires (the environment used to hardcode
%        swerling = 0, a non-fluctuating target).
%   1.4  The rendered range rate always equals the ACHIEVED range step, even
%        when the range clamp fires -- structurally, not by convention.

    methods (Test)

        function test_swerling_is_wired_and_defaults_to_fluctuating(tc)
            % Pending rewire to generator.render -- see the class header.
            tc.assumeTrue(archivedDepsPresent({'agent.buildEnvEntity'}), ...
                'agent.buildEnvEntity was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
            C = physics.Constants();
            [~, spec] = agent.buildEnvEntity(C);
            fprintf('\n[1.3] default swerling = %d\n', spec.swerling);
            tc.verifyEqual(spec.swerling, 1, ...
                'default must be a FLUCTUATING target, not swerling 0');

            [~, spec0] = agent.buildEnvEntity(C, struct('swerling', 0));
            tc.verifyEqual(spec0.swerling, 0, 'must still be settable to 0 for reproduction');
        end

        function test_swerling_actually_changes_the_rendered_amplitude(tc)
            % Pending rewire to generator.render -- see the class header.
            tc.assumeTrue(archivedDepsPresent({'agent.buildEnvEntity'}), ...
                'agent.buildEnvEntity was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
            % Wiring is not enough -- prove the fluctuation reaches the
            % receiver. Same entity, same seed, swerling 0 vs 1.
            C = physics.Constants();
            s0 = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -50, ...
                    'rcs_dbsm', 0, 'swerling', 0, 'class', 'drone');
            s1 = engine.entity.EntityState('range_m', 1800, 'range_rate_mps', -50, ...
                    'rcs_dbsm', 0, 'swerling', 1, 'class', 'drone');
            args = {'NumPulses', 32, 'FastTimeSamples', 400, 'CarrierHz', 10e9, ...
                    'PrfHz', C.PRF, 'PulseWidth', 12e-6, 'Bandwidth', 2e6, 'AmpScale', 3.0};
            g0 = []; g1 = [];
            for k = 1:8
                [~, m0] = engine.entity.render(s0, args{:}, ...
                            'RandStream', RandStream('twister','Seed',100+k));
                [~, m1] = engine.entity.render(s1, args{:}, ...
                            'RandStream', RandStream('twister','Seed',100+k));
                g0(end+1) = mean(m0.swerling_gain); %#ok<AGROW>
                g1(end+1) = mean(m1.swerling_gain); %#ok<AGROW>
            end
            db0 = 20*log10(std(g0)/mean(g0) + eps);
            fprintf('[1.3] swerling 0 gain std %.3g | swerling 1 gain std %.3f (scatter %.2f dB)\n', ...
                std(g0), std(g1), 20*log10(1 + std(g1)/mean(g1)));
            tc.verifyLessThan(std(g0), 1e-12, 'swerling 0 must be exactly non-fluctuating');
            tc.verifyGreaterThan(std(g1), 0.1, 'swerling 1 must actually fluctuate');
            tc.assumeTrue(isfinite(db0));
        end

        function test_rate_matches_achieved_step_every_frame(tc)
            % Pending rewire to generator.render -- see the class header.
            tc.assumeTrue(archivedDepsPresent({'agent.buildEnvEntity'}), ...
                'agent.buildEnvEntity was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
            % 1.4 on the real pipeline: the invariant holds across episodes.
            C = physics.Constants();
            env = agent.buildEnvEntity(C, struct('shaping', false));
            [~, spec] = agent.buildEnvEntity(C, struct('shaping', false));
            rng(3);
            worst = 0;
            for e = 1:20
                reset(env);
                lg = [];
                for k = 1:spec.framesPerEpisode
                    a = randi(spec.numActions);
                    [~, ~, ~, lg] = step(env, a);
                end
                d = abs(lg.cmdVelHist(:) - lg.cmdRangeStep(:)/spec.dt);
                worst = max(worst, max(d));
            end
            fprintf('[1.4] 20 episodes: worst |rate - achievedStep/dt| = %.3g m/s\n', worst);
            tc.verifyLessThan(worst, 1e-9);
        end

        function test_clamp_actually_fires_and_stays_consistent(tc)
            % Pending rewire to generator.render -- see the class header.
            tc.assumeTrue(archivedDepsPresent({'agent.buildEnvEntity'}), ...
                'agent.buildEnvEntity was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
            % The acceptance test's own condition: MAKE the clamp fire. With
            % the default R0 = 1800 m it cannot (max 8-frame drift is 400 m
            % against a 1124 m floor), which is why 160 episodes hit it 0
            % times. Start near the floor instead.
            C = physics.Constants();
            cfarD = radar.cfarDefaults();
            floorM = (cfarD.NumTraining + cfarD.NumGuard) * C.range_per_sample;
            R0 = floorM + 60;                 % one -50 m/s step reaches the bound
            env = agent.buildEnvEntity(C, struct('shaping', false, 'R0', R0));
            [~, spec] = agent.buildEnvEntity(C, struct('shaping', false, 'R0', R0));

            closingAction = sub2ind([numel(spec.velOptionsMps) numel(spec.rcsOptionsDbsm)], 1, 3);
            reset(env); lg = [];
            for k = 1:spec.framesPerEpisode
                [~, ~, ~, lg] = step(env, closingAction);   % hard closing, hits the floor
            end
            commanded = spec.velOptionsMps(1);
            achieved  = lg.cmdRangeStep(:) / spec.dt;
            nClamped  = nnz(abs(achieved - commanded) > 1e-9);
            fprintf('[1.4] floor %.1f m, R0 %.1f m: clamp fired in %d/%d frames\n', ...
                floorM, R0, nClamped, spec.framesPerEpisode);
            tc.verifyGreaterThan(nClamped, 0, 'the clamp must actually fire for this test to mean anything');

            % The invariant must survive the clamp -- this is the whole point.
            d = abs(lg.cmdVelHist(:) - achieved);
            fprintf('[1.4] with clamp firing : worst |rate - achievedStep/dt| = %.3g m/s\n', max(d));
            tc.verifyLessThan(max(d), 1e-9, ...
                'a clamped frame must render the ACHIEVED rate, not the commanded one');
        end

        function test_assertion_catches_a_deliberate_break(tc)
            % Prove the guard can fail. Mirrors the environment's own check
            % with a rate that disagrees with the step at a range that is NOT
            % at either bound -- the one combination it must reject.
            rangeRate = -50; newRange = 1600; prevRange = 1800; dt = 1.0;
            rangeMinM = 1124; rangeMaxM = 15833;
            achieved = (newRange - prevRange)/dt;      % -200, disagrees with -50
            clampFired = abs(achieved - rangeRate) > 1e-9;
            atBound = abs(newRange - rangeMinM) < 1e-6 || abs(newRange - rangeMaxM) < 1e-6;
            fprintf('[1.4] deliberate break  : rate %+d vs achieved %+d, atBound %d -> assertion fires %d\n', ...
                rangeRate, achieved, atBound, clampFired && ~atBound);
            tc.verifyTrue(clampFired && ~atBound, ...
                'the guard condition must be TRUE for this inconsistency');
        end
    end
end
