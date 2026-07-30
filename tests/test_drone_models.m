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
    % different spectra, not just different struct fields. Mavic 2 Pro
    % (100 Hz) vs Phantom 4 Pro (200 Hz) at a dwell long enough to resolve
    % them -- 512 pulses at 50 kHz PRF, the T8 dwell.
    nPulses = 512; prf = 50e3;
    peakHz = @(name) localCombPeak(name, nPulses, prf);
    tc.verifyEqual(peakHz('Mavic 2 Pro'),   100, 'AbsTol', prf/nPulses);
    tc.verifyEqual(peakHz('Phantom 4 Pro'), 200, 'AbsTol', prf/nPulses);
end

% ------------------------------------------------------------------------
function f = localCombPeak(name, nPulses, prf)
%LOCALCOMBPEAK  Strongest non-zero micro-Doppler line, in Hz, of a
%   stationary entity of the named model. Stationary so the body Doppler
%   sits at 0 and does not compete with the comb.
    s = engine.entity.EntityState('class', 'drone', 'model', name, ...
        'range_rate_mps', 0, 'swerling', 0);
    cube = engine.entity.render(s, 'NumPulses', nPulses, 'PrfHz', prf, ...
        'CarrierHz', 10e9);
    % Slow-time spectrum of the range bin holding the target.
    [~, rb] = max(sum(abs(cube), 2));
    S = abs(fftshift(fft(cube(rb, :))));
    ax = (-nPulses/2 : nPulses/2-1) * (prf / nPulses);
    S(abs(ax) < prf/nPulses) = 0;      % blank DC / the body line
    [~, k] = max(S);
    f = abs(ax(k));
end
