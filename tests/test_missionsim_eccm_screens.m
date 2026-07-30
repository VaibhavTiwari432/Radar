classdef test_missionsim_eccm_screens < matlab.unittest.TestCase
%TEST_MISSIONSIM_ECCM_SCREENS  Mission Simulator build order Step 7: ECCM
%   screens.
%
%   Acceptance criterion (verbatim): "Feed a naive constant-amplitude
%   zero-Doppler phantom: amplitude-range screen must flag it. Feed a real
%   target: must pass."
%
%   Reuses tests/Stage5_Test.m's own two established fixtures directly
%   (not reinvented) -- the VERDICT comes from track.discriminator, the
%   sole authority (CLAUDE.md's Golden Rule); missionsim.computeEccmScreens
%   only adds the measured-value gauges alongside it.

    methods (Test)

        function test_naive_decoy_is_flagged_and_gauge_reflects_it(tc)
            C = physics.Constants();
            decoy = struct('range', [2000 2000 2000 2000 2000], ...
                            'amplitude', [1 1 1 1 1], 'doppler', [0 0 0 0 0]);

            [label, ~] = track.discriminator(decoy, C);
            tc.verifyEqual(string(label), "decoy", ...
                'The judge itself (track.discriminator) must flag the naive decoy -- the sole authority.');

            screens = missionsim.computeEccmScreens(decoy);
            fprintf('decoy gauge: slope=%.2f (real ref=%d, repeater ref=%d)\n', ...
                screens.amplitudeRangeSlopeDbDecade, screens.realRefDbDecade, screens.repeaterRefDbDecade);
            tc.verifyTrue(isnan(screens.amplitudeRangeSlopeDbDecade), ...
                'A perfectly flat range/amplitude has no fittable slope -- the gauge must show that honestly (NaN), not fabricate a number.');
            tc.verifyEqual(screens.realRefDbDecade, -40);
            tc.verifyEqual(screens.repeaterRefDbDecade, -20);
        end

        function test_real_target_passes_and_gauge_matches_the_real_reference(tc)
            C = physics.Constants();
            R = 2000 - (0:4)*40;
            realTarget = struct('range', R, 'amplitude', 1./R.^2, 'doppler', -ones(1,5)*50);

            [label, ~] = track.discriminator(realTarget, C);
            tc.verifyEqual(string(label), "real", ...
                'The judge itself must pass a physically-consistent real target.');

            screens = missionsim.computeEccmScreens(realTarget);
            fprintf('real gauge: slope=%.2f (real ref=%d, repeater ref=%d)\n', ...
                screens.amplitudeRangeSlopeDbDecade, screens.realRefDbDecade, screens.repeaterRefDbDecade);
            tc.verifyEqual(screens.amplitudeRangeSlopeDbDecade, -40, 'AbsTol', 1e-6, ...
                'A target built with amplitude=1/R^2 should measure exactly -40 dB/decade, matching the real reference line.');
        end

        function test_derivation_matches_claudemd_rule1_table(tc)
            % CLAUDE.md's own Rule 1 table: "real ~ 1/R^2 (voltage),
            % repeater ~ 1/R^1" -- the reference lines here must be
            % DERIVED from that relation (20*log10 amplitude convention),
            % not independently typed numbers that happen to agree.
            screens = missionsim.computeEccmScreens(struct('range', [1 10], 'amplitude', [1 1], 'doppler', [0 0]));
            tc.verifyEqual(screens.realRefDbDecade, 20 * (-2));       % 1/R^2 -> slope -2 -> 20*(-2) dB/decade
            tc.verifyEqual(screens.repeaterRefDbDecade, 20 * (-1));   % 1/R^1 -> slope -1 -> 20*(-1) dB/decade
        end

        function test_ui_table_shows_gauge_columns(tc)
            app = missionsim.MissionSimulatorApp();
            cleanupObj = onCleanup(@() delete(app)); %#ok<NASGU>

            tc.verifyEqual(app.TrackTable.ColumnName{7}, 'Amp-range slope (dB/dec)');
            tc.verifyEqual(app.TrackTable.ColumnName{8}, 'Doppler resid. (m/s)');
        end

    end

end
