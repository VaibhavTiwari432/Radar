classdef test_generator_judge_summary < matlab.unittest.TestCase
%TEST_GENERATOR_JUDGE_SUMMARY  Guards the Python bridge's contract.
%
%   generator.judgeSummary is the ONLY path by which Phase C's training loop
%   reads a judge verdict (generator/decision/matlab_bridge.py ->
%   generator/decision/env.py). Every reward in that run is one of these
%   structs, so a silent defect here corrupts training rather than crashing
%   it -- and it was the last of the seven +generator/ entry points with no
%   test (10 Aug 2026 audit).
%
%   IT USES THE TWO-PHANTOM SCENE ON PURPOSE. The bug this wrapper exists to
%   prevent is not a wrong number, it is a CONVERSION failure: MATLAB Engine
%   for Python can only return a struct that is scalar at every level, and
%   engine.runJudge's frame_log holds a STRUCT ARRAY per frame -- one element
%   per simultaneous track. It is therefore scalar, and the bridge is happy,
%   right up until a frame contains a second track. That is why the original
%   training run survived ~75 episodes before dying: a single-phantom test
%   would pass here and prove nothing.
%
%   The cobearing pair confirms two tracks in the same frames, which is
%   exactly the shape that crashed it.

    properties
        FixtureDir
        JudgeMat
    end

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'generator.tests.build_gate_a_scenes not importable from this MATLAB''s Python environment (pyenv).');
        end

        function buildScene(tc)
            tc.FixtureDir = tempname;
            mkdir(tc.FixtureDir);
            mod = py.importlib.import_module('generator.tests.build_gate_a_scenes');
            py.importlib.reload(mod);
            pre = fullfile(tc.FixtureDir, 'gateA_cobearing_pair.mat');
            mod.build_cobearing_pair(pre);
            rng(1, 'twister');
            tc.JudgeMat = fullfile(tc.FixtureDir, 'summary_judge.mat');
            generator.render(pre, tc.JudgeMat, 'IncludeAngleChannel', true);
        end
    end

    methods (TestClassTeardown)
        function cleanFixtures(tc)
            if ~isempty(tc.FixtureDir) && isfolder(tc.FixtureDir)
                rmdir(tc.FixtureDir, 's');
            end
        end
    end

    methods (Test)

        function test_the_scene_really_is_multi_track(tc)
            % Guard the guard. If this scene ever stops producing two
            % simultaneous tracks, every other test in this file silently
            % reverts to exercising the case that never crashed.
            fb = engine.runJudge(tc.JudgeMat);
            tc.verifyGreaterThanOrEqual(fb.confirmed_tracks, 2, ...
                ['This file must exercise a MULTI-TRACK frame -- that is the ' ...
                 'only shape that breaks the Python bridge.']);
        end

        function test_summary_is_scalar_all_the_way_down(tc)
            % The actual contract: MATLAB Engine for Python converts a
            % struct only if it, and everything nested in it, is 1x1.
            s = generator.judgeSummary(tc.JudgeMat);
            tc.verifySize(s, [1 1], 'judgeSummary must return a SCALAR struct.');
            f = fieldnames(s);
            for k = 1:numel(f)
                v = s.(f{k});
                tc.verifyTrue(isnumeric(v) || islogical(v) || ischar(v), ...
                    sprintf(['field ''%s'' is a %s. Only numeric/logical/char ' ...
                             'survive the bridge -- a struct, cell or string ' ...
                             'here is the crash this wrapper exists to prevent.'], ...
                            f{k}, class(v)));
                if isnumeric(v) || islogical(v)
                    tc.verifyNumElements(v, 1, ...
                        sprintf('field ''%s'' must be scalar, not a %s array.', f{k}, mat2str(size(v))));
                end
            end
        end

        function test_summary_does_not_disagree_with_the_judge(tc)
            % A wrapper that returns clean, convertible, WRONG numbers would
            % pass the test above. runJudge is deterministic given a rendered
            % .mat (the noise is added in render, not in the judge), so the
            % two are directly comparable.
            fb = engine.runJudge(tc.JudgeMat);
            s  = generator.judgeSummary(tc.JudgeMat);
            tc.verifyEqual(s.confirmed_tracks,       fb.confirmed_tracks);
            tc.verifyEqual(s.false_tracks_surviving, fb.false_tracks_surviving);
            tc.verifyEqual(s.flagged_decoys,         fb.flagged_decoys);
            tc.verifyEqual(s.eccm_label,             char(fb.eccm_label));
            tc.verifyEqual(s.track_label, strjoin(cellstr(fb.track_label), ','), ...
                'Per-track labels must survive the flattening, not just the counts.');
        end

        function test_name_value_options_reach_the_judge(tc)
            % judgeSummary forwards varargin. If that ever breaks, Phase C
            % would train against a DEFAULT radar while believing it had
            % configured one -- a silent scientific error, not a crash.
            %
            % The lever is ConfirmationThreshold, not EccmScreens. The first
            % version of this test used the screen mask and FAILED, because
            % of the property asserted in the next test down: on THIS scene
            % the mask cannot change the label. That failure was the test
            % being wrong, not the wrapper -- recorded here because
            % "disabling the screens must change something" is an easy and
            % wrong assumption to make about a co-bearing scene.
            sDefault = generator.judgeSummary(tc.JudgeMat);
            sStrict  = generator.judgeSummary(tc.JudgeMat, 'ConfirmationThreshold', [20 20]);
            tc.verifyGreaterThanOrEqual(sDefault.confirmed_tracks, 2);
            tc.verifyEqual(sStrict.confirmed_tracks, 0, ...
                ['A 20-of-20 confirmation threshold cannot be met in an ' ...
                 '8-frame scene, so this must confirm nothing. Any tracks ' ...
                 'here mean varargin is being dropped before it reaches ' ...
                 'engine.runJudge.']);
        end

        function test_cobearing_is_not_gated_by_the_screen_mask(tc)
            % A real property of the judge, worth locking: the co-bearing
            % test lives in engine.runJudge, NOT in track.discriminator, so
            % it is not a member of EccmScreens and cannot be ablated with
            % one. Disabling every discriminator screen still leaves this
            % pair condemned.
            %
            % This is the structural reason the monopulse wall is not a
            % tuning result. Every screen a phantom CAN satisfy is in the
            % mask; the one it cannot is not, because "do these tracks share
            % a bearing?" is not answerable per track.
            sOn  = generator.judgeSummary(tc.JudgeMat, 'EccmScreens', {'amplitude','doppler','micro'});
            sOff = generator.judgeSummary(tc.JudgeMat, 'EccmScreens', {'__no_screens__'});
            tc.verifyEqual(sOff.track_label, sOn.track_label, ...
                'Co-bearing must condemn this pair regardless of the discriminator mask.');
            tc.verifyEqual(sOn.track_label, 'decoy,decoy');
        end

    end
end

function tf = localPythonReady()
    try
        py.importlib.import_module('generator.tests.build_gate_a_scenes');
        tf = true;
    catch
        tf = false;
    end
end
