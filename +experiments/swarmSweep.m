function results = swarmSweep(varargin)
%SWARMSWEEP  Does a multi-drone swarm break the co-bearing wall? (Track A, SIM)
%
%   results = experiments.swarmSweep('Name', value, ...)
%
%   Each trial builds N on-manifold phantoms (one per drone), each radiated from
%   its OWN bearing via +generator/render.m's PhantomAzimuthRad. A single-
%   aperture swarm (spread 0) is the F7 wall; a spread swarm inside the monopulse
%   unambiguous sector should escape it. "Survivor" = a confirmed track the judge
%   labels 'real'; "fully survives" = all N real. Predictions in
%   SWARM_PREDICTIONS.md were committed before this ran.
%
%   Name-value
%       'Ns'         [2 4 8]      swarm sizes
%       'SpreadsDeg' [0 1 2 4 7]  TOTAL azimuth spread across the swarm; 0 is the
%                                 single-aperture wall, 7 exceeds the +-2.866 deg
%                                 sector (wrap). Drones placed evenly in
%                                 [-s/2, +s/2].
%       'NumSeeds'   20           Monte-Carlo trials per (N, spread)
%       'EqualPower' true         scale RCS ~ R^4 so far drones do not fade
%       'StartRangeM' 1900        first phantom range (clear of blind range)
%       'SpacingM'   1200         range spacing (clears the CFAR window)
%       'RateMps'    -35          each phantom's closing rate
%
%   Wilson CIs on P(fully survives), per Blueprint Rule 5.

    p = inputParser;
    p.addParameter('Ns', [2 4 8]);
    p.addParameter('SpreadsDeg', [0 1 2 4 7]);
    p.addParameter('NumSeeds', 20);
    p.addParameter('EqualPower', true, @islogical);
    % 2400 m, not 1900: at -35 m/s over 8 frames a phantom closes 245 m, so a
    % 1900 m start ends at 1655 m -- inside the 1799 m blind range and vetoed.
    % 2400 m ends at 2155 m, clear for the whole dwell.
    p.addParameter('StartRangeM', 2400);
    p.addParameter('SpacingM', 1200);
    p.addParameter('RateMps', -35);
    p.parse(varargin{:});
    o = p.Results;

    fprintf('\n=== SWARM SWEEP [SIM] === %d seeds, equalPower=%d\n', o.NumSeeds, o.EqualPower);
    fprintf('%4s %10s %12s %12s %20s\n', 'N', 'spread', 'meanSurv', 'meanFlag', 'P(all real) 95%CI');
    rows = struct('N', {}, 'spreadDeg', {}, 'meanSurvivors', {}, 'meanFlagged', {}, ...
                  'pAllReal', {}, 'ciLow', {}, 'ciHigh', {}, 'n', {});

    for N = o.Ns
        ranges = o.StartRangeM + o.SpacingM * (0:N-1);
        if o.EqualPower
            rcs = 1.0 * (ranges / o.StartRangeM).^4;   % equalise received power
        else
            rcs = ones(1, N);
        end
        for sDeg = o.SpreadsDeg
            s = deg2rad(sDeg);
            if N == 1 || sDeg == 0
                az = zeros(N, 1);
            else
                az = linspace(-s/2, s/2, N)';
            end
            survivors = zeros(1, o.NumSeeds);
            flagged   = zeros(1, o.NumSeeds);
            allReal   = 0;
            for seed = 1:o.NumSeeds
                rng(seed, 'twister');
                jm = renderPhantomScene(ranges, o.RateMps, 'Rcs', rcs, ...
                    'MotherRangeM', 900, 'NumFrames', 8, 'NumPulses', 32, ...
                    'SourceAzimuthRad', 0, 'PhantomAzimuthRad', az, ...
                    'Tag', sprintf('swarm_N%d_s%d_%d', N, round(sDeg*10), seed));
                fb = engine.runJudge(jm);
                lbl = cellstr(fb.track_label);
                survivors(seed) = nnz(strcmp(lbl, 'real'));
                flagged(seed)   = nnz(strcmp(lbl, 'decoy'));
                if fb.confirmed_tracks >= N && all(strcmp(lbl, 'real'))
                    allReal = allReal + 1;
                end
            end
            [pHat, lo, hi] = localWilson(allReal, o.NumSeeds);
            fprintf('%4d %9.1fd %12.2f %12.2f %6.2f [%.2f, %.2f]\n', ...
                N, sDeg, mean(survivors), mean(flagged), pHat, lo, hi);
            rows(end+1) = struct('N', N, 'spreadDeg', sDeg, ...
                'meanSurvivors', mean(survivors), 'meanFlagged', mean(flagged), ...
                'pAllReal', pHat, 'ciLow', lo, 'ciHigh', hi, 'n', o.NumSeeds); %#ok<AGROW>
        end
    end
    results = rows;
end

function [pHat, lo, hi] = localWilson(k, n)
    z = 1.96; pHat = k / n; denom = 1 + z^2/n;
    center = (pHat + z^2/(2*n)) / denom;
    half = (z/denom) * sqrt(pHat*(1-pHat)/n + z^2/(4*n^2));
    lo = max(0, center - half); hi = min(1, center + half);
end
