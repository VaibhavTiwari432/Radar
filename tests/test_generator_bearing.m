classdef test_generator_bearing < matlab.unittest.TestCase
%TEST_GENERATOR_BEARING  A MOVING transmitter, and the guarantee that adding
%   one changed nothing for anybody who did not ask for it.
%
%   WHAT CHANGED (16 Aug 2026). +generator/render.m took ONE scalar
%   'SourceAzimuthRad' for the whole scene and hoisted the monopulse phase
%   OUT of its frame loop, so the transmitter was nailed to a fixed bearing
%   for all time. It now accepts a per-frame bearing series, so a mother
%   platform that actually flies can be rendered.
%
%   WHY THAT IS WORTH A TEST FILE OF ITS OWN. Every phantom is radiated from
%   the one platform (Blueprint 2.4, enforced architecturally -- there is
%   still no per-phantom angle argument anywhere in render.m), so once the
%   platform moves, every phantom inherits its bearing TRAJECTORY while
%   claiming a range of its own. Through v_cross = R*dtheta/dt that inflates
%   the tangential speed a phantom implies by exactly the range ratio -- a
%   PER-TRACK signature, and therefore the first one that can condemn a LONE
%   phantom. The co-bearing screen needs N >= 2 and is silent at N = 1, which
%   is why PHASE_B_RESULTS.md records single-phantom P_confirm = 1.00 across
%   every radar class.
%
%   THE TESTS BELOW ARE IN TWO GROUPS, AND THE FIRST MATTERS MORE.
%     1. Nothing moved. A scalar bearing must render EXACTLY what it always
%        did, sample for sample -- including that the new elevation channel
%        does not perturb the shared RNG stream while it is switched off.
%        Every published Gate A / Phase B number depends on this.
%     2. The new capability is real, measured with +engine/runJudge.m's OWN
%        monopulse estimator (phiEst = 2*atan(imag(Delta/Sigma))), not with a
%        second copy of the formula written to agree with itself.

    properties (Constant)
        RANGES  = 2500          % one phantom, clear of the 1798.8 m blind range
        RATE    = -35           % m/s closing, inside v_ua = 59.958 m/s
        NFRAMES = 8
        SUBSEP  = 0.30          % render.m's default azimuth baseline [m]
        % Small but not zero: a noiseless render would make the recovered
        % bearing exact by construction and prove nothing about robustness.
        % This is ~94 dB below the default 0.05, so the recovery below is
        % limited by the estimator, not by the draw.
        QUIET_NOISE = 1e-6
    end

    methods (Test)

        % ---------- group 1: nothing moved ----------

        function test_scalar_and_constant_vector_are_byte_identical(tc)
            % The broadcast path IS the scalar path. If these ever differ,
            % every fixture that passes a scalar has silently re-based.
            az = 0.012;
            a = localRender(tc, 'SourceAzimuthRad', az, 'Seed', 7);
            b = localRender(tc, 'SourceAzimuthRad', repmat(az, 1, tc.NFRAMES), 'Seed', 7);

            tc.verifyTrue(isequal(a.rx_frames, b.rx_frames), ...
                'sum channel differs between scalar and constant-vector bearing');
            tc.verifyTrue(isequal(a.rx_frames_delta, b.rx_frames_delta), ...
                'difference channel differs between scalar and constant-vector bearing');
        end

        function test_the_elevation_channel_defaults_off_because_it_moves_the_rng(tc)
            % THE REASON THE DEFAULT IS false, asserted rather than asserted-in-
            % a-comment. A third receive chain needs its own independent noise
            % draw; that draw advances the SHARED stream, so every later
            % pulse's sum- and difference-channel noise changes. Switching it
            % on is therefore not a free addition, and any scene compared
            % across the switch is comparing two different noise realisations.
            off = localRender(tc, 'Seed', 11);
            on  = localRender(tc, 'Seed', 11, 'IncludeElevationChannel', true);

            tc.verifyFalse(isfield(off, 'rx_frames_delta_el'), ...
                'elevation channel was written when it was not requested');
            tc.verifyTrue(isfield(on, 'rx_frames_delta_el'));
            tc.verifyFalse(isequal(off.rx_frames, on.rx_frames), ...
                ['the elevation draw did NOT perturb the stream -- if this ' ...
                 'ever passes, the default-off rationale is wrong and should ' ...
                 'be revisited, not the test relaxed']);
        end

        function test_zero_elevation_leaves_the_azimuth_channel_untouched(tc)
            % The azimuth phase became 2*pi*d*sin(az)*cos(el)/lambda. At
            % el = 0, cos(el) = 1 and it collapses to the historical
            % 2*pi*d*sin(az)/lambda -- so adding elevation costs the existing
            % path exactly nothing. Compared with elevation SUPPLIED as zero
            % against elevation not supplied at all.
            a = localRender(tc, 'SourceAzimuthRad', 0.02, 'Seed', 3);
            b = localRender(tc, 'SourceAzimuthRad', 0.02, 'SourceElevationRad', 0, 'Seed', 3);
            tc.verifyTrue(isequal(a.rx_frames_delta, b.rx_frames_delta));
        end

        % ---------- group 2: the transmitter really moves ----------

        function test_a_moving_transmitter_is_recovered_frame_by_frame(tc)
            % The capability. A commanded bearing SERIES comes back out of the
            % rendered difference channel, per frame, through the judge's own
            % estimator -- which has never heard of the generator.
            azCmd = deg2rad(linspace(-1.2, 1.2, tc.NFRAMES));   % inside the
            % +-2.8640 deg unambiguous sector, so this measures bearing and
            % not phase wrap (generator/platform.py's sector_dwell_s).
            S = localRender(tc, 'SourceAzimuthRad', azCmd, 'Seed', 5, ...
                            'NoiseAmplitude', tc.QUIET_NOISE);

            tc.verifyEqual(S.source_azimuth_rad(:)', azCmd, 'AbsTol', 1e-12, ...
                'the bearing series was not exported as commanded');

            azEst = localEstimateAzPerFrame(S, tc.SUBSEP);
            tc.verifyEqual(azEst, azCmd, 'AbsTol', deg2rad(0.01), ...
                'recovered bearing does not track the commanded trajectory');

            % ...and it genuinely VARIES. A constant series must not.
            tc.verifyGreaterThan(max(azEst) - min(azEst), deg2rad(2.0));
            fixed = localRender(tc, 'SourceAzimuthRad', 0.005, 'Seed', 5, ...
                                'NoiseAmplitude', tc.QUIET_NOISE);
            spread = max(localEstimateAzPerFrame(fixed, tc.SUBSEP)) - ...
                     min(localEstimateAzPerFrame(fixed, tc.SUBSEP));
            tc.verifyLessThan(spread, deg2rad(0.01));
        end

        function test_every_phantom_shares_the_one_bearing_at_every_frame(tc)
            % Blueprint 2.4 still holds, now stated over TIME. Three phantoms
            % at widely different ranges, one commanded bearing series: the
            % difference/sum ratio is a property of the FRAME, so it must be
            % identical at all three range bins within a frame. There is no
            % render.m code path that could make it otherwise -- this asserts
            % the architecture rather than hoping for it.
            azCmd = deg2rad(linspace(-1.0, 1.0, tc.NFRAMES));
            S = localRender(tc, 'Ranges', [2200 3600 5000], 'SourceAzimuthRad', azCmd, ...
                            'Seed', 9, 'NoiseAmplitude', tc.QUIET_NOISE);

            % Compared as BEARINGS, not as raw Delta/Sigma ratios. The three
            % phantoms sit at 2200/3600/5000 m, so the 1/R^2 law leaves the
            % farthest ~5x weaker and the same noise floor perturbs its ratio
            % ~5x more in relative terms. Requiring the complex ratios to
            % match to a fixed epsilon would therefore be a test of the SNR
            % spread, not of the shared bearing. 0.001 deg is still ~70x
            % tighter than the 0.0726 deg within-track azimuth scatter
            % tests/test_monopulse_snr_boundary.m measured.
            C = physics.Constants();
            lambda = C.c / double(S.carrier_hz);
            for k = 1:tc.NFRAMES
                sig = S.rx_frames(:, 1, k);
                dif = S.rx_frames_delta(:, 1, k);
                [~, ord] = sort(abs(sig), 'descend');
                bins = ord(1:3);
                azBins = zeros(1, 3);
                for j = 1:3
                    ratio = dif(bins(j)) / sig(bins(j));
                    sinTh = 2*atan(imag(ratio)) * lambda / (2*pi*tc.SUBSEP);
                    azBins(j) = asin(max(-1, min(1, sinTh)));
                end
                tc.verifyLessThan(max(azBins) - min(azBins), deg2rad(0.001), ...
                    sprintf('phantoms disagreed on bearing within frame %d', k));
            end
        end

        function test_a_short_bearing_series_is_refused_not_padded(tc)
            % A silently-padded schedule would render the last frames on a
            % stale bearing and look like a slowing platform. Same posture
            % render.m already takes for a short sweep_schedule.
            tc.verifyError( ...
                @() localRender(tc, 'SourceAzimuthRad', zeros(1, tc.NFRAMES - 2)), ...
                'generator:render:shortBearing');
        end

    end
end


function S = localRender(tc, varargin)
%LOCALRENDER  One scene through the real generator, loaded back as a struct.
    p = inputParser;
    p.KeepUnmatched = true;
    p.addParameter('Ranges', tc.RANGES, @isnumeric);
    p.addParameter('Seed', 1, @isscalar);
    p.parse(varargin{:});
    extra = namedargs2cell(p.Unmatched);

    tag = sprintf('bearing_%s', char(matlab.lang.makeValidName(num2str(rand))));
    rng(double(p.Results.Seed), 'twister');
    judgeMat = renderPhantomScene(p.Results.Ranges, tc.RATE, ...
        'NumFrames', tc.NFRAMES, 'Tag', tag, extra{:});
    S = load(judgeMat);
end


function az = localEstimateAzPerFrame(S, subSep)
%LOCALESTIMATEAZPERFRAME  +engine/runJudge.m's OWN monopulse estimator,
%   verbatim (runJudge.m:300-303), applied at each frame's strongest bin.
%   Copied rather than called because runJudge estimates azimuth only at
%   CFAR-detected peaks inside its full detection chain, and this test is
%   about the RENDERER: putting CFAR in the loop would make a bearing failure
%   and a detection failure indistinguishable.
    C = physics.Constants();
    lambda = C.c / double(S.carrier_hz);
    numFrames = size(S.rx_frames, 3);
    az = zeros(1, numFrames);
    for k = 1:numFrames
        sig = S.rx_frames(:, 1, k);
        dif = S.rx_frames_delta(:, 1, k);
        [~, b] = max(abs(sig));
        ratio  = dif(b) / sig(b);
        phiEst = 2 * atan(imag(ratio));
        sinTh  = phiEst * lambda / (2*pi*subSep);
        az(k)  = asin(max(-1, min(1, sinTh)));
    end
end
