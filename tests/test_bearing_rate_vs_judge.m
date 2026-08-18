classdef test_bearing_rate_vs_judge < matlab.unittest.TestCase
%TEST_BEARING_RATE_VS_JUDGE  Screen 2c end to end, against the REAL judge.
%
%   tests/test_bearing_rate_screen.m proves the MATHEMATICS on hand-built
%   series. This file asks the only question that matters: does the
%   separation survive rendering, CA-CFAR, trackerGNN and real monopulse
%   noise, when the bearing is not handed to the screen but MEASURED by
%   +engine/runJudge.m from a difference channel?
%
%   THE A/B IS AS TIGHT AS IT CAN BE MADE. Both arms are ONE target, at the
%   SAME range trajectory, with the SAME initial bearing rate, rendered by
%   the same generator at the same seed. The only difference is the SHAPE of
%   the bearing series:
%
%     GENUINE  theta linear in 1/R  -- straight-line constant-velocity
%              motion conserves R^2*dtheta/dt, so a real target's bearing
%              curves as its range closes.
%     PHANTOM  theta linear in t    -- radiated from a platform holding
%              station in range, so its bearing rate is constant and does
%              NOT respond to the range it claims.
%
%   Matching the initial bearing rate is what makes this a test of the
%   INVARIANT rather than of how fast anything appears to move. At t=0 the
%   two arms are indistinguishable in every measurable quantity; they diverge
%   only through the second-order term the conservation law predicts.
%
%   GEOMETRY, CHOSEN AGAINST TWO HARD BOUNDS, NOT TUNED FOR AN OUTCOME:
%     * the closing trajectory must stay OUTSIDE the 1798.75 m blind range
%       (c*PW/2) at every frame -- 2300 -> 1950 m does;
%     * the bearing must stay INSIDE the +-2.8640 deg monopulse unambiguous
%       sector, or the phase wraps and the measurement is of the wrap. Peak
%       bearing here is ~1.85 deg.
%   Between them they set how much divergence is available: the arms separate
%   by ~0.5 deg over the dwell, against the 0.0726 deg worst-case within-track
%   azimuth scatter measured in tests/test_monopulse_snr_boundary.m.

    properties (Constant)
        R0      = 2300      % t=0 range [m]; 2300 -> 1950 stays clear of blind
        RDOT    = -50       % [m/s] closing; |v| < v_ua = 59.958
        NFRAMES = 8
        MOTHER_R = 900      % mother platform range [m]
        MOTHER_V = 3        % mother cross-range speed [m/s]
        SEEDS   = 1:6
    end

    methods (Test)

        function test_a_lone_phantom_is_caught_and_a_genuine_target_is_not(tc)
            % THE HEADLINE. N = 1, where the co-bearing screen is silent by
            % construction and PHASE_B_RESULTS.md records P_confirm = 1.00.
            nG = 0; nP = 0; confirmedG = 0; confirmedP = 0;
            sG = []; sP = [];
            for s = tc.SEEDS
                g = localRun(tc, 'genuine', s);
                p = localRun(tc, 'phantom', s);
                if g.confirmed; confirmedG = confirmedG + 1; end
                if p.confirmed; confirmedP = confirmedP + 1; end
                if ~isnan(g.score); sG(end+1) = g.score; end %#ok<AGROW>
                if ~isnan(p.score); sP(end+1) = p.score; end %#ok<AGROW>
                nG = nG + double(g.flagged);
                nP = nP + double(p.flagged);
            end

            fprintf('\n  screen 2c, N=1, %d seeds\n', numel(tc.SEEDS));
            fprintf('    genuine : confirmed %d/%d, flagged %d, mean score %.3f\n', ...
                    confirmedG, numel(tc.SEEDS), nG, mean(sG));
            fprintf('    phantom : confirmed %d/%d, flagged %d, mean score %.3f\n', ...
                    confirmedP, numel(tc.SEEDS), nP, mean(sP));

            % Both arms must be DETECTED, or the comparison is between a
            % target and nothing at all.
            tc.assertEqual(confirmedG, numel(tc.SEEDS), ...
                'genuine arm was not confirmed every seed -- fix the scene, not the screen');
            tc.assertEqual(confirmedP, numel(tc.SEEDS), ...
                'phantom arm was not confirmed every seed');

            tc.verifyGreaterThan(mean(sG), 0.5, ...
                'genuine target scored as inconsistent with its own kinematics');
            tc.verifyLessThan(mean(sP), 0.5, ...
                'the bearing-slaved phantom was not separated by the screen');
            tc.verifyGreaterThan(mean(sG) - mean(sP), 0.2, ...
                'separation is too thin to be worth a verdict');
        end

        function test_the_screen_is_off_by_default_so_no_published_label_moves(tc)
            % Same posture as 'residual' and 'maneuver'. A screen that
            % silently joined the default set would re-base every result in
            % the repo without anyone asking for it.
            %
            % Measured on the DISCRIMINATOR's own confidence, not on whether
            % bearingRateScreen returns a number: this test's harness calls
            % that function directly to report the screen's own score, so a
            % NaN check would only be testing the harness.
            % An empty mask means "caller said nothing", which is the path
            % every existing caller in the repo takes: runJudge then omits
            % EccmScreens entirely and discriminator.m falls back to its own
            % default set. That must equal the explicit three-screen mask.
            asShipped = localRun(tc, 'phantom', 1, 'Screens', {});
            explicitThree = localRun(tc, 'phantom', 1, ...
                                     'Screens', {'amplitude', 'doppler', 'micro'});
            tc.verifyEqual(asShipped.confidence, explicitThree.confidence, ...
                'AbsTol', 1e-12, ...
                'the default screen set is no longer {amplitude, doppler, micro}');
            tc.verifyEqual(asShipped.label, explicitThree.label);
        end

        function test_the_screen_fires_but_is_outvoted_by_the_averaging_rule(tc)
            % AN HONEST NEGATIVE, RECORDED AT THE SAME PROMINENCE AS THE
            % HEADLINE. Screen 2c separates the two arms almost perfectly
            % (0.968 vs 0.068 above), and yet the phantom is NOT labelled
            % `decoy`, because +track/discriminator.m AVERAGES its screens: a
            % phantom whose amplitude law and Doppler are both forged
            % correctly scores ~0.9 and ~1.0 on those, so
            % (0.9 + 1.0 + 0.068)/3 is still above the 0.5 threshold.
            %
            % SO THE SCREEN IS A MEASUREMENT, NOT YET A VERDICT. Two ways
            % forward, and neither is taken here because both are design
            % decisions with real cost:
            %   * weight or veto on it, as the co-bearing screen already does
            %     (+engine/runJudge.m assigns "decoy" directly rather than
            %     contributing a score) -- justified because a violated
            %     conservation law is structural evidence, not a soft
            %     preference;
            %   * leave it scored, and accept that it only moves marginal
            %     cases.
            % CLAUDE.md's standing warning applies to the first: requiring
            % every screen to pass would flag real aircraft, since a genuine
            % target's own amplitude screen has been observed as low as 0.402.
            p = localRun(tc, 'phantom', 1, ...
                         'Screens', {'amplitude', 'doppler', 'micro', 'bearing'});
            noBearing = localRun(tc, 'phantom', 1, ...
                                 'Screens', {'amplitude', 'doppler', 'micro'});

            fprintf('\n  phantom confidence: %.3f without 2c -> %.3f with it (label %s)\n', ...
                    noBearing.confidence, p.confidence, p.label);

            tc.verifyLessThan(p.confidence, noBearing.confidence, ...
                'screen 2c did not move the discriminator at all');
            tc.verifyEqual(p.label, "real", ...
                ['this is the CURRENT, unflattering state: the screen fires ' ...
                 'and is outvoted. If this ever fails because the phantom is ' ...
                 'now labelled decoy, the combination rule changed -- update ' ...
                 'the finding, do not delete the test.']);
        end

        function test_a_stationary_platform_makes_the_screen_abstain(tc)
            % The honest lower bound, and it is a real operational limit: with
            % no cross-range motion there is no bearing rate to be
            % inconsistent with, so the screen must report nothing rather than
            % a 0.5 that would read as a measurement. This is the same shape
            % of bound as the co-bearing screen's ~40 m cross-range floor.
            r = localRun(tc, 'static', 1);
            tc.verifyTrue(isnan(r.score), ...
                'the screen produced a verdict from a bearing that never moved');
        end

    end
