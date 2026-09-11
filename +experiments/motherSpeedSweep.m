function T = motherSpeedSweep(varargin)
%MOTHERSPEEDSWEEP  Does the mother drone's speed and heading change deception? (SIM)
%
%   T = experiments.motherSpeedSweep('Name', value, ...)
%
%   One mother drone at 4000 m (its crossing path centred on boresight, so 50 m/s
%   stays inside the +-2.864 deg monopulse sector), K phantoms from 6400 m out.
%   Every cell is one experiments.skinBacktrackCheck call on the moving-mother
%   platform path, swarm vs genuine formation. Heading 0 = closing, 90 =
%   crossing. Predictions S1-S6 in SWARM_PREDICTIONS.md were committed first.
%
%   'Env' "thermal" (clutter and MTI off) or "clutter_mti" (-15 dB land clutter
%   plus the 3.75 m/s MTI notch, which removes radial speeds below ~5.6 m/s).

    p = inputParser;
    p.addParameter('SpeedMps', [0 10 20 35 50]);
    p.addParameter('HeadingDeg', [0 45 90]);
    p.addParameter('K', [1 3]);
    p.addParameter('PlatformRcs', 0.1);
    p.addParameter('NumSeeds', 10);
    p.addParameter('Env', "thermal");
    p.parse(varargin{:});
    o = p.Results;

    env = {};
    if o.Env == "clutter_mti"; env = {'ClutterGammaDB', -15, 'MtiNotchMps', 3.75}; end
    [S, H] = ndgrid(o.SpeedMps, o.HeadingDeg);
    cells = unique([S(:), H(:) .* (S(:) > 0)], 'rows');   % speed 0 once
    T = table();
    for K = o.K
        for i = 1:size(cells, 1)
            sp = cells(i, 1); hd = cells(i, 2);
            vel = sp * [-cosd(hd), sind(hd)];               % [closing(-x), crossing(+y)]
            r = struct2table(experiments.skinBacktrackCheck('N', 1, 'K', K, ...
                'DroneStartM', 4000, 'GapM', 2400, 'SpreadDeg', 1, ...
                'PlatformRcs', o.PlatformRcs, 'NumSeeds', o.NumSeeds, ...
                'DroneVelocityMps', vel, 'Arms', ["swarm", "genuine"], env{:}), ...
                'AsArray', true);
            r.speed = repmat(sp, height(r), 1);
            r.heading = repmat(hd, height(r), 1);
            r.env = repmat(string(o.Env), height(r), 1);
            T = [T; r]; %#ok<AGROW>
        end
    end
    fprintf('\n=== MOTHER SPEED SWEEP [SIM] summary, env %s ===\n', o.Env);
    fprintf('%2s %6s %4s %-8s %6s %6s %6s %6s %6s\n', 'K', 'speed', 'hdg', 'arm', ...
        'skin', 'cob', 'real', 'backtk', 'EAfake');
    for i = 1:height(T)
        fprintf('%2d %6g %4g %-8s %6.2f %6.2f %6.2f %6.2f %6.2f\n', T.K(i), T.speed(i), ...
            T.heading(i), T.arm{i}, T.skinDetected(i), T.cobFlagged(i), T.farReal(i), ...
            T.farBacktracked(i), T.farFake(i));
    end
end
