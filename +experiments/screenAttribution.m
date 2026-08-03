function out = screenAttribution(nEp, seed, swerling)
%SCREENATTRIBUTION  Which ECCM screen is responsible for the structural
%   CV-coherent generator's 22.0% real-rate against the independent judge?
%
%   out = experiments.screenAttribution(nEp, seed, swerling)   % 100, 7, 1
%
%   METHOD. Roll out experiments.t4JudgeGap's EXACT arm (agent.buildEnvEntity,
%   Swerling I, one CV action held for all 8 frames, zero-velocity excluded),
%   score each episode's received cube with engine.runJudge ONCE, then re-score
%   the DISCRIMINATOR alone under each screen mask from the per-track series
%   the judge returns. Detection, tracking and confirmation are therefore
%   IDENTICAL across every row of the table -- only the screen mask moves, so a
%   difference between two rows cannot be a different noise draw or a different
%   set of confirmed tracks. The baseline row is asserted equal to the judge's
%   own eccm_label episode for episode, so the re-scoring is verified against
%   the real judge rather than trusted.
%
%   NO SEPARATE ABLATION DISCRIMINATOR. +track/discriminator.m already takes a
%   screensEnabled mask (and engine.runJudge an 'EccmScreens' option) for
%   exactly this measurement. A forked copy would attribute loss in a file that
%   is not the judge, which is the one thing this experiment must not do.
%
%   THE FOUR SCREENS IN THE BRIEF ARE NOT THE FOUR SCREENS THIS JUDGE HAS.
%   Mapped honestly, and every mismatch is reported rather than faked:
%     amplitude_vs_range -> discriminator screen 1, log(A)-vs-log(R) slope
%     doppler            -> discriminator screen 2, Doppler/range-rate SIGN
%     range-rate         -> track.rangeRateConsistency, the Tier 1.2 MAGNITUDE
%                           check. It is a SEPARATE COLUMN, deliberately never
%                           folded into the label, so it is attributed here as
%                           "baseline AND rate pass" instead of as a mask.
%     NIS                -> track.nisConsistency, same treatment (Tier 1.1).
%     residual           -> discriminator screen 4, veto-only, OFF by default.
%                           Swerling I is what unblocked measuring it at all.
%     monopulse_angle    -> NOT MEASURABLE ON THIS ARM, and not because it was
%                           skipped. runJudge's co-bearing screen is gated on
%                           nnz(valid) >= 2 -- it asks whether SEVERAL tracks
%                           share a bearing, which a single-phantom scene
%                           cannot answer -- and buildEnvEntity keeps the sum
%                           channel only, so there is no delta channel either.
%                           Reported as structurally inapplicable, count 0.
%     waveform_agility   -> not a screen at all; a radar property. Measured as
%                           its own row (sweep_schedule handed to the judge),
%                           and see the caveat printed with it.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): every label is computed after the
%   episode is complete and none is visible to the policy.

    if nargin < 1 || isempty(nEp);      nEp = 100;    end
    if nargin < 2 || isempty(seed);     seed = 7;     end
    if nargin < 3 || isempty(swerling); swerling = 1; end

    C = physics.Constants();
    [env, spec] = agent.buildEnvEntity(C, struct('shaping', false, ...
                        'keepCube', true, 'swerling', swerling));
    nVel = numel(spec.velOptionsMps);
    nRcs = numel(spec.rcsOptionsDbsm);
    zeroVel = find(abs(spec.velOptionsMps) < 1e-9);   % excluded, as in t4JudgeGap

    masks = { {'amplitude','doppler'},              'all (baseline)'
              {'doppler'},                          'no amplitude'
              {'amplitude'},                        'no doppler'
              {'none'},                             'no screens at all'
              {'amplitude','doppler','residual'},   'baseline + residual' };
    nMask = size(masks, 1);

    nReal   = zeros(1, nMask);
    nConf   = 0;
    nRate   = 0;    % baseline real AND Tier 1.2 range-rate magnitude pass
    nNis    = 0;    % baseline real AND Tier 1.1 NIS pass
    nAgile  = 0;    % baseline mask, agile radar
    nAgileC = 0;

    rng(seed);
    for e = 1:nEp
        reset(env);
        vi = zeroVel;
        while vi == zeroVel; vi = randi(nVel); end
        a = sub2ind([nVel nRcs], vi, randi(nRcs));
        lg = [];
        for k = 1:spec.framesPerEpisode
            [~, ~, ~, lg] = step(env, a);          % HELD -- one state, 8 frames
        end
        if isempty(lg.cubeFrames); continue; end

        fb = localJudge(lg.cubeFrames, C, spec, ones(1, spec.framesPerEpisode), ...
                        masks{1,1});
        confirmed = fb.confirmed_tracks >= 1;
        nConf = nConf + double(confirmed);
        if ~confirmed; continue; end

        for m = 1:nMask
            if strcmp(localRescore(fb, masks{m,1}), 'real')
                nReal(m) = nReal(m) + 1;
            end
        end
        % Verified, not trusted: the re-scored baseline must BE the judge's
        % own verdict on this episode.
        assert(strcmp(localRescore(fb, masks{1,1}), char(fb.eccm_label)), ...
            'experiments:screenAttribution:rescoreMismatch', ...
            'episode %d: re-scored "%s" but the judge said "%s"', ...
            e, localRescore(fb, masks{1,1}), char(fb.eccm_label));

        baselineReal = strcmp(localRescore(fb, masks{1,1}), 'real');
        nRate = nRate + double(baselineReal && all(fb.track_rate_pass));
        nNis  = nNis  + double(baselineReal && all(fb.track_nis_pass));

        % ---- waveform agility: same cube, agile radar ----
        % The cube was rendered with a FIXED up-chirp (engine.entity.render's
        % default), so against an alternating schedule it is mismatched on half
        % the frames. That measures STALENESS, not phantom-ness: a genuine
        % target reflects the frame's own pulse and would not be penalised
        % (tests/test_eccm_ladder.m, DEFECT 1), and a fresh-intercept phantom
        % is one ChirpOverride away from the same immunity.
        fbA = localJudge(lg.cubeFrames, C, spec, (-1).^(0:spec.framesPerEpisode-1), ...
                         masks{1,1});
        nAgileC = nAgileC + double(fbA.confirmed_tracks >= 1);
        nAgile  = nAgile  + double(fbA.confirmed_tracks >= 1 && ...
                                   strcmp(char(fbA.eccm_label), 'real'));
    end

    rows = struct('name', {}, 'real', {}, 'ci', {}, 'lossPp', {});
    base = nReal(1) / nEp;
    for m = 1:nMask
        rows(end+1) = localRow(masks{m,2}, nReal(m), nEp, base); %#ok<AGROW>
    end
    rows(end+1) = localRow('baseline AND rate pass', nRate,   nEp, base);
    rows(end+1) = localRow('baseline AND NIS pass',  nNis,    nEp, base);
    rows(end+1) = localRow('baseline, AGILE radar',  nAgile,  nEp, base);
    rows(end+1) = localRow('confirmed at all (ceiling)', nConf, nEp, base);

    out = struct('nEp', nEp, 'seed', seed, 'swerling', swerling, ...
        'rows', rows, 'confirmed', nConf/nEp, 'agileConfirmed', nAgileC/nEp, ...
        'monopulse', 'inapplicable (single track)');

    fprintf(['\nSCREEN ATTRIBUTION -- structural CV-coherent generator, ' ...
             'swerling %d, n=%d, seed=%d\n'], swerling, nEp, seed);
    fprintf('%-28s %8s %16s %12s\n', 'screens enabled', 'real', 'Wilson 95%', 'loss (pp)');
    for i = 1:numel(rows)
        if isnan(rows(i).lossPp); lossStr = '     --';
        else;                     lossStr = sprintf('%+7.1f', rows(i).lossPp); end
        fprintf('%-28s %7.1f%% [%5.1f, %5.1f]%%  %s\n', rows(i).name, ...
            100*rows(i).real, 100*rows(i).ci(1), 100*rows(i).ci(2), lossStr);
    end
    fprintf(['  monopulse/co-bearing: INAPPLICABLE -- needs >= 2 confirmed tracks ' ...
             '(runJudge nnz(valid)>=2)\n']);
    fprintf('  agile radar confirmed %.1f%% (vs %.1f%% fixed) -- detection, not screening\n', ...
        100*nAgileC/nEp, 100*nConf/nEp);
    % Brief's note 5, answered rather than measured: the range clamp cannot
    % fire on this arm. R0 = 1800 m with a +-50 m/s grid over 8 frames spans
    % [1400, 2200] m, inside bounds of about [1030, 16900] m -- the env's own
    % comment (buildEnvEntity.m, "the clamp is simply unreachable in 8
    % frames") and the assertion beside it are what make that structural.
    fprintf('  range clamp: unreachable on this arm (see buildEnvEntity.m)\n');
end

% ------------------------------------------------------------------------
function label = localRescore(fb, screens)
%LOCALRESCORE  The judge's own aggregation rule (runJudge's eccm_label),
%   recomputed per track from the series it returned, under a screen mask.
%   Mirrors runJudge exactly: < 2 hits -> "unscreened"; unanimous -> that
%   label; mixed -> "mixed".
    n = fb.confirmed_tracks;
    if n < 1; label = ''; return; end
    lbl = strings(1, n);
    for i = 1:n
        R = fb.track_range_m{i};
        if numel(R) < 2
            lbl(i) = "unscreened";
            continue;
        end
        ts = struct('range', R, 'amplitude', fb.track_amp{i}, ...
                    'doppler', fb.track_range_rate_mps{i}, ...
                    'dopplerMeasured', true, ...
                    'screensEnabled', {cellstr(screens)});
        lbl(i) = string(track.discriminator(ts, physics.Constants()));
    end
    % The co-bearing screen can only condemn a GROUP; single-track scenes
    % never reach it, and this arm has no delta channel at all.
    if all(lbl == lbl(1)); label = char(lbl(1)); else; label = 'mixed'; end
end

% ------------------------------------------------------------------------
function fb = localJudge(cubeFrames, C, spec, sched, screens)
    S = struct('rx_frames', cubeFrames, 'fs', C.fs, ...
        'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', C.PRF, ...
        'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz, ...
        'sweep_schedule', sched);
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f, 'EccmScreens', screens);
end

% ------------------------------------------------------------------------
function row = localRow(name, k, n, base)
    [lo, hi] = localWilson(k, n);
    p = k/n;
    if strcmp(name, 'all (baseline)') || contains(name, 'ceiling')
        loss = NaN;
    else
        loss = 100*(p - base);
    end
    row = struct('name', name, 'real', p, 'ci', [lo hi], 'lossPp', loss);
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end
