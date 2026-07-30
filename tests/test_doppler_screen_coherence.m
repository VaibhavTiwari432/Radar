function tests = test_doppler_screen_coherence
%TEST_DOPPLER_SCREEN_COHERENCE  Pins the defect that made the D3QN untrainable,
%   and pins the fix.
%
%   THE CLAIM UNDER TEST. +agent/buildEnvFeatureConditioned.m has no slow-time
%   axis, so it synthesises the Doppler it hands to the ECCM:
%
%       dopSeq = diff(rngSeq)/dt;  dopSeq = [dopSeq(1), dopSeq];
%
%   +track/discriminator.m screen 2 then evaluates
%
%       sign(mean(diff(R))) == sign(mean(D))
%
%   Because D is built from diff(R), this is very nearly self-comparison. The
%   quantitative claim -- and the reason it matters for LEARNING rather than
%   just for tidiness -- is that its failure rate depends on the COHERENCE of
%   the policy:
%
%       * incoherent (sign-alternating) range walks CAN fail it
%       * coherent walks -- one direction held, i.e. what a converged policy
%         produces -- fail it 0% of the time
%
%   So the screen stops being able to punish the agent exactly as the agent
%   stops exploring. Half the ECCM verdict becomes free at convergence. That
%   is a reward-signal defect, not a cosmetic one, and no episode budget
%   fixes it.
%
%   Ref: BENCHMARK_RESULTS.md (Doppler tautology correction on the JUDGE
%   path, +engine/runJudge.m); this is the same defect surviving on the
%   TRAINING path.

    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    testCase.TestData.C = physics.Constants();
end

% =====================================================================
% 1. The defect: a coherent policy can never fail the legacy screen.
% =====================================================================
function test_legacy_screen_cannot_fail_under_coherent_policy(testCase)
    C = testCase.TestData.C;
    rng(7);
    deltaOptions = linspace(-120, 120, 5);
    F = 8; R0 = 1800; dt = 1.0;
    q = C.range_per_sample;

    nTrial = 4000;
    fails = 0; evaluated = 0;
    for t = 1:nTrial
        % COHERENT: one non-zero delta held for the whole episode.
        d = deltaOptions(randi([1 5]));
        if d == 0; continue; end
        r = R0; R = zeros(1, F);
        for k = 1:F
            r = min(2950, max(150, r + d));
            R(k) = round(r/q)*q;                       % CFAR quantisation
        end
        if range(R) < 1e-9; continue; end              % clamped flat
        dd = diff(R)/dt;  D = [dd(1), dd];             % the legacy construction
        if abs(mean(diff(R))) > 1e-9 && abs(mean(D)) > 1e-9
            evaluated = evaluated + 1;
            if sign(mean(diff(R))) ~= sign(mean(D)); fails = fails + 1; end
        end
    end

    verifyGreaterThan(testCase, evaluated, 100, ...
        'test is vacuous if the screen never even evaluated');
    verifyEqual(testCase, fails, 0, ...
        sprintf(['REGRESSION GUARD: the legacy diff(range)-as-Doppler screen ' ...
                 'failed %d/%d coherent episodes. It is supposed to be ' ...
                 'incapable of failing them -- if this now fails, the ' ...
                 'construction changed and the premise of ' ...
                 'agent.buildEnvDoppler should be re-derived.'], fails, evaluated));
end

% =====================================================================
% 2. The screen CAN fail on incoherent walks -- so the 0% above is a
%    property of coherence, not of a screen that never fires at all.
%    Without this the first test would also pass on a screen that was
%    simply dead, which is a different bug with the same symptom.
% =====================================================================
function test_legacy_screen_does_fire_on_incoherent_walks(testCase)
    C = testCase.TestData.C;
    rng(11);
    deltaOptions = linspace(-120, 120, 5);
    F = 8; R0 = 1800; dt = 1.0;
    q = C.range_per_sample;

    fails = 0; evaluated = 0;
    for t = 1:4000
        d = deltaOptions(randi(5, 1, F));               % INCOHERENT
        r = R0; R = zeros(1, F);
        for k = 1:F
            r = min(2950, max(150, r + d(k)));
            R(k) = round(r/q)*q;
        end
        if range(R) < 1e-9; continue; end
        dd = diff(R)/dt;  D = [dd(1), dd];
        if abs(mean(diff(R))) > 1e-9 && abs(mean(D)) > 1e-9
            evaluated = evaluated + 1;
            if sign(mean(diff(R))) ~= sign(mean(D)); fails = fails + 1; end
        end
    end

    verifyGreaterThan(testCase, fails, 0, ...
        ['the legacy screen must fail SOMETIMES on incoherent walks; a 0% ' ...
         'rate here would mean the screen is dead rather than tautological, ' ...
         'which is a different defect']);
end

% =====================================================================
% 3. The fix: a MEASURED range-rate that contradicts the range walk is
%    caught, because dopplerMeasured arms discriminator screen 2.
% =====================================================================
function test_measured_doppler_catches_kinematic_contradiction(testCase)
    C = testCase.TestData.C;
    R = 1800:60:2220;                       % OPENING: range increasing
    A = 2.0 ./ ((R/R(1)).^2);               % honest 1/R^2 amplitude ramp

    % Truthful: range-rate positive (opening), matching the range walk.
    honest = struct('range', R, 'amplitude', A, ...
                    'doppler', repmat(+60, 1, numel(R)), 'dopplerMeasured', true);
    verifyEqual(testCase, track.discriminator(honest, C), "real", ...
        'a phantom whose measured Doppler agrees with its range walk should pass');

    % Contradiction: range opening, Doppler says closing. Physically
    % impossible; the legacy env could not express this state at all.
    liar = honest; liar.doppler = repmat(-60, 1, numel(R));
    verifyEqual(testCase, track.discriminator(liar, C), "decoy", ...
        'a measured Doppler of the wrong SIGN must be caught');

    % Silent: range moving, no Doppler at all. Under dopplerMeasured=true
    % this is a contradiction, not missing evidence -- the hole that let a
    % phantom make the case against it inadmissible by declining to move.
    silent = honest; silent.doppler = zeros(1, numel(R));
    verifyEqual(testCase, track.discriminator(silent, C), "decoy", ...
        'zero measured Doppler on a moving range must score 0, not be skipped');

    % Same silent evidence WITHOUT the measured flag stays inadmissible --
    % proving the new behaviour comes from dopplerMeasured and that legacy
    % callers are untouched.
    legacySilent = rmfield(silent, 'dopplerMeasured');
    verifyEqual(testCase, track.discriminator(legacySilent, C), "real", ...
        ['a caller that never claimed to measure Doppler must keep its old ' ...
         'behaviour -- discriminator.m must not start flagging tracks on ' ...
         'evidence its caller never had']);
end
