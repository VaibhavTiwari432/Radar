classdef test_fractional_delay_render < matlab.unittest.TestCase
%TEST_FRACTIONAL_DELAY_RENDER  generator.fracDelayKernel, and the staircase it
%   removes from +generator/render.m.
%
%   WHY THIS EXISTS. render.m has always placed each phantom at
%   round(2R/c * fs). One sample is 46.84 m in this simulation, so a target
%   moving slower than one cell per revisit holds a FROZEN apparent range and
%   then jumps a whole cell. That is a staircase where the physics says ramp,
%   on the exact observable the range-rate screens integrate -- and it is
%   indistinguishable from a repeater that cannot resolve its own trajectory.
%
%   IT ALSO DECIDES WHETHER THE SPEC'S V3 TABLE HAS AN ARM A AT ALL.
%   PHANTOM_GENERATOR_ARCHITECTURE_v1.md's ablation lists arm B as "fractional
%   delay -> integer". With rounding permanently on, arm B *is* the baseline
%   and there is nothing to ablate against; the row would compare a thing to
%   itself.
%
%   TWO IMPLEMENTATIONS, ONE DEFINITION. generator/render.py carries the same
%   17-tap Kaiser kernel for the hardware path. Two copies exist because
%   render.m must build its own IQ in MATLAB (the same reason
%   +radar/agileWaveform.m gives for never reimplementing the chirp in
%   Python). The first test below binds them by calling the Python one
%   directly, so they are two implementations of one definition rather than
%   two definitions that will drift.

    methods (Test)

        % ---------------- the kernel ---------------------------------------

        function test_kernel_matches_the_python_one(tc)
            % startup.m puts generator/ on the Python path for exactly this.
            try
                pyMod = py.importlib.import_module('generator.render');
            catch err
                tc.assumeFail(['Python bridge unavailable: ' err.message]);
            end
            for mu = [-0.5, -0.17, 0, 0.25, 0.49]
                mine   = generator.fracDelayKernel(mu);
                theirs = double(py.array.array('d', ...
                            pyMod.frac_delay_kernel(mu).tolist()));
                tc.verifyEqual(mine(:), theirs(:), 'AbsTol', 1e-12, ...
                    sprintf('MATLAB and Python kernels disagree at mu = %+.2f', mu));
            end
        end

        function test_kernel_has_unit_dc_gain(tc)
            % Gain ~= 1 would put a constant offset on log(A) and tilt the very
            % slope the amplitude screen fits.
            for mu = [-0.5, -0.1, 0, 0.3, 0.49]
                tc.verifyEqual(sum(generator.fracDelayKernel(mu)), 1, ...
                    'RelTol', 1e-12);
            end
        end

        function test_even_taps_are_refused(tc)
            tc.verifyError(@() generator.fracDelayKernel(0.25, 16), ...
                'generator:fracDelayKernel:evenTaps');
        end

        function test_zero_offset_is_very_nearly_a_delta(tc)
            h = generator.fracDelayKernel(0);
            [~, k] = max(abs(h));
            tc.verifyEqual(k, 9);                       % centre tap of 17
            tc.verifyGreaterThan(h(9), 0.99);
        end

        % ---------------- the placement, through the real renderer ---------

        function test_default_is_unchanged_and_lands_on_a_whole_sample(tc)
            %THE REGRESSION GUARD. FractionalDelay defaults false, so every
            % scene in this repo must still put its phantom exactly where
            % round() would.
            [prof, wantBin] = localPeakProfile(tc, false);
            [~, kPk] = max(prof);
            tc.verifyEqual(kPk, wantBin, ...
                'the default path no longer rounds; published scenes have moved');
            [~, frac] = radar.subBinPeak(prof, kPk);
            tc.verifyLessThan(abs(frac), 0.05, ...
                'a rounded delay should sit on the bin centre');
        end

        function test_fractional_delay_lands_between_bins(tc)
            %THE PAYOFF. The same phantom, at a range chosen to fall half a
            % sample off a bin centre, must now measure half a bin off -- which
            % is only visible because radar.subBinPeak exists to see it.
            [prof, ~, wantFrac] = localPeakProfile(tc, true);
            [~, kPk] = max(prof);
            [~, frac] = radar.subBinPeak(prof, kPk);
            tc.verifyEqual(frac, wantFrac, 'AbsTol', 0.15, ...
                'the sub-sample remainder did not reach the rendered signal');
        end

        function test_the_staircase_disappears(tc)
            %THE ARTIFACT, BOTH WAYS. A slow target's apparent range must move
            % EVERY frame under fractional delay, and in whole-cell jumps
            % without it. Asserted from both sides, because a test that only
            % showed the smooth case could not tell "fixed" from "the target
            % was never slow enough to stair".
            stepInt  = localFrameSteps(tc, false);
            stepFrac = localFrameSteps(tc, true);
            tc.verifyGreaterThan(nnz(stepInt == 0), 0, ...
                'the integer path never froze, so there is no staircase to remove');
            tc.verifyEqual(nnz(stepFrac == 0), 0, ...
                'the fractional path still freezes -- the remainder is being lost');
        end
    end
end

% ======================= file-local helpers ===========================

function [prof, wantBin, wantFrac] = localPeakProfile(tc, useFrac) %#ok<INUSL>
%LOCALPEAKPROFILE  Render ONE static phantom and return its compressed range
%   profile, plus where it was asked to be. The range is deliberately chosen
%   to sit 0.5 samples off a bin centre so the two paths must disagree.
    C = physics.Constants();
    halfSample = C.range_per_sample / 2;
    R = 40 * C.range_per_sample + halfSample;      % x.5 samples, by construction
    wantExact = 2*R/C.c * C.fs;
    wantBin   = round(wantExact) + 1;              % MATLAB 1-based
    wantFrac  = wantExact - round(wantExact);

    out = renderPhantomScene(R, 0, 'NumFrames', 2, 'NumPulses', 4, ...
             'MotherRangeM', 300, 'ApplyVetoes', false, ...
             'NoiseAmplitude', 1e-9, 'FractionalDelay', useFrac, ...
             'Tag', sprintf('fd_static_%d', useFrac));
    S = load(out);
    wav = radar.agileWaveform(+1, C.fs, C.pulse_width, C.PRF, C.bandwidth);
    prof = radar.pulseCompress(S.rx_frames(:, 1, 1), wav);
end

function steps = localFrameSteps(tc, useFrac) %#ok<INUSL>
%LOCALFRAMESTEPS  Per-frame change in the MEASURED peak position for a target
%   too slow to cross a range cell each revisit. Integer delay freezes it;
%   fractional delay must not.
    C = physics.Constants();
    out = renderPhantomScene(2000, -10, 'NumFrames', 6, 'NumPulses', 4, ...
             'MotherRangeM', 300, 'ApplyVetoes', false, ...
             'NoiseAmplitude', 1e-9, 'FractionalDelay', useFrac, ...
             'Tag', sprintf('fd_walk_%d', useFrac));
    S = load(out);
    wav = radar.agileWaveform(+1, C.fs, C.pulse_width, C.PRF, C.bandwidth);
    nF = size(S.rx_frames, 3);
    pos = zeros(nF, 1);
    for k = 1:nF
        prof = radar.pulseCompress(S.rx_frames(:, 1, k), wav);
        [~, kPk] = max(prof);
        pos(k) = radar.subBinPeak(prof, kPk);
    end
    steps = round(diff(pos), 6);
end
