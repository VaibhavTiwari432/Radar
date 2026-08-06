classdef tD0_filter_state_extraction < matlab.unittest.TestCase
%TD0_FILTER_STATE_EXTRACTION  track.getFilterState, hand-constructed (no
%   scene, no CFAR, no rendering -- just a live trackerGNN fed a handful of
%   detections directly, per this task's own "don't need a full scene").

    methods (TestClassSetup)
        function addProjectPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)

        function test_imm_track_reports_mode_probabilities_summing_to_one(tc)
            [tracker, tid, rangeSeq, timeSeq] = tc.buildTrack('imm');
            C = physics.Constants();
            out = track.getFilterState(tracker, tid, rangeSeq, timeSeq, C);

            tc.verifyNotEmpty(out.modeProbabilities, ...
                'IMM track should report mode probabilities.');
            tc.verifyEqual(sum(out.modeProbabilities), 1, 'AbsTol', 1e-9);
            tc.verifyGreaterThanOrEqual(out.dominantMode, 1);
            tc.verifyLessThanOrEqual(out.dominantMode, numel(out.modeProbabilities));
            fprintf('[tD0] IMM modeProbabilities = %s, dominant = %d\n', ...
                mat2str(out.modeProbabilities, 4), out.dominantMode);
        end

        function test_cv_track_returns_empty_gracefully_not_error(tc)
            [tracker, tid, rangeSeq, timeSeq] = tc.buildTrack('cv');
            C = physics.Constants();
            out = track.getFilterState(tracker, tid, rangeSeq, timeSeq, C);

            tc.verifyEmpty(out.modeProbabilities, ...
                'A plain CV filter has no IMM mode probabilities -- must be empty, not errored.');
            tc.verifyTrue(isnan(out.dominantMode));
            fprintf('[tD0] CV track: modeProbabilities correctly empty, dominantMode = NaN\n');
        end

        function test_nis_matches_nisConsistency_directly(tc)
            % getFilterState's NIS must be the SAME number
            % track.nisConsistency itself produces on the identical
            % range/time series -- it is a thin, reused wrapper, not a
            % second, divergent formula (see file header: not shadowEKF).
            [tracker, tid, rangeSeq, timeSeq] = tc.buildTrack('cv');
            C = physics.Constants();
            out = track.getFilterState(tracker, tid, rangeSeq, timeSeq, C);
            direct = track.nisConsistency(rangeSeq, timeSeq, C);

            tc.verifyEqual(out.meanNIS, direct.meanNIS, 'AbsTol', 1e-12);
            tc.verifyEqual(out.nis, direct.nis, 'AbsTol', 1e-12);
            fprintf('[tD0] NIS cross-check: getFilterState meanNIS=%.4f matches nisConsistency exactly\n', ...
                out.meanNIS);
        end

    end

    methods (Access = private)
        function [tracker, tid, rangeSeq, timeSeq] = buildTrack(~, filterModel)
        %BUILDTRACK  Hand-feed a trackerGNN a closing target directly via
        %   objectDetection -- no rendering, no CFAR, matching this task's
        %   own "hand-construct it, don't need a full scene" instruction.
            C = physics.Constants();
            switch filterModel
                case 'cv';  filtFcn = @initcvekf;
                case 'imm'; filtFcn = @initekfimm;
            end
            tracker = trackerGNN('ConfirmationThreshold', [2 3], 'DeletionThreshold', [3 3], ...
                'AssignmentThreshold', [200 inf], 'FilterInitializationFcn', filtFcn);
            timeSeq = (0:4)';
            rangeSeq = 1800 - 60*timeSeq;
            measNoise = diag([C.range_per_sample^2, 1, 1]);
            for k = 1:numel(timeSeq)
                det = objectDetection(timeSeq(k), [rangeSeq(k); 0; 0], 'MeasurementNoise', measNoise);
                tks = tracker(det, timeSeq(k));
            end
            confirmed = tks([tks.IsConfirmed]);
            tc_assertConfirmed(confirmed);
            tid = confirmed(1).TrackID;
        end
    end
end

function tc_assertConfirmed(confirmed)
    assert(~isempty(confirmed), 'tD0:noTrackConfirmed', ...
        'Test setup failed to confirm a track at all -- fixture bug, not the thing under test.');
end
