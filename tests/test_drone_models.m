function tests = test_drone_models
%TEST_DRONE_MODELS  T10 -- class-conditional combs from the four MEASURED
%   TSMS-Drone models. Checks that naming a model supplies its blade rate,
%   that an explicit rate still wins, that the rotorcraft/class mismatch is
%   caught rather than silently dropped, and -- the one that matters -- that
%   two different models actually render to two different combs.
%
%   Source of the rates: results/tsms_cw_analysis.mat, median over 15 ranges
%   x 25 cells. See +engine/+entity/EntityState.m for what transfers between
%   carriers and what does not.
    tests = functiontests(localfunctions);
end

function test_named_model_supplies_measured_rate(tc)
    expected = {'Inspire 2', 110; 'Matrice 30', 182; ...
                'Mavic 2 Pro', 100; 'Phantom 4 Pro', 200};
    for i = 1:size(expected, 1)
        s = engine.entity.EntityState('class', 'drone', 'model', expected{i,1});
        tc.verifyEqual(s.micro_doppler_hz, expected{i,2}, ...
            sprintf('%s should carry its measured blade rate', expected{i,1}));
    end
end

function test_explicit_rate_beats_the_table(tc)
    % Naming a model SUPPLIES the measurement; it does not overrule a caller
    % who stated a rate deliberately.
    s = engine.entity.EntityState('class', 'drone', 'model', 'Mavic 2 Pro', ...
        'micro_doppler_hz', 137);
    tc.verifyEqual(s.micro_doppler_hz, 137);
end

function test_unnamed_model_changes_nothing(tc)
    a = engine.entity.EntityState('class', 'drone', 'micro_doppler_hz', 100);
    tc.verifyEqual(a.micro_doppler_hz, 100);
    tc.verifyEmpty(a.model);
    b = engine.entity.EntityState();          % the pre-T10 default path
    tc.verifyEqual(b.micro_doppler_hz, 0);
end

function test_bad_model_and_class_mismatch_fail_fast(tc)
    tc.verifyError(@() engine.entity.EntityState('class', 'drone', ...
        'model', 'Mavic 3 Pro'), 'engine:entity:badModel');
    % A rotorcraft mislabelled 'fighter' renders NO comb at all -- the
    % measurement would vanish silently. Must throw.
    tc.verifyError(@() engine.entity.EntityState('class', 'fighter', ...
        'model', 'Inspire 2'), 'engine:entity:modelClassMismatch');
end

function test_two_models_render_distinguishable_combs(tc)
    % The point of the whole task: different measured models must produce
    % different spectra, not just different struct fields.
    %
    % ============ PHASE 1.5 -- REKEYED ON COMB SPACING ============
    % This test used to assert PEAK POSITION == blade rate. That assertion
    % was only ever true by under-resolution, and the corrected 8 kHz PRF
    % exposed it. Two facts, both derived, neither guessed:
    %
    %  1. The modulation index beta = 2*v_tip/(lambda*f_blade) does NOT
    %     depend on the PRF -- v_tip, lambda and f_blade are all
    %     PRF-independent. beta was IDENTICAL at 50 kHz. Nothing about the
    %     comb's amplitude distribution changed; only our ability to see it.
    %
    %  2. exp(i*beta*sin(wt)) = SUM_n J_n(beta) exp(i n w t), so line n
    %     carries J_n(beta)^2. At this project's measured v_tip = 4.55 m/s:
    %
    %       Mavic 2 Pro   f=100 Hz -> beta 3.035 -> J_1^2 0.106, J_2^2 0.237
    %                                            -> DOMINANT LINE IS n=2, 200 Hz
    %       Phantom 4 Pro f=200 Hz -> beta 1.518 -> J_1^2 0.314, J_2^2 0.056
    %                                            -> dominant line is n=1, 200 Hz
    %
    %     BOTH MODELS PEAK AT 200 Hz. Peak position cannot distinguish them
    %     even in principle. At 50 kHz the 512-pulse dwell had 97.7 Hz bins,
    %     so the Mavic's 100 Hz and 200 Hz lines fell in adjacent bins and
    %     the blur landed on 100 Hz -- the old test passed by accident.
    %
    % COMB SPACING is the invariant: it is the blade-passage rate itself, a
    % mechanical property, independent of beta and of which harmonic happens
    % to be strongest. Mavic 100 Hz vs Phantom 200 Hz -- distinguishable.
    prf = physics.Constants().PRF;

    % TOLERANCE, DERIVED. Spacing is the difference of two bin-quantised
    % peak positions, so its worst-case error is ONE FFT bin (each peak
    % rounds within +-0.5 bin). Bin width is prf/nPulses, so to land inside
    % a 5 Hz tolerance the dwell must satisfy nPulses >= prf/5 = 1600.
    nPulses = 2048;                       % -> bin = 3.906 Hz <= 5 Hz
    binHz = prf / nPulses;
    tc.assertLessThanOrEqual(binHz, 5, ...
        'Dwell too short: one FFT bin exceeds the 5 Hz spacing tolerance.');
    fprintf(['\n[T1] dwell %d pulses at PRF %.0f Hz -> FFT bin %.3f Hz\n' ...
             '[T1] spacing tolerance = 1 bin = %.3f Hz (derived, not chosen)\n'], ...
             nPulses, prf, binHz, binHz);

    models = {'Mavic 2 Pro', 100; 'Phantom 4 Pro', 200};
    peaks = zeros(1, size(models,1));
    for i = 1:size(models,1)
        name = models{i,1}; fRot = models{i,2};
        [spacing, lines, peakHz] = localCombSpacing(name, nPulses, prf);
        peaks(i) = peakHz;
        fprintf(['[T1] %-14s f_rot %3d Hz | comb lines [%s] Hz | ' ...
                 'spacing %.2f Hz | STRONGEST line %.1f Hz\n'], ...
                 name, fRot, strjoin(compose('%.0f', lines), ' '), spacing, peakHz);
        tc.verifyEqual(spacing, fRot, 'AbsTol', binHz, sprintf( ...
            '%s: measured comb spacing %.2f Hz is not its blade rate %d Hz', ...
            name, spacing, fRot));
    end

    % THE POINT OF THE REKEY, ASSERTED: both models peak at the same line, so
    % the old peak-based test could not have discriminated them even with a
    % perfect dwell. Spacing (100 vs 200 Hz) does.
    fprintf('[T1] strongest line: Mavic %.1f Hz | Phantom %.1f Hz -> identical\n', ...
        peaks(1), peaks(2));
    tc.verifyEqual(peaks(1), peaks(2), 'AbsTol', binHz, ...
        ['The two models no longer peak at the same line. That would mean beta ' ...
         'or v_tip moved -- re-derive the Bessel table in this comment.']);
