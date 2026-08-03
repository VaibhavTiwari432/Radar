classdef test_action_grid_unambiguous < matlab.unittest.TestCase
%TEST_ACTION_GRID_UNAMBIGUOUS  Every commandable radial velocity in every RL
%   environment must stay inside this radar's unambiguous velocity
%   v_ua = lambda*PRF/4 = 59.958 m/s at PRF = 8 kHz.
%
%   WHY. A commanded -60 m/s renders f_d = +4002.8 Hz, which aliases past the
%   +-4000 Hz Nyquist edge and is MEASURED as +59.9 m/s: range closing while
%   Doppler opens -- the exact RGPO/VGPO signature +track/discriminator.m
%   screen 2 exists to catch. The generator would be condemning itself with
%   its own action space, and every evasion number measured on that grid is a
%   measurement of the grid, not of the policy.
%
%   +agent/buildEnvDoppler.m:152 cited this file as its verification. It did
%   not exist until 2 Aug 2026 (Tier 0.1); the claim was unbacked. Written
%   now, and it covers the LATENT half of the same bug too: velocity and the
%   range-walk step share one grid because dt = 1 s, so a range step of d
%   metres per frame IS a range-rate of d m/s. Under manifold projection the
%   commanded velocity is DERIVED from the achieved step, so leaving
%   deltaOptionsM past the fold would alias via the range walk even with
%   velOptionsMps clamped.

    methods (Test)

        function test_buildEnvDoppler_grids_inside_v_ua(tc)
            C = physics.Constants();
            [~, ~, spec] = agent.buildEnvDoppler(C, [], ...
                struct('project', true, 'shaping', false));

            vFromStep = max(abs(spec.deltaOptionsM)) / spec.dt;
            vFromVel  = max(abs(spec.velOptionsMps));

            fprintf(['\n[0.1] v_ua %.3f m/s | max step %.1f m/frame @ dt %.1f s ' ...
                     '-> %.3f m/s | max vel %.3f m/s\n'], ...
                C.v_unambiguous, max(abs(spec.deltaOptionsM)), spec.dt, ...
                vFromStep, vFromVel);
            fprintf('[0.1] margin %.3f m/s = %.2f Doppler bins (bin %.3f m/s)\n', ...
                C.v_unambiguous - max(vFromStep, vFromVel), ...
                (C.v_unambiguous - max(vFromStep, vFromVel)) / spec.dopplerBinMps, ...
                spec.dopplerBinMps);

            tc.verifyLessThan(vFromStep, C.v_unambiguous, ...
                'range-step grid implies a velocity past v_ua');
            tc.verifyLessThan(vFromVel, C.v_unambiguous, ...
                'velocity grid exceeds v_ua');
        end

        function test_buildEnvEntity_grid_inside_v_ua(tc)
            C = physics.Constants();
            src = fileread(fullfile(fileparts(mfilename('fullpath')), ...
                '..', '+agent', 'buildEnvEntity.m'));
            v = localGridFromSource(tc, src, 'velOptionsMps');
            fprintf('[0.1] buildEnvEntity velOptionsMps max |v| = %.3f m/s\n', max(abs(v)));
            tc.verifyLessThan(max(abs(v)), C.v_unambiguous);
        end

        function test_t1TrajectoryDof_print_copy_matches_env(tc)
            % t1TrajectoryDof keeps a HAND-SYNCED copy of deltaOptionsM purely
            % to label its by-step breakdown. A stale copy mislabels every row
            % of that table, so it is checked rather than trusted.
            C = physics.Constants();
            [~, ~, spec] = agent.buildEnvDoppler(C, [], ...
                struct('project', true, 'shaping', false));
            src = fileread(fullfile(fileparts(mfilename('fullpath')), ...
                '..', '+experiments', 't1TrajectoryDof.m'));
            deltas = localGridFromSource(tc, src, 'deltas');
            fprintf('[0.1] t1TrajectoryDof print copy [%s] vs env [%s]\n', ...
                num2str(deltas(:)'), num2str(spec.deltaOptionsM(:)'));
            tc.verifyEqual(deltas(:)', spec.deltaOptionsM(:)', 'AbsTol', 1e-9, ...
                't1TrajectoryDof''s hand-synced delta grid has drifted from buildEnvDoppler''s');
        end

        function test_episodes_emit_no_aliasing_warning(tc)
            % The dynamic half: run the real environment the way
            % experiments.t1TrajectoryDof runs it and confirm no achieved
            % range-rate crosses the fold and no warning fires.
            C = physics.Constants();
            env = agent.buildEnvDoppler(C, [], ...
                struct('project', true, 'shaping', false));
            rng(77);
            nEp = 10; wcount = 0; maxV = 0;
            for e = 1:nEp
                reset(env);
                a = sub2ind([5 5 5], randi(5), randi(5), 3);
                lg = [];
                for k = 1:8
                    lastwarn('');
                    [~, ~, ~, lg] = step(env, a);
                    if ~isempty(lastwarn); wcount = wcount + 1; end
                end
                maxV = max(maxV, max(abs(lg.cmdVelHist)));
            end
            fprintf('[0.1] %d episodes: %d warnings, max |achieved Rdot| = %.3f m/s (v_ua %.3f)\n', ...
                nEp, wcount, maxV, C.v_unambiguous);
            tc.verifyEqual(wcount, 0);
            tc.verifyLessThanOrEqual(maxV, C.v_unambiguous);
        end
    end
end

% ------------------------------------------------------------------------
function v = localGridFromSource(tc, src, name)
    tok = regexp(src, [name '\s*=\s*linspace\(([^)]*)\)'], 'tokens', 'once');
    tc.assertNotEmpty(tok, sprintf('no linspace assignment to %s found', name));
    v = eval(['linspace(' tok{1} ')']);
end
