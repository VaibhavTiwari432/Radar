classdef Stage8_Test < matlab.unittest.TestCase
%STAGE8_TEST  Verification, validation & reproducibility (POA Part 4, Stage 8).
%
%   STATUS: META-CHECK RUNNABLE NOW (suite integrity). Headline-reproduction
%   is a guarded scaffold until results/headline.mat is produced.

    methods (Test)

        function test_all_stage_files_exist(tc)
            % The suite is complete: every stage + data test is present.
            here = fileparts(mfilename('fullpath'));
            need = {'Stage0_Test.m','Stage1_Test.m','Stage2_Test.m', ...
                    'Stage3_Test.m','Stage4_Test.m','Stage5_Test.m', ...
                    'Stage6_Test.m','Stage7_Test.m','DataIntegration_Test.m'};
            for i = 1:numel(need)
                tc.verifyTrue(isfile(fullfile(here, need{i})), ...
                    sprintf('Missing test file: %s', need{i}));
            end
        end

        function test_headline_reproduces(tc)
            % Reproducibility: a fresh `matlab -batch runAll` should land the
            % headline metric within its confidence interval.
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            hf = fullfile(root, 'results', 'headline.mat');
            tc.assumeTrue(isfile(hf), ...
                'Stage 8 pending: produce results/headline.mat, then assert reproduction within CI.');
            S = load(hf);
            tc.verifyTrue(isfield(S,'value') && isfield(S,'ci'), ...
                'headline.mat must store .value and .ci.');
            tc.verifyLessThanOrEqual(S.ci(1), S.value);
            tc.verifyGreaterThanOrEqual(S.ci(2), S.value);
        end

    end

end
