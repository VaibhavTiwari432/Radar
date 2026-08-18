classdef test_nis_consistency < matlab.unittest.TestCase
%TEST_NIS_CONSISTENCY  Tier 1.1 -- the judge's multi-dwell NIS gate.
%
%   Covers the three things that make the screen worth having: a genuine CV
%   track sits inside the gate, a kinematically impossible one does not, and
%   the quantity is actually plumbed through +engine/runJudge.m as its OWN
%   reported column rather than being folded into the ECCM label.

    methods (Test)

        function test_cv_track_stays_in_gate(tc)
            C = physics.Constants();
            % A genuine closing target, quantised to real range bins -- the
            % measurement the judge would actually receive, not a clean line.
            t = (0:7)';
            rTrue = 1800 - 50*t;
            r = round(rTrue / C.range_per_sample) * C.range_per_sample;
            out = track.nisConsistency(r, t, C);
            fprintf('\n[1.1] genuine CV : meanNIS %.3f | in-gate %.0f%% | pass %d (gate %.2f)\n', ...
                out.meanNIS, 100*out.inGateFrac, out.pass, out.gate);
            tc.verifyTrue(out.pass, 'a quantised constant-velocity track must stay in gate');
            tc.verifyEqual(out.nScored, 7);
        end

        function test_range_jump_is_caught(tc)
            C = physics.Constants();
            t = (0:7)';
            r = 1800 - 50*t;
            r(5) = r(5) + 3000;          % teleport: no CV object can do this
            out = track.nisConsistency(r, t, C);
            fprintf('[1.1] range jump  : meanNIS %.1f | in-gate %.0f%% | pass %d\n', ...
                out.meanNIS, 100*out.inGateFrac, out.pass);
            tc.verifyFalse(out.pass, 'a 3 km teleport must fail the gate');
            tc.verifyGreaterThan(out.meanNIS, out.gate);
        end

        function test_birth_dwell_is_not_scored_as_zero(tc)
            % A missing innovation is not a perfect one. If the birth dwell
            % were scored as nis = 0 it would drag every mean down and make a
            % short track look better than a long one for free.
            C = physics.Constants();
            t = (0:7)'; r = 1800 - 50*t;
            out = track.nisConsistency(r, t, C);
            tc.verifyTrue(isnan(out.nis(1)), 'birth dwell must be NaN, not 0');
            tc.verifyEqual(out.nScored, numel(r) - 1);
        end

        function test_gate_is_tunable_not_baked_in(tc)
            C = physics.Constants();
            t = (0:7)'; r = 1800 - 50*t;
            r(4) = r(4) + 120;                    % a moderate, not absurd, jolt
            loose = track.nisConsistency(r, t, C, 'GateChi2', 7.81);
            tight = track.nisConsistency(r, t, C, 'GateChi2', 3.84);
            fprintf('[1.1] tunable gate: meanNIS %.3f | pass@7.81 %d | pass@3.84 %d\n', ...
                loose.meanNIS, loose.pass, tight.pass);
            tc.verifyEqual(loose.meanNIS, tight.meanNIS, 'AbsTol', 1e-12, ...
                'the NIS series must not depend on the gate');
            tc.verifyGreaterThanOrEqual(loose.inGateFrac, tight.inGateFrac, ...
                'a looser gate cannot admit fewer dwells than a tighter one');
        end

        function test_runJudge_reports_nis_as_its_own_column(tc)
            % The plumbing check: the column exists, is per-track, and does
            % NOT change the ECCM label. Rendered through the real generator
            % so this is a real signal, not a hand-built series.
            %
            % REWIRED 12 Aug 2026 from engine.entity.render (archived 7 Aug)
            % to generator.render via tests/renderPhantomScene.m. R0 moved
            % 1800 -> 2400 m: at -50 m/s over 8 frames the old start ends at
            % 1450 m, 349 m inside the 1798.75 m blind range, which the
            % rebuilt path's eclipse veto refuses (the archived renderer
            % never evaluated it). Nothing here depends on R0 -- the subject
            % is that track_nis_* is REPORTED as its own column and does not
            % feed the label.
            rng(11, 'twister');
            [f, ~] = renderPhantomScene(2400, -50, ...
                'NumFrames', 8, 'NumPulses', 32, 'Tag', 'nis_column');

            fb = engine.runJudge(f);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, 'need a track to test');
            tc.verifyTrue(isfield(fb, 'track_nis_mean'));
            tc.verifyTrue(isfield(fb, 'track_nis_pass'));
            tc.verifyEqual(numel(fb.track_nis_mean), fb.confirmed_tracks);
            tc.verifyEqual(fb.nis_gate_chi2, 7.81);
            fprintf(['[1.1] runJudge    : confirmed %d | label %s | ' ...
                     'nisMean %.3f | nisPass %d | gate %.2f\n'], ...
                fb.confirmed_tracks, fb.eccm_label, fb.track_nis_mean(1), ...
                fb.track_nis_pass(1), fb.nis_gate_chi2);

            % The separation guarantee: moving the gate must NOT move the
            % ECCM label. If this ever fails, the column has been folded in.
            fbTight = engine.runJudge(f, 'NisGateChi2', 0.001);
            tc.verifyEqual(fbTight.eccm_label, fb.eccm_label, ...
                'the NIS gate must not influence the ECCM label (Tier 1.1c)');
            tc.verifyFalse(fbTight.track_nis_pass(1), ...
                'an absurdly tight gate must still be able to fail');
        end
    end
end
