classdef test_sim_units < matlab.unittest.TestCase
%TEST_SIM_UNITS  Phase B1/B2: the thermal floor, the amplitude calibration,
%   and the genuine target return -- each against its stated target.
%
%   +physics/linkBudget.m's own header says "SNR in this project has no
%   absolute meaning, and neither does any detection range." These tests are
%   what makes that sentence obsolete.

    methods (Test)

        % ------------------------------------------------------------------
        % B1 -- thermal noise floor
        % ------------------------------------------------------------------
        function test_b1_thermal_floor_hits_its_verification_target(tc)
            U = physics.simUnits();
            fprintf('\n[B1] N = %.4e W = %.3f dBW  (target 1.598e-14 W, -137.97 dBW)\n', ...
                U.noise_power_w, U.noise_power_dbw);
            fprintf('[B1] delta from target: %+.4f dB\n', U.noise_power_dbw - (-137.97));

            tc.verifyEqual(U.noise_power_w, 1.598e-14, 'RelTol', 1e-3);
            tc.verifyLessThan(abs(U.noise_power_dbw - (-137.97)), 0.1, ...
                'B1 must land within 0.1 dB of -137.97 dBW.');
        end

        function test_b1_constants_are_the_si_exact_values(tc)
            C = physics.Constants();
            tc.verifyEqual(C.k_boltzmann, 1.380649e-23);
            tc.verifyEqual(C.T0_kelvin, 290);
        end

        function test_b1_link_budget_reads_the_same_floor(tc)
            % linkBudget.m and simUnits.m must not drift: same k, same T0,
            % same formula, so the same number.
            L = physics.linkBudget();
            U = physics.simUnits();
            tc.verifyEqual(L.noise_power_w, U.noise_power_w, 'RelTol', 1e-12);
        end

        % ------------------------------------------------------------------
        % B1 -- the amplitude calibration, in ONE place
        % ------------------------------------------------------------------
        function test_b1_noise_amplitude_maps_exactly_to_the_thermal_floor(tc)
            % The anchor, by construction: the simulation's own noise
            % amplitude IS the thermal floor. If this ever stops holding, the
            % unit system has two definitions and every SNR is ambiguous.
            U = physics.simUnits();
            p = physics.simAmplitudeToWatts(U.noise_amplitude);
            fprintf('[B1] sim noise amp %.3f -> %.4e W (floor %.4e W)\n', ...
                U.noise_amplitude, p, U.noise_power_w);
            tc.verifyEqual(p, U.noise_power_w, 'RelTol', 1e-12);
        end

        function test_b1_conversion_round_trips(tc)
            for a = [0.05 0.5 3.0 12.7]
                tc.verifyEqual(physics.wattsToSimAmplitude( ...
                    physics.simAmplitudeToWatts(a)), a, 'RelTol', 1e-12);
            end
        end

        function test_b1_snr_is_scale_invariant(tc)
            % The point of the calibration: a ratio computed in sim units and
            % the same ratio computed in watts are the SAME number, so no
            % existing result moves -- they just acquire an absolute meaning.
            U = physics.simUnits();
            ampSnrDb = 20*log10(3.0 / U.noise_amplitude);
            wattSnrDb = 10*log10(physics.simAmplitudeToWatts(3.0) / U.noise_power_w);
            fprintf('[B1] amp_scale 3.0: SNR in sim units %.3f dB | in watts %.3f dB\n', ...
                ampSnrDb, wattSnrDb);
            tc.verifyEqual(wattSnrDb, ampSnrDb, 'AbsTol', 1e-9);
        end

        function test_b1_python_and_matlab_agree_on_the_anchor(tc)
            % Same rule as the constants tables (A2): two languages, one fact.
            %
            % REWIRED 12 Aug 2026. This guarded on localPythonReady(), which
            % probes py.cogengine.radar_params -- archived 7 Aug, so the
            % guard could never succeed again and the test was permanently
            % skipped. The rebuild has the same two facts:
            %   thermal_noise_power_w  directly, in physics_projection
            %   watts_per_sim_power    as N_watts / noise_amplitude^2, the
            %                          calibration sim_amplitude_for_range's
            %                          own docstring states and uses
            % So this is a guard swap plus one derivation, not a new claim --
            % and it is worth keeping, because a silently-skipped
            % cross-language check is exactly how the two anchors would drift.
            U = physics.simUnits();
            pp = py.importlib.import_module('generator.physics_projection');
            pyN = double(pp.thermal_noise_power_w());
            pyW = pyN / U.noise_amplitude^2;
            tc.verifyEqual(pyN, U.noise_power_w, 'RelTol', 1e-12);
            tc.verifyEqual(pyW, U.watts_per_sim_power, 'RelTol', 1e-12);
        end

        % ------------------------------------------------------------------
        % B2 -- the genuine target return
        % ------------------------------------------------------------------
        function test_b2_target_return_hits_its_verification_targets(tc)
            % AUTHORITATIVE READING: Pt = 1 kW (the stated radar), so the
            % brief's three targets shift up by the 30.00 dB documented in the
            % next test. Targets asserted here are the 1 kW ones.
            T = physics.targetReturn();      % default is now 1 kW

            fprintf('\n[B2] lambda            = %.4f m\n', T.wavelength_m);
            fprintf('[B2] P_r               = %.4e W        (target 4.320e-11 W)\n', T.received_power_w);
            fprintf('[B2] SNR pre-comp      = %+.3f dB         (target 34.32 dB)\n', T.snr_pre_compression_db);
            fprintf('[B2] comp gain B*T     = %.1f = %.3f dB   (target 24, 13.80 dB)\n', ...
                T.compression_gain, T.compression_gain_db);
            fprintf('[B2] SNR at detector   = %+.3f dB         (target 48.12 dB)\n', T.snr_at_detector_db);
            fprintf('[B2] that Pr, in sim amplitude units = %.4f (noise amp 0.05)\n', T.sim_amplitude);

            tc.verifyEqual(T.received_power_w, 4.320e-11, 'RelTol', 2e-3);
            tc.verifyEqual(T.snr_pre_compression_db, 34.32, 'AbsTol', 0.05);
            tc.verifyEqual(T.compression_gain, 24, 'RelTol', 1e-12);
            tc.verifyEqual(T.compression_gain_db, 13.80, 'AbsTol', 0.01);
            tc.verifyEqual(T.snr_at_detector_db, 48.12, 'AbsTol', 0.05);
        end

        function test_b2_the_amp_scale_anchor_is_vindicated(tc)
            % THE HEADLINE OF PHASE B. cogengine/renderer.py and
            % planner_cem.py both state that amp_scale has no link budget
            % behind it. Now that there is one, ask what amp_scale = 3.0
            % actually claims: it is a sigma = 1.33 m^2 target at 1800 m.
            % The convention was very nearly right all along.
            T = physics.targetReturn('RcsM2', 1.0, 'RangeM', 1800);
            impliedSigma = physics.simAmplitudeToWatts(3.0) / T.received_power_w;
            hotDb = 20*log10(3.0 / T.sim_amplitude);

            fprintf('\n[B2] genuine 1 m^2 @ 1800 m renders at sim amplitude %.4f\n', T.sim_amplitude);
            fprintf('[B2] the project renders phantoms at amp_scale = 3.0\n');
            fprintf('[B2] -> amp_scale 3.0 IS a sigma = %.3f m^2 target: %+.2f dB hot for 1 m^2\n', ...
                impliedSigma, hotDb);

            tc.verifyEqual(impliedSigma, 1.331, 'RelTol', 5e-3);
            tc.verifyLessThan(abs(hotDb), 2.0, ...
                'amp_scale 3.0 should be within a couple of dB of a 1 m^2 target.');
        end

        function test_b2_the_stated_1kW_conflicts_with_the_stated_targets(tc)
            % PHASE B2 DISCREPANCY, asserted so it stays visible in the test
            % output instead of becoming folklore. The brief specified
            % Pt = 1 kW AND three verification targets; they disagree by
            % exactly 30.00 dB, and the three targets agree with each other,
            % so Pt was the single inconsistent quantity. Work STOPPED and
            % reported rather than adjusting a target. RESOLVED 1 Aug 2026 in
            % favour of Pt = 1 kW -- the stated radar is authoritative, the
            % three targets were mis-stated.
            kw = physics.targetReturn('TransmitPowerW', 1e3);
            w1 = physics.targetReturn('TransmitPowerW', 1.0);

            offsetDb = kw.snr_at_detector_db - w1.snr_at_detector_db;
            fprintf('\n[B2 DISCREPANCY] at the STATED Pt = 1 kW:\n');
            fprintf('   P_r             = %.4e W   vs target 4.320e-14 W  (%+.2f dB)\n', ...
                kw.received_power_w, 10*log10(kw.received_power_w/4.320e-14));
            fprintf('   SNR pre-comp    = %+.3f dB      vs target 4.32 dB      (%+.2f dB)\n', ...
                kw.snr_pre_compression_db, kw.snr_pre_compression_db - 4.32);
            fprintf('   SNR at detector = %+.3f dB      vs target 18.1 dB      (%+.2f dB)\n', ...
                kw.snr_at_detector_db, kw.snr_at_detector_db - 18.1);
            fprintf('   the three targets are self-consistent; only Pt disagrees, by %.2f dB\n', offsetDb);

            tc.verifyEqual(offsetDb, 30.0, 'AbsTol', 0.01, ...
                '1 kW vs 1 W must be exactly 30 dB -- if not, the reading changed.');
            tc.verifyGreaterThan(abs(kw.snr_at_detector_db - 18.1), 29.9, ...
                'The stated 1 kW no longer misses the stated target: re-derive B2.');
        end

        function test_b2_reference_range_is_not_derivable_from_the_link_budget(tc)
            % B2 asks to DERIVE REFERENCE_RANGE_M rather than assert 1800 m,
            % and to say whether the derived value agrees. It does not, and
            % the honest answer is that the link budget does not determine it.
            %
            % The physically meaningful reference the budget DOES fix is the
            % range at which a sigma = 1 m^2 target reaches the detector's own
            % threshold. Report it; do not rename it REFERENCE_RANGE_M.
            SNR_THRESHOLD_DB = 13;   % ~Pd 0.9 at Pfa 1e-4, Swerling 0
                                     % (+physics/linkBudget.m's SnrThresholdDB)
            T = physics.targetReturn('RangeM', 1800);
            % Pr ~ 1/R^4, so R_thr = R * (snr/thr)^(1/4)
            Rthr = 1800 * (10^((T.snr_at_detector_db - SNR_THRESHOLD_DB)/10))^(1/4);

            fprintf('\n[B2] derived detection-threshold range = %.1f m\n', Rthr);
            fprintf('[B2] existing REFERENCE_RANGE_M anchor  = 1800.0 m\n');
            fprintf('[B2] they DISAGREE by %.1f m (%.2fx) -- see PHASE3_RESULTS.md B2\n', ...
                Rthr - 1800, Rthr/1800);

            tc.verifyGreaterThan(Rthr, 1800, ...
                ['If the threshold range fell BELOW the reference range, the ' ...
                 'project would be anchoring its amplitude scale outside its own ' ...
                 'detection envelope -- a different and worse finding.']);
            % Pinned so the disagreement is a recorded baseline, not a surprise.
            tc.verifyEqual(Rthr, 13589, 'AbsTol', 60);

            % PHASE 4.1 UPDATE -- THIS BLOCK'S FINDING IS NOW RESOLVED.
            % It used to read: "this radar can DETECT a 1 m^2 target out to
            % 13.6 km but can only place it unambiguously out to 2998 m at
            % 50 kHz PRF -- an overrun of 4.5x, so range ambiguity is not a
            % corner case, it is the normal condition." That was the Phase 3
            % finding that drove Phase 4.1. With the PRF resolved to its
            % self-consistent 8 kHz the overrun is GONE: the radar can now
            % unambiguously place everything it can detect, which is what a
            % coherent design looks like. Asserted in the new direction so the
            % contradiction cannot silently return.
            C = physics.Constants();
            Rua = C.R_unambiguous;
            fprintf('[B2] unambiguous range at %.0f kHz PRF   = %.1f m\n', C.PRF/1e3, Rua);
            fprintf('[B2] detection range / R_ua = %.2f  (was 4.53 at the old 50 kHz)\n', Rthr/Rua);
            tc.verifyLessThan(Rthr, Rua, ...
                ['Detection range once again exceeds the unambiguous range. At the ' ...
                 'resolved 8 kHz PRF it must not -- see PHASE4_RESULTS.md Phase 1.']);
        end
    end
end

function ok = localPythonReady()
    ok = false;
    try
        py.importlib.import_module('cogengine.radar_params');
        ok = true;
    catch
    end
end
