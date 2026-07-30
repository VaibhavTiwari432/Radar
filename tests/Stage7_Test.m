classdef Stage7_Test < matlab.unittest.TestCase
%STAGE7_TEST  Deception benchmark & honest trade-off curves.
%              (POA Part 4, Stage 7; claim C10)
%
%   STATUS: RUNNABLE NOW. experiments.runBenchmark(struct('quick',true)) is
%   run ONCE in TestClassSetup and shared by all three test methods below
%   (it takes several minutes -- Random/BruteForce/DQN x 5 seeds -- so
%   re-running it per test method would triple the wall-clock for no
%   reason).
%
%   Claims under test:
%     * >= 5 seeds per condition (results are real, not lucky) - C10
%     * At least one condition where the RADAR WINS
%       (P_false_track_confirmed < 1) -- otherwise the radar is a strawman.

    properties
        T
    end

    methods (TestClassSetup)
        function runBenchmarkOnce(tc)
            tc.T = experiments.runBenchmark(struct('quick', true));
        end
    end

    methods (Test)

        function test_metrics_columns_present(tc)
            need = {'P_detected','P_false_track_confirmed', ...
                    'P_rejected_by_ECCM','MeanEIRP','Seed'};
            tc.verifyTrue(all(ismember(need, tc.T.Properties.VariableNames)), ...
                sprintf('Benchmark table missing columns. Has: %s', ...
                    strjoin(tc.T.Properties.VariableNames, ', ')));
        end

        function test_at_least_five_seeds(tc)
            tc.verifyGreaterThanOrEqual(numel(unique(tc.T.Seed)), 5, ...
                'Need >= 5 seeds per condition for confidence intervals.');
        end

        function test_radar_wins_somewhere(tc)
            tc.verifyLessThan(min(tc.T.P_false_track_confirmed), 1.0, ...
                'If deception is 100% everywhere, the radar/ECCM is too weak (strawman).');
        end

    end

end
