classdef test_trajectory_envelope_audit < matlab.unittest.TestCase
%TEST_TRAJECTORY_ENVELOPE_AUDIT  Phase 4.1.3: which existing scenes survive
%   the corrected radar, and which were only ever renderable because the
%   radar was two radars at once.
%
%   The corrected 8 kHz PRF widens the unambiguous RANGE by 6.25x (2998 ->
%   18737 m) and narrows the unambiguous VELOCITY by the same factor
%   (+-375 -> +-60 m/s). Both directions matter, and they matter to different
%   scenes: nothing in this repo is range-ambiguous any more, and almost
%   everything fast is Doppler-ambiguous.
%
%   This test REPORTS rather than gates. It asserts only the facts it needs
%   to stay true for the report to mean anything.

    methods (Test)

        function test_report_canonical_scenes_against_the_corrected_envelope(tc)
            C = physics.Constants();
            fprintf('\n=== 4.1.3 TRAJECTORY AUDIT vs the corrected radar ===\n');
            fprintf('R_ua = %.1f m (was 2997.9) | v_ua = +-%.1f m/s (was +-375.0)\n\n', ...
                C.R_unambiguous, C.v_unambiguous);

            % name, ranges [m], radial speeds [m/s], source
            scenes = {
              'canonical single phantom', 1800,                        -60,   'CLAUDE.md / most tests'
              'canonical 4-phantom swarm', [1800 3000 4200 5400],      -60,   'test_four_phantom_swarm.m'
              'angle-channel formation',   [1800 2600 3400 4200],      -60,   'test_angle_channel.m'
              'D2 monopulse scene',        [900 1600 2300 2900],       -60,   'test_monopulse_snr_boundary.m'
              'VEE deception geom 1',      1800,                       -60,   'test_vee_deception_check.m'
              'VEE deception geom 2',      4000,                       -150,  'test_vee_deception_check.m'
              'planner search envelope',   [600 18737],                -120,  'DEFAULT_BOUNDS_MULTI (pre-4.1)'
              'RadChar three-arm',         1800,                       -60,   'test_radchar_three_arm.m'
            };

            fprintf('%-28s %-22s %8s %9s %9s %-9s\n', 'scene', 'ranges [m]', ...
                '|v| m/s', 'R>R_ua?', 'v>v_ua?', 'verdict');
            nRangeAmbig = 0; nVelAmbig = 0;
            for i = 1:size(scenes,1)
                rngs = scenes{i,2}; v = abs(scenes{i,3});
                rAmb = any(rngs > C.R_unambiguous);
                vAmb = v > C.v_unambiguous;
                nRangeAmbig = nRangeAmbig + rAmb;
                nVelAmbig   = nVelAmbig + vAmb;
                if vAmb
                    verdict = 'FOLDS';
                elseif abs(v - C.v_unambiguous) < 1.0
                    verdict = 'AT EDGE';
                else
                    verdict = 'ok';
                end
                fprintf('%-28s %-22s %8.0f %9s %9s %-9s\n', scenes{i,1}, ...
                    mat2str(rngs), v, tf(rAmb), tf(vAmb), verdict);
            end

            fprintf(['\nRANGE: %d of %d scenes exceed R_ua. The corrected PRF makes every\n' ...
                     '  scene in this repository range-unambiguous -- including the canonical\n' ...
                     '  4-phantom swarm, three of whose phantoms were beyond the OLD 2998 m\n' ...
                     '  R_ua. Phase 3''s "N >= 4 is not feasible at this PRF" is WITHDRAWN:\n' ...
                     '  it was a consequence of the wrong PRF, not of the geometry.\n'], ...
                     nRangeAmbig, size(scenes,1));
            fprintf(['\nVELOCITY: %d of %d scenes exceed v_ua, and the canonical -60 m/s sits\n' ...
                     '  EXACTLY ON THE EDGE. This is now the binding constraint.\n'], ...
                     nVelAmbig, size(scenes,1));

            tc.verifyEqual(nRangeAmbig, 0, ...
                'A scene is range-ambiguous at the corrected PRF -- re-derive this audit.');
            tc.verifyGreaterThan(nVelAmbig, 0, ...
                'No scene exceeds v_ua -- the velocity constraint claim needs re-deriving.');
        end

        function test_the_canonical_60mps_sits_exactly_on_the_fold_edge(tc)
        % THE SHARPEST CONSEQUENCE, and it deserves its own assertion.
        % v_ua = 59.96 m/s. This project's canonical closing rate is 60 m/s.
        % Its Doppler is 2*60/lambda = 4000 Hz, and PRF/2 is also 4000 Hz --
        % the Nyquist edge exactly. The canonical scene is not comfortably
        % inside the envelope; it is ON it.
            C = physics.Constants();
            vCanon = 60;
            fd = 2*vCanon / C.lambda;
            fprintf('\n[4.1.3] canonical |v| = %.0f m/s -> f_d = %.0f Hz\n', vCanon, fd);
            fprintf('[4.1.3] PRF/2 (Nyquist) = %.0f Hz | v_ua = %.2f m/s\n', C.PRF/2, C.v_unambiguous);
            fprintf('[4.1.3] margin = %.2f m/s (%.3f%% of v_ua) -- ON THE EDGE\n', ...
                C.v_unambiguous - vCanon, 100*(C.v_unambiguous - vCanon)/C.v_unambiguous);

            tc.verifyEqual(fd, C.PRF/2, 'RelTol', 1e-3, ...
                'The canonical Doppler must sit at the Nyquist edge -- that is the finding.');
            tc.verifyLessThan(abs(vCanon - C.v_unambiguous), 1.0, ...
                'The canonical speed is no longer on the fold edge; re-derive 4.1.3.');
        end

        function test_which_target_classes_are_renderable_at_this_prf(tc)
        % Should faster classes be marked unrenderable rather than silently
        % folding? Reported as measured fact, per class, so the answer is a
        % decision someone makes with numbers rather than a default.
            C = physics.Constants();
            classes = {
              'drone (quad, cruise)',   15
              'drone (racing)',         40
              'drone (fast fixed-wing)',60
              'airliner (approach)',   140
              'fighter (subsonic)',    250
              'missile (cruise)',      300
            };
            fprintf('\n=== 4.1.3 which classes can this radar measure unambiguously? ===\n');
            fprintf('%-26s %10s %12s %-16s\n', 'class', 'typ |v|', 'folds to', 'renderable?');
            nOk = 0;
            for i = 1:size(classes,1)
                v = classes{i,2};
                folded = mod(v + C.v_unambiguous, 2*C.v_unambiguous) - C.v_unambiguous;
                ok = v <= C.v_unambiguous;
                nOk = nOk + ok;
                if ok; verdict = 'YES'; else; verdict = 'NO -- folds'; end
                fprintf('%-26s %10.0f %12.1f %-16s\n', classes{i,1}, v, folded, verdict);
            end
            fprintf(['\n[4.1.3] %d of %d classes are unambiguously measurable. The scope of\n' ...
                     '  this radar is DRONE-CLASS SPEEDS ONLY. Fighter and missile phantoms\n' ...
                     '  are not renderable here in any meaningful sense -- their Doppler\n' ...
                     '  folds to a value unrelated to their range walk, which the judge''s\n' ...
                     '  OWN range-rate consistency screen would then flag as inconsistent.\n' ...
                     '  engine.entity.EntityState now WARNS rather than silently rendering\n' ...
                     '  them (it does not refuse: a real fast target is a legitimate thing\n' ...
                     '  to simulate, as long as nobody reads its measured velocity as the\n' ...
                     '  rendered one).\n'], nOk, size(classes,1));

            % MEASURED 2, not the 3 a quick reading suggests: v_ua is 59.958
            % m/s, so a 60 m/s "fast fixed-wing drone" is 0.04 m/s PAST the
            % edge and folds. That 0.04 m/s is not a rounding curiosity -- see
            % test_the_canonical_closing_target_folds_to_OPENING below.
            tc.verifyEqual(nOk, 2, ...
                'The renderable-class count moved -- re-derive the 4.1.3 class table.');
        end

        function test_the_canonical_closing_target_folds_to_OPENING(tc)
        % THE CONSEQUENCE OF THAT 0.04 m/s, MEASURED END TO END.
        %
        % v = -60 m/s (closing) gives f_d = +4002.8 Hz. Nyquist is +-4000 Hz,
        % so it aliases to -3997.2 Hz, which the judge reads back as
        % v = +59.9 m/s -- OPENING. The magnitude survives; THE SIGN DOES NOT.
        %
        % That matters far more than a 0.07% error, because +track/
        % discriminator.m's screen 2 asks whether the sign of the range walk
        % agrees with the sign of the measured Doppler. A genuine closing
        % target whose Doppler folds therefore presents as range-closing and
        % Doppler-opening: the exact RGPO/VGPO-inconsistent signature the
        % screen exists to catch. The radar would flag real aircraft.
        %
        % Measured here rather than argued, because the arithmetic being right
        % does not prove the pipeline does it.
            C = physics.Constants();
            v = -60;
            fd = -2*v / C.lambda;                       % +4002.8 Hz
            aliased = mod(fd + C.PRF/2, C.PRF) - C.PRF/2;
            vMeas = -C.lambda * aliased / 2;

            fprintf('\n[4.1.3] ARITHMETIC: v = %+.0f m/s -> f_d = %+.1f Hz\n', v, fd);
            fprintf('[4.1.3]   Nyquist band +-%.0f Hz -> aliases to %+.1f Hz\n', C.PRF/2, aliased);
            fprintf('[4.1.3]   judge would read v = %+.2f m/s  <-- SIGN FLIPPED\n', vMeas);
            tc.verifyLessThan(v * vMeas, 0, ...
                'The canonical closing rate no longer sign-flips; re-derive 4.1.3.');

            % --- and now MEASURE it through the real renderer and judge ---
            %
            % REWIRED 12 Aug 2026 from engine.entity.render (archived 7 Aug)
            % to generator.render via tests/renderPhantomScene.m. R0 = 3000 m
            % at -60 m/s ends at 2580 m, clear of the 1798.75 m blind range,
            % so no geometry change was needed here.
            %
            % CheckVelocityAmbiguity IS TURNED OFF HERE, AND THAT IS THE
            % POINT OF THE FLAG. As of 12 Aug 2026 project_action has a
            % fourth veto that REFUSES |v| >= v_ua = 59.958 m/s -- added
            % because this very test showed what happens without it (the
            % generator planning a phantom whose folded Doppler condemns it
            % on screen 2, i.e. defeating itself with its own action space).
            %
            % But this test's SUBJECT is that fold, so it has to be able to
            % build one. The opt-out is deliberately a separate flag from
            % ApplyVetoes: "check my ranges, but let me construct a
            % Doppler-folded target on purpose" is exactly this case, and it
            % must not be reachable by accident from a caller who merely
            % wanted looser range checks.
            F = 8; nP = 32;
            R0 = 3000;
            rng(31337, 'twister');
            f = renderPhantomScene(R0, v, 'NumFrames', F, 'NumPulses', nP, ...
                'CheckVelocityAmbiguity', false, 'Tag', 'envelope_fold');
            fb = engine.runJudge(f);

            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, ...
                'Nothing confirmed -- the measurement would be vacuous.');
            rSeq = fb.track_range_m{1}(:);
            dSeq = fb.track_range_rate_mps{1}(:);
            fprintf('[4.1.3] MEASURED: range walk %+.1f m/frame, mean Doppler %+.2f m/s\n', ...
                mean(diff(rSeq)), mean(dSeq));
            fprintf('[4.1.3] judge label on a GENUINE closing target: ''%s''\n', ...
                fb.eccm_label);

            tc.verifyLessThan(mean(diff(rSeq)), 0, 'The target must measure as closing in RANGE.');
            tc.verifyGreaterThan(mean(dSeq), 0, ...
                ['The measured Doppler must come back POSITIVE (opening) for a ' ...
                 'closing target -- that is the fold, and it is the finding.']);
            tc.verifyEqual(string(fb.eccm_label), "decoy", ...
                ['A GENUINE closing target at the canonical speed is expected to be ' ...
                 'labelled decoy at this PRF, because its folded Doppler contradicts ' ...
                 'its range walk. If this passes as real, re-derive 4.1.3.']);
        end

        function test_generator_refuses_past_v_ua_and_is_quiet_inside_it(tc)
            % RE-ENABLED 12 Aug 2026, after the counterpart was BUILT.
            %
            % This was Class C for one session: it asserted that a commanded
            % rate past v_ua = 59.958 m/s is caught, the archived
            % engine.entity.EntityState warned
            % (engine:entity:EntityState:dopplerFolds), and the rebuilt
            % generator had nothing to point at -- project_action's three
            % vetoes were EVERY ONE a constraint on RANGE. Writing the
            % feature inside its own test would have been the wrong fix, so
            % it was recorded as a capability gap instead.
            %
            % physics_projection.project_action now carries a FOURTH veto.
            % Two deliberate differences from the behaviour this test
            % originally checked, both strengthening it:
            %   REFUSES rather than warns -- past v_ua the Doppler does not
            %       lose precision, it flips SIGN, and the sibling test above
            %       measures the consequence (a GENUINE -60 m/s target
            %       labelled `decoy`). An action that self-flags is not a
            %       usable action.
            %   the BOUND ITSELF is refused -- exactly v_ua sits on the
            %       Nyquist edge, where the measured sign is decided by
            %       floating-point noise rather than physics.
            C = physics.Constants();
            pp = py.importlib.import_module('generator.physics_projection');
            vUa = double(pp.unambiguous_velocity_mps(C.PRF));
            tc.verifyEqual(vUa, C.v_unambiguous, 'RelTol', 1e-12, ...
                'MATLAB and Python disagree about v_ua.');

            % velocity_ambiguity_veto returns a (ok, margin) tuple. cell() is
            % the way to unpack it -- MATLAB cannot index a call result
            % directly (f(a)(b) is a PARSE error, not a runtime one).
            a = cell(pp.velocity_ambiguity_veto(-0.9*vUa, C.PRF));
            b = cell(pp.velocity_ambiguity_veto(-150.0, C.PRF));
            e = cell(pp.velocity_ambiguity_veto(-vUa, C.PRF));
            inside = logical(a{1});  beyond = logical(b{1});  atEdge = logical(e{1});

            fprintf('[4.1.3] v_ua = %.4f m/s | -0.9*v_ua ok=%d | -150 ok=%d | at edge ok=%d\n', ...
                vUa, inside, beyond, atEdge);
            tc.verifyTrue(logical(inside), ...
                'A rate comfortably inside v_ua was refused -- the veto over-fires.');
            tc.verifyFalse(logical(beyond), ...
                'A rate past v_ua was allowed; its Doppler would fold and flip sign.');
            tc.verifyFalse(logical(atEdge), ...
                'v exactly at v_ua was allowed -- the sign there is noise, not physics.');
        end

        function test_archived_entity_state_warning_is_superseded(tc)
            % Kept as a marker, not a check: the archived warning path is
            % gone and its replacement is asserted above. Retire this method
            % if engine.entity is ever genuinely restored.
            tc.assumeTrue(archivedDepsPresent({'engine.entity.render'}), ...
                ['engine.entity.EntityState''s dopplerFolds WARNING is ' ...
                 'superseded by project_action''s velocity veto -- see ' ...
                 'test_generator_refuses_past_v_ua_and_is_quiet_inside_it.']);
            C = physics.Constants();
            tc.verifyWarningFree(@() engine.entity.EntityState( ...
                'range_m', 1800, 'range_rate_mps', -0.9*C.v_unambiguous));
            tc.verifyWarning(@() engine.entity.EntityState( ...
                'range_m', 1800, 'range_rate_mps', -150), ...
                'engine:entity:EntityState:dopplerFolds');
        end
    end
end

function s = tf(b)
    if b; s = 'YES'; else; s = 'no'; end
end
