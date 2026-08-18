classdef test_surface_clutter < matlab.unittest.TestCase
%TEST_SURFACE_CLUTTER  The ground return model, and what it overturns.
%
%   Two groups, and the second is why the first was built.
%
%   THE PHYSICS: +physics/surfaceClutter.m must derive what it can and cite
%   what it cannot. Beamwidth comes from the antenna gain, sigma0 from the
%   constant-gamma model, the patch area from the range resolution -- and only
%   gamma is an assumption. Getting any of those wrong changes every clutter
%   number, so they are pinned individually rather than through an end-to-end
%   detection count.
%
%   THE CONSEQUENCE: clutter does not touch a fast phantom and destroys a slow
%   drone. That asymmetry costs the RADAR its view of the emitter while
%   costing the ADVERSARY nothing, and it overturns this project's own earlier
%   conclusion that a drone "must hide inside the blind range" -- a conclusion
%   reached on a thermal-noise-only model, which is the only model this repo
%   had until 16 Aug 2026.
%
%   DEFAULT-OFF IS ITSELF TESTED. The clutter draw advances the shared RNG
%   stream, so if it ran by default every published scene would move. The last
%   test here asserts byte-identical output with clutter absent.

    properties (Constant)
        DRONE_R   = 2000      % outside the 1798.75 m blind range
        PHANTOM_R = 3600
        RATE      = -50
    end

    methods (Test)

        function test_beamwidth_is_derived_from_the_antenna_gain(tc)
            % Not typed in: a pencil beam has G = 4*pi/(th_az*th_el), so a
            % symmetric beam is sqrt(4*pi/G). At this project's 30 dBi that is
            % 6.42 deg, which independently agrees with the lambda/D beamwidth
            % of the 0.30 m aperture the monopulse baseline assumes.
            S = physics.surfaceClutter('RangesM', 2000);
            tc.verifyEqual(S.beamwidth_rad, sqrt(4*pi/1000), 'RelTol', 1e-12);
            tc.verifyEqual(rad2deg(S.beamwidth_rad), 6.42, 'AbsTol', 0.01);
        end

        function test_the_patch_uses_range_resolution_not_sample_spacing(tc)
            % Clutter competes over a RESOLUTION cell, c/(2B) = 74.95 m, which
            % at this operating point is COARSER than the 46.84 m sample
            % spacing. Using the sample spacing would understate every clutter
            % number by 1.6x.
            C = physics.Constants();
            S = physics.surfaceClutter('RangesM', 2000);
            tc.verifyEqual(S.range_resolution_m, C.c/(2*2e6), 'RelTol', 1e-12);
            tc.verifyGreaterThan(S.range_resolution_m, C.range_per_sample);
        end

        function test_constant_gamma_makes_clutter_rcs_independent_of_range(tc)
            % A real property of the model worth pinning, because it is
            % surprising and it drives everything else: sigma0 = gamma*sin(psi)
            % falls as 1/R while the illuminated patch grows as R, so their
            % product -- the clutter RCS the target actually competes with --
            % is CONSTANT. Hence a flat signal-to-clutter ratio at every range.
            S = physics.surfaceClutter('RangesM', [1400 2000 3600 6800 10000]);
            % Constant to within the sec(psi) term, which varies by 2.5e-5
            % across this span -- not exactly flat, and the tolerance says so
            % rather than pretending the geometry is one-dimensional.
            spread = (max(S.clutter_rcs_m2) - min(S.clutter_rcs_m2)) / mean(S.clutter_rcs_m2);
            tc.verifyLessThan(spread, 1e-4, ...
                'clutter RCS should be constant with range under constant-gamma');

            % ...and the range exponent that follows. NOT the 1/R^3 usually
            % quoted: that assumes sigma0 constant, and constant-gamma's own
            % 1/R fall cancels the patch growth exactly. Both target and
            % clutter therefore go as 1/R^4 and the SCR is flat.
            r = S.ranges_m;
            slope = log(S.clutter_power_w(end)/S.clutter_power_w(1)) / log(r(end)/r(1));
            tc.verifyEqual(slope, -4, 'AbsTol', 0.05, ...
                'constant-gamma surface clutter power should fall as 1/R^4');
        end

        function test_a_moving_phantom_is_unaffected_by_clutter(tc)
            % Ground return is at zero Doppler by construction (one
            % realisation held across every pulse in a frame). A phantom
            % closing at -50 m/s is thirteen Doppler bins away, so the judge's
            % own processing separates it for free.
            [nOff, lblOff] = localRun(tc, []);
            [nOn,  lblOn ] = localRun(tc, -15);
            tc.verifyGreaterThanOrEqual(nOff, 1);
            tc.verifyGreaterThanOrEqual(nOn, 1, ...
                'clutter removed a phantom it should not have touched');
            tc.verifyEqual(lblOn, lblOff, ...
                'clutter changed the phantom''s label');
        end

        function test_clutter_hides_a_realistic_drone(tc)
            % THE FINDING. A 0.1 m^2 drone -- still generous for a quadcopter --
            % is found in every seed without clutter and in none with it,
            % because its crossing motion gives it almost no radial rate and it
            % lands in the clutter notch.
            out = experiments.clutterImpact('DroneRcs', [1.0 0.1], 'Seeds', 1:5);
            tc.verifyEqual(out.found_clutter_off(2), 5, ...
                'the 0.1 m^2 drone should be found in every clutter-free seed');
            tc.verifyEqual(out.found_clutter_on(2), 0, ...
                'the 0.1 m^2 drone should be lost in ground return');
        end

        function test_clutter_is_off_by_default_and_changes_nothing(tc)
            % The RNG-stream guarantee. Rendering without the parameter and
            % rendering with it explicitly empty must produce IDENTICAL
            % samples, or every published scene silently moves.
            rng(3, 'twister');
            a = load(renderPhantomScene(tc.PHANTOM_R, tc.RATE, 'NumFrames', 4, ...
                'MotherRangeM', tc.DRONE_R, 'Tag', 'clutdef_a'));
            rng(3, 'twister');
            b = load(renderPhantomScene(tc.PHANTOM_R, tc.RATE, 'NumFrames', 4, ...
                'MotherRangeM', tc.DRONE_R, 'ClutterGammaDB', [], 'Tag', 'clutdef_b'));
            tc.verifyEqual(b.rx_frames, a.rx_frames, ...
                'the default path is not byte-identical to explicitly-off');
        end

    end
end


function [n, lbl] = localRun(tc, gammaDB)
    rng(17, 'twister');
    args = {tc.PHANTOM_R, tc.RATE, 'NumFrames', 8, 'MotherRangeM', tc.DRONE_R, ...
            'MotherVelocityMps', [0 3 0], 'IncludeAngleChannel', false, ...
            'Tag', sprintf('clut_%d', isempty(gammaDB))};
    if ~isempty(gammaDB); args = [args, {'ClutterGammaDB', gammaDB}]; end
    fb = engine.runJudge(renderPhantomScene(args{:}));
    n = fb.confirmed_tracks;
    lbl = "";
    if n >= 1
        % The PHANTOM specifically -- the track nearest its own range, not
        % whatever confirmed first.
        rr = cellfun(@(r) mean(r), fb.track_range_m);
        [~, k] = min(abs(rr - (tc.PHANTOM_R + tc.RATE*4)));
        lbl = string(fb.track_label{k});
    end
end
