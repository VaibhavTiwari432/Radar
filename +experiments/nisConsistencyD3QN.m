function out = nisConsistencyD3QN(nEp, seed, outDir)
%NISCONSISTENCYD3QN  Does the agent's emitted track look like the next
%   deterministic position of ONE moving body? (POA Phase 3, T7)
%
%   out = experiments.nisConsistencyD3QN(nEp, seed, outDir)
%
%   THE QUESTION, STATED PHYSICALLY. A real object's frame k+1 is not a free
%   choice -- it is what x_{k+1} = f(x_k, dt) produces. A tracker tests this
%   directly: it predicts the next range from frames 1..k and measures the
%   innovation. NIS (normalised innovation squared) is that residual scaled
%   by the filter's own predicted covariance, so a self-consistent target
%   sits inside the chi-square band and an object tracing a path no single
%   body could trace does not.
%
%   REUSES THE PROJECT'S OWN MACHINERY on purpose:
%   engine.track.shadowEKF and the same in-band gate as
%   +experiments/benchmarkSuite.m's shadowDiagnostics. A privately-written
%   NIS would not be comparable to the number already published for the VEE
%   (85.7% in-band, BENCHMARK_RESULTS.md), and comparability is the whole
%   point of computing it.
%
%   ONE DELIBERATE DIFFERENCE. shadowDiagnostics feeds TRUTH ranges through
%   `quant()` to simulate the range-bin quantiser. Here the series is already
%   the CFAR-measured range out of the environment, so it is fed as-is --
%   re-quantising an already-quantised series would double-count the effect.
%
%   NIS ONLY. The lag-1 innovation whiteness statistic is NOT computed.
%   BENCHMARK_RESULTS.md tested it, found rho swinging -0.254 / -0.185 /
%   +0.282 / -0.283 / +0.022 across -30..-150 m/s for targets that were ALL
%   genuine, and withdrew it as not generator-attributable. Re-deriving it
%   here would repeat a documented mistake.
%
%   ARMS. Each is a different GENERATOR at the same judge, so any difference
%   is attributable to how the signal was made:
%     unproj-random     24 DOF, no constraint
%     unproj-trained    24 DOF, 1200 episodes (results/doppler_agent_shaped.mat)
%     proj-random       9 DOF  (manifold projection, free range walk)
%     proj-coherent     3 DOF  (projection + a CV trajectory)

    if nargin < 1 || isempty(nEp);  nEp = 150; end
    if nargin < 2 || isempty(seed); seed = 77; end
    if nargin < 3 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results');
    end
    if ~isfolder(outDir); mkdir(outDir); end

    C  = physics.Constants();
    q  = engine.entity.calibrateQ();
    dt = 1.0;

    trained = [];
    f = fullfile(outDir, 'doppler_agent_shaped.mat');
    if isfile(f); S = load(f); trained = S.agnt; end

    arms = { ...
        'unproj-random',   false, 'random',   [] ; ...
        'unproj-trained',  false, 'agent',    trained ; ...
        'proj-random',     true,  'random',   [] ; ...
        'proj-coherent',   true,  'coherent', [] };

    out = struct('armName', {{}}, 'nisInBand', [], 'nisLo', [], 'nisHi', [], ...
        'nEpUsed', [], 'nSamples', [], ...
        'nZero', [], 'nOver', [], 'nisInBandInformative', [], ...
        'infLo', [], 'infHi', []);

    fprintf('nisConsistencyD3QN: %d episodes/arm, gate = benchmarkSuite''s\n', nEp);
    for a = 1:size(arms,1)
        name = arms{a,1}; proj = arms{a,2}; mode = arms{a,3}; agnt = arms{a,4};
        if strcmp(mode,'agent') && isempty(agnt)
            fprintf('  %-16s SKIPPED (no trained agent on disk)\n', name);
            continue;
        end
        env = agent.buildEnvDoppler(C, [], struct('project', proj, 'shaping', false));
        [inBand, nEpUsed, nSamp, nZero, nOver] = localArm(env, mode, agnt, nEp, seed, q, dt, C);
        [lo, hi] = localWilson(round(inBand*nSamp), nSamp);
        % Informative denominator: drop the degenerate NIS~0 innovations,
        % which are uninformative rather than inconsistent. This is the
        % honest estimate; the raw fraction above is a floor.
        nInf = nSamp - nZero;
        pInf = NaN; iLo = NaN; iHi = NaN;
        if nInf > 0
            pInf = round(inBand*nSamp) / nInf;
            [iLo, iHi] = localWilson(round(inBand*nSamp), nInf);
        end
        out.armName{end+1} = name;
        out.nisInBand(end+1) = inBand;
        out.nisLo(end+1) = lo; out.nisHi(end+1) = hi;
        out.nEpUsed(end+1) = nEpUsed; out.nSamples(end+1) = nSamp;
        out.nZero(end+1) = nZero; out.nOver(end+1) = nOver;
        out.nisInBandInformative(end+1) = pInf;
        out.infLo(end+1) = iLo; out.infHi(end+1) = iHi;
        fprintf(['  %-16s NIS in-band %5.1f%% [%.1f, %.1f] (floor, n=%d)  |  ' ...
                 'informative %5.1f%% [%.1f, %.1f] (n=%d)  |  zero %d  over %d\n'], ...
            name, 100*inBand, 100*lo, 100*hi, nSamp, ...
            100*pInf, 100*iLo, 100*iHi, nInf, nZero, nOver);
    end

    fprintf('\n  published reference (BENCHMARK_RESULTS.md, same gate):\n');
    fprintf('     VEE phantom 85.7%%  |  naive DRFM 86.4%%  |  BruteForce 100.0%%\n');

    fo = fullfile(outDir, 'nis_consistency_d3qn.mat');
    save(fo, '-struct', 'out');
    fprintf('\nsaved -> %s\n', fo);
