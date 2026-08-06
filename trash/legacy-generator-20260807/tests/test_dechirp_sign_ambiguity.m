classdef test_dechirp_sign_ambiguity < matlab.unittest.TestCase
%TEST_DECHIRP_SIGN_AMBIGUITY  Task 4 (PHASE2_COMPLETION_POA.md): the
%   wrong-sign nominal case was untested until now -- only the correct-sign
%   nominal had ever been exercised (Integration_Report.md's own "Honest
%   caveats"). Deliberately constructing it found a REAL silent failure:
%   a wrong-sign nominal (true rate = -nominal) gave aliasingMargin=0.0091,
%   just above synthesizeTxPulse.m's aliasingMargin<=0 fallback gate, so
%   the old single-sign +features/characterizeInterceptDechirp.m would
%   silently commit to a wrong-signed chirp_rate_hz_s estimate instead of
%   either recovering or failing loudly.
%
%   Fixed by trying both signs of the caller-supplied nominal and keeping
%   the higher-quality match (characterizeInterceptDechirp.m's own header;
%   Integration_Report.md had already flagged this as the natural
%   extension, just not built). This test proves the fix, not just that
%   the function runs.

    methods (Test)

        function test_wrong_sign_nominal_still_recovers_true_rate(tc)
            C = physics.Constants();
            fs = C.fs;
            pulseWidthS = 12e-6; bandwidthHz = 2e6;   % this project's real waveform
            k0 = bandwidthHz / pulseWidthS;
            n = round(pulseWidthS * fs);
            t = (0:n-1)' / fs;
            trueChirp = exp(1i * pi * k0 * t.^2);      % TRUE rate is +k0

            nominalWrongSign.chirp_rate_hz_s = -k0;    % caller's prior has the WRONG sign
            nominalWrongSign.n_samples = n;

            p = features.characterizeInterceptDechirp(trueChirp, fs, nominalWrongSign);

            fprintf(['wrong-sign nominal: aliasingMargin=%.4f confidence=%.4f ' ...
                'k_est=%.6g (true=%.6g) sign_used=%d\n'], ...
                p.aliasingMargin, p.confidence, p.chirp_rate_hz_s, k0, p.sign_used);

            % "Handled correctly" (Task 4's definition of done), not merely
            % "failed loudly": the true rate is recovered despite the wrong
            % prior sign, and which sign actually matched is observable.
            tc.verifyEqual(p.chirp_rate_hz_s, k0, 'RelTol', 1e-6, ...
                'A wrong-sign nominal should still recover the TRUE chirp rate.');
            tc.verifyEqual(p.sign_used, -1, ...
                'sign_used should record that the caller-supplied nominal sign was overridden.');
            tc.verifyGreaterThan(p.aliasingMargin, 0.9);
            tc.verifyGreaterThan(p.confidence, 0.9);
        end

        function test_correct_sign_nominal_unaffected(tc)
            % Regression guard: trying both signs must not change behavior
            % for the already-validated correctly-signed case (the normal,
            % every-frame path every other test in this project depends on).
            C = physics.Constants();
            fs = C.fs;
            pulseWidthS = 12e-6; bandwidthHz = 2e6;
            k0 = bandwidthHz / pulseWidthS;
            n = round(pulseWidthS * fs);
            t = (0:n-1)' / fs;
            trueChirp = exp(1i * pi * k0 * t.^2);

            nominalCorrect.chirp_rate_hz_s = k0;
            nominalCorrect.n_samples = n;

            p = features.characterizeInterceptDechirp(trueChirp, fs, nominalCorrect);

            tc.verifyEqual(p.chirp_rate_hz_s, k0, 'RelTol', 1e-6);
            tc.verifyEqual(p.sign_used, 1);
            tc.verifyGreaterThan(p.aliasingMargin, 0.9);
            tc.verifyGreaterThan(p.confidence, 0.9);
        end

    end

end
