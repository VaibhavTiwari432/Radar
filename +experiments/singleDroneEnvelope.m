function out = singleDroneEnvelope(varargin)
%SINGLEDRONEENVELOPE  The actual mission: ONE drone, ONE phantom, can it pass?
%
%   out = experiments.singleDroneEnvelope()
%   out = experiments.singleDroneEnvelope('Seeds', 1:8)
%
%   THE MISSION, STATED EXACTLY. There is one drone. It radiates from one
%   aperture. The game is to transmit a signal the radar accepts as a real
%   target. Everything below is what that constrains.
%
%   WHY N = 1 IS THE ONLY GAME. +experiments/phaseControllability.m measures
%   that a single aperture's transmitted phase cancels identically in the
%   monopulse ratio, so every phantom it radiates arrives on the drone's own
%   bearing. Two phantoms are therefore two tracks on one bearing, which the
%   co-bearing screen in +engine/runJudge.m answers directly -- PHASE_B_RESULTS
%   records 1.00 -> 0.00 the instant the difference channel is on. N >= 2 is
%   not hard for a single drone; it is unavailable. So the whole game is one
%   phantom.
%
%   TWO CONSTRAINTS THE DRONE MUST SATISFY, AND ONLY ONE IS OBVIOUS.
%
%   1. IT MUST NOT BE SEEN ITSELF. A drone outside the blind range reflects
%      the radar's own pulse, and that skin echo is a SECOND track sharing its
%      angular rate -- which is exactly the comparison
%      +track/emitterAttribution.m needs. Measured: one phantom plus a
%      detectable drone gives "source-or-real, radiated-fake", i.e. the
%      phantom is named. Inside c*PW/2 = 1798.75 m the receiver is deaf while
%      transmitting and no skin echo exists, so the drone must fly INSIDE its
%      own blind range. Causality is satisfied for free there, since every
%      phantom is further out anyway.
%
%   2. IT MUST FLY A TRAJECTORY THAT MATCHES THE RANGE IT IS CLAIMING. This is
%      the part with no signal-processing answer. The phantom inherits the
%      drone's angular rate while reporting its own range, and a genuine
%      constant-velocity target conserves R^2*dtheta/dt. Those agree only when
%      the two trajectories are PROPORTIONAL:
%
%          Rdot_drone / R_drone(0)  ==  Rdot_phantom / R_phantom(0)
%
%      so the drone's own closing speed is dictated by the range it wants the
%      phantom to claim. That is a flight-control problem, not a waveform one,
%      and it is the single-drone game's real cost.
%
%   WHAT THIS SWEEP MEASURES: over phantom range x drone radial speed, with
%   the drone hidden and crossing, how often the phantom is (a) confirmed,
%   (b) labelled `real` by the ECCM discriminator, and (c) NOT named by
%   attribution. All three are required -- a phantom that is confirmed and
%   labelled real but named `radiated-fake` has not won anything.

    p = inputParser;
    p.addParameter('PhantomRanges', [2300 2900 3600 4400], @isnumeric);
    p.addParameter('SpeedRatios', [0 1.0 1.5 2.5], @isnumeric);
    p.addParameter('PhantomRate', -50, @isscalar);
    p.addParameter('DroneRangeM', 1400, @isscalar);   % inside the blind range
    p.addParameter('DroneCrossMps', 3, @isscalar);
    p.addParameter('NumFrames', 8, @isscalar);
    p.addParameter('Seeds', 1:5, @isnumeric);
    p.parse(varargin{:});
    o = p.Results;

    C = physics.Constants();
    assert(o.DroneRangeM < C.blind_range, 'singleDroneEnvelope:droneVisible', ...
        ['the drone must sit inside the %.1f m blind range, or its own skin ' ...
         'return hands the judge the second track it needs'], C.blind_range);

    fprintf('\n=== SINGLE DRONE, SINGLE PHANTOM ===\n');
    fprintf('drone at %.0f m (inside the %.1f m blind range: no skin return), ', ...
            o.DroneRangeM, C.blind_range);
    fprintf('crossing at %.1f m/s\n', o.DroneCrossMps);
    fprintf('phantom closing at %+.0f m/s, %d frames, %d seeds per cell\n\n', ...
            o.PhantomRate, o.NumFrames, numel(o.Seeds));
    fprintf(['speed ratio 1.0 = the invariant-matching drone speed ' ...
             'Rdot_d = R_d*Rdot_p/R_p\n\n']);

    nR = numel(o.PhantomRanges); nS = numel(o.SpeedRatios);
    survive = zeros(nR, nS); conf = zeros(nR, nS);
    realLbl = zeros(nR, nS); score2c = nan(nR, nS); matched = nan(nR, 1);

    fprintf('%8s %10s |', 'Rp0 [m]', 'matched');
    for j = 1:nS; fprintf(' %12s', sprintf('x%.1f', o.SpeedRatios(j))); end
    fprintf('\n');

    for i = 1:nR
        Rp0 = o.PhantomRanges(i);
        matched(i) = o.DroneRangeM * o.PhantomRate / Rp0;
        fprintf('%8.0f %10.1f |', Rp0, matched(i));
        for j = 1:nS
            mrdot = matched(i) * o.SpeedRatios(j);
            [survive(i,j), conf(i,j), realLbl(i,j), score2c(i,j)] = ...
                localCell(o, Rp0, mrdot);
            fprintf(' %5d/%-6d', survive(i,j), numel(o.Seeds));
        end
        fprintf('\n');
    end

    fprintf('\nmean screen-2c score (>0.75 clears, <0.25 condemns, between = undetermined):\n');
    fprintf('%8s %10s |', 'Rp0 [m]', '');
    for j = 1:nS; fprintf(' %12s', sprintf('x%.1f', o.SpeedRatios(j))); end
    fprintf('\n');
    for i = 1:nR
        fprintf('%8.0f %10s |', o.PhantomRanges(i), '');
        for j = 1:nS; fprintf(' %12.3f', score2c(i,j)); end
        fprintf('\n');
    end

    % ---- the reading -----------------------------------------------------
    best = max(survive(:));
    [bi, bj] = find(survive == best, 1);
    fprintf('\n=== READING ===\n');
    fprintf('  best cell: Rp0 = %.0f m at %.1fx matched -> %d/%d survive\n', ...
        o.PhantomRanges(bi), o.SpeedRatios(bj), best, numel(o.Seeds));
    fprintf('\n  WHAT DECIDES A CELL, and it is not only the geometry. Screen 2c\n');
    fprintf('  separates "theta linear in 1/R" from "theta linear in t". Two\n');
    fprintf('  effects set how well it can:\n');
    fprintf('    (a) PHYSICS, second order: 1/R departs from linearity in t only\n');
    fprintf('        as (dR/R0)^2, so doubling the claimed range at a fixed\n');
    fprintf('        closing rate cuts the discriminating signal ~4x while the\n');
    fprintf('        bearing noise is unchanged.\n');
    fprintf('    (b) QUANTISATION, and at this radar it is comparable or larger:\n');
    fprintf('        R is measured as a STAIRCASE of %.2f m cells. At %+.0f m/s\n', ...
            C.range_per_sample, o.PhantomRate);
    fprintf('        the phantom crosses %.3f cells per frame, so it double-steps\n', ...
            abs(o.PhantomRate)/C.range_per_sample);
    fprintf('        occasionally, and WHERE those steps land changes the\n');
    fprintf('        genuine-model residual by more than an order of magnitude\n');
    fprintf('        (measured: rmsG 2.56e-5 vs 7.26e-4 at two neighbouring\n');
    fprintf('        ranges on otherwise identical geometry).\n');
    fprintf('\n  THE JITTER CHANGED THE ANSWER, WHICH IS THE POINT OF HAVING IT.\n');
    fprintf('  Without sub-cell jitter this sweep read 1/5,5/5,5/5,5/5 across the\n');
    fprintf('  2300 m row and 0/5 across most of 2900 and 3600 -- a dramatic\n');
    fprintf('  range dependence that was almost entirely ONE staircase per cell\n');
    fprintf('  repeated five times. Averaged over quantisation phase the same\n');
    fprintf('  sweep is broadly FLAT in range, and the mean 2c scores collapse\n');
    fprintf('  toward 0.5 instead of spanning 0.02-0.97.\n');
    fprintf('\n  WHAT SURVIVES AS A CLAIM, at N = %d seeds:\n', numel(o.Seeds));
    fprintf('    * The drone must be INSIDE the blind range. That is not in this\n');
    fprintf('      table -- it is the precondition for the table, measured\n');
    fprintf('      separately: a detectable drone supplies the second co-bearing\n');
    fprintf('      track and attribution names the phantom immediately.\n');
    fprintf('    * At the CLOSEST claimed range the drone''s own trajectory\n');
    fprintf('      decides: station-keeping %d/%d vs flying %d/%d.\n', ...
            survive(1,1), numel(o.Seeds), survive(1,end), numel(o.Seeds));
    fprintf('    * Beyond that, screen 2c is not discriminating: every cell sits\n');
    fprintf('      near %d-%d of %d whatever the drone does, and the mean score\n', ...
            min(survive(2:end,:), [], 'all'), max(survive(2:end,:), [], 'all'), ...
            numel(o.Seeds));
    fprintf('      sits in the undetermined band. The phantom gets a near-free\n');
    fprintf('      pass on bearing there -- it does not have to fly well.\n');
    fprintf('\n  DO NOT READ A RANGE TREND OFF THIS TABLE. Differences of one or\n');
    fprintf('  two counts at N = %d are not significant, and the only contrast\n', ...
            numel(o.Seeds));
    fprintf('  wide enough to survive a test is the %d/%d vs %d/%d one above.\n', ...
            survive(1,1), numel(o.Seeds), survive(1,end), numel(o.Seeds));

    out = struct('phantom_ranges_m', o.PhantomRanges, 'speed_ratios', o.SpeedRatios, ...
                 'matched_speed_mps', matched, 'survive', survive, ...
                 'confirmed', conf, 'labelled_real', realLbl, ...
                 'mean_screen_2c', score2c, 'n_seeds', numel(o.Seeds));
