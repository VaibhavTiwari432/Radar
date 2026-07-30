classdef test_missionsim_schema < matlab.unittest.TestCase
%TEST_MISSIONSIM_SCHEMA  Mission Simulator build order (MISSION_SIMULATOR_
%   UI_SPEC.md Section 9), Step 0: frame schema + validator.
%
%   Acceptance criterion 0 (the spec's own words): "Validator REJECTS a
%   frame with a value lacking provenance. Test asserts the rejection."
%   test_rejects_value_without_provenance is that exact test.

    methods (Test)

        function test_rejects_value_without_provenance(tc)
            % Acceptance criterion 0, verbatim.
            frame.synth.eirp.peakW = 180;               % plain, fine (not wrapped)
            frame.synth.phantoms(1).range = struct('value', 2391.9, 'unit', 'm');
            % ^ MISSING provenance -- must be rejected.

            [valid, errors] = missionsim.validateFrame(frame);

            tc.verifyFalse(valid, ...
                'A frame with a "value" lacking "provenance" must be rejected.');
            tc.verifyNotEmpty(errors);
            tc.verifyTrue(any(contains(errors, 'range')), ...
                'The reported error should point at the offending field.');
        end

        function test_accepts_fully_provenanced_frame(tc)
            frame.synth.phantoms(1).range = struct('value', 2391.9, 'unit', 'm', 'provenance', 'DERIVED');
            frame.radar.identity.fs = struct('value', 3.2e6, 'unit', 'Hz', 'provenance', 'DERIVED');
            frame.radar.tracks(1).hits = 10;             % plain, unwrapped -- allowed (see header)
            frame.radar.tracks(1).score = 0.81;

            [valid, errors] = missionsim.validateFrame(frame);

            tc.verifyTrue(valid, sprintf('Expected a fully-provenanced frame to validate; errors: %s', ...
                strjoin(errors, '; ')));
            tc.verifyEmpty(errors);
        end

        function test_rejects_violation_nested_inside_array(tc)
            % A violation buried inside a struct ARRAY (multiple phantoms/
            % tracks, the realistic case) must still be caught, not just a
            % top-level one.
            frame.synth.phantoms(1).range = struct('value', 100, 'unit', 'm', 'provenance', 'DERIVED');
            frame.synth.phantoms(2).range = struct('value', 200, 'unit', 'm');  % missing provenance

            [valid, errors] = missionsim.validateFrame(frame);
            tc.verifyFalse(valid);
            tc.verifyTrue(any(contains(errors, 'phantoms[1]')), ...
                sprintf('Expected the second array element to be flagged; got: %s', strjoin(errors, '; ')));
        end

        function test_accepts_string_json_input_directly(tc)
            json = '{"radar":{"identity":{"fs":{"value":3.2e6,"unit":"Hz","provenance":"DERIVED"}}}}';
            [valid, errors] = missionsim.validateFrame(json);
            tc.verifyTrue(valid, strjoin(errors, '; '));
        end

        function test_spec_example_frame_validates(tc)
            % A reduced version of MISSION_SIMULATOR_UI_SPEC.md Section 8's
            % own worked example -- proves the validator works on the
            % actual documented shape, not just synthetic minimal cases.
            frame.frame = 142;
            frame.t = 14.2;
            frame.seed = 20261166;
            frame.phase = "DECEPTION_HOLDING";
            frame.synth.engineMode = "D3QN";
            frame.synth.phantoms(1) = struct( ...
                'id', "P1", 'delaySamples', 51, ...
                'range', struct('value', 2391.9, 'unit', 'm', 'provenance', "DERIVED"), ...
                'doppler', struct('value', 120, 'unit', 'Hz', 'provenance', "ASSUMED"), ...
                'amplitude', 1.0, 'phaseDeg', 13.0);
            frame.synth.sicIsolationDb = struct('value', 35, 'provenance', "ASSUMED");
            frame.radar.identity.fs = struct('value', 3.2e6, 'unit', 'Hz', 'provenance', "DERIVED");
            frame.radar.identity.priUs = struct('value', 20.0, 'unit', 'us', 'provenance', "MEASURED");
            frame.radar.detection.designPfa = struct('value', 1e-4, 'provenance', "ASSUMED");
            frame.radar.detection.measuredPfa = struct('value', 1.1e-4, 'provenance', "MEASURED");
            frame.radar.tracks(1) = struct('id', "T01", 'state', "CONFIRMED", ...
                'ageFrames', 12, 'hits', 10, 'misses', 2, 'score', 0.81, ...
                'groundTruth', "PHANTOM");
            frame.radar.scoreboard.deceptionRate = struct('value', 0.62, 'provenance', "MEASURED");
            frame.radar.scoreboard.controlC1Pass = true;

            [valid, errors] = missionsim.validateFrame(frame);
            tc.verifyTrue(valid, strjoin(errors, '; '));
        end

    end

end
