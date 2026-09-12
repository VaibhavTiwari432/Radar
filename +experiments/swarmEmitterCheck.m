function results = swarmEmitterCheck(varargin)
%SWARMEMITTERCHECK  The SECOND wall: does the swarm beat emitter attribution?
%
%   results = experiments.swarmEmitterCheck('Name', value, ...)
%
%   Phase 1 showed a spread swarm beats the co-bearing LABEL. But
%   +track/emitterAttribution.m is a separate diagnostic that keys on ANGULAR
%   RATE: N tracks at different ranges sharing ONE omega were radiated from one
%   aperture; a genuine formation has N different omegas (omega = v_cross/R).
%
%   Two swarm modes, both spread 2 deg (inside the co-bearing window), each
%   phantom at a far range while its drone sits at 900 m:
%     'static'  every phantom at a CONSTANT bearing -> omega ~ 0 for all,
%               SHARED. Predicted: beats the label, caught by emitter attribution.
%     'moving'  each drone crosses at its OWN speed -> each phantom's bearing
%               sweeps at its own omega, DIVERSE. Predicted: beats both -- and is
%               indistinguishable from a genuine formation, which is signal-
%               identical (N returns at N independently-moving bearings).
%
%   Reports, per mode: label survivors (co-bearing wall) and the count of tracks
%   emitter attribution calls "radiated-fake" (emitter wall). A swarm deceives
%   only if BOTH are clean.

    p = inputParser;
    p.addParameter('N', 4);
    p.addParameter('SpreadDeg', 2.0);
    p.addParameter('NumSeeds', 10);
    p.addParameter('DroneRangeM', 900);
    p.addParameter('StartRangeM', 2400);
    p.addParameter('SpacingM', 1200);
    p.addParameter('RateMps', -35);
    p.addParameter('CrossSpeedsMps', []);   % [] -> linspace(-3,3,N) for 'moving'
    p.addParameter('UseBaseline2', false, @islogical);   % the radar's swarm counter
    p.addParameter('SeedOffset', 0);   % seeds SeedOffset+(1:NumSeeds); 0 = the published runs
    p.addParameter('MeasurementSpace', 'range');   % runJudge's; 'range' = the published runs
    p.parse(varargin{:});
    o = p.Results;

    N = o.N;
    ranges = o.StartRangeM + o.SpacingM * (0:N-1);
    rcs = 1.0 * (ranges / o.StartRangeM).^4;             % equal received power
    frameTimes = 0:7;                                     % 8 frames at 1 s
    s = deg2rad(o.SpreadDeg);
    az0 = linspace(-s/2, s/2, N)';                        % mean bearing per drone
    % Cross speeds bounded so a drone at DroneRangeM stays inside the +-2.866 deg
    % monopulse sector for the whole 8 s dwell (|v|*8/DroneRangeM < sector):
    % at 900 m that caps |v| ~ 5 m/s. Distinct values -> distinct omega.
    cross = o.CrossSpeedsMps; if isempty(cross); cross = linspace(-4.5, 4.5, N); end

    fprintf('\n=== SWARM EMITTER CHECK [SIM] === N=%d spread=%.1f deg, %d seeds\n', ...
        N, o.SpreadDeg, o.NumSeeds);
    fprintf('%-8s %14s %20s\n', 'mode', 'label surv', 'radiated-fake (of N)');
    results = struct('mode', {}, 'meanSurvivors', {}, 'meanRadiatedFake', {});

    % Genuine formation: each member's cross speed AT ITS OWN RANGE, kept in
    % the sector. Its bearing follows its own position, so implied cross speed
    % (omega*R) equals its real speed -- the honest reference for emitter
    % attribution. Distinct ranges give distinct omega even at equal speed.
    vGen = linspace(-10, 10, N);

    for mode = ["static", "moving", "genuine"]
        % Per-phantom bearing series [N x numFrames].
        az = zeros(N, numel(frameTimes));
        for i = 1:N
            if mode == "static"
                az(i, :) = az0(i);                        % constant -> omega ~ 0
            elseif mode == "genuine"
                az(i, :) = atan2(vGen(i) * frameTimes, ranges(i));  % bearing from OWN range
            else
                % Each drone starts on boresight and crosses at its OWN speed,
                % so its azimuth sweeps at its own omega. Starting at boresight
                % maximises the in-sector travel; the distinct speeds give
                % distinct omegas, which is what emitter attribution groups on.
                az(i, :) = atan2(cross(i) * frameTimes, o.DroneRangeM);
            end
        end
        survivors = zeros(1, o.NumSeeds); radiatedFake = zeros(1, o.NumSeeds);
        for seed = 1:o.NumSeeds
            rng(seed + o.SeedOffset, 'twister');
            jm = renderPhantomScene(ranges, o.RateMps, 'Rcs', rcs, ...
                'MotherRangeM', o.DroneRangeM, 'NumFrames', 8, 'NumPulses', 32, ...
                'SourceAzimuthRad', 0, 'PhantomAzimuthRad', az, ...
                'IncludeSecondBaseline', o.UseBaseline2, ...
                'Tag', sprintf('swemit_%s_b2%d_%d', mode, o.UseBaseline2, seed + o.SeedOffset));
            fb = engine.runJudge(jm, 'MeasurementSpace', o.MeasurementSpace);
            lbl = cellstr(fb.track_label);
            survivors(seed) = nnz(strcmp(lbl, 'real'));
            verdict = track.emitterAttribution(fb);
            radiatedFake(seed) = nnz(verdict == "radiated-fake");
        end
        fprintf('%-8s %14.2f %20.2f\n', mode, mean(survivors), mean(radiatedFake));
        results(end+1) = struct('mode', char(mode), ...
            'meanSurvivors', mean(survivors), 'meanRadiatedFake', mean(radiatedFake)); %#ok<AGROW>
    end
end
