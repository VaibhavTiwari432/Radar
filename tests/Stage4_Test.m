classdef Stage4_Test < matlab.unittest.TestCase
%STAGE4_TEST  Physics-correctness pass (POA Part 4, Stage 4; claim C3).
%
%   STATUS: CORE IS RUNNABLE NOW (pure derivations, no toolbox). The full
%   phased.* transmit/receive round-trip is a guarded scaffold.
%
%   Enforces CLAUDE.md Rule 1: every metre/velocity derives from c, fs, PRI.
%   No magic constants -- this is the test that would catch the old
%   "390.6 m/sample" fabrication.

    methods (TestClassSetup)
        function addProjectPath(~)
            here = fileparts(mfilename('fullpath'));
            addpath(fileparts(here));   % project root, so +physics resolves
        end
    end

    methods (Test)

        % ---------- runnable now ----------
        function test_physics_validators_all_pass(tc)
            checks = physics.Validators();
            for i = 1:numel(checks)
                tc.verifyTrue(checks(i).pass, sprintf( ...
                    'Physics check failed: %s (got %.6g, want %.6g, tol %.2g).', ...
                    checks(i).name, checks(i).got, checks(i).want, checks(i).tol));
            end
        end

        function test_delay_range_roundtrip(tc)
            % R -> two-way delay -> samples -> back to R must be identity.
            C = physics.Constants();
            for R = [500 1500 2400 12000]
                tau   = 2*R / C.c;                 % two-way delay [s]
                nSamp = tau / C.Ts;                % delay in fast-time samples
                Rhat  = nSamp * C.range_per_sample;
                tc.verifyEqual(Rhat, R, 'AbsTol', 1e-6, sprintf( ...
                    'Range round-trip broke at R=%g m (got %.6g).', R, Rhat));
            end
        end

        function test_ambiguity_ordering(tc)
            % Unambiguous range (from PRI) must be smaller than the full
            % 512-sample window -- i.e. the record can be range-ambiguous.
            C = physics.Constants();
            tc.verifyLessThan(C.Rua_max, C.range_window, ...
                'Rua_max should be < the 512-sample range window.');
        end

        % ---------- full signal-chain round-trip ----------
        function test_full_chain_range_roundtrip(tc)
            % Place a real phased.RadarTarget at range R, propagate the
            % transmit pulse out and back via two phased.FreeSpace legs
            % (monostatic: same tx/rx position), recover R from the
            % pulse-compressed peak, and assert |Rhat-R| < 1 range cell.
            % This is the noiseless ground-truth check that radar.pulseCompress's
            % delay compensation (added for this claim) is physically correct,
            % independent of radar.rangeDoppler.
            tc.assumeTrue(localHas('phased.FreeSpace'), ...
                'Phased Array System Toolbox (phased.FreeSpace) required.');

            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();
            Lp = numel(pulse);

            fc = 10e9;   % X-band, representative surveillance-radar carrier (8-12 GHz, IEEE)
            channel = phased.FreeSpace('SampleRate', C.fs, 'OperatingFrequency', fc);
            target  = phased.RadarTarget('MeanRCS', 1, 'OperatingFrequency', fc);
            origin = [0;0;0]; zeroVel = [0;0;0];

            for R = [500 1500 2400 3000]
                tauSamples = round(2*R / C.c * C.fs);
                bufferLen  = tauSamples + Lp + 20;
                txsig = [pulse; zeros(bufferLen - Lp, 1)];
                tgtPos = [R;0;0];

                outbound  = channel(txsig, origin, tgtPos, zeroVel, zeroVel);
                reflected = target(outbound);
                received  = channel(reflected, tgtPos, origin, zeroVel, zeroVel);

                power = radar.pulseCompress(received, wav);
                [~, peakIdx] = max(power);
                Rhat = (peakIdx-1) * C.range_per_sample;

                tc.verifyLessThan(abs(Rhat - R), C.range_per_sample, sprintf( ...
                    'Round-trip range recovery failed at R=%g m (got Rhat=%.2f m, tol=%.2f m).', ...
                    R, Rhat, C.range_per_sample));
            end
        end

    end

end

% ===================== file-local helpers =============================
function tf = localHas(name)
    tf = ~isempty(which(name));
end
