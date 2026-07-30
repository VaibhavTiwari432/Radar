classdef test_link_budget < matlab.unittest.TestCase
%TEST_LINK_BUDGET  physics.linkBudget -- the first thermal-noise model this
%   project has ever had (RADAR_REALISM_AUDIT.md 2.1).
%
%   Before this, `noise_amplitude = 0.05` was a bare convention with no kTBF
%   behind it, so SNR here had no absolute meaning and neither did any
%   detection range. These tests check the physics laws hold exactly, not
%   that any particular number is flattering.

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_inverse_fourth_power_law_is_exact(tc)
            % Received power must fall as 1/R^4: doubling range divides by 16.
            a = physics.linkBudget('RangeM', 900);
            b = physics.linkBudget('RangeM', 1800);
            c = physics.linkBudget('RangeM', 3600);
            tc.verifyEqual(a.received_power_w / b.received_power_w, 16, 'RelTol', 1e-12);
            tc.verifyEqual(b.received_power_w / c.received_power_w, 16, 'RelTol', 1e-12);
        end

        function test_noise_is_ktbf_not_a_convention(tc)
            % N = k*T0*B*F, checked against the constants directly.
            BOLTZMANN = 1.380649e-23; T0 = 290;
            for F_dB = [0 3 6]
                L = physics.linkBudget('NoiseFigureDB', F_dB, 'BandwidthHz', 2e6);
                expected = BOLTZMANN * T0 * 2e6 * 10^(F_dB/10);
                tc.verifyEqual(L.noise_power_w, expected, 'RelTol', 1e-12);
            end
            % Doubling bandwidth doubles noise power.
            n1 = physics.linkBudget('BandwidthHz', 1e6).noise_power_w;
            n2 = physics.linkBudget('BandwidthHz', 2e6).noise_power_w;
            tc.verifyEqual(n2/n1, 2, 'RelTol', 1e-12);
        end

        function test_coherent_integration_gain_is_n(tc)
            L1 = physics.linkBudget('NumPulses', 1);
            L32 = physics.linkBudget('NumPulses', 32);
            tc.verifyEqual(L32.snr_integrated_db - L1.snr_integrated_db, ...
                10*log10(32), 'AbsTol', 1e-9);
        end

        function test_detection_range_is_self_consistent(tc)
            % At the reported detection range, integrated SNR must equal the
            % threshold -- i.e. the solve inverts the 1/R^4 law correctly.
            L = physics.linkBudget();
            atR = physics.linkBudget('RangeM', L.detection_range_m);
            tc.verifyEqual(atR.snr_integrated_db, L.inputs.SnrThresholdDB, 'AbsTol', 1e-9);
        end

        function test_this_projects_own_geometry_is_physically_sensible(tc)
            % Reported, not asserted as flattering: the ranges this project
            % actually uses, at its own 60 W / 10 GHz / 2 MHz operating point.
            fprintf('\n[link budget] Pt=60 W, G=30 dBi, 10 GHz, sigma=1 m^2, B=2 MHz, F=3 dB, 32 pulses\n');
            L = physics.linkBudget();
            fprintf('   noise kT0BF = %.3e W (%.1f dBW) | detection range = %.0f m @ %.0f dB\n', ...
                L.noise_power_w, L.noise_power_dbw, L.detection_range_m, L.inputs.SnrThresholdDB);
            for R = [1800 3800 5400]
                q = physics.linkBudget('RangeM', R);
                fprintf('   R=%5d m -> Pr=%.3e W  SNR(1)=%+5.1f dB  SNR(32)=%+5.1f dB\n', ...
                    R, q.received_power_w, q.snr_single_pulse_db, q.snr_integrated_db);
                tc.verifyGreaterThan(q.snr_integrated_db, 13, sprintf( ...
                    ['A target at %d m -- a range this project uses in its own scenes -- ' ...
                     'is below a 13 dB detection threshold.'], R));
            end
        end

    end
end
