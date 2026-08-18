classdef test_generator_agility < matlab.unittest.TestCase
%TEST_GENERATOR_AGILITY  Un-freezes claim C2 on the rebuilt generator.
%
%   C2 ("waveform agility costs a stale repeater 14.2 dB and 24x range
%   smearing") was marked FROZEN in CLAIMABLE_RESULTS.md when
%   test_waveform_agility.m broke in the 7 August archive -- its scene was
%   built by engine.entity.render. The ledger's own note said C2 was "the
%   most likely of these to survive a re-derivation, but it has not had
%   one." This is that re-derivation.
%
%   It drives generator.checkAgilityMechanism, which already re-measured
%   the effect on the new generator but only PRINTED it. Returning the
%   numbers was the whole cost of making the claim testable again.
%
%   WHAT REPRODUCES AND WHAT DOES NOT -- read before quoting this:
%     * The dB loss reproduces essentially exactly: 14.16 dB measured here
%       against 14.2 dB published, with the underlying peak powers
%       (1444.0 matched, 55.35 mismatched) matching the published figures
%       too. That is the load-bearing half of C2.
%     * The 24x SMEARING figure does NOT reproduce as stated, because the
%       original never recorded which bin-width criterion it used. This
%       file measures a -3 dB main-lobe width -- self-referencing, so it
%       reports spreading independently of the 14 dB level drop happening
%       simultaneously -- and gets 1 bin matched vs 49 mismatched, i.e.
%       49x. Quote 49x WITH the -3 dB definition attached, or quote the dB
%       loss alone. Do not quote 24x: nothing here re-derives it.

    properties
        FixtureDir
        Out
    end

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'generator.tests.build_phase_b_scenes not importable from this MATLAB''s Python environment (pyenv).');
        end

        function buildAndMeasure(tc)
            tc.FixtureDir = tempname;
            mkdir(tc.FixtureDir);
            mod = py.importlib.import_module('generator.tests.build_phase_b_scenes');
            py.importlib.reload(mod);
            mod.build_one_phantom_agile_radar( ...
                fullfile(tc.FixtureDir, 'phaseB_1phantom_agile.mat'), ...
                pyargs('num_pulses_per_frame', int32(32)));
            tc.Out = generator.checkAgilityMechanism(tc.FixtureDir);
        end
    end

    methods (TestClassTeardown)
        function cleanFixtures(tc)
            if ~isempty(tc.FixtureDir) && isfolder(tc.FixtureDir)
                rmdir(tc.FixtureDir, 's');
            end
        end
    end

    methods (Test)

        function test_C2_sweep_mismatch_costs_about_14_dB(tc)
            % The isolated matched-filter measurement -- no scene, no CFAR,
            % no tracker. That isolation is why C2 was always the most
            % portable claim in the ledger: nothing about it depends on the
            % generator that was archived.
            tc.verifyGreaterThan(tc.Out.lossDb, 13.0, ...
                'A stale (wrong-sweep) repeater must pay a large pulse-compression penalty.');
            tc.verifyLessThan(tc.Out.lossDb, 15.5, ...
                'Loss far above the published 14.2 dB would mean the waveform or fs changed, not that agility got better.');
        end

        function test_C2_mismatch_smears_the_response(tc)
            % Asserted as a RATIO, not an absolute bin count, so it does not
            % break if fs or the receive window changes -- the physics being
            % claimed is "the energy spreads", not "it spreads over exactly
            % 49 bins at this sample rate".
            tc.verifyEqual(tc.Out.matchedBins, 1, ...
                'A correctly matched filter should compress to essentially one bin.');
            tc.verifyGreaterThan(tc.Out.smearRatio, 10, ...
                'Mismatched compression must spread the response over many bins.');
        end

        function test_stale_belief_loses_detections_the_omniscient_one_keeps(tc)
            % The end-to-end consequence, and the reason agility matters at
            % all: the SAME phantom, differing only in whether it guessed
            % the radar's sweep direction, reaches the judge with fewer
            % usable detections. This is the mechanism behind Phase B's
            % plus_agility row -- asserted here so a P_confirm=1.00 in that
            % row can be read as "effect too small to flip the label"
            % rather than "effect absent".
            nOmni  = numel(tc.Out.fbOmni.track_range_m{1});
            nStale = numel(tc.Out.fbStale.track_range_m{1});
            tc.verifyGreaterThan(nOmni, nStale, ...
                ['A repeater synthesising from a stale intercept must be ' ...
                 'detected on fewer frames than an omniscient one; equal ' ...
                 'counts would mean the sweep schedule is not reaching render.']);
        end

    end
end

function tf = localPythonReady()
    try
        py.importlib.import_module('generator.tests.build_phase_b_scenes');
        tf = true;
    catch
        tf = false;
    end
end
