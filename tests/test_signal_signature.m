classdef test_signal_signature < matlab.unittest.TestCase
%TEST_SIGNAL_SIGNATURE  Positions -> (amplitude, frequency, delay) -> verdict.
%
%   generator/tests/test_geometry.py proves the map in closed form. This file
%   asks the question that settles it: hand the REAL judge nothing but complex
%   samples, and does it reconstruct the quantities the position implied, and
%   what does it conclude?
%
%   THE RADAR IS SINGLE-APERTURE, which is the configuration this pipeline
%   exists for. One receive channel, no monopulse, no bearing. It measures
%   range, range-rate and amplitude -- and every one of those is derived by
%   generator/physics_projection.py from ONE range trajectory, so they cannot
%   disagree with each other. The expected outcome is therefore that the
%   phantoms pass, and the tests assert exactly that.
%
%   THE TWO-APERTURE CASE IS KEPT AS ONE CONTRAST TEST, not deleted: it is the
%   published Phase B result and the reason the single-aperture assumption is
%   load-bearing rather than a convenience. One argument separates them.

    methods (Test)

        function test_the_radar_reconstructs_the_range_the_position_implied(tc)
            % Delay is the adversary's to set, so |P| comes back within the
            % instrument's own resolution.
            out = experiments.signalSignature('OutDir', tempdir);
            C = physics.Constants();
            tc.verifyLessThan(max(out.range_error_m), C.range_per_sample, ...
                'a requested range was not honoured to within one range cell');
        end

        function test_it_reconstructs_the_range_rate_too(tc)
            % The frequency primitive carries u.V, and the judge recovers it
            % from a slow-time FFT it was never told anything about.
            % Tolerance is one velocity bin, lambda*PRF/(2*numPulses).
            out = experiments.signalSignature('OutDir', tempdir);
            C = physics.Constants();
            binMps = C.lambda * C.PRF / (2 * 32);
            tc.verifyLessThan(max(out.rdot_error_mps), 2 * binMps, ...
                'the measured range-rate is more than two velocity bins from truth');
        end

        function test_a_single_aperture_radar_accepts_all_of_them(tc)
            % THE RESULT THE PIPELINE EXISTS FOR. Nothing the radar can
            % measure disagrees with anything else, because all of it is
            % derived from one range trajectory.
            out = experiments.signalSignature('OutDir', tempdir);
            tc.verifyTrue(out.single_aperture);
            tc.verifyEqual(out.feedback.angle_source, 'none', ...
                'the radar was supposed to have no difference channel');
            tc.verifyFalse(out.feedback.cobearing_flagged, ...
                'a radar with no bearing cannot run a co-bearing screen');
            labels = out.labels;
            tc.verifyEqual(nnz(strcmp(labels, 'real')), numel(labels), ...
                'a fully self-consistent phantom was still flagged');
        end

        function test_the_cross_range_offset_is_unfalsifiable_not_honoured(tc)
            % The honest half. The requested lateral offset is NOT delivered --
            % the radar assumes boresight -- but neither is it contradicted,
            % because nothing measured it. Asserting the displacement is real
            % stops this being read as "positions work in 3D".
            out = experiments.signalSignature('OutDir', tempdir);
            lateral = out.offsets_m(:, 2);
            [~, ord] = sort(lateral);
            r = out.residual_m(ord);
            tc.verifyEqual(r, sort(r), 'AbsTol', 1e-9, ...
                'displacement is not monotone in the requested lateral offset');
            tc.verifyGreaterThan(max(out.residual_m), 300, ...
                'a 600 m lateral request should show as hundreds of metres');
            % ...and it cost nothing, which is the whole point.
            tc.verifyEqual(nnz(strcmp(out.labels, 'real')), numel(out.labels), ...
                'the displacement was penalised, but nothing measured it');
        end

        function test_an_on_bearing_phantom_needs_no_projection(tc)
            % The control: a position the geometry can deliver exactly.
            out = experiments.signalSignature('Offsets', [2200 0 0], ...
                'OffsetVelocities', [-50 0 0], 'OutDir', tempdir);
            C = physics.Constants();
            tc.verifyLessThan(out.residual_m(1), C.range_per_sample);
        end

        function test_adding_the_second_aperture_flips_every_verdict(tc)
            % THE CONTRAST, kept because it is the reason single-aperture is an
            % assumption and not a detail. Same scene, same seed, same
            % phantoms; the only difference is whether the radar has a
            % difference channel.
            single = experiments.signalSignature('OutDir', tempdir);
            dual   = experiments.signalSignature('SingleAperture', false, ...
                                                  'OutDir', tempdir);

            tc.verifyEqual(nnz(strcmp(single.labels, 'real')), numel(single.labels));
            tc.verifyEqual(nnz(strcmp(dual.labels, 'decoy')), numel(dual.labels), ...
                'monopulse should condemn every co-bearing phantom');
            tc.verifyTrue(dual.feedback.cobearing_flagged);
        end

    end
end
