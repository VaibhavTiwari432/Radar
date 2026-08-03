classdef test_judge_config_isolation < matlab.unittest.TestCase
%TEST_JUDGE_CONFIG_ISOLATION  Phase A1: the adversary cannot configure the judge.
%
%   Until this test existed, cogengine.matlab_judge.export_scene_for_judge
%   wrote the TWIN's own cfar_pfa / cfar_num_training / cfar_num_guard into
%   the .mat and engine.runJudge configured its CA-CFAR from them -- the
%   scored party setting the scorer's detection threshold, which is exactly
%   the self-grading loop CLAUDE.md Rule 2 exists to forbid. It was
%   invisible because TwinConfig's values happened to equal
%   +radar/cfarDetect.m's own defaults, so the override never changed a
%   number and never showed up in a diff of results.
%
%   The test is deliberately built so it would FAIL on the old code: it
%   plants a Pfa four orders of magnitude away from the judge's own (1e-4 ->
%   0.5), which on the old read path floods the range profile with false
%   alarms and cannot possibly leave the detection count untouched.

    properties (Constant)
        FS_HZ    = 3.2e6
        PW_S     = 12e-6
        BW_HZ    = 2e6
        PRF_HZ   = physics.Constants().PRF
        CARRIER  = 10e9
        DT_S     = 1.0
        NPULSES  = 32
        NFRAMES  = 8
    end

    methods (Test)

        function test_mat_cfar_fields_cannot_move_the_judge(tc)
            % Same signal, judged twice. The only difference is a deliberately
            % absurd CFAR config planted in the .mat by the "adversary".
            cube = tc.buildCube(12345);

            honest = tc.judgeCube(cube, struct());
            planted = tc.judgeCube(cube, struct( ...
                'cfar_pfa', 0.5, ...          % 5000x the judge's own 1e-4
                'cfar_num_training', 2, ...   % 10x narrower training window
                'cfar_num_guard', 0));

            fprintf('\n[A1] detections with honest .mat : %d confirmed tracks\n', ...
                honest.confirmed_tracks);
            fprintf('[A1] detections with planted .mat: %d confirmed tracks\n', ...
                planted.confirmed_tracks);

            tc.verifyEqual(planted.confirmed_tracks, honest.confirmed_tracks, ...
                'A cfar_* field in the .mat moved the judge. The wire is not cut.');
            tc.verifyEqual(planted.track_range_m, honest.track_range_m, ...
                'AbsTol', 0, 'Planted CFAR config changed the judge''s ranges.');
        end

        function test_mat_tracker_and_eccm_fields_cannot_move_the_judge(tc)
            cube = tc.buildCube(6789);

            honest = tc.judgeCube(cube, struct());
            planted = tc.judgeCube(cube, struct( ...
                'assignment_gate_m', 1, ...                 % gate everything out
                'confirmation_threshold', [5 5], ...
                'deletion_threshold', [1 1], ...
                'filter_model', 'ca', 'tracker_type', 'jpda', ...
                'eccm_screens', {{''}}, ...                 % all screens off
                'expect_micro_doppler', true, ...
                'micro_blade_hz_min', 1));

            fprintf('[A1] honest : %d confirmed, label ''%s''\n', ...
                honest.confirmed_tracks, honest.eccm_label);
            fprintf('[A1] planted: %d confirmed, label ''%s''\n', ...
                planted.confirmed_tracks, planted.eccm_label);

            tc.verifyEqual(planted.confirmed_tracks, honest.confirmed_tracks, ...
                'A tracker field in the .mat moved the judge. The wire is not cut.');
            tc.verifyEqual(string(planted.eccm_label), string(honest.eccm_label), ...
                'An eccm_screens/expect_micro_doppler field in the .mat moved the ECCM verdict.');
        end

        function test_explicit_caller_args_DO_move_the_judge(tc)
            % The control: the isolation above must come from cutting the .mat
            % wire, NOT from the knobs being dead. A MATLAB caller -- the
            % radar's own operator, not the adversary -- can still sweep them.
            cube = tc.buildCube(6789);

            baseline = engine.runJudge(tc.writeMat(cube, struct()));
            swept = engine.runJudge(tc.writeMat(cube, struct()), ...
                'AssignmentThreshold', [1 inf]);   % gate everything out
            % The SAME absurd CFAR config test 1 planted in the .mat and saw
            % ignored -- proving test 1's null result is isolation, not a
            % dead knob.
            loose = engine.runJudge(tc.writeMat(cube, struct()), ...
                'Pfa', 0.5, 'NumTraining', 2, 'NumGuard', 0);

            fprintf('[A1] caller default gate     : %d confirmed\n', baseline.confirmed_tracks);
            fprintf('[A1] caller gate=1 m (swept) : %d confirmed\n', swept.confirmed_tracks);
            fprintf('[A1] caller Pfa=0.5 (swept)  : %d confirmed\n', loose.confirmed_tracks);

            tc.verifyGreaterThan(baseline.confirmed_tracks, 0, ...
                'Scene did not confirm at all -- the control proves nothing.');
            tc.verifyLessThan(swept.confirmed_tracks, baseline.confirmed_tracks, ...
                'A 1 m assignment gate did not reduce confirmations: the knob is dead, not isolated.');
            tc.verifyGreaterThan(loose.confirmed_tracks, baseline.confirmed_tracks, ...
                ['Pfa=0.5 via the CALLER did not change the judge either -- the ' ...
                 'CFAR knob is dead, so test 1 proves nothing about isolation.']);
        end

        function test_frame_log_gate_follows_the_tracker_not_a_copy(tc)
            % C3: runJudge carried a literal ASSIGNMENT_GATE_M = 200 copied
            % from the tracker, so a swept gate left the frame log logging
            % hits against a threshold nothing was using.
            cube = tc.buildCube(12345);
            wide = engine.runJudge(tc.writeMat(cube, struct()));
            tight = engine.runJudge(tc.writeMat(cube, struct()), ...
                'AssignmentThreshold', [5 inf]);

            hitsWide = tc.countHits(wide);
            hitsTight = tc.countHits(tight);
            fprintf('[A1/C3] frame-log hits, gate 200 m: %d | gate 5 m: %d\n', ...
                hitsWide, hitsTight);
            tc.verifyLessThan(hitsTight, hitsWide, ...
                ['The frame log recorded the same hit count under a 40x tighter ' ...
                 'gate -- it is still using a stale hardcoded 200 m copy.']);
        end
    end

    methods (Access = private)

        function n = countHits(~, fb)
            n = 0;
            for k = 1:numel(fb.frame_log)
                tkk = fb.frame_log{k};
                for t = 1:numel(tkk)
                    n = n + double(tkk(t).hitThisFrame);
                end
            end
        end

        function cube = buildCube(tc, seed)
            % One genuine closing target, this project's canonical geometry.
            rs = RandStream('mt19937ar', 'Seed', seed);
            nFast = 400;
            cube = complex(zeros(nFast, tc.NPULSES, tc.NFRAMES));
            R0 = 1800; v = -40;
            for k = 1:tc.NFRAMES
                st = engine.entity.EntityState('range_m', R0 + v*(k-1)*tc.DT_S, ...
                        'range_rate_mps', v, 'class', "drone");
                sig = engine.entity.render(st, 'NumPulses', tc.NPULSES, ...
                    'FastTimeSamples', nFast, 'PulseWidth', tc.PW_S, ...
                    'Bandwidth', tc.BW_HZ, 'CarrierHz', tc.CARRIER, ...
                    'PrfHz', tc.PRF_HZ, 'AmpScale', 3.0, 'RandStream', rs);
                cube(:,:,k) = sig + 0.05 * (randn(rs, nFast, tc.NPULSES) + ...
                                     1i*randn(rs, nFast, tc.NPULSES)) / sqrt(2);
            end
        end

        function f = writeMat(tc, cube, extra)
            C = physics.Constants();
            S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', tc.PW_S, ...
                'bandwidth_hz', tc.BW_HZ, 'prf_hz', tc.PRF_HZ, ...
                'carrier_hz', tc.CARRIER, 'frame_interval_s', tc.DT_S);
            fn = fieldnames(extra);
            for i = 1:numel(fn); S.(fn{i}) = extra.(fn{i}); end
            f = [tempname '.mat'];
            save(f, '-struct', 'S');
        end

        function fb = judgeCube(tc, cube, extra)
            f = tc.writeMat(cube, extra);
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end
    end
end
