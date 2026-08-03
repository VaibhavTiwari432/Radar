classdef test_prf_consistency < matlab.unittest.TestCase
%TEST_PRF_CONSISTENCY  Phase 4.1: the radar must be ONE radar.
%
%   PATH NOTE: the scope of work asked for this at
%   +physics/tests/test_prf_consistency.m. No such folder exists -- every
%   test in this project lives in tests/ and is discovered by
%   runAllTests.m's TestSuite.fromFolder('tests'). Putting it under
%   +physics/tests/ would have made it invisible to the suite, so it is
%   here. Correction recorded in PHASE4_RESULTS.md Step 0.
%
%   ================= WHAT THIS EXISTS TO PREVENT =================
%   Phase 3 found this project taking the range-Doppler ambiguity trade BOTH
%   WAYS AT ONCE: it declared a 50 kHz PRF (used for Doppler unambiguity,
%   +-375 m/s) while listening for 400 fast-time samples (used for range
%   coverage, 18.7 km), which is an 8 kHz radar's window. No single radar
%   can have both. The contradiction survived because no file declared a
%   PRF -- 50e3 was a literal in ~20 places and nothing checked it against
%   anything.
%
%   These assertions are deliberately mutual: change the PRF without the
%   window, or the window without the PRF, and this fails loudly.

    methods (Test)

        function test_check_a_samples_per_pri_matches_the_listening_window(tc)
            C = physics.Constants();
            fprintf('\n[1.1a] PRF %.0f Hz -> PRI %.1f us -> %.0f samples at fs %.1f MHz\n', ...
                C.PRF, C.PRI*1e6, C.pri_samples, C.fs/1e6);
            fprintf('[1.1a] receive window in use: %d samples\n', C.fast_time_samples);

            tc.verifyEqual(C.pri_samples, C.fs / C.PRF, 'RelTol', 1e-12);
            tc.verifyEqual(C.pri_samples, 400, 'RelTol', 1e-12);
            % THE LOAD-BEARING ONE: a radar cannot listen for longer than the
            % gap between its own pulses.
            tc.verifyLessThanOrEqual(C.fast_time_samples, C.pri_samples, ...
                ['The receive window is LONGER than one PRI. The radar is ' ...
                 'listening for echoes after it has already transmitted the ' ...
                 'next pulse -- everything past R_ua is a folded return being ' ...
                 'read as unambiguous. This is exactly the Phase 3 finding.']);
        end

        function test_check_b_duty_cycle_is_a_pulsed_radar(tc)
            C = physics.Constants();
            fprintf('[1.1b] duty cycle = %.1f us * %.0f Hz = %.1f%%\n', ...
                C.pulse_width*1e6, C.PRF, 100*C.duty_cycle);

            tc.verifyEqual(C.duty_cycle, C.pulse_width * C.PRF, 'RelTol', 1e-12);
            tc.verifyEqual(C.duty_cycle, 0.096, 'RelTol', 1e-9);
            % A "pulsed" radar at 60% duty (what 50 kHz implied) is nearly CW
            % and cannot range-gate its own transmission at all.
            tc.verifyLessThan(C.duty_cycle, 0.20, ...
                ['Duty cycle above 20%% is not a pulsed radar. At 50 kHz this ' ...
                 'was 60%%, which is why that PRF was never physical.']);
            tc.verifyGreaterThan(C.duty_cycle, 0.01, ...
                'Duty cycle below 1% wastes the transmitter; check the pulse width.');
        end

        function test_check_c_unambiguous_range_matches_the_window_span(tc)
            C = physics.Constants();
            windowSpan = C.fast_time_samples * C.range_per_sample;
            fprintf('[1.1c] R_ua = c/(2*PRF) = %.1f m | window spans %.1f m\n', ...
                C.R_unambiguous, windowSpan);

            tc.verifyEqual(C.R_unambiguous, C.c/(2*C.PRF), 'RelTol', 1e-12);
            tc.verifyEqual(C.R_unambiguous, 18737.0, 'AbsTol', 0.1);
            % Checks (a) and (c) are the same identity seen twice, so this
            % must hold exactly, not approximately.
            tc.verifyEqual(windowSpan, C.R_unambiguous, 'RelTol', 1e-12, ...
                'Window span and R_ua disagree: (a) and (c) are the same identity.');
        end

        function test_unambiguous_velocity_is_the_price_paid(tc)
            % Phase 1.2's verification target. Stated as a COST, because it is
            % one: the 50 kHz reading bought +-375 m/s and could not pay for
            % its own range window.
            C = physics.Constants();
            fprintf('[1.2] v_ua = lambda*PRF/4 = %.4f * %.0f / 4 = %+.1f m/s\n', ...
                C.lambda, C.PRF, C.v_unambiguous);
            fprintf('[1.2] (was +-375.0 m/s at the old 50 kHz reading)\n');

            tc.verifyEqual(C.lambda, C.c/C.carrier, 'RelTol', 1e-12);
            tc.verifyEqual(C.lambda, 0.03, 'AbsTol', 1e-4);
            tc.verifyEqual(C.v_unambiguous, 60.0, 'AbsTol', 0.05, ...
                'v_ua must be 60 m/s at 8 kHz / 10 GHz.');
        end

        function test_blind_range_is_prf_independent(tc)
            % Pulse eclipsing: the receiver is deaf while transmitting. This
            % does NOT move with the PRF, which is why it is a separate
            % constraint from R_ua and why 2.2 has to deal with it separately.
            C = physics.Constants();
            fprintf('[1.1] blind range = c*tau/2 = %.1f m (PRF-independent)\n', C.blind_range);
            tc.verifyEqual(C.blind_range, C.c*C.pulse_width/2, 'RelTol', 1e-12);
            tc.verifyEqual(C.blind_range, 1798.8, 'AbsTol', 0.1);
        end

        function test_the_old_50kHz_reading_fails_every_check(tc)
            % Asserted so the rejected option stays rejected FOR A REASON,
            % rather than becoming folklore that someone re-litigates.
            C = physics.Constants();
            OLD_PRF = 50e3;
            oldPriSamples = C.fs / OLD_PRF;
            oldDuty       = C.pulse_width * OLD_PRF;
            oldRua        = C.c / (2 * OLD_PRF);

            fprintf('\n[1.1] the REJECTED 50 kHz reading, for the record:\n');
            fprintf('       samples/PRI %.0f (window needs %d)  duty %.0f%%  R_ua %.1f m\n', ...
                oldPriSamples, C.fast_time_samples, 100*oldDuty, oldRua);

            tc.verifyLessThan(oldPriSamples, C.fast_time_samples, ...
                '(a) 50 kHz PRI must be SHORTER than the window -- that was the bug.');
            tc.verifyGreaterThan(oldDuty, 0.5, '(b) 50 kHz implies >50% duty cycle.');
            tc.verifyLessThan(oldRua, C.fast_time_samples * C.range_per_sample, ...
                '(c) 50 kHz R_ua must be shorter than the window span.');
        end

        function test_no_file_re_declares_the_prf_as_a_literal(tc)
            % The single-source rule, enforced. Phase 4 replaced ~20 literal
            % 50e3 sites; this stops them growing back. Frozen historical
            % fixtures are exempt by design -- their whole purpose is
            % reproducing pre-existing numbers.
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            offenders = {};
            for d = {'+agent','+engine','+experiments','+features','+missionsim', ...
                     '+physics','+radar','+synth','+track','tests'}
                offenders = [offenders, localScan(fullfile(root, d{1}))]; %#ok<AGROW>
            end
            if ~isempty(offenders)
                fprintf('\n[1.1] literal PRF re-declarations found:\n');
                fprintf('   %s\n', offenders{:});
            end
            tc.verifyEmpty(offenders, ...
                'A PRF literal was re-typed instead of read from physics.Constants().');
        end
    end