end

% ------------------------------------------------------------------------
function [spacing, lines, peakHz] = localCombSpacing(name, nPulses, prf)
%LOCALCOMBSPACING  Micro-Doppler comb SPACING (Hz) of the named model.
%   Returns the median gap between adjacent comb lines -- the blade-passage
%   rate itself -- plus the located lines and the strongest one, so a caller
%   can report peak position without depending on it.
    [S, ax, binHz] = localCombSpacingRaw(name, nPulses, prf);

    % Locate comb lines: local maxima standing clearly above the floor. The
    % threshold is the spectrum's own median times a margin, so it adapts to
    % however much power the entity happens to have -- no absolute level.
    thresh = 8 * median(S);
    isPeak = [false, S(2:end-1) > S(1:end-2) & S(2:end-1) > S(3:end), false] & S > thresh;
    pos = ax > 0 & isPeak;                       % positive half; comb is symmetric
    lines = sort(ax(pos));
    assert(numel(lines) >= 2, ...
        '%s: found %d comb line(s) above threshold; need >= 2 to measure a spacing', ...
        name, numel(lines));

    % MEDIAN gap, not lines(2)-lines(1): if one harmonic happens to fall
    % below threshold (J_n(beta) has zeros), a single difference would
    % report 2x the true spacing. The median over all adjacent gaps is
    % robust to a missing line the way a single difference is not.
    gaps = diff(lines);
    spacing = median(gaps);
    [~, k] = max(S(pos));
    peakHz = lines(k);
    if binHz > spacing   % guard: cannot resolve a comb finer than one bin
        error('localCombSpacing:unresolvable', ...
            '%s: bin %.2f Hz exceeds spacing %.2f Hz', name, binHz, spacing);
    end
end

function [S, ax, binHz] = localCombSpacingRaw(name, nPulses, prf)
%LOCALCOMBSPACINGRAW  Slow-time spectrum of a STATIONARY entity of the named
%   model, body line blanked. Stationary so the body Doppler sits at 0 and
%   does not compete with the comb.
    s = engine.entity.EntityState('class', 'drone', 'model', name, ...
        'range_rate_mps', 0, 'swerling', 0);
    cube = engine.entity.render(s, 'NumPulses', nPulses, 'PrfHz', prf, ...
        'CarrierHz', 10e9, 'RandStream', RandStream('twister', 'Seed', 11));
    [~, rb] = max(sum(abs(cube), 2));
    % Hann window: the rectangular record's leakage floors the weak outer
    % lines, and the peak-finder would then measure the window, not the comb.
    w = hann(nPulses).';
    S = abs(fftshift(fft(cube(rb, :) .* w)));
    binHz = prf / nPulses;
    ax = (-nPulses/2 : nPulses/2-1) * binHz;
    S(abs(ax) < 2*binHz) = 0;          % blank DC / the body line
end
