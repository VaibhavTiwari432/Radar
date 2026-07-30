classdef Stage6_Test < matlab.unittest.TestCase
%STAGE6_TEST  DRFM synthesizer + RL agent, judged by the radar AND the ECCM.
%              (POA Part 4-5, Stage 6; claim C9)
%
%   STATUS: RUNNABLE NOW.
%
%   Intended contracts:
%       env   = agent.buildEnv(C)      % rlFunctionEnv wrapping the radar chain
%       agnt  = agent.buildAgent(env)  % dueling Double-DQN (D3QN)
%
%   Multi-step episode (F=8 frames/steps): observation is
%   [frameIndex/F ; currentFakeRange/3000 ; wasDetectedLastFrame], and the
%   action is a per-frame (range-walk delta, gain) choice -- so Doppler is
%   DERIVED from the agent's own kinematic choices, not fixed at zero, and
%   the agent can in principle learn a gain-vs-range policy that mimics a
%   physical 1/R^2 return.
%
%   The environment reward MUST come from BOTH track.runTracker's
%   confirmed-track count AND track.discriminator's real/decoy label
%   (independence, CLAUDE.md Rule 2) -- not a hand-written formula, and not
%   just the raw tracker (a naive, kinematically-flat replay should be
%   confirmable but still catchable by the ECCM; only a trajectory that
%   also passes track.discriminator counts as a full win).
%
%   Claim under test: a trajectory whose gain tracks its own range roughly
%   like 1/R^2 (self-consistent Doppler comes for free from the walk)
%   scores strictly higher than a static replay that gives the tracker/ECCM
%   nothing to be fooled by beyond one range/gain pair repeated 8 times.

    methods (TestMethodSetup)
        function requireImpl(tc)
            tc.assumeTrue(localHas('agent.buildEnv'), ...
                'Stage 6 pending: implement +agent/buildEnv.m (rlFunctionEnv over the radar).');
        end
    end

    methods (Test)

        function test_environment_validates(tc)
            C = physics.Constants();
            env = agent.buildEnv(C);
            validateEnvironment(env);        % throws (=> Failed) if malformed
            tc.verifyTrue(true);
        end

        function test_action_space_is_45(tc)
            C = physics.Constants();
            env = agent.buildEnv(C);
            actInfo = getActionInfo(env);
            tc.verifyEqual(numel(actInfo.Elements), 45, ...
                'Discrete swarm action space should have 45 actions (POA).');
        end

        function test_reward_originates_from_tracker_and_eccm(tc)
            % Structural guard (CLAUDE.md Rule 2): reward must derive from
            % BOTH track.runTracker and track.discriminator, not a
            % hand-rolled formula or any +synth self-grading.
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            src = fileread(fullfile(root, '+agent', 'buildEnv.m'));
            tc.verifyTrue(contains(src, 'track.runTracker('), ...
                '+agent/buildEnv.m must call track.runTracker to gate the reward.');
            tc.verifyTrue(contains(src, 'track.discriminator('), ...
                '+agent/buildEnv.m must call track.discriminator so a confirmed-but-caught track scores below a confirmed-and-real one.');

            % Behavioral check: a trajectory whose gain tracks 1/R^2 as it
            % walks its own fake range (self-consistent Doppler comes free
            % from the walk) must score strictly higher over a full episode
            % than a static replay (same range/gain all 8 frames) -- proof
            % that BOTH the tracker and the ECCM are live in the reward,
            % not just the tracker.
            C = physics.Constants();
            deltaOptionsM = linspace(-120, 120, 5);
            gainOptions   = linspace(0.5, 4.5, 9);

            rng(11);
            env = agent.buildEnv(C);
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
            env2 = agent.buildEnv(C);
            reset(env2);
            staticTotal = 0;
            for k = 0:7
                a = (1-1)*5 + 3;   % delta=0, fixed low gain, every frame
                [~, r] = step(env2, a);
                staticTotal = staticTotal + r;
            end

            tc.verifyGreaterThan(smartTotal, staticTotal, sprintf( ...
                ['A range-walk trajectory with gain tracking 1/R^2 (total=%.2f) should ' ...
                 'score above a static replay (total=%.2f) -- only the former can pass ' ...
                 'track.discriminator, not just track.runTracker.'], smartTotal, staticTotal));
        end

    end

end

% ===================== file-local helpers =============================
function tf = localHas(name)
    tf = ~isempty(which(name));
end
