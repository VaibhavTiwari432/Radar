classdef test_feature_integration < matlab.unittest.TestCase
%TEST_FEATURE_INTEGRATION  Baseline (generic replay) vs feature-matched
%   (characterize -> coherent replica) synthesis, compared on the SAME
%   judge chain (radar.pulseCompress -> radar.cfarDetect -> track.runTracker
%   -> track.discriminator).
%
%   STATUS: full story, honestly reported end to end (CLAUDE.md Rule 7):
%
%   1. test_blind_estimator_aliases_on_project_waveform -- the project's
%      ACTUAL waveform (SweepBandwidth=2e6 Hz at fs=3.2e6 Hz) aliases
%      features.characterizeIntercept's blind phase-differencing (its
%      instantaneous frequency crosses +Nyquist partway through the
%      39-sample pulse -- verified on the clean, noiseless signal, so this
%      is a real Nyquist limit, not a noise-sensitivity bug).
%
%   2. test_dechirp_estimator_fixes_project_waveform -- the FIX:
%      features.characterizeInterceptDechirp uses the KNOWN nominal chirp
%      rate (this project's "known radar" premise) to dechirp first, which
%      is Nyquist-safe and correctly recovers wclass='lfm' with high
%      confidence on the SAME waveform.
%
%   3. test_nyquist_compliant_waveform_shows_real_benefit -- the blind
%      estimator's OWN valid regime (BW < fs/2, matching
%      cognitive_engine's test suite): a 4x+ pulse-compression benefit,
%      confirming the underlying mechanism works.
%
%   4. test_feature_matched_confirms_reliably_at_high_intercept_noise --
%      feature-matched synthesis is now the SOLE path agent.buildEnvWithFeatures
%      can produce (mission: "remove the generic/baseline path as a
%      caller-facing option everywhere"), so this test verifies it directly
%      rather than comparing against a 'generic' mode this function can no
%      longer build. THE ORIGINAL generic-vs-feature-matched comparison that
%      established the mission's success criterion (confirmation rate 0%
%      baseline -> 100% feature-matched, same scene/noise) is preserved,
%      frozen, in tests/historical_baseline/test_synthesis_mode_comparison_matlab.m
%      -- not deleted, just no longer reproducible via the active,
%      single-mode agent.buildEnvWithFeatures. At LOWER noise (0.02-0.5,
%      tried first) the benefit is real at the signal level (compression
%      ratio 1.00x-1.1x) but too small to flip any downstream CFAR/tracker
%      decision -- reported as such, not hidden.
%
%      Also verifies the confidence gate (+features/synthesizeTxPulse.m)
%      does NOT fire (degradedEvent is empty) at this same canonical noise
%      level -- the fallback exists for structural characterization failure,
%      not ordinary high noise, and should stay near-zero here.

    methods (Test)

        function test_blind_estimator_aliases_on_project_waveform(tc)
            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();
            activePulse = pulse(1:numel(getMatchedFilter(wav)));

            wp = features.characterizeIntercept(activePulse, C.fs);
            tc.verifyNotEqual(wp.wclass, 'lfm', ...
                ['Expected the project''s actual 2 MHz-bandwidth waveform to ALIAS the blind ' ...
                 'phase-based IF estimator (documented Nyquist limit) -- if this now says lfm, ' ...
                 're-verify Integration_Report.md before trusting the blind estimator here.']);
            fprintf('Blind estimator on project waveform: wclass=%s confidence=%.4f (EXPECTED misclassification -- Nyquist)\n', ...
                wp.wclass, wp.confidence);
        end

        function test_dechirp_estimator_fixes_project_waveform(tc)
            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();
            activePulse = pulse(1:numel(getMatchedFilter(wav)));

            rng(1);
            noisyIntercept = activePulse + 0.5*(randn(size(activePulse))+1i*randn(size(activePulse)))/sqrt(2);
            nominal.chirp_rate_hz_s = 2e6 / 12e-6;
            nominal.n_samples = numel(noisyIntercept);

            wp = features.characterizeInterceptDechirp(noisyIntercept, C.fs, nominal);
            tc.verifyEqual(wp.wclass, 'lfm', ...
                'Dechirping against the known nominal rate should recover lfm on the project waveform.');
            tc.verifyLessThan(abs(wp.chirp_rate_hz_s - nominal.chirp_rate_hz_s) / nominal.chirp_rate_hz_s, 0.01, ...
                'Recovered chirp rate should be within 1% of the (correct) nominal.');
            fprintf('Dechirp estimator on project waveform: wclass=%s confidence=%.4f k_est=%.4e (FIXED)\n', ...
                wp.wclass, wp.confidence, wp.chirp_rate_hz_s);
        end

        function test_nyquist_compliant_waveform_shows_real_benefit(tc)
            fs = 3.2e6;
            pulseWidthS = 12e-6;
            bwHz = 800e3;             % < fs/2=1.6e6: Nyquist-compliant, matches
                                       % cognitive_engine's own validated test regime
            n = round(pulseWidthS * fs);
            t = (0:n-1)' / fs;
            kTrue = bwHz / pulseWidthS;
            cleanChirp = exp(1i*pi*kTrue*t.^2);
            cleanChirp = cleanChirp / sqrt(sum(abs(cleanChirp).^2));

            rng(12345);
            interceptNoiseAmp = 0.02;
            noisyIntercept = cleanChirp + interceptNoiseAmp * (randn(n,1)+1i*randn(n,1))/sqrt(2);

            wp = features.characterizeIntercept(noisyIntercept, fs);
            tc.verifyEqual(wp.wclass, 'lfm', ...
                'Nyquist-compliant intercept should classify confidently as lfm.');
            tc.verifyGreaterThan(wp.confidence, 0.6);
            tc.verifyLessThan(abs(wp.chirp_rate_hz_s - kTrue)/kTrue, 0.10, ...
                'Recovered chirp rate should be within 10% of truth.');

            replicaMatched = features.coherentReplica(wp, fs, n);
            genericParams = struct('wclass','tone','f0_hz',0,'bandwidth_hz',NaN, ...
                'chirp_rate_hz_s',NaN,'pulse_width_s',NaN,'n_samples',n,'confidence',NaN);
            replicaGeneric = features.coherentReplica(genericParams, fs, n);

            mfPeak = @(sig, tmpl) max(abs(conv(sig, conj(flipud(tmpl)))));
            pkMatched = mfPeak(cleanChirp, replicaMatched);
            pkGeneric = mfPeak(cleanChirp, replicaGeneric);

            fprintf('Nyquist-compliant waveform: wclass=%s confidence=%.4f k_recovered=%.4e k_true=%.4e\n', ...
                wp.wclass, wp.confidence, wp.chirp_rate_hz_s, kTrue);
            fprintf('Pulse-compression peak: matched=%.4f generic=%.4f ratio=%.2fx\n', ...
                pkMatched, pkGeneric, pkMatched/pkGeneric);

            tc.verifyGreaterThanOrEqual(pkMatched, 3.0 * pkGeneric, ...
                'Matched replica should pulse-compress at least 3x better than a generic copy.');
        end

        function test_feature_matched_confirms_reliably_at_high_intercept_noise(tc)
            % agent.buildEnvWithFeatures uses interceptNoiseAmp=2.0 internally --
            % verified (frozen historical comparison) this is where a noisy
            % verbatim replay stops detecting at all (its numerically larger
            % raw peak is a WORSE CFAR statistic: uncorrelated intercept
            % noise elevates nearby training cells too, not just the peak),
            % while the feature-matched (dechirped, denoised) replica keeps
            % detecting reliably.
            C = physics.Constants();
            actionIdx = 6;   % closing delta + a gain level, arbitrary but fixed
            numEpisodes = 10;

            [env, degradedEvent] = agent.buildEnvWithFeatures(C);
            tc.verifyEmpty(degradedEvent, ...
                'Confidence gate should NOT fire on this canonical scene/noise level -- if it does, that is real information (report it), not noise.');

            confirmedCount = 0;
            for ep = 1:numEpisodes
                rng(1000 + ep);
                reset(env);
                info = struct('confirmedCount', 0, 'eccmLabel', "");
                for k = 1:8
                    [~, ~, ~, info] = step(env, actionIdx);
                end
                confirmedCount = confirmedCount + double(info.confirmedCount >= 1);
            end
            rate = confirmedCount / numEpisodes;

            fprintf('Feature-matched confirmation rate over %d episodes: %.0f%%\n', numEpisodes, rate*100);

            tc.verifyGreaterThan(rate, 0.5, ...
                'Feature-matched synthesis should confirm reliably at this noise level (see historical baseline for the 0%% generic-replay comparison).');
        end

    end

end
