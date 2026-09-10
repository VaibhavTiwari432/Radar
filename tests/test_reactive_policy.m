classdef test_reactive_policy < matlab.unittest.TestCase
%TEST_REACTIVE_POLICY  RL v2 Step 2: the radar reacts only to a track that
%   barely passed, one escalation per trigger, and agility never rewrites the
%   past.
%
%   THE TEST THAT MATTERS MOST is test_confident_real_track_changes_nothing. A
%   radar that escalated on every track would bite genuine targets too, and the
%   Step 2 kill-switch would credit it with deception-beating power it had
%   bought with false alarms.

    methods (Static, Access = private)
        function s = base()
            s = struct('screens', {{'amplitude', 'bearing'}}, 'confirm', [3 5], ...
                       'agile_from', 0, 'n_reactions', 0, 'last', '');
        end

        function fb = judged(conf, rateFail)
            fb = struct('min_real_confidence', conf, 'any_rate_fail', rateFail);
        end
    end

    methods (Test)
        function test_confident_real_track_changes_nothing(tc)
            s0 = tc.base();
            tc.verifyEqual(radar.reactivePolicy(s0, tc.judged(0.9, false), 'NextFrame', 4), s0);
        end

        function test_no_real_track_changes_nothing(tc)
            % NaN: nothing the radar calls real, so nothing to be suspicious of.
            s0 = tc.base();
            tc.verifyEqual(radar.reactivePolicy(s0, tc.judged(NaN, false), 'NextFrame', 4), s0);
        end

        function test_barely_passing_track_adds_the_first_screen(tc)
            s1 = radar.reactivePolicy(tc.base(), tc.judged(0.1, false), 'NextFrame', 4);
            tc.verifyEqual(s1.screens, {'amplitude', 'bearing', 'rangerate'});
            tc.verifyEqual(s1.n_reactions, 1);
            tc.verifyEqual(s1.last, 'screen');
        end

        function test_range_rate_failure_alone_triggers(tc)
            s1 = radar.reactivePolicy(tc.base(), tc.judged(0.9, true), 'NextFrame', 4);
            tc.verifyEqual(s1.n_reactions, 1);
        end

        function test_escalation_order_and_fall_through(tc)
            s = tc.base();
            frames = [4 7 10 10];
            for k = 1:4
                s = radar.reactivePolicy(s, tc.judged(0.1, false), 'NextFrame', frames(k));
            end
            % screen, agility, confirm -- then screen again, the others spent.
            tc.verifyEqual(s.screens, {'amplitude', 'bearing', 'rangerate', 'residual'});
            tc.verifyEqual(s.agile_from, 7);
            tc.verifyEqual(s.confirm, [4 5]);
            tc.verifyEqual(s.n_reactions, 4);
        end

        function test_agility_starts_at_the_next_block_not_the_past(tc)
            s = tc.base();
            s.n_reactions = 1;          % agility is reaction 2 in the default order
            s1 = radar.reactivePolicy(s, tc.judged(0.1, false), 'NextFrame', 7);
            tc.verifyEqual(s1.agile_from, 7);
            tc.verifyEqual(s1.last, 'agility');
        end

        function test_nothing_left_to_escalate_is_a_no_op(tc)
            s = tc.base();
            s.screens = {'amplitude', 'bearing', 'rangerate', 'residual', 'maneuver'};
            s.agile_from = 4;
            s.confirm = [4 5];
            s.n_reactions = 5;
            tc.verifyEqual(radar.reactivePolicy(s, tc.judged(0.1, false), 'NextFrame', 10), s);
        end
    end
end
