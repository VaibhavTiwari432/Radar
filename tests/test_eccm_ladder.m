classdef test_eccm_ladder < matlab.unittest.TestCase
%TEST_ECCM_LADDER  Guards the two scene defects that were found in
%   +experiments/eccmLadder.m AFTER it had already produced a 20-seed table.
%   Both were mine, both looked like radar findings, and neither would have
%   been caught by the experiment's own output -- so they get assertions.
%
%   DEFECT 1: the genuine arm was handed a FIXED chirp on every frame, so
%   against an agile radar it was mismatched on half of them and penalised
%   exactly like a stale repeater. Its apparent collapse at the agility rung
%   (3/20) was that bug; corrected it is 8/20, flat with the rung below.
%   A genuine target reflects whatever the radar transmitted on THAT frame.
%
%   DEFECT 2: building the monopulse delta channel consumed draws from the
%   SHARED RandStream, re-rolling the sum channel's noise, so a rung that
%   added the angle channel differed from the one below it for reasons that
%   had nothing to do with angle. (That rung is gone -- co-bearing needs >= 2
%   tracks and the ladder is single-target -- but the shared-stream hazard
%   remains if it is ever re-added.)

    methods (TestClassSetup)
        function assumeArchivedDependencyPresent(tc)
            % 7 Aug 2026 archive: every scene in this file is built by
            % engine.entity.render, which no longer exists. Report Incomplete --
            % this project's own honest "not built yet" outcome, the same
            % one DataIntegration_Test uses for an absent dataset -- rather
            % than erroring. 63 errored methods made a real regression
            % invisible; a skip keeps the suite usable as an instrument.
            % NOT a fix: rewire to generator.render to genuinely re-enable.
            tc.assumeTrue(archivedDepsPresent({'engine.entity.render'}), ...
                'engine.entity.render was archived 7 Aug 2026 (GOVERNANCE.md). This test is PENDING REWIRE to generator.render, not passing -- see trash/BROKEN_DOWNSTREAM.md.');
        end
    end

    methods (Test)

        function test_agility_does_not_penalise_a_genuine_target(tc)
            % THE REGRESSION GUARD. Waveform agility must cost a STALE
            % repeater and must NOT cost a target reflecting the radar's own
            % pulse. If the genuine arm drops when agility is switched on,
            % the scene is mis-specified -- that is the bug, not a result.
            out = experiments.eccmLadder(6);

            gen = out(strcmp({out.arm}, 'genuine'));
            r2 = gen(contains({gen.rung}, 'amplitude')).deceived;
            r3 = gen(contains({gen.rung}, 'agility')).deceived;
            fprintf('\n[2.0] genuine accepted: R2 %d/6 -> R3(+agility) %d/6\n', r2, r3);
            tc.verifyGreaterThanOrEqual(r3, r2 - 1, ...
                ['agility cost the GENUINE target acceptance -- it reflects the ' ...
                 'radar''s own per-frame pulse and cannot be mismatched']);

            % And the phantom must still be caught by the rung that works.
            naive = out(strcmp({out.arm}, 'naive-drfm'));
            tc.verifyEqual(sum([naive.deceived]), 0, ...
                'the naive DRFM deceived the judge at some rung -- ladder is broken');
        end

        function test_range_rate_screen_separates_the_arms(tc)
            % Tier 1.2's acceptance, as a standing assertion rather than a
            % one-off run: the magnitude check must fail the naive repeater
            % everywhere and pass both physically-consistent arms everywhere.
            out = experiments.eccmLadder(6);
            for a = {'vee-phantom', 'genuine'}
                sel = out(strcmp({out.arm}, a{1}));
                fprintf('[1.2] %-12s rate pass %d/%d cells fully passing | mismatch %.2f m/s\n', ...
                    a{1}, nnz([sel.ratePass] == [sel.confirmed]), numel(sel), ...
                    mean([sel.rateMismatch], 'omitnan'));
                tc.verifyEqual([sel.ratePass], [sel.confirmed], ...
                    sprintf('%s failed the range-rate check -- it is kinematically consistent', a{1}));
            end
            naive = out(strcmp({out.arm}, 'naive-drfm'));
            fprintf('[1.2] naive-drfm   rate pass %d total | mismatch %.2f m/s\n', ...
                sum([naive.ratePass]), mean([naive.rateMismatch], 'omitnan'));
            tc.verifyEqual(sum([naive.ratePass]), 0, ...
                'the naive DRFM passed the range-rate check -- the screen is inert');
        end

        function test_nis_is_reported_inert_not_quietly_dropped(tc)
            % Tier 1.1's honest negative, asserted so it cannot rot into a
            % silent claim either way: NIS does NOT separate these arms. If
            % this ever starts failing, the screen has gained real capability
            % and the report's "inert" language must be revisited.
            out = experiments.eccmLadder(6);
            vee = mean([out(strcmp({out.arm}, 'vee-phantom')).nisMean], 'omitnan');
            nai = mean([out(strcmp({out.arm}, 'naive-drfm')).nisMean], 'omitnan');
            fprintf('[1.1] NIS mean: vee %.3f | naive %.3f | separation %.3f\n', ...
                vee, nai, abs(vee - nai));
            tc.verifyLessThan(abs(vee - nai), 0.05, ...
                ['NIS now separates the VEE phantom from the naive DRFM -- that is ' ...
                 'a NEW capability, not a regression, but the report says inert']);
        end

        function test_residual_screen_is_inert_at_this_track_length(tc)
            % The residual-variance screen changes NOTHING on this scene, and
            % the reason is arithmetic rather than a wiring fault: its veto
            % floor carries a small-sample correction, 0.233*(1-3/sqrt(2(N-1))),
            % which at N=8 hits is 0.046 dB -- while the LEAST-scattered arm
            % here (the constant-gain naive DRFM, which does not fluctuate at
            % all) still measures ~0.97 dB of scatter from receiver noise on
            % the amplitude estimate alone. Nothing can fall below the floor,
            % so nothing is vetoed. Asserted so the inertness is a standing
            % measurement, not a one-off observation: if the residual rungs
            % ever diverge from the rungs they extend, the screen has gained
            % real capability and the report's language must be revisited.
            out = experiments.eccmLadder(6);
            pairs = {'R2 +amplitude', 'R2+residual'; 'R3 +agility', 'R3+residual'};
            for p = 1:size(pairs, 1)
                base = out(strcmp({out.rung}, pairs{p,1}));
                resid = out(strcmp({out.rung}, pairs{p,2}));
                fprintf('[resid] %-14s deceived %s -> %-12s %s\n', pairs{p,1}, ...
                    mat2str([base.deceived]), pairs{p,2}, mat2str([resid.deceived]));
                tc.verifyEqual([resid.deceived], [base.deceived], ...
                    sprintf(['%s differs from %s -- the residual screen has become ' ...
                             'active on this scene'], pairs{p,2}, pairs{p,1}));
            end

            % And the mechanism, not just the outcome: every arm's scatter
            % must sit above the floor the veto tests against.
            floorDb = 0.233 * max(0, 1 - 3/sqrt(2*(8-1)));
            sigmas = [out.residSigmaDb];
            fprintf('[resid] min arm scatter %.3f dB vs veto floor %.3f dB\n', ...
                min(sigmas), floorDb);
            tc.verifyGreaterThan(min(sigmas), floorDb, ...
                'an arm fell below the residual veto floor -- the screen can now fire');
        end
    end
end
