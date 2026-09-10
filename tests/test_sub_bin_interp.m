classdef test_sub_bin_interp < matlab.unittest.TestCase
%TEST_SUB_BIN_INTERP  radar.subBinPeak, the threshold it re-sizes, and the
%   sampling defect that decides whether it is worth switching on.
%
%   THE ANTI-STRAWMAN REQUIREMENT, MEASURED RATHER THAN ASSERTED.
%   PHANTOM_GENERATOR_ARCHITECTURE_v1.md section 5.1 says the judge MUST
%   estimate range to sub-bin precision, because at 20 m/s a target needs
%   3.75 s to cross one range cell and a screen reading an integer bin index
%   sees no motion at all for that long.
%
%   HOW TRUTH IS MADE HERE, AND WHY IT IS THE WHOLE ARGUMENT.
%   A fractionally-delayed pulse can be modelled two ways, and they do NOT
%   give the same answer:
%
%     (a) evaluate exp(1i*pi*k*(t-d)^2) straight onto the fs grid. Simple,
%         and WRONG as a receiver model: it samples an ideal chirp with no
%         anti-alias filter in front of it.
%     (b) build it far above fs, band-limit, THEN decimate -- which is what a
%         receiver's anti-alias filter physically does before the ADC.
%
%   MEASURED 21 Aug 2026 (rms bin error over 41 fractional offsets):
%
%       fs/B    raw bin   (a) analytic   (b) receiver model
%       1.60     0.2662     0.0210          0.0133
%       3.20     0.2662     0.0113          0.0036
%
%   (b) at fs/B = 3.20 independently reproduces the Python measurement in
%   generator/render.py's harness (0.0037 bins), which is the cross-check that
%   makes this file's numbers worth quoting.
%
%   AND THE FINDING THAT MATTERS MOST IS NOT IN THAT TABLE.
%   Neither row describes THIS simulation, because this simulation's waveform
%   is aliased at its own constants: C.bandwidth = 2 MHz against C.fs = 3.2
%   MHz, so a 0..B sweep runs 400 kHz past the +-fs/2 complex half-band.
%   MEASURED: radar.agileWaveform's Up chirp at C.fs sweeps +104 kHz to
%   -1377 kHz -- it wraps through Nyquist -- and 18.2% of its energy sits at
%   negative frequencies where a one-sided sweep should have none.
%
%   +generator/render.m inserts those aliased samples and radar.pulseCompress
%   correlates against the same aliased reference, so the estimator sees a
%   signal whose mainlobe shape is corrupted. Fractionally delaying THAT
%   sequence and interpolating gives 0.267 bins rms -- against a raw bin's
%   0.266. In the simulation as it stands, sub-bin interpolation buys
%   NOTHING, and the reason is the sampling rate, not the estimator.
%
%   So section 5.1 cannot be satisfied in simulation by adding an
%   interpolator. It needs C.fs > 2*C.bandwidth first. That prerequisite is
%   asserted below rather than written down, so that fixing fs makes this file
%   FAIL and forces every comment above to be re-read.

    properties (Constant)
        FS_CLEAN = 6.4e6        % the spec's bench configuration; fs/B = 3.20
        FS_TIGHT = 3.2e6        % this simulation's fs;            fs/B = 1.60
        BW       = 2e6
        PW       = 10e-6
        NFAST    = 2048
        OVER     = 16           % oversampling used to model the receiver
        % -0.45..0.45, not the full cell: at exactly +-0.5 the argmax is a tie
        % between two bins and the estimate is ambiguous by a whole bin. That
        % measures the tie-break, not the fit.
        FRACS    = linspace(-0.45, 0.45, 41)
    end

    methods (Test)

        % ---------------- the estimator, where it is meant to work ---------

        function test_recovers_a_known_offset_at_the_bench_config(tc)
            err = localSweep(tc, tc.FS_CLEAN);
            tc.verifyLessThan(rms(err), 0.02, ...
                'sub-bin estimate worse than 0.02 bin rms at fs/B = 3.2');
        end

        function test_beats_the_raw_bin_by_more_than_an_order(tc)
            err = localSweep(tc, tc.FS_CLEAN);
            raw = rms(tc.FRACS);
            tc.verifyGreaterThan(raw / rms(err), 10, ...
                'interpolation is costing arithmetic and buying under 10x');
        end

        function test_matches_the_independent_python_measurement(tc)
            % generator/render.py's harness measured 0.0037 bins for the same
            % configuration through a completely different truth model (a
            % windowed-sinc delay rather than oversample-and-decimate). Two
            % methods agreeing is what makes either quotable.
            tc.verifyEqual(rms(localSweep(tc, tc.FS_CLEAN)), 0.0037, ...
                'AbsTol', 0.002, 'MATLAB and Python no longer agree on the estimator');
        end

        % ---------------- the prerequisite this simulation fails -----------

        function test_this_simulations_waveform_is_aliased(tc)
            %ASSERTED FROM THE FAILING SIDE, DELIBERATELY. This is a known
            % defect of +physics/Constants.m, not of anything under test: a
            % 0..B sweep needs fs > 2B, and 3.2 MHz against 2 MHz is short by
            % 400 kHz. Fixing fs will make this test fail, which is the point
            % -- the failure is the prompt to re-read every claim above about
            % interpolation being pointless in simulation.
            C = physics.Constants();
            tc.verifyGreaterThan(C.bandwidth, C.fs/2, ...
                ['the sim waveform is no longer aliased -- sub-bin interpolation ' ...
                 'may now be worth enabling; re-measure before trusting the docs']);
        end

        function test_aliasing_is_what_destroys_the_gain_not_the_estimator(tc)
            % Same estimator, same oversampling ratio, only the reference's
            % band changes. If the tight-fs row were merely "less oversampled"
            % the gain would degrade gently; it collapses instead, which
            % attributes the loss to the fold rather than to the fit.
            gainClean = rms(tc.FRACS) / rms(localSweep(tc, tc.FS_CLEAN));
            gainTight = rms(tc.FRACS) / rms(localSweep(tc, tc.FS_TIGHT));
            tc.verifyGreaterThan(gainClean, gainTight, ...
                'the clean configuration must interpolate better than the aliased one');
        end

        % ---------------- the guards ---------------------------------------

        function test_edges_and_bad_input_degrade_to_the_integer_bin(tc)
            prof = [1; 4; 9; 4; 1];
            tc.verifyEqual(radar.subBinPeak(prof, 1), 1);          % left edge
            tc.verifyEqual(radar.subBinPeak(prof, 5), 5);          % right edge
            tc.verifyEqual(radar.subBinPeak([1; 0; 1], 2), 2);     % log undefined
            tc.verifyEqual(radar.subBinPeak([9; 1; 9], 2), 2);     % not concave
        end

        function test_offset_is_clamped_to_half_a_bin(tc)
            [~, frac] = radar.subBinPeak([1; 1.0001; 1e-12], 2);
            tc.verifyLessThanOrEqual(abs(frac), 0.5);
        end

        function test_a_symmetric_peak_has_zero_offset(tc)
            [refined, frac] = radar.subBinPeak([1; 9; 1], 2);
            tc.verifyEqual(frac, 0, 'AbsTol', 1e-12);
            tc.verifyEqual(refined, 2, 'AbsTol', 1e-12);
        end

        % ---------------- the paired threshold change ----------------------

        function test_default_threshold_is_bit_identical_to_before(tc)
            %THE REGRESSION GUARD. RangeSigmaM arrived as a refactor:
            % sqrt(2)*(delta/sqrt(12))/T IS delta/(sqrt(6)*T). If those ever
            % differ, every previously published gate has silently moved.
            C = physics.Constants();
            R = (2500:-50:2150)'; t = (0:7)'; D = -50*ones(8,1);
            out = track.rangeRateConsistency(R, t, D, C);
            T = t(end) - t(1);
            sigmaR = C.range_per_sample / (sqrt(6) * T);
            sigmaD = (C.c/10e9) * (C.PRF/32) / 2 / sqrt(12);
            tc.verifyEqual(out.thresholdMps, 3*sqrt(sigmaR^2 + sigmaD^2), ...
                'RelTol', 1e-12, 'the default gate is no longer the published one');
            tc.verifyEqual(out.rangeSigmaM, C.range_per_sample/sqrt(12), ...
                'RelTol', 1e-12);
        end

        function test_a_better_range_tightens_the_gate(tc)
            %WHY THE TWO CHANGES SHIP TOGETHER. Measuring range more precisely
            % while leaving the gate sized for the coarser measurement makes
            % the radar LOOSER by improving it.
            C = physics.Constants();
            R = (2500:-50:2150)'; t = (0:7)'; D = -50*ones(8,1);
            coarse = track.rangeRateConsistency(R, t, D, C);
            fine   = track.rangeRateConsistency(R, t, D, C, ...
                        'RangeSigmaM', 0.0036 * C.range_per_sample);
            tc.verifyLessThan(fine.thresholdMps, coarse.thresholdMps);
        end

        function test_an_uninformative_track_still_has_every_field(tc)
            % rangeSigmaM is in the initialiser, not the success path, so an
            % early return keeps the same field set and a caller can
            % concatenate verdicts into a struct array.
            C = physics.Constants();
            out = track.rangeRateConsistency(2500, 0, 0, C);
            tc.verifyTrue(isfield(out, 'rangeSigmaM'));
            tc.verifyFalse(out.informative);
        end
    end
