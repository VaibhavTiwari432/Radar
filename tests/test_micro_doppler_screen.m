function tests = test_micro_doppler_screen
%TEST_MICRO_DOPPLER_SCREEN  The third ECCM screen, and the two gates that
%   keep it from flagging honest targets.
%
%   The screen asks: does this track's slow-time spectrum carry a rotor comb?
%   A DRFM repeater cannot make one -- +synth/synthesizeSwarm.m applies a
%   delay, a gain and a CONSTANT phase, which is a single Doppler line.
%
%   The reason this file spends most of its length on the GATES rather than
%   on the detection is that the detection is the easy part. The screen is
%   the first one in this project that is not class-agnostic, and an
%   ungated version would flag every genuine fixed-wing target -- the exact
%   failure that got the whiteness screen withdrawn (BENCHMARK_RESULTS.md).

    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    testCase.TestData.C = physics.Constants();
end

function ts = baseTrack()
%BASETRACK  A track that PASSES screens 1 and 2, so that anything this file
%   observes is attributable to screen 3 alone.
    R = 1800:60:2220;                       % opening
    ts = struct( ...
        'range',           R, ...
        'amplitude',       2.0 ./ ((R/R(1)).^2), ...   % honest 1/R^2
        'doppler',         repmat(+60, 1, numel(R)), ... % agrees with the walk
        'dopplerMeasured', true);
end

% =====================================================================
% The screen itself
% =====================================================================
function test_comb_present_and_absent_change_the_verdict(testCase)
    C = testCase.TestData.C;

    % A genuine rotorcraft: comb fraction in the measured band (0.375-0.658
    % at resolving dwells, experiments.microDopplerScreenability).
    drone = baseTrack();
    drone.combFrac = 0.50;
    drone.microResolvable = true;
    drone.expectMicroDoppler = true;
    verifyEqual(testCase, track.discriminator(drone, C), "real", ...
        'a track carrying a real rotor comb must pass');

    % A repeater: single Doppler line, only window leakage outside it.
    phantom = baseTrack();
    phantom.combFrac = 0.03;
    phantom.microResolvable = true;
    phantom.expectMicroDoppler = true;
    verifyEqual(testCase, track.discriminator(phantom, C), "decoy", ...
        ['a flat-spectrum repeater must be caught even though it satisfies ' ...
         'BOTH of the older screens -- that is the entire point of adding ' ...
         'a third']);
end

% =====================================================================
% Gate 1: the dwell has to be able to see a comb
% =====================================================================
function test_screen_self_disables_when_dwell_cannot_resolve(testCase)
    C = testCase.TestData.C;
    phantom = baseTrack();
    phantom.combFrac = 0.03;
    phantom.expectMicroDoppler = true;
    phantom.microResolvable = false;         % e.g. this project's 32-pulse dwell
    verifyEqual(testCase, track.discriminator(phantom, C), "real", ...
        ['with a dwell too short to resolve a comb, absence of one is not ' ...
         'evidence -- the screen must abstain, exactly as screen 2 abstains ' ...
         'when Doppler was never measured']);
end

% =====================================================================
% Gate 2: the caller has to have asserted a rotorcraft threat model
% =====================================================================
function test_screen_off_by_default_protects_fixed_wing(testCase)
    C = testCase.TestData.C;
    % A GENUINE fighter: no rotor, so no comb, but otherwise honest.
    fighter = baseTrack();
    fighter.combFrac = 0.03;
    fighter.microResolvable = true;
    % expectMicroDoppler deliberately NOT set.
    verifyEqual(testCase, track.discriminator(fighter, C), "real", ...
        ['without an explicit rotorcraft threat model the screen must not ' ...
         'run: a fixed-wing target has no comb and flagging it would be the ' ...
         'whiteness-screen mistake again']);

    % And the older callers, which know nothing about any of this, are
    % untouched -- no combFrac field at all.
    legacy = baseTrack();
    verifyEqual(testCase, track.discriminator(legacy, C), "real", ...
        'a caller that never supplied combFrac must keep its old behaviour');
end

% =====================================================================
% The ablation mask has to reach the new screen too
% =====================================================================
function test_ablation_mask_can_disable_the_new_screen(testCase)
    C = testCase.TestData.C;
    phantom = baseTrack();
    phantom.combFrac = 0.03;
    phantom.microResolvable = true;
    phantom.expectMicroDoppler = true;
    verifyEqual(testCase, track.discriminator(phantom, C), "decoy");

    phantom.screensEnabled = {'amplitude', 'doppler'};   % micro ablated out
    verifyEqual(testCase, track.discriminator(phantom, C), "real", ...
        ['+experiments/benchmarkSuite.m ablates screens by name; the new ' ...
         'screen must honour that mask or the ablation reports the wrong ' ...
         'attribution']);
end

% =====================================================================
% The threshold is set by the NULL, not by the positive class
% =====================================================================
function test_threshold_sits_above_measured_repeater_leakage(testCase)
    C = testCase.TestData.C;
    % Worst single-line leakage measured across 32..1024-pulse dwells was
    % 0.0457. A repeater at that level must still be caught.
    worstLeak = baseTrack();
    worstLeak.combFrac = 0.0457;
    worstLeak.microResolvable = true;
    worstLeak.expectMicroDoppler = true;
    verifyEqual(testCase, track.discriminator(worstLeak, C), "decoy", ...
        'the threshold must sit ABOVE the worst measured repeater leakage');

    % And the weakest genuine comb measured (0.375, at 512 pulses) must pass
    % with margin.
    weakest = baseTrack();
    weakest.combFrac = 0.375;
    weakest.microResolvable = true;
    weakest.expectMicroDoppler = true;
    verifyEqual(testCase, track.discriminator(weakest, C), "real", ...
        'the weakest genuine comb measured must still clear the threshold');
end