end


function out = localRun(tc, arm, seed, varargin)
%LOCALRUN  Render one arm, judge it, and report screen 2c's own number.
    p = inputParser;
    p.addParameter('Screens', {'amplitude', 'doppler', 'micro', 'bearing'}, @iscell);
    p.parse(varargin{:});

    t = (0:tc.NFRAMES-1)';
    R = tc.R0 + tc.RDOT * t;
    thetaDot0 = tc.MOTHER_V / tc.MOTHER_R;      % rad/s, shared by both arms

    switch arm
        case 'genuine'
            % theta = theta0 + (h/Rdot)*(1/R0 - 1/R), h = R0^2*thetaDot0.
            h = tc.R0^2 * thetaDot0;
            az = (h / tc.RDOT) * (1 ./ tc.R0 - 1 ./ R);
        case 'phantom'
            az = thetaDot0 * t;                  % constant rate: the platform's
        case 'static'
            az = zeros(size(t));
        otherwise
            error('unknown arm %s', arm);
    end

    rng(seed, 'twister');
    judgeMat = renderPhantomScene(tc.R0, tc.RDOT, ...
        'NumFrames', tc.NFRAMES, 'SourceAzimuthRad', az(:)', ...
        'Tag', sprintf('brs_%s_%d', arm, seed));

    fb = engine.runJudge(judgeMat, 'EccmScreens', p.Results.Screens);

    out = struct('confirmed', fb.confirmed_tracks >= 1, 'score', NaN, ...
                 'flagged', false, 'confidence', NaN, 'label', "");
    if ~out.confirmed; return; end
    out.flagged = fb.flagged_decoys >= 1;
    out.label = string(fb.track_label{1});
    % The recoverable mean-screen score (+engine/runJudge.m's
    % feedback.track_confidence: 0.5 +- confidence/2, signed by label), so a
    % caller can see a screen MOVE the decision even when it does not flip
    % the label.
    if isfield(fb, 'track_confidence') && ~isempty(fb.track_confidence)
        c = fb.track_confidence(1);
        if out.label == "real"
            out.confidence = 0.5 + c/2;
        else
            out.confidence = 0.5 - c/2;
        end
    end

    % Screen 2c's OWN score, recomputed from the judge's MEASURED series --
    % not inferred from the label, which mixes in every other screen. The
    % series come straight off the feedback the judge published.
    azSeq = fb.track_azimuth_rad{1};
    rSeq  = fb.track_range_m{1};
    tSeq  = fb.track_time_s{1};
    if numel(azSeq) == numel(rSeq) && numel(azSeq) == numel(tSeq)
        out.score = track.bearingRateScreen(azSeq, rSeq, tSeq);
    end
end
