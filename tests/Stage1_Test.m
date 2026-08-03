classdef Stage1_Test < matlab.unittest.TestCase
%STAGE1_TEST  The honest radar front-end: CFAR detection controls.
%
%   STATUS: RUNNABLE NOW (needs Phased Array System Toolbox; if absent, the
%   tests report Incomplete rather than Failed).
%
%   Exercises radar.cfarDetect and radar.pulseCompress and encodes POA
%   claims C1/C2:
%       C2 (negative control) - CFAR holds its design false-alarm rate on
%                               noise-only input.  <-- build this first
%       C1 (positive control) - a real target above the noise is detected,
%                               and detection improves with SNR.
%       + matched filter concentrates energy (pulse-compression gain).
%
%   These are the tests that convert "the radar detects" from an assertion
%   into evidence (POA Part 6). Determinism via rng() so runs are repeatable.

    methods (TestClassSetup)
        function addProjectPath(~)
            here = fileparts(mfilename('fullpath'));
            addpath(fileparts(here));   % project root, so +radar/+physics resolve
        end
    end

    methods (TestMethodSetup)
        function requirePhased(tc)
            tc.assumeTrue(localHas('phased.CFARDetector'), ...
                'Phased Array System Toolbox required (see Stage 0).');
        end
    end

    methods (Test)

        % ---- C2: negative control (the most important single test) --------
        function test_C2_false_alarm_rate(tc)
            rng(2026);
            Pfa = 1e-2;  N = 1e5;  nt = 20;  ng = 4;
            x = (randn(N,1) + 1i*randn(N,1)) / sqrt(2);   % unit-power complex noise
            p = abs(x).^2;                                % exponential power
            detIdx = radar.cfarDetect(p, 'Pfa', Pfa, ...
                        'NumTraining', nt, 'NumGuard', ng);
            margin   = nt + ng;
            testable = N - 2*margin;
            pfaHat   = numel(detIdx) / testable;
            relErr   = abs(pfaHat - Pfa) / Pfa;
            tc.verifyLessThan(relErr, 0.30, sprintf( ...
                'Empirical Pfa = %.3g vs design %.3g (rel err %.1f%%).', ...
                pfaHat, Pfa, 100*relErr));
        end

        % ---- C1: positive control -----------------------------------------
        function test_C1_target_detected(tc)
            rng(7);
            N = 400; nt = 20; ng = 4; b = 200;
            x = (randn(N,1) + 1i*randn(N,1)) / sqrt(2);
            p = abs(x).^2;
            p(b) = 50;                          % strong target (~17 dB over noise)
            detIdx = radar.cfarDetect(p, 'Pfa', 1e-4, ...
                        'NumTraining', nt, 'NumGuard', ng);
            tc.verifyTrue(ismember(b, detIdx), ...
                'Injected strong target was not detected by CFAR.');
        end

        function test_C1_detection_improves_with_snr(tc)
            rng(11);
            nt = 20; ng = 4; N = 200; b = 100; trials = 200;
            pdLow  = localPd(2,   trials, N, b, nt, ng);   % weak  (~4.8 dB)
            pdHigh = localPd(100, trials, N, b, nt, ng);   % strong (~20 dB)
            tc.verifyGreaterThan(pdHigh, pdLow, ...
                'Detection probability did not increase with SNR.');
            tc.verifyGreaterThan(pdHigh, 0.90, ...
                'Strong target should be detected almost always.');
        end

        % ---- matched-filter / pulse-compression gain ----------------------
        function test_pulse_compression_gain(tc)
            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();                       % one PRI of samples (col)
            rng(3);
            n1 = 0.1*(randn(300,1)+1i*randn(300,1))/sqrt(2);
            n2 = 0.1*(randn(300,1)+1i*randn(300,1))/sqrt(2);
            rx = [n1; pulse; n2];
            rawRatio  = max(abs(rx).^2) / (median(abs(rx).^2) + eps);
            power     = radar.pulseCompress(rx, wav);
            compRatio = max(power) / (median(power) + eps);
            tc.verifyGreaterThan(compRatio, rawRatio, ...
                'Matched filter did not concentrate energy (no pulse-compression gain).');
        end

    end

end

% ===================== file-local helpers =============================
function tf = localHas(name)
    tf = ~isempty(which(name));
end

function pd = localPd(targetPow, trials, N, b, nt, ng)
%LOCALPD  Empirical detection probability at bin b over many noise trials.
    hits = 0;
    for t = 1:trials
        x = (randn(N,1) + 1i*randn(N,1)) / sqrt(2);
        p = abs(x).^2;
        p(b) = p(b) + targetPow;                 % add target power to that cell
        idx = radar.cfarDetect(p, 'Pfa', 1e-3, ...
                  'NumTraining', nt, 'NumGuard', ng);
        hits = hits + double(ismember(b, idx));
    end
    pd = hits / trials;
end