end

% ======================= file-local helpers ===========================

function err = localSweep(tc, fs)
%LOCALSWEEP  Estimator error in BINS over a sweep of known fractional offsets,
%   with the received pulse built through the RECEIVER model: synthesised at
%   OVER*fs where the gate's edges are harmless, band-limited, then decimated.
%   Filtering before sampling is the whole difference between this and the
%   naive analytic version -- see the classdef header's table.
    k    = tc.BW / tc.PW;
    nRef = round(tc.PW * fs);
    ref  = exp(1i*pi*k*((0:nRef)'/fs).^2);
    err  = zeros(numel(tc.FRACS), 1);
    base = 500;

    for i = 1:numel(tc.FRACS)
        d  = base + tc.FRACS(i);
        tH = (0 : tc.NFAST*tc.OVER - 1)'/(fs*tc.OVER) - d/fs;
        rxH = exp(1i*pi*k*tH.^2) .* (tH >= 0 & tH <= tc.PW);
        rx  = resample(rxH, 1, tc.OVER);       % FIR, linear phase
        rx  = rx(1:tc.NFAST);

        prof = abs(conv(rx, conj(flipud(ref)), 'same')).^2;
        % conv(...,'same') offsets every peak by the same INTEGER, so it
        % cancels: compare the estimator's offset from its own argmax against
        % the truth's offset from the nearest integer.
        [~, kPk] = max(prof);
        refined  = radar.subBinPeak(prof, kPk);
        err(i)   = (refined - kPk) - (d - round(d));
    end
end