end


function [nSurvive, nConf, nReal, meanScore] = localCell(o, Rp0, mrdot)
%LOCALCELL  One (range, drone speed) cell, over the seed set.
%   SURVIVAL IS THE STRICT DEFINITION USED EVERYWHERE IN THIS PROJECT AND ONE
%   MORE: confirmed, labelled `real`, AND not named by attribution. A phantom
%   the discriminator accepts but the attribution names has not won -- the
%   operator is told which track was radiated, which is the whole point.
    nSurvive = 0; nConf = 0; nReal = 0; scores = [];
    C = physics.Constants();
    for s = o.Seeds
        rng(s, 'twister');
        % SUB-CELL RANGE JITTER, and it is not cosmetic. The measured range is
        % a STAIRCASE: at -50 m/s the phantom crosses 1.067 range cells per
        % frame, so it steps one cell most frames and two occasionally, and
        % WHERE those double-steps land dominates screen 2c's genuine-model
        % residual (measured: rmsG differs 28x between two neighbouring
        % ranges, 2.56e-5 vs 7.26e-4). Without this jitter every seed in a
        % cell shares one staircase and only the noise draw varies -- so five
        % seeds would report the confidence of one. Offsetting the start range
        % by a fraction of a cell per seed samples the quantisation phase,
        % which is the dominant variable here.
        offset = C.range_per_sample * (s - o.Seeds(1)) / numel(o.Seeds);
        try
            m = renderPhantomScene(Rp0 + offset, o.PhantomRate, 'NumFrames', o.NumFrames, ...
                'MotherRangeM', o.DroneRangeM, ...
                'MotherVelocityMps', [mrdot, o.DroneCrossMps, 0], ...
                'Tag', sprintf('sde_%d_%d_%d', round(Rp0), round(mrdot*10)+2000, s));
        catch ME
            % A veto is a real answer -- the drone physically cannot fly that
            % trajectory against that claim -- not an error to swallow.
            if contains(ME.message, 'causality') || contains(ME.message, 'eclipse')
                continue
            end
            rethrow(ME)
        end
        fb = engine.runJudge(m, 'EccmScreens', {'amplitude', 'doppler', 'bearing'});
        if fb.confirmed_tracks < 1; continue; end
        nConf = nConf + 1;
        isReal = fb.track_label{1} == "real";
        nReal = nReal + double(isReal);
        v = track.emitterAttribution(fb);
        scores(end+1) = track.bearingRateScreen(fb.track_azimuth_rad{1}, ...
            fb.track_range_m{1}, fb.track_time_s{1}); %#ok<AGROW>
        if isReal && v(1) ~= "radiated-fake"
            nSurvive = nSurvive + 1;
        end
    end
    meanScore = mean(scores, 'omitnan');
end
