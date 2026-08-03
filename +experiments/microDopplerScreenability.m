function out = microDopplerScreenability(pulseCounts, nSeeds, outDir)
%MICRODOPPLERSCREENABILITY  Could a micro-Doppler ECCM screen separate a real
%   drone from a DRFM phantom -- and what dwell would the radar have to pay?
%
%   out = experiments.microDopplerScreenability(pulseCounts, nSeeds, outDir)
%
%   WHY THIS AND NOT "RE-RUN THE BENCHMARK". +engine/runJudge.m and
%   +track/discriminator.m contain ZERO references to micro-Doppler: the ECCM
%   screens amplitude-vs-range, Doppler sign and co-bearing, nothing else. So
%   re-running +experiments/benchmarkSuite.m after changing render.m's
%   micro-Doppler model is guaranteed to return identical numbers -- not
%   because the model does not matter, but because nothing scores it. The
%   answerable question is whether the physics is SCREENABLE at all.
%
%   THE PHYSICAL ASYMMETRY. A DRFM repeater retransmits the radar's own pulse
%   with a delay, a gain and a CONSTANT phase (+synth/synthesizeSwarm.m does
%   exactly those three). Constant phase across slow time is a single Doppler
%   line. A rotor phase-modulates its return, which by Jacobi-Anger is a comb.
%   A phantom claiming to be a drone but showing no comb is catchable.
%
%   ---------------------------------------------------------------------
%   WHAT THE FIRST VERSION OF THIS FILE GOT WRONG (27 July 2026)
%   ---------------------------------------------------------------------
%   1. DEGENERATE VARIANCE. It rendered with swerling=0 at a fixed range,
%      velocity and blade rate, so every seed produced almost the same
%      combFrac and the only spread was receiver noise at very high SNR.
%      d' then divided a real mean difference by an almost-zero pooled sigma
%      and reported values up to 15697 -- an artefact of the design, not a
%      separation. FIXED: Swerling-1 fluctuation, and range, range-rate and
%      blade rate are drawn per seed across the MEASURED operating band.
%      A screen that only works at exactly 150 Hz would be useless anyway.
%
%   2. A GUARD THAT ATE THE SIGNAL. It excluded a fixed +-2 bins around the
%      main line. But the first comb line sits at f_blade, which is only
%      f_blade/dopplerRes bins out -- 0.10 bins at 32 pulses, 1.54 at 512.
%      So at short dwells the comb fell INSIDE the guard and was subtracted
%      away, and AUC flipped non-monotonically (0, 1, 1, 0, 1, 1) depending
%      on which lines happened to escape. The +-2-bin mainlobe guard is
%      CORRECT for a rectangular slow-time window; the error was reporting
%      rows where the comb is physically unresolvable as if they were
%      measurements. FIXED: linesResolved = f_blade/dopplerRes is computed
%      and reported per row, and rows below the Rayleigh-style criterion
%      (linesResolved < 2) are flagged UNRESOLVED rather than interpreted.
%
%   FEATURE (deliberately BLIND, as a real screen must be): combFrac =
%   fraction of the range cell's slow-time energy outside the main Doppler
%   lobe. It does not assume knowledge of f_blade, because an ECCM screen
%   does not get told the rotor rate of the thing it is looking at.
%
%   CONTROL: a 'fighter' entity is rendered alongside. render.m grants
%   micro-Doppler only to CLASSES_EXPECTING_MICRO, so a fighter must land on
%   top of the phantom. If it does not, combFrac is measuring something other
%   than rotor modulation and the drone/phantom gap means nothing.

    if nargin < 1 || isempty(pulseCounts); pulseCounts = [32 64 128 256 512 1024]; end
    if nargin < 2 || isempty(nSeeds);      nSeeds = 40; end
    if nargin < 3 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results');
    end
    if ~isfolder(outDir); mkdir(outDir); end

    C = physics.Constants();
    K = struct('PRF_HZ', physics.Constants().PRF, 'CARRIER', 10e9, 'PW_S', 12e-6, 'BW_HZ', 2e6, ...
               'N_FAST', 400, 'AMP', 3.0);
    lambda = C.c / K.CARRIER;
    % Operating band, all MEASURED or established rather than picked:
    % blade rate from the TSMS-Drone CW set (100-200 Hz across four drone
    % types); range/velocity from this project's own canonical engagement.
    BLADE_LO = 100; BLADE_HI = 200;
    R_LO = 1500; R_HI = 2500;
    V_LO = -100; V_HI = -40;

    nP = numel(pulseCounts);
    combDrone   = nan(nP, nSeeds);
    combPhantom = nan(nP, nSeeds);
    combFighter = nan(nP, nSeeds);
    bladeUsed   = nan(nP, nSeeds);

    fprintf('microDopplerScreenability: blade %g-%g Hz, Swerling 1, %d seeds\n', ...
        BLADE_LO, BLADE_HI, nSeeds);
    t0 = tic;
    for ip = 1:nP
        nPul = pulseCounts(ip);
        for s = 1:nSeeds
            % One stream per (dwell, seed) so the SCENARIO is identical
            % across dwell lengths and only the integration changes.
            sc = RandStream('twister', 'Seed', 90000 + s);
            R0      = R_LO + (R_HI-R_LO)*rand(sc);
            VR      = V_LO + (V_HI-V_LO)*rand(sc);
            bladeHz = BLADE_LO + (BLADE_HI-BLADE_LO)*rand(sc);
            bladeUsed(ip,s) = bladeHz;

            rs = RandStream('twister', 'Seed', 4200 + s);

            sd = engine.entity.EntityState('range_m', R0, 'range_rate_mps', VR, ...
                    'class', 'drone', 'rcs_dbsm', 0, 'swerling', 1, ...
                    'micro_doppler_hz', bladeHz);
            cd_ = engine.entity.render(sd, 'AmpScale', K.AMP, 'NumPulses', nPul, ...
                    'FastTimeSamples', K.N_FAST, 'CarrierHz', K.CARRIER, ...
                    'PrfHz', K.PRF_HZ, 'PulseWidth', K.PW_S, 'Bandwidth', K.BW_HZ, ...
                    'RandStream', rs);

            sf = engine.entity.EntityState('range_m', R0, 'range_rate_mps', VR, ...
                    'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 1);
            cf = engine.entity.render(sf, 'AmpScale', K.AMP, 'NumPulses', nPul, ...
                    'FastTimeSamples', K.N_FAST, 'CarrierHz', K.CARRIER, ...
                    'PrfHz', K.PRF_HZ, 'PulseWidth', K.PW_S, 'Bandwidth', K.BW_HZ, ...
                    'RandStream', rs);

            % DRFM phantom: same claimed kinematics, built through the
            % project's own repeater (delay + gain + constant phase).
            wav = phased.LinearFMWaveform('SampleRate', C.fs, 'PulseWidth', K.PW_S, ...
                    'PRF', K.PRF_HZ, 'SweepBandwidth', K.BW_HZ);
            pulse = wav();
            mfLen = numel(getMatchedFilter(wav));
            xT = [pulse(1:mfLen); zeros(K.N_FAST - mfLen, 1)];
            dopHz = -2 * VR / lambda;
            pri = 1 / K.PRF_HZ;
            cp = complex(zeros(K.N_FAST, nPul));
            for q = 0:(nPul-1)
                a = struct('delay_s', 2*R0/C.c, ...
                           'phase_rad', 2*pi*dopHz*(q*pri), 'gain', K.AMP);
                cp(:, q+1) = synth.synthesizeSwarm(xT, a, C);
            end

            combDrone(ip,s)   = localCombFrac(cd_, wav, C, rs);
            combFighter(ip,s) = localCombFrac(cf, wav, C, rs);
            combPhantom(ip,s) = localCombFrac(cp, wav, C, rs);
        end
        dopRes = K.PRF_HZ / nPul;
        lr = mean(bladeUsed(ip,:)) / dopRes;
        fprintf(['  %5d pulses | dopRes %7.1f Hz | linesResolved %5.2f %s | ' ...
                 'drone %.4f  fighter %.4f  phantom %.4f | AUC %.3f  [%.1f min]\n'], ...
            nPul, dopRes, lr, localFlag(lr), mean(combDrone(ip,:),'omitnan'), ...
            mean(combFighter(ip,:),'omitnan'), mean(combPhantom(ip,:),'omitnan'), ...
            localAUC(combDrone(ip,:), combPhantom(ip,:)), toc(t0)/60);
    end

    dopplerResHz = K.PRF_HZ ./ pulseCounts(:);
    linesResolved = mean(bladeUsed, 2, 'omitnan') ./ dopplerResHz;

    out = struct('pulseCounts', pulseCounts(:), 'nSeeds', nSeeds, ...
        'combDrone', combDrone, 'combPhantom', combPhantom, ...
        'combFighter', combFighter, 'bladeUsed', bladeUsed, ...
        'prfHz', K.PRF_HZ, 'dopplerResHz', dopplerResHz, ...
        'linesResolved', linesResolved, 'elapsedMin', toc(t0)/60);
    out.auc    = arrayfun(@(i) localAUC(combDrone(i,:), combPhantom(i,:)), (1:nP)');
    out.dPrime = arrayfun(@(i) localDPrime(combDrone(i,:), combPhantom(i,:)), (1:nP)');
    out.aucCI  = cell2mat(arrayfun(@(i) localAUCci(combDrone(i,:), combPhantom(i,:)), ...
                    (1:nP)', 'uni', 0));
    % linesResolved > 1, i.e. nPulses > PRF/f_blade. See localFlag for why
    % this is 1 and not the 2 originally assumed -- the second harmonic
    % escapes the mainlobe before the first does.
    out.resolvedCriterion = 1;

    f = fullfile(outDir, 'micro_doppler_screenability.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s (%.1f min)\n', f, out.elapsedMin);

    fprintf('\n pulses  dopRes   lines    drone   phantom  fighter    AUC [95%% CI]      d''    verdict\n');
    for ip = 1:nP
        fprintf(' %6d %7.1f %7.2f  %.4f  %.4f  %.4f  %.3f [%.2f,%.2f] %7.2f   %s\n', ...
            pulseCounts(ip), dopplerResHz(ip), linesResolved(ip), ...
            mean(combDrone(ip,:),'omitnan'), mean(combPhantom(ip,:),'omitnan'), ...
            mean(combFighter(ip,:),'omitnan'), out.auc(ip), ...
            out.aucCI(ip,1), out.aucCI(ip,2), out.dPrime(ip), localFlag(linesResolved(ip)));
    end
    fprintf(['\nRows marked UNRESOLVED sit below linesResolved = %d: the first comb line ' ...
             'falls\ninside the slow-time mainlobe, so a blind screen physically cannot ' ...
             'see it there.\nTheir AUC is not evidence either way.\n'], out.resolvedCriterion);
end

% ========================================================================
function s = localFlag(lr)
%LOCALFLAG  Resolvability criterion, CORRECTED BY THE DATA (27 July 2026).
%
%   This started at linesResolved >= 2, reasoning that the FIRST comb line
%   (at f_blade) had to clear the +-2-bin mainlobe. The measurement says
%   otherwise: at 512 pulses linesResolved = 1.56 -- first line still inside
%   the lobe -- and the screen already reaches AUC 1.000 [1.00, 1.00].
%
%   The reason is that beta ~ 2 at this band, so J_2 is substantial and the
%   SECOND harmonic at 2*f_blade escapes the lobe while the first is still
%   buried. The screen only needs SOME significant line outside the mainlobe,
%   not the first one. That puts the criterion at
%
%       2*f_blade > 2*dopplerRes   <=>   linesResolved > 1
%                                  <=>   nPulses > PRF / f_blade
%
%   which the sweep confirms exactly: 256 pulses (0.78) fails at AUC 0.788,
%   512 pulses (1.56) succeeds at 1.000.
    if lr > 1; s = 'resolved'; else; s = 'UNRESOLVED'; end
end

% ------------------------------------------------------------------------
function cf = localCombFrac(cube, wav, C, rs)
%LOCALCOMBFRAC  Slow-time energy outside the main Doppler lobe, at the range
%   cell holding the return. Uses the judge's own chain so the number is what
%   the radar could actually see.
    nPul = size(cube, 2);
    nz = 0.05 * (randn(rs, size(cube,1), nPul) + 1i*randn(rs, size(cube,1), nPul))/sqrt(2);
    cube = cube + nz;
    compressed = complex(zeros(size(cube)));
    for q = 1:nPul
        [~, compressed(:,q)] = radar.pulseCompress(cube(:,q), wav);
    end
    [rdMap, ~, ~] = radar.rangeDoppler(compressed, wav, C);
    [~, rBin] = max(max(rdMap, [], 2));
    spec = rdMap(rBin, :);
    tot = sum(spec);
    if ~(tot > 0); cf = NaN; return; end
    % +-2 bins is the rectangular-window mainlobe, a property of the DFT and
    % therefore correct at every dwell length. Where the comb falls inside it,
    % the comb is genuinely unresolvable -- that is reported as UNRESOLVED
    % rather than worked around.
    [~, dBin] = max(spec);
    idx = 1:numel(spec);
    cf = sum(spec(abs(idx - dBin) > 2)) / tot;
end

% ------------------------------------------------------------------------
function d = localDPrime(a, b)
    a = a(isfinite(a)); b = b(isfinite(b));
    if numel(a) < 2 || numel(b) < 2; d = NaN; return; end
    sp = sqrt((var(a) + var(b)) / 2);
    if sp <= eps; d = NaN; return; end        % degenerate: refuse to report
    d = (mean(a) - mean(b)) / sp;
end

% ------------------------------------------------------------------------
function auc = localAUC(pos, neg)
    pos = pos(isfinite(pos)); neg = neg(isfinite(neg));
    if isempty(pos) || isempty(neg); auc = NaN; return; end
    r = tiedrank([pos(:); neg(:)]);
    auc = (sum(r(1:numel(pos))) - numel(pos)*(numel(pos)+1)/2) / (numel(pos)*numel(neg));
end

% ------------------------------------------------------------------------
function ci = localAUCci(pos, neg)
%LOCALAUCCI  Hanley-McNeil 95% interval on the AUC. An AUC of 1.000 from 40
%   samples is not the same claim as an AUC of 1.000 from 4000, and the
%   interval is what says so.
    pos = pos(isfinite(pos)); neg = neg(isfinite(neg));
    if isempty(pos) || isempty(neg); ci = [NaN NaN]; return; end
    a = localAUC(pos, neg); m = numel(pos); n = numel(neg);
    q1 = a/(2-a); q2 = 2*a^2/(1+a);
    se = sqrt((a*(1-a) + (m-1)*(q1-a^2) + (n-1)*(q2-a^2)) / (m*n));
    ci = [max(0, a-1.96*se), min(1, a+1.96*se)];
end