end

% ========================================================================
function [inBand, nEpUsed, nSamp, nZero, nOver] = localArm(env, mode, agnt, nEp, seed, q, dt, C) %#ok<INUSD>
%   nZero / nOver decompose the OUT-of-band count, which the headline
%   fraction alone cannot distinguish (T7 confound, closed 28 Jul 2026):
%     nZero  nis <= 0.001. A DEGENERATE innovation, not an inconsistent one.
%            A stationary draw (delta = 0) holds range constant, the EKF
%            predicts it exactly, and NIS collapses to ~0. The gate below
%            counts that as out-of-band, which DEFLATES the reported
%            fraction -- so the headline is a FLOOR, not an estimate.
%     nOver  nis > gate. Genuinely inconsistent with the filter.
%   The informative fraction hits/(nSamp-nZero) is the honest estimate.
    rng(seed);
    gate = 2*erfinv(0.99)^2;          % identical to shadowDiagnostics
    hits = 0; nSamp = 0; nEpUsed = 0; nZero = 0; nOver = 0;
    for e = 1:nEp
        obs = reset(env);
        di = randi(5); gi = randi(5);          % for the coherent arm
        lg = [];
        for k = 1:8
            switch mode
                case 'random';   act = randi(125);
                case 'coherent'; act = sub2ind([5 5 5], di, gi, 3);
                otherwise
                    act = getAction(agnt, {obs});
                    if iscell(act); act = act{1}; end
                    act = double(act);
            end
            [obs, ~, ~, lg] = step(env, act);
        end
        r = lg.rangeHist(~isnan(lg.rangeHist));
        if numel(r) < 3; continue; end          % need >=2 innovations
        nEpUsed = nEpUsed + 1;
        fEKF = engine.track.shadowEKF([], r(1), dt, 'Class', 'fighter', ...
                    'SigmaAccelMps2', q.sigma_accel_mps2);
        for k = 2:numel(r)
            [fEKF, o] = engine.track.shadowEKF(fEKF, r(k), dt);
            nSamp = nSamp + 1;
            if o.nis <= 0.001
                nZero = nZero + 1;            % degenerate, not inconsistent
            elseif o.nis <= gate
                hits = hits + 1;
            else
                nOver = nOver + 1;            % genuinely out of band
            end
        end
    end
    if nSamp == 0; inBand = NaN; else; inBand = hits / nSamp; end
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end