end

function hits = localScan(folder)
    hits = {};
    if ~isfolder(folder); return; end
    listing = dir(fullfile(folder, '**', '*.m'));
    for i = 1:numel(listing)
        if contains(listing(i).folder, 'historical_baseline'); continue; end
        if strcmp(listing(i).name, 'test_prf_consistency.m'); continue; end
        if strcmp(listing(i).name, 'Constants.m'); continue; end
        txt = fileread(fullfile(listing(i).folder, listing(i).name));
        lines = strsplit(txt, newline);
        for k = 1:numel(lines)
            L = strtrim(lines{k});
            if isempty(L) || startsWith(L, '%'); continue; end
            % An RNG seed that happens to be 50000 is not a PRF.
            if contains(lower(L), 'seed') || contains(lower(L), 'rng'); continue; end
            % A deliberate negative control -- code that passes the REJECTED
            % PRF on purpose, to prove a checker still rejects it. Must be
            % marked explicitly, so an unmarked literal is still caught.
            if contains(L, 'PRF-LITERAL-OK'); continue; end
            if contains(L, '50e3') || contains(L, '50000') || ...
               contains(L, '8e3') && contains(lower(L), 'prf')
                hits{end+1} = sprintf('%s:%d: %s', listing(i).name, k, L); %#ok<AGROW>
            end
        end
    end
end
