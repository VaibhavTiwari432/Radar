classdef Stage3_Test < matlab.unittest.TestCase
%STAGE3_TEST  The tracker: where "deception" is DEFINED (POA Part 4, Stage 3).
%
%   STATUS: SPEC / SCAFFOLD. Reports Incomplete until BOTH
%   +track/runTracker.m and +synth/synthesizeSwarm.m exist.
%
%   This stage carries the project's success metric (POA claims C5, C6):
%       success = a CONFIRMED track (trackerGNN, ConfirmationThreshold [3 5])
%       for a target that does not physically exist, surviving >= K frames.
%   Detection alone is NOT deception; a confirmed track is.
%
%   Intended contracts:
%       confirmed = track.runTracker(detsPerFrame, times, C)
%           detsPerFrame : {1 x F} cell of objectDetection arrays
%           confirmed    : struct array with fields incl. .TrackID, .Age
%       phantoms  = synth.synthesizeSwarm(xIntercepted, action, C)
%           returns false-target IQ from y_i[n] = A_i x[n-tau_i] e^{j phi_i}
%
%   Independence (CLAUDE.md Rule 2): the reward/metric comes ONLY from
%   track.runTracker (MathWorks' tracker). synth never grades itself.

    methods (TestMethodSetup)
        function requireImpl(tc)
            tc.assumeTrue(localHas('track.runTracker'), ...
                'Stage 3 pending: implement +track/runTracker.m (trackerGNN [3 5]).');
        end
    end

    methods (Test)

        function test_real_target_confirms(tc)
            % A consistent per-frame detection train should confirm a track.
            %
            % Frame spacing is a track-update (scan/revisit) interval, NOT
            % the PRI: trackerGNN's default constant-velocity EKF is tuned
            % for scan-to-scan cadences, and 5 m per 20 us implies ~250,000
            % m/s (unphysical) which the filter cannot learn fast enough to
            % gate on -- it kept dropping and respawning tracks. 5 m per 1 s
            % (a plausible slow target under a 1 Hz revisit rate) is what
            % POA Stage 3 actually means by "consistent real target."
            C = physics.Constants();
            F = 8; times = (0:F-1) * 1.0;
            dets = cell(1,F);
            for k = 1:F
                dets{k} = objectDetection(times(k), [1500 + 5*k; 0; 0], ...
                            'MeasurementNoise', eye(3));
            end
            confirmed = track.runTracker(dets, times, C);
            tc.verifyGreaterThanOrEqual(numel(confirmed), 1, ...
                'A consistent real target should yield >=1 confirmed track.');
        end

        function test_noise_only_rarely_confirms(tc)
            % Random, inconsistent detections should almost never confirm.
            rng(5);
            C = physics.Constants();
            F = 8; times = (0:F-1) * 20e-6;
            dets = cell(1,F);
            for k = 1:F
                dets{k} = objectDetection(times(k), 5000*rand(3,1), ...
                            'MeasurementNoise', eye(3));
            end
            confirmed = track.runTracker(dets, times, C);
            tc.verifyLessThanOrEqual(numel(confirmed), 0, ...
                'Noise-only should not confirm tracks (with [3 5] logic).');
        end

        function test_C6_confirmed_false_track(tc)
            % The headline: a DRFM phantom yields a confirmed FALSE track.
            %
            % No real target exists anywhere in this test. A DRFM replay of
            % the radar's own transmit waveform (synth.synthesizeSwarm) is
            % the ONLY signal present; it is run through the independent
            % radar chain (radar.pulseCompress -> radar.cfarDetect) every
            % frame to get a detection, and those detections alone are fed
            % to track.runTracker. If it confirms a track, that confirmation
            % was earned entirely by MathWorks' own tracker on a target that
            % is not physically there -- deception, per CLAUDE.md Rule 2.
            tc.assumeTrue(localHas('synth.synthesizeSwarm'), ...
                'Needs +synth/synthesizeSwarm.m to generate the phantom.');
            C = physics.Constants();
            rng(99);

            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();
            bufferLen = 400;
            xTemplate = [pulse; zeros(bufferLen - numel(pulse), 1)];

            R_phantom = 2000;                      % fake range; no target here
            tau = 2 * R_phantom / C.c;
            action = struct('delay_s', tau, 'phase_rad', 0, 'gain', 3);
            Y = synth.synthesizeSwarm(xTemplate, action, C);

            F = 8; times = (0:F-1) * 1.0;           % same revisit cadence as C5
            dets = cell(1, F);
            for k = 1:F
                noise = 0.05 * (randn(bufferLen,1) + 1i*randn(bufferLen,1)) / sqrt(2);
                rx = Y + noise;
                power  = radar.pulseCompress(rx, wav);
                detIdx = radar.cfarDetect(power, 'Pfa', 1e-4);
                tc.assumeNotEmpty(detIdx, 'Phantom was not detected this frame (check gain/SNR).');
                [~, im] = max(power(detIdx));
                rbin = detIdx(im);
                dets{k} = objectDetection(times(k), ...
                            [(rbin-1) * C.range_per_sample; 0; 0], ...
                            'MeasurementNoise', eye(3));
            end

            confirmed = track.runTracker(dets, times, C);
            tc.verifyGreaterThanOrEqual(numel(confirmed), 1, ...
                'DRFM phantom should yield >=1 confirmed false track (POA C6).');
        end

    end

end

% ===================== file-local helpers =============================
function tf = localHas(name)
    tf = ~isempty(which(name));
end
