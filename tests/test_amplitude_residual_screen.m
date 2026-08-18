classdef test_amplitude_residual_screen < matlab.unittest.TestCase
%TEST_AMPLITUDE_RESIDUAL_SCREEN  Phase 3.2b prototype, measured on three arms.
%
%   The existing amplitude screen (+track/discriminator.m, screen 1) fits the
%   log(A)-vs-log(R) SLOPE. Measured on this project's own TEST 3 scene that
%   fit has std 2.67 against a decision half-width of 1.0, so genuine and
%   phantom tracks score identically (72% vs 71% <= 0.5) -- a coin flip
%   applied to both arms alike.
%
%   track.amplitudeResidualScreen fixes the slope at the physical -2 and
%   scores the SCATTER about it instead. This file measures whether that
%   actually separates the arms, on synthetic tracks whose amplitude law is
%   known exactly, so the screen is tested against physics rather than
%   against the pipeline's own quirks.
%
%   THREE ARMS, all at this project's real 8-frame dwell and its real
%   1.15x range excursion -- i.e. exactly where the slope fit fails:
%     genuine    1/R^2 with MEASURED scintillation (calibrateQ's 0.233 dB)
%     perfect    1/R^2 with NO scintillation -- a servo-driven repeater
%     constERP   constant received amplitude -- a naive DRFM

    properties (Constant)
        N_FRAMES = 8
        R0       = 3000
        V        = -40      % inside v_ua = 59.96 m/s
        SCINT_DB = 0.233    % engine.entity.calibrateQ's MEASURED floor
        N_SEEDS  = 200      % synthetic: cheap, so measure the distribution properly
    end

    methods (Test)

        function test_rcs_independence_is_exact(tc)
        % The load-bearing property: the score must not move when the target's
        % RCS changes, because a radar cannot know RCS. With the slope fixed,
        % sqrt(sigma) lives entirely in the fitted intercept.
            R = tc.R0 + tc.V*(0:tc.N_FRAMES-1);
            base = (tc.R0 ./ R).^2;
            rng(7); jitter = 10.^((tc.SCINT_DB*randn(1,tc.N_FRAMES))/20);
            A = base .* jitter;

            [s1, d1] = track.amplitudeResidualScreen(R, A);
            [s2, d2] = track.amplitudeResidualScreen(R, A * 1000);   % +60 dB RCS
            [s3, d3] = track.amplitudeResidualScreen(R, A * 1e-4);   % -80 dB RCS

            fprintf('\n[3.2b] RCS independence: sigma_db %.4f / %.4f / %.4f over a 140 dB span\n', ...
                d1.residual_sigma_db, d2.residual_sigma_db, d3.residual_sigma_db);
            tc.verifyEqual(d2.residual_sigma_db, d1.residual_sigma_db, 'RelTol', 1e-12);
            tc.verifyEqual(d3.residual_sigma_db, d1.residual_sigma_db, 'RelTol', 1e-12);
            tc.verifyEqual(s2, s1); tc.verifyEqual(s3, s1);
        end

        function test_three_arms_at_the_dwell_where_the_slope_fit_fails(tc)
            R = tc.R0 + tc.V*(0:tc.N_FRAMES-1);
            fprintf('\n=== 3.2b: residual-variance screen, %d frames, Rmax/Rmin %.3f ===\n', ...
                tc.N_FRAMES, max(R)/min(R));
            fprintf('(the slope fit has std 2.67 at this exact lever arm)\n\n');

            arms = ["genuine", "perfect", "constERP"];
            sig = struct(); flagRate = struct(); slopeStd = struct();
            for a = arms
                sg = zeros(1, tc.N_SEEDS); sc = zeros(1, tc.N_SEEDS);
                sl = zeros(1, tc.N_SEEDS);
                for s = 1:tc.N_SEEDS
                    rs = RandStream('twister', 'Seed', 2000 + s);
                    A = tc.buildArm(a, R, rs);
                    [sc(s), d] = track.amplitudeResidualScreen(R, A);
                    sg(s) = d.residual_sigma_db;
                    pf = polyfit(log(R(:)), log(A(:)), 1);   % the OLD screen, same data
                    sl(s) = pf(1);
                end
                sig.(a) = sg; flagRate.(a) = mean(sc <= 0.5); slopeStd.(a) = std(sl);
                fprintf(['%-9s residual sigma  mean %6.3f dB  p5 %6.3f  p95 %6.3f | ' ...
                         'NEW flag %5.1f%% | OLD slope std %6.2f\n'], ...
                    a, mean(sg), prctile(sg,5), prctile(sg,95), 100*flagRate.(a), slopeStd.(a));
            end

            oldScore = @(sl) max(0, 1 - abs(sl+2)/2);
            fprintf('\n%-9s %-14s %-14s\n', '', 'NEW flag rate', 'OLD flag rate');
            oldFlag = struct();
            for a = arms
                sl = zeros(1, tc.N_SEEDS);
                for s = 1:tc.N_SEEDS
                    rs = RandStream('twister', 'Seed', 2000 + s);
                    A = tc.buildArm(a, R, rs);
                    pf = polyfit(log(R(:)), log(A(:)), 1);
                    sl(s) = pf(1);
                end
                oldFlag.(a) = mean(oldScore(sl) <= 0.5);
                fprintf('%-9s %12.1f%% %12.1f%%\n', a, 100*flagRate.(a), 100*oldFlag.(a));
            end

            newSep = min(flagRate.perfect, flagRate.constERP) - flagRate.genuine;
            oldSep = min(oldFlag.perfect, oldFlag.constERP) - oldFlag.genuine;
            fprintf(['\nseparation (worst decoy arm minus genuine):  NEW %+.1f pts  |  ' ...
                     'OLD %+.1f pts\n'], 100*newSep, 100*oldSep);

            % ============ THE MEASURED RESULT: COMPLEMENTARY, NOT A REPLACEMENT ====
            % Each screen catches exactly what the other misses:
            %   servo-perfect repeater -> slope is EXACTLY -2, so the slope fit
            %       says "real" (0% caught). Residual sigma is 0.000 dB, so the
            %       residual screen catches it 100%.
            %   constant-ERP repeater  -> slope is 0, so the slope fit catches it
            %       100%. Its residual sigma is only 0.596 dB at this lever arm,
            %       under the 3.0 dB ceiling, so the residual screen misses it.
            %
            % The ceiling is NOT retuned down to 0.5 dB to close that gap. It
            % would work on these two arms and then break: constERP's residual
            % sigma SCALES WITH THE RANGE EXCURSION (a wrong law only shows up
            % over a long span) while a genuine target's scintillation floor
            % does not. A ceiling fitted at 8 frames would misfire at 32. That
            % is fitting a threshold to a desired flag rate, which this
            % function's own docstring forbids.
            %
            % So the deliverable is the COMBINATION, scored as the weaker of
            % the two -- a track must be consistent in BOTH senses.
            tc.verifyLessThanOrEqual(flagRate.genuine, 0.10, ...
                'The residual screen condemns genuine scintillating targets.');
            tc.verifyGreaterThanOrEqual(flagRate.perfect, 0.90, ...
                ['A servo-perfect repeater was not caught. This is the capability the ' ...
                 'slope fit does NOT have -- its slope is exactly -2.']);
            tc.verifyEqual(oldFlag.perfect, 0, ...
                'The slope fit now catches the servo-perfect arm; the complementarity claim needs re-deriving.');
            tc.verifyGreaterThanOrEqual(oldFlag.constERP, 0.90, ...
                'The slope fit no longer catches constant-ERP; re-derive the complementarity claim.');

            % ---- combined screen: min(residual, slope), measured on all arms ----
            fprintf('\n%-9s %-16s %-16s %-16s\n', '', 'residual only', 'slope only', 'COMBINED');
            combFlag = struct();
            for a = arms
                nFlag = 0;
                for s = 1:tc.N_SEEDS
                    rs = RandStream('twister', 'Seed', 2000 + s);
                    A = tc.buildArm(a, R, rs);
                    sRes = track.amplitudeResidualScreen(R, A);
                    pf = polyfit(log(R(:)), log(A(:)), 1);
                    sSlp = oldScore(pf(1));
                    nFlag = nFlag + (min(sRes, sSlp) <= 0.5);
                end
                combFlag.(a) = nFlag / tc.N_SEEDS;
                fprintf('%-9s %14.1f%% %14.1f%% %14.1f%%\n', a, ...
                    100*flagRate.(a), 100*oldFlag.(a), 100*combFlag.(a));
            end
            combSep = min(combFlag.perfect, combFlag.constERP) - combFlag.genuine;
            fprintf('\nseparation (worst decoy arm minus genuine): residual %+.1f | slope %+.1f | COMBINED %+.1f pts\n', ...
                100*newSep, 100*oldSep, 100*combSep);

            tc.verifyLessThanOrEqual(combFlag.genuine, 0.10, ...
                'The combined screen condemns genuine targets.');
            tc.verifyGreaterThanOrEqual(min(combFlag.perfect, combFlag.constERP), 0.90, ...
                'The combined screen fails to catch one of the two repeater types.');
            tc.verifyGreaterThan(combSep, max(newSep, oldSep), ...
                'Combining the two screens is no better than the better one alone.');
        end

        function test_dwell_stability_on_real_pipeline_tracks(tc)
            % ATTEMPTED REWIRE, 12 Aug 2026 -- AND REVERTED, because the
            % rewire silently changed the physics under test. Recorded here
            % rather than left as a passing-looking green tick.
            %
            % The rewire to generator.render works mechanically: the scene
            % builds, tracks confirm, three of this file's four tests pass.
            % The fourth FAILED -- spreadResid 0.133 vs spreadSlope 0.117 --
            % and the reason is not a threshold worth moving.
            %
            % THIS ARM'S GENUINE TRACKS REQUIRE SCINTILLATION, AND THE
            % REBUILT GENERATOR HAS NONE. engine.entity.render drew RCS
            % process noise (calibrateQ's MEASURED 0.233 dB floor);
            % generator.render's amplitude is a deterministic 1/R^2 from
            % physics_projection.amplitude_trajectory, with no fluctuation
            % term anywhere. So a "genuine" track rendered through the new
            % path is amplitude-PERFECT -- which is this file's OWN `perfect`
            % arm, the servo-driven repeater it flags 100% by design. The
            % residual screen scores SCATTER about the -2 law; with the only
            % scatter coming from receiver noise rather than target
            % scintillation, it is no longer measuring the quantity this
            % test was written to measure.
            %
            % Tuning the threshold to make it pass would fit a constant to a
            % desired flag rate, which track.amplitudeResidualScreen's own
            % docstring forbids and which this very test's failure message
            % warns against ("documented as such, not tuned").
            %
            % So this method is CLASS C, not Class A -- same debt as
            % test_swerling_scale, and paid the same way: build fluctuation
            % into the generator. The other three tests in this file are
            % synthetic, need no generator, and run.
            tc.assumeTrue(archivedDepsPresent({'engine.entity.render'}), ...
                ['This arm needs TARGET SCINTILLATION, which the rebuilt ' ...
                 'generator cannot render (engine.entity.render, archived ' ...
                 '7 Aug 2026, could). NOT rewirable -- see ' ...
                 'trash/BROKEN_DOWNSTREAM.md Class C.']);
        % ===== Phase 3.2b steps 4-5: the question actually worth answering =====
        %
        % The synthetic arms above show the two screens are complementary. This
        % one asks the DIFFERENT question: is residual variance more STABLE
        % ACROSS DWELL LENGTH than the slope fit? The slope fit's precision
        % accumulates with lever arm (measured: pass rate 10% -> 30% -> 70% at
        % 8/16/32 frames). Residual variance is local consistency, so it should
        % not care.
        %
        % Measured on REAL pipeline tracks -- full render, CFAR, tracker -- not
        % on synthetic amplitude series, because the whole reason the slope fit
        % degrades is CFAR range quantisation and amplitude measurement noise
        % that synthetic arms do not have.
        %
        % GEOMETRY: ranges 5000-9000 m, v = -30 m/s. Chosen so that even a
        % 32-frame dwell (930 m of travel) stays clear of the 1124 m CFAR blind
        % zone AND inside R_ua = 18737 m -- so DWELL is the only variable. The
        % TEST 3 scene could not do this: at its 1800 m near range a 32-frame
        % dwell walks into the blind zone and the track simply vanishes, which
        % is why the earlier lever-arm sweep returned "no tracks" at 64+.
        %
        % EXPECTATION, stated before the numbers (and it is not a discrimination
        % claim): the phantoms here are rendered with the CORRECT 1/R^2 law, so
        % they are amplitude-physical and NO amplitude screen can separate them
        % -- they are caught by angle, 12/12, in TEST 3. What is being measured
        % is PASS RATE ON GENUINE TRACKS vs dwell, i.e. how often each screen
        % wrongly condemns a real target as the dwell shortens.
            C = physics.Constants();
            dwells = [8 16 32];
            nObj = 5; nSeeds = 12;
            ranges0 = linspace(5000, 9000, nObj);
            v = -30;

            fprintf('\n=== 3.2b steps 4-5: dwell stability on REAL pipeline tracks ===\n');
            fprintf('ranges %.0f-%.0f m, v %d m/s, %d objects, %d seeds\n', ...
                ranges0(1), ranges0(end), v, nObj, nSeeds);
            fprintf('PASS rate = %% of GENUINE tracks scoring > 0.5 (higher is better)\n\n');
            fprintf('%8s %10s %14s %14s %12s\n', 'frames', 'Rmax/Rmin', ...
                'slope PASS', 'residual PASS', 'n tracks');

            passSlope = zeros(1, numel(dwells));
            passResid = zeros(1, numel(dwells));
            for di = 1:numel(dwells)
                F = dwells(di);
                sSlope = []; sResid = [];
                for seed = 1:nSeeds
                    tracks = tc.renderRealTracks(ranges0, v, F, seed, C);
                    for t = 1:numel(tracks)
                        R = tracks{t}.R; A = tracks{t}.A;
                        ok = R > 0 & A > 0;
                        if nnz(ok) < 3; continue; end
                        pf = polyfit(log(R(ok)), log(A(ok)), 1);
                        sSlope(end+1) = max(0, 1 - abs(pf(1)+2)/2); %#ok<AGROW>
                        sr = track.amplitudeResidualScreen(R(ok), A(ok));
                        if ~isnan(sr); sResid(end+1) = sr; end %#ok<AGROW>
                    end
                end
                passSlope(di) = mean(sSlope > 0.5);
                passResid(di) = mean(sResid > 0.5);
                fprintf('%8d %10.3f %13.0f%% %13.0f%% %12d\n', F, ...
                    ranges0(1)/(ranges0(1)+v*(F-1)), 100*passSlope(di), ...
                    100*passResid(di), numel(sSlope));
            end

            spreadSlope = max(passSlope) - min(passSlope);
            spreadResid = max(passResid) - min(passResid);
            fprintf(['\nVARIATION ACROSS DWELL (max - min pass rate):\n' ...
                     '  slope    %.0f points   <- accumulates with lever arm\n' ...
                     '  residual %.0f points   <- local consistency\n'], ...
                     100*spreadSlope, 100*spreadResid);

            if spreadResid < spreadSlope
                fprintf(['VERDICT: residual variance IS more dwell-stable. It is a tool for\n' ...
                         '  radars whose dwell or geometry cannot be extended -- which this\n' ...
                         '  one''s cannot, being bounded above by the 1124 m CFAR blind zone\n' ...
                         '  and below by v_ua = %.1f m/s.\n'], C.v_unambiguous);
            else
                fprintf(['VERDICT: residual variance is NOT more dwell-stable. It shares the\n' ...
                         '  slope fit''s constraint rather than sidestepping it.\n']);
            end

            % The step-4 verification target: residual must beat the slope
            % screen's own 8-frame genuine pass rate.
            fprintf('\n[target] residual PASS at 8 frames = %.0f%% vs slope %.0f%% at the same dwell\n', ...
                100*passResid(1), 100*passSlope(1));
            tc.verifyGreaterThan(passResid(1), passSlope(1), ...
                ['At the shortest dwell the residual screen must pass more GENUINE ' ...
                 'tracks than the slope fit -- that is the whole claim being tested.']);
            tc.verifyLessThan(spreadResid, spreadSlope, ...
                ['Residual variance is not more dwell-stable than the slope fit. If this ' ...
                 'holds, the prototype does not deliver its stated advantage and the ' ...
                 'result should be documented as such, not tuned.']);
        end

        function test_it_reports_rather_than_guesses_when_too_short(tc)
            % Two points cannot have a scatter. NaN ("not measured"), never 0
            % ("suspicious") -- the same MISSING-vs-ABSENT distinction
            % +track/discriminator.m already had to learn for Doppler.
            [s, d] = track.amplitudeResidualScreen([3000 2960], [1 1.02]);
            tc.verifyTrue(isnan(s));
            tc.verifyEqual(d.verdict, "insufficient");
        end
    end

    methods (Access = private)

        function tracks = renderRealTracks(tc, ranges0, v, F, seed, C)
        %RENDERREALTRACKS  Full pipeline: entity render -> CFAR -> tracker, and
        %   return each confirmed track's own (range, amplitude) series -- the
        %   exact series +track/discriminator.m screens. Nothing synthetic.
            % REWIRED 12 Aug 2026 from engine.entity.render (archived 7 Aug)
            % to generator.render via tests/renderPhantomScene.m. The
            % GEOMETRY is unchanged -- 5000-9000 m at -30 m/s was already
            % chosen to clear the blind range at every dwell length, which is
            % why this file needed no R0 move (unlike the 1800 m tests).
            %
            % The per-object compensation is expressed as RCS now, not
            % AmpScale, because that is the knob the rebuilt path has. It is
            % the SAME compensation: received amplitude ~ sqrt(rcs)/R^2, so
            % rcs ~ R^4 holds it flat across the spread exactly as
            % ampScale ~ R^2 did. Referenced to the nearest object, so it is
            % rcs = 1.0 there rather than the archived 3.0-at-1800 m anchor
            % -- a common scale factor on every object, which no assertion
            % here depends on.
            %
            % The archived comment still governs and is worth keeping:
            %   "Compensate ONCE from the initial range so every object
            %    starts comparably detectable while its amplitude still rises
            %    as 1/R^2 as it closes. Re-compensating per frame would pin
            %    amplitude flat -- the naive-DRFM signature -- and this test
            %    would then be measuring its own scene bug."
            % renderPhantomScene compensates once by construction: RCS is a
            % scalar per phantom for the whole trajectory, so the per-frame
            % re-compensation bug is not expressible here.
            rng(5000 + seed, 'twister');
            rcs = (ranges0(:).' / ranges0(1)).^4;
            f = renderPhantomScene(ranges0, v, 'Rcs', rcs, ...
                'NumFrames', F, 'NumPulses', 32, ...
                'Tag', sprintf('ampres_F%d_s%d', F, seed));
            fb = engine.runJudge(f);
            tracks = cell(1, fb.confirmed_tracks);
            for t = 1:fb.confirmed_tracks
                tracks{t} = struct('R', fb.track_range_m{t}(:), ...
                                   'A', fb.track_amp{t}(:));
            end
        end

        function A = buildArm(tc, arm, R, rs)
            base = (tc.R0 ./ R).^2;                 % exact 1/R^2 in amplitude
            switch arm
                case "genuine"
                    A = base .* 10.^((tc.SCINT_DB*randn(rs,1,numel(R)))/20);
                case "perfect"
                    A = base;                        % servo-driven: no scintillation
                case "constERP"
                    A = ones(1, numel(R)) * base(1); % received power does not change
            end
        end
    end
end
