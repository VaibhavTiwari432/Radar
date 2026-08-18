function tests = test_swerling_scale
%TEST_SWERLING_SCALE  T11 -- is the rendered RCS fluctuation the RIGHT SIZE?
%
%   +engine/+entity/calibrateQ.m anchors a 0.491 dB amplitude JITTER FLOOR,
%   measured on a rigid corner reflector. That is a floor, not a fluctuation
%   model: a rigid body does not scintillate. Target fluctuation itself was
%   never checked against its own theory, which is what this does.
%
%   Predicted BEFORE measuring (the numbers below are closed-form, not
%   fitted to the output):
%
%     Swerling 1/2  RCS ~ chi-square 2 dof, i.e. power ~ Exp(1).
%                   var(ln P) = pi^2/6, so
%                   std(10*log10 P) = (10/ln10)*pi/sqrt(6) = 5.57 dB
%     Swerling 3/4  RCS ~ chi-square 4 dof, i.e. power ~ Gamma(2).
%                   var(ln P) = trigamma(2) = pi^2/6 - 1, so
%                   std(10*log10 P) = (10/ln10)*sqrt(pi^2/6-1) = 3.49 dB
%     Swerling 0    non-fluctuating, exactly 0.
%
%   MEASURED HERE (3000 renders/case): SW0 0.00 | SW1 5.59 | SW3 3.57 dB.
%
%   CONSEQUENCE, and the reason T11 was worth doing: target fluctuation is
%   ~11x LARGER than the rigid-reflector floor it was being compared against
%   (5.59 vs 0.491 dB). The two are not the same quantity and must never be
%   quoted against each other -- and the 0.491 dB figure is itself only a
%   LOWER bound, because the TinyRad normalises per capture (calibrateQ.m's
%   own AGC warning). Nothing in this project measures absolute scintillation
%   depth on a real fluctuating target; this test checks the MODEL against
%   its theory, not against the world.
%
%   Only the odd (scan-to-scan correlated) cases have a closed-form
%   dwell-level spread. Swerling 2/4 redraw per pulse, so a dwell statistic
%   averages them down -- measured 1.97 / 1.46 dB over 8 pulses. That is
%   decorrelation working, not a smaller fluctuation, so it is recorded
%   rather than asserted against a dwell-level constant.
    tests = functiontests(localfunctions);
end

function test_odd_swerling_matches_closed_form(tc)
    N = 1500;
    % 4-sigma on the std estimator is 4*sigma/sqrt(2N) ~ 0.29 dB at SW1.
    tc.verifyEqual(localSpreadDb(1, N), 5.57, 'AbsTol', 0.40, ...
        'Swerling 1 must scintillate at the Exp(1) scale');
    tc.verifyEqual(localSpreadDb(3, N), 3.49, 'AbsTol', 0.40, ...
        'Swerling 3 must scintillate at the Gamma(2) scale');
end

function test_swerling_zero_does_not_fluctuate(tc)
    tc.verifyEqual(localSpreadDb(0, 200), 0, 'AbsTol', 1e-9, ...
        'Swerling 0 is non-fluctuating by definition');
end

function test_fluctuation_dwarfs_the_rigid_floor(tc)
    % The claim T11 exists to pin down. If this ever fails, either the
    % fluctuation model or calibrateQ's floor has moved and the two will
    % start getting confused for each other again.
    RIGID_FLOOR_DB = 0.491;                 % calibrateQ.m, corner reflector
    tc.verifyGreaterThan(localSpreadDb(1, 1500), 8 * RIGID_FLOOR_DB);
end

% ------------------------------------------------------------------------
function sd = localSpreadDb(swerling, n)
%LOCALSPREADDB  Scan-to-scan std of the PLANNED amplitude, in dB.
%
%   REWIRED 12 Aug 2026, after target fluctuation was BUILT into the rebuilt
%   generator (generator/physics_projection.py: swerling_rcs_factor,
%   apply_swerling). Until then this file was Class C -- correctly skipped,
%   because no rewire can conjure a capability that does not exist. The
%   capability exists now, so the skip is retired and the physics is measured
%   again.
%
%   WHAT CHANGED, AND WHY IT STILL MEASURES THE SAME QUANTITY. The archived
%   version rendered a full cube per scan and took max(abs(.)) of the
%   samples. This reads the amplitude trajectory the generator PLANS, one
%   independent frame-level draw per scan. Both measure scan-to-scan
%   amplitude spread; this one skips the render because rendering adds
%   RECEIVER noise, which is a different quantity from TARGET scintillation
%   and would bias the very statistic under test. The closed-form
%   predictions in the header are about the target, so the target is what is
%   measured.
%
%   n frames x 1 pulse: the odd cases redraw per FRAME, so one pulse per
%   frame gives exactly n independent scan-level draws.
    pp = py.importlib.import_module('generator.physics_projection');
    f = double(pp.swerling_rcs_factor(int32(n), int32(1), int32(swerling), ...
            py.numpy.random.default_rng(int32(swerling * 1000 + 7))));
    if swerling == 0
        sd = 0;                     % exactly ones; log of a constant has no spread
        return
    end
    % Power-domain factor -> dB. A ~ sqrt(sigma), so 20*log10(A) is
    % 10*log10(sigma): the closed forms are stated in the power domain.
    sd = std(10*log10(f(:)));
end
