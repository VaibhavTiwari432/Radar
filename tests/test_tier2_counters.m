classdef test_tier2_counters < matlab.unittest.TestCase
%TEST_TIER2_COUNTERS  Standing guards for the three Tier 2 counter-DRFM
%   experiments, which until now existed only as one-off runs whose numbers
%   live in REPORT_HAC-2026-1166.md §4.12a / §4.9a / §4.8a. Each experiment
%   produced a load-bearing finding -- two negative, one that WITHDREW the
%   report's strongest defensive claim -- and none of them could fail loudly
%   if the code beneath it drifted.
%
%   Seed counts are reduced from the published runs (6 / 6 / closed-form) so
%   the file is runnable; every assertion is a BAND around the published
%   figure, not an equality, for exactly that reason. The published numbers
%   are quoted in each method so a drift is legible as a drift.
%
%   These are guards, not re-measurements. A failure here does not
%   automatically mean a bug -- it means a number the report quotes has moved
%   and the report must be revisited before the number is quoted again.

    methods (Test)

        function test_2p1_edge_sees_latency_but_is_lost_under_a_repeat(tc)
            % §4.12a. TWO claims, and they point opposite ways -- both are
            % guarded, because quoting either alone misrepresents the result.
            %
            % (a) THE POSITIVE, which corrected an earlier wrong argument:
            % edge ESTIMATION PRECISION is bounded by rise time / SNR, not by
            % rise time. So even this radar's 2 MHz sees a 10 ns latency.
            % (b) THE NEGATIVE, which is the actual finding: with the skin
            % return and a 20 dB repeat in ONE dwell, the edge does not land
            % on the skin return at all -- the repeat's own -13.2 dB sidelobes
            % sit +6.8 dB above it. Published as NOT ESTABLISHED.
            out = experiments.drfmLatency(6);
            C = physics.Constants();

            % (a) single return, this radar's own bandwidth, 10 ns = 1.50 m.
            % Published at 20 seeds: shift 1.31 m, noise 0.152 m, detectable.
            sel = out([out.bandwidthHz] == 2e6 & [out.latencyNs] == 10);
            fprintf('\n[2.1] B=2 MHz, 10 ns (true 1.50 m): shift %.2f m, noise %.3f m, detectable %d\n', ...
                sel.edgeShiftM, sel.edgeNoiseM, sel.detectable);
            tc.verifyTrue(logical(sel.detectable), ...
                ['a 10 ns latency is no longer detectable at 2 MHz -- §4.12a''s ' ...
                 'correction (precision is rise time / SNR, not rise time) is at risk']);
            tc.verifyGreaterThan(sel.edgeShiftM, 0.5);
            tc.verifyLessThan(sel.edgeShiftM, 2.5, ...
                'measured shift no longer brackets the true 1.50 m');

            % ...and the mechanism behind (a): precision is orders finer than
            % the rise time (74.95 m at 2 MHz), which is the whole correction.
            tc.verifyLessThan(sel.edgeNoiseM, sel.riseTimeM / 100, ...
                'edge precision has collapsed toward the rise time');

            % (b) two-return case, same bandwidth. Stored with a NEGATIVE
            % latency tag by the experiment; edgeShiftM holds mean|edge error|
            % against the skin return's own reference. A leading-edge tracker
            % that WORKED would sit near zero in every cell regardless of
            % separation. Published (6 seeds): 109.8 / 73.8 / 45.3 / 390.6 m.
            two = out([out.bandwidthHz] == 2e6 & [out.latencyNs] < 0);
            fprintf('[2.1] B=2 MHz two-return edge error per cell: %s m\n', ...
                mat2str(round([two.edgeShiftM], 1)));
            tc.verifyGreaterThan(max([two.edgeShiftM]), C.range_per_sample, ...
                ['the edge estimator now recovers the skin return under a 20 dB ' ...
                 'repeat -- leading-edge tracking has become a usable counter and ' ...
                 '§4.12a''s "declared ineffective" must be revisited']);
        end

        function test_2p2_stagger_is_free_weak_and_below_the_rgpo_gate(tc)
            % §4.9a. Three claims, and the third is the one that keeps the
            % report honest: stagger BIASES the predictive repeater's apparent
            % velocity rather than destroying its coherence, and the bias
            % stays BELOW track.rangeRateConsistency's own derived gate -- so
            % stagger does not trip the RGPO screen by itself.
            out = experiments.prfJitter(6);
            j0 = out([out.jitter] == 0);
            j4 = out([out.jitter] == 0.40);

            % FREE: the genuine arm is passive, sampled at the radar's own
            % true transmit times. Published at 20 seeds: 0.01 dB, v error
            % unchanged at 1.28 m/s.
            fprintf('\n[2.2] jitter 0.40: genuine %+.2f dB (v err %.2f -> %.2f m/s)\n', ...
                j4.genPeakDb, j0.genVErr, j4.genVErr);
            tc.verifyLessThan(abs(j4.genPeakDb), 0.5, ...
                'PRF stagger now costs the GENUINE target integration gain -- it is not free');
            tc.verifyLessThan(abs(j4.genVErr - j0.genVErr), 0.1, ...
                'PRF stagger now costs the GENUINE target range-rate accuracy');

            % COSTS THE PREDICTIVE REPEATER, but weakly. Published: -1.83 dB,
            % net advantage 1.84 dB against waveform agility's 14.2 dB.
            net = j4.genPeakDb - j4.repPeakDb;
            fprintf('[2.2] jitter 0.40: repeater %+.2f dB | net advantage %.2f dB\n', ...
                j4.repPeakDb, net);
            tc.verifyGreaterThan(net, 1.0, ...
                'the predictive repeater no longer pays for the stagger');

            % AND IT IS WEAK: the induced velocity bias must stay below the
            % gate. Derived from track.rangeRateConsistency itself rather than
            % hardcoding 8.81, so the two move together if the gate is re-derived.
            t = (0:7)';                            % 8 frames, 1 Hz revisit
            gate = track.rangeRateConsistency(1800 - 60*t, t, -60*ones(8,1), ...
                physics.Constants());
            fprintf('[2.2] repeater v error %.2f m/s vs RGPO gate %.2f m/s\n', ...
                j4.repVErr, gate.thresholdMps);
            tc.verifyLessThan(j4.repVErr, gate.thresholdMps, ...
                ['the stagger-induced velocity bias now exceeds the range-rate gate ' ...
                 '-- stagger trips the RGPO screen by itself and §4.9a''s "weak" ' ...
                 'reading is no longer correct']);
        end

        function test_2p3_cross_eye_defeats_the_veto_and_a_equals_one_is_a_null(tc)
            % §4.8a. This experiment WITHDREW §4.8's "cannot be defeated", so
            % it is the one guard here protecting a correction rather than a
            % measurement. Closed form, deterministic -- no seeds.
            out = experiments.crossEyeSpike();

            % DEFEATED, with margin. Published: 2.671 deg achievable against a
            % 0.398 deg threshold = 6.7x.
            fprintf('\n[2.3] achievable spread %.3f deg vs screen threshold %.3f deg (%.1fx)\n', ...
                out.achievableDeg, out.neededDeg, out.achievableDeg / out.neededDeg);
            tc.verifyGreaterThan(out.achievableDeg, 5 * out.neededDeg, ...
                ['cross-eye no longer clears the co-bearing threshold with margin ' ...
                 '-- §4.8a''s withdrawal of "cannot be defeated" depends on this']);

            % AT A TOLERANCE OF ~1 deg, NOT "a few degrees" (§3.9 was optimistic
            % by ~2x). Published: 1.0 deg defeats, 2.0 deg does not.
            fprintf('[2.3] largest phase error still defeating the screen: %.1f deg\n', ...
                out.phaseTolDeg);
            tc.verifyGreaterThanOrEqual(out.phaseTolDeg, 0.5);
            tc.verifyLessThan(out.phaseTolDeg, 2, ...
                'the phase tolerance has loosened -- §3.9 and §4.8a quote ~1 deg');

            % THE NULL AT a = 1, which is a property of THIS judge: runJudge
            % uses only imag(Delta/Sigma), and at a = 1 the entire phi_ce
            % dependence sits in the REAL part. The apparent bearing is the
            % jammer's own (0.800 deg) at every phase. An adversary tuning
            % toward the textbook optimum tunes into the radar's blind spot.
            THETA_JAMMER = 0.8;                   % crossEyeSpike's own scene
            unity = out.apparent(out.amps == 1.00, :);
            unity = unity(isfinite(unity));       % phi_ce = 180 exactly is a perfect null
            fprintf('[2.3] a=1.00 apparent bearings: %s (true %.3f)\n', ...
                mat2str(round(unity, 3)), THETA_JAMMER);
            % Judged against the screen's own threshold, not an arbitrary
            % epsilon: the residual deflection at a = 1 is 6.5e-5 deg, four
            % orders below the 0.398 deg the adversary needs.
            tc.verifyLessThan(max(abs(unity - THETA_JAMMER)), out.neededDeg / 100, ...
                ['a = 1 exactly is no longer a null -- §4.8a''s inversion of the ' ...
                 'textbook result is a claim about this judge''s estimator']);
        end
    end
end
