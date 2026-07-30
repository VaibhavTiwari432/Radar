classdef DataIntegration_Test < matlab.unittest.TestCase
%DATAINTEGRATION_TEST  Verify the RadChar dataset loads and is well-formed.
%
%   STATUS: RUNNABLE once data/RadChar-*.h5 is present. If no file is found,
%   every test reports Incomplete (not Failed) so a missing download never
%   looks like a bug. See data/README.md to fetch it from Kaggle.
%
%   Checks the verified RadChar schema:
%       /iq     -> [512 x N] complex
%       /labels -> signal_type in 0..4, SNR in [-20,20] dB, PRI > pulse_width

    properties
        DataFile = ''
    end

    methods (TestClassSetup)
        function findData(tc)
            here = fileparts(mfilename('fullpath'));
            addpath(fileparts(here));   % project root, so +data/+physics resolve
            tc.DataFile = localFindData();
        end
    end

    methods (TestMethodSetup)
        function requireData(tc)
            tc.assumeNotEmpty(tc.DataFile, ...
                'No data/RadChar-*.h5 found. See data/README.md to download it.');
        end
    end

    methods (Test)

        function test_iq_shape_and_type(tc)
            D = data.loadRadChar(tc.DataFile, 'MaxSignals', 1000);
            tc.verifyEqual(size(D.iq,1), 512, 'IQ must have 512 fast-time samples.');
            tc.verifyEqual(size(D.iq,2), D.N, 'IQ column count must equal N.');
            tc.verifyFalse(isreal(D.iq), 'IQ must be complex baseband.');
        end

        function test_signal_types_in_range(tc)
            D = data.loadRadChar(tc.DataFile, 'MaxSignals', 2000);
            u = unique(D.signal_type(~isnan(D.signal_type)));
            tc.verifyTrue(all(u >= 0 & u <= 4), ...
                sprintf('signal_type out of 0..4: [%s]', num2str(u(:).')));
        end

        function test_snr_within_dataset_bounds(tc)
            C = physics.Constants();
            D = data.loadRadChar(tc.DataFile, 'MaxSignals', 2000);
            s = D.signal_to_noise_ratio(~isnan(D.signal_to_noise_ratio));
            tc.verifyGreaterThanOrEqual(min(s), C.SNR_min_dB - 1);
            tc.verifyLessThanOrEqual(max(s),    C.SNR_max_dB + 1);
        end

        function test_pulse_width_less_than_pri(tc)
            % Physical sanity: a pulse must fit inside its repetition interval.
            D = data.loadRadChar(tc.DataFile, 'MaxSignals', 2000);
            pw  = D.pulse_width(~isnan(D.pulse_width));
            pri = D.pulse_repetition_interval(~isnan(D.pulse_repetition_interval));
            n = min(numel(pw), numel(pri));
            tc.verifyTrue(all(pw(1:n) < pri(1:n)), ...
                'Found pulse_width >= PRI, which is unphysical.');
        end

    end

end

% ===================== file-local helpers =============================
function f = localFindData()
%LOCALFINDDATA  Locate a RadChar .h5 relative to the project root.
    here = fileparts(mfilename('fullpath'));   % tests/
    root = fileparts(here);                    % project root
    d = dir(fullfile(root, 'data', 'RadChar*.h5'));
    if isempty(d)
        f = '';
    else
        f = fullfile(d(1).folder, d(1).name);
    end
end
