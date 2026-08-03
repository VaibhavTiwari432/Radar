function out = eccmLadder(nSeeds)
%ECCMLADDER  Tier 1.1 + 1.2 acceptance: the evasion ladder with the two NEW
%   consistency columns reported ALONGSIDE the existing ECCM verdict.
%
%   out = experiments.eccmLadder(nSeeds)     % default 20
%
%   RUNGS (the radar configuration ladder, §4.12):
%       R1  Doppler screen only
%       R2  + amplitude screen        (the authoritative rung)
%       R3  + waveform agility        (per-frame sweep reversal)
%       R2+residual  R2 + residual-variance screen (screen 4, veto-only)
%       R3+residual  R3 + the same screen
%
%   THE RUNG LABELS HERE ARE THIS FILE'S OWN AND DO NOT MAP ONTO THE REPORT'S
%   §4.12 LADDER. That ladder's R4 is monopulse and its R5 is agility; this
%   file has no monopulse rung (see below) and its R3 already IS agility. The
%   two new rungs are therefore named for what they add to an existing rung,
%   not given fresh R-numbers that already mean something else elsewhere.
%
%   WHY THE RESIDUAL RUNGS EXIST NOW AND NOT BEFORE. discriminator.m's residual-variance
%   screen is off by default, and its own header states the single reason:
%   it vetoes a return with literally zero scatter about the 1/R^2 law, which
%   is the servo-repeater signature -- and every genuine reference arm in
%   this project rendered `swerling = 0`, i.e. a non-fluctuating target that
%   trips exactly that veto. Enabling it therefore required genuine targets
%   to fluctuate first. Tier 1.3 did that (swerling is a stated parameter,
%   default I), so the blocker is gone and the screen can finally be measured
%   against a genuine arm it will not falsely condemn. R2 is the rung where
%   the amplitude slope screen was measured UNABLE to separate phantom from
%   genuine (35% vs 40%, p = 0.74); the residual rungs test whether the
%   residual screen fixes that.
%
%   THE MONOPULSE RUNG IS DELIBERATELY NOT HERE, and the reason is a defect
%   found in the first version of this file rather than a scoping preference.
%   +engine/runJudge.m's co-bearing screen is gated on `nnz(valid) >= 2`: it
%   asks whether SEVERAL tracks share a bearing, which no single-target scene
%   can answer. A first run included a "+monopulse" rung anyway and it
%   produced numbers that differed from the rung below it -- entirely because
%   building the delta channel consumed extra draws from the shared
%   RandStream and re-rolled the sum channel's noise. It measured nothing but
%   its own RNG. Monopulse is measured properly, on a 4-phantom scene, in
%   tests/test_angle_channel.m (12/12 seeds); a worse duplicate here would add
%   no information. The delta channel now draws from its OWN stream so no rung
%   can perturb another's noise.
%
%   ARMS:
%       VEE phantom  -- one propagated entity, every observable rendered from
%                       it, Swerling I (Tier 1.3: the non-fluctuating target
%                       the older numbers used is not a physical object)
%       naive DRFM   -- the pre-VEE adversary: range walks, gain CONSTANT (no
%                       1/R^2 law), no Doppler shift at all
%       genuine      -- the control. If this arm is flagged, the screen is
%                       accusing real aircraft and the result is worthless.
%
%   WHAT IS REPORTED, AND WHY SEPARATELY. `deceived` is the existing verdict
%   (confirmed AND labelled real). `NIS pass` (Tier 1.1) and `rate pass`
%   (Tier 1.2) are the two new screens, reported as their OWN columns and
%   NEVER folded into the ECCM score -- so their effect on the evasion rate
%   is readable in isolation before anyone decides to combine them. That is
%   the Tier 1.1 brief's explicit instruction and it applies to 1.2 equally.

    if nargin < 1 || isempty(nSeeds); nSeeds = 20; end
    C = physics.Constants();

    cfg = struct('nFast', 400, 'nPulses', 32, 'nFrames', 8, ...
                 'R0', 1800, 'V', -50, 'amp', 3.0, 'pw', 12e-6, ...
                 'bw', 2e6, 'carrier', 10e9, 'interceptNoise', 2.0);

    rungs = { ...
        'R1 doppler',        {'doppler'},              false, false; ...
        'R2 +amplitude',     {'doppler','amplitude'},  false, false; ...
        'R3 +agility',       {'doppler','amplitude'},  false, true; ...
        'R2+residual',       {'doppler','amplitude','residual'}, false, false; ...
        'R3+residual',       {'doppler','amplitude','residual'}, false, true};
    arms = {'vee-phantom', 'naive-drfm', 'genuine'};

    fprintf('\n============ ECCM LADDER, %d seeds/cell ============\n', nSeeds);
    fprintf('%-14s %-13s %9s %9s %11s %11s\n', 'rung', 'arm', 'confirm', ...
        'deceived', 'NIS pass', 'rate pass');

    out = struct('rung', {}, 'arm', {}, 'confirmed', {}, 'deceived', {}, ...
                 'nisPass', {}, 'ratePass', {}, 'nisMean', {}, 'rateMismatch', {}, ...
                 'residSigmaDb', {});

    for r = 1:size(rungs, 1)
        for a = 1:numel(arms)
            nConf = 0; nDec = 0; nNis = 0; nRate = 0;
            nisVals = []; rateVals = []; sigVals = [];
            for seed = 1:nSeeds
                % The sweep schedule is handed to the ARM as well as the
                % judge: a GENUINE target reflects whatever the radar
                % transmitted on THAT frame, so it must be built from the
                % same per-frame waveform the judge will match-filter with.
                % Giving it a fixed chirp against an agile radar penalises it
                % exactly like a stale repeater -- a first version of this
                % file did that, and the genuine arm's apparent collapse at
                % the agility rung was that bug, not a screen property.
                sched = localSchedule(rungs{r,4}, cfg.nFrames);
                [cube, delta] = localBuildArm(arms{a}, seed, cfg, C, rungs{r,3}, sched);
                fb = localJudge(cube, delta, C, cfg, rungs{r,2}, sched);
                if fb.confirmed_tracks < 1; continue; end
                nConf = nConf + 1;
                nDec  = nDec + double(strcmp(char(fb.eccm_label), 'real'));
                nNis  = nNis  + double(all(fb.track_nis_pass));
                nRate = nRate + double(all(fb.track_rate_pass));
                nisVals(end+1)  = mean(fb.track_nis_mean(~isnan(fb.track_nis_mean))); %#ok<AGROW>
                m = fb.track_rate_mismatch_mps(~isnan(fb.track_rate_mismatch_mps));
                if ~isempty(m); rateVals(end+1) = mean(m); end %#ok<AGROW>
                sd = localResidSigmaDb(fb);
                if ~isnan(sd); sigVals(end+1) = sd; end %#ok<AGROW>
            end
            fprintf('%-14s %-13s %6d/%-2d %6d/%-2d %8d/%-2d %8d/%-2d\n', ...
                rungs{r,1}, arms{a}, nConf, nSeeds, nDec, nSeeds, ...
                nNis, nSeeds, nRate, nSeeds);
            out(end+1) = struct('rung', rungs{r,1}, 'arm', arms{a}, ...
                'confirmed', nConf, 'deceived', nDec, 'nisPass', nNis, ...
                'ratePass', nRate, 'nisMean', mean(nisVals), ...
                'rateMismatch', mean(rateVals), ...
                'residSigmaDb', mean(sigVals)); %#ok<AGROW>
        end
    end

    fprintf('\nNIS mean / rate mismatch / residual scatter by arm (all rungs pooled):\n');
    for a = 1:numel(arms)
        sel = strcmp({out.arm}, arms{a});
        fprintf('  %-13s NIS %8.3f | rate mismatch %8.2f m/s | resid sigma %7.3f dB\n', ...
            arms{a}, mean([out(sel).nisMean], 'omitnan'), ...
            mean([out(sel).rateMismatch], 'omitnan'), ...
            mean([out(sel).residSigmaDb], 'omitnan'));
    end
    fprintf(['  (residual veto fires only BELOW the floor; at N=%d hits that is ' ...
             '%.3f dB)\n'], cfg.nFrames, ...
             0.233 * max(0, 1 - 3/sqrt(2*(cfg.nFrames-1))));
end

% ------------------------------------------------------------------------
function sd = localResidSigmaDb(fb)
%LOCALRESIDSIGMADB  The scatter about the 1/R^2 law that discriminator.m's
%   residual screen vetoes on, recomputed here from the judge's OWN returned
%   series with the same formula. Reported so that "the residual rung changed
%   nothing" is readable as a MEASUREMENT (scatter sits above the veto floor)
%   rather than as a suspicion that the screen was never wired in.
    sd = NaN;
    if ~isfield(fb, 'track_range_m') || isempty(fb.track_range_m); return; end
    R = fb.track_range_m{1}(:); A = fb.track_amp{1}(:);
    ok = isfinite(R) & isfinite(A) & R > 0 & A > 0;
    if nnz(ok) < 3 || range(R(ok)) <= 1e-9; return; end
    lr = log(R(ok)); la = log(A(ok));
    sd = std(20/log(10) * (la - (-2*lr + mean(la + 2*lr))));
end

% ------------------------------------------------------------------------
function [cube, delta] = localBuildArm(name, seed, cfg, C, wantAngle, sched)
    rs = RandStream('twister', 'Seed', 1000 + seed);
    % SEPARATE stream for the delta channel, so building it cannot consume
    % draws from rs and re-roll the sum channel's noise (see header).
    rsD = RandStream('twister', 'Seed', 7000 + seed);
    cube  = complex(zeros(cfg.nFast, cfg.nPulses, cfg.nFrames));
    delta = [];
    if wantAngle; delta = complex(zeros(cfg.nFast, cfg.nPulses, cfg.nFrames)); end

    % The pulse the RADAR actually transmits on each frame. A genuine target
    % reflects this; a repeater holds a STALE copy of one of them, which is
    % what makes agility bite.
    txPerFrame = cell(1, cfg.nFrames);
    for k = 1:cfg.nFrames
        [~, txPerFrame{k}] = radar.agileWaveform(sched(k), C.fs, cfg.pw, C.PRF, cfg.bw);
    end
    chirp = txPerFrame{1};      % the repeater's one stored intercept

    if strcmp(name, 'naive-drfm')
        % Per-frame independent knobs: delay walks, gain CONSTANT, no Doppler.
        for k = 1:cfg.nFrames
            R = cfg.R0 + cfg.V*(k-1);
            d = round(2*R/C.c * C.fs);
            c = complex(zeros(cfg.nFast, cfg.nPulses));
            c(d + (1:numel(chirp)), :) = chirp * (cfg.amp * ones(1, cfg.nPulses));
            cube(:,:,k) = c + localNoise(rs, cfg);
            if wantAngle; delta(:,:,k) = 0.01*c + localNoise(rsD, cfg); end
        end
        return;
    end

    % SWERLING I, not 0 (Tier 1.3): a non-fluctuating target is not a
    % physical object and never had to survive a fluctuation check.
    s = engine.entity.EntityState('range_m', cfg.R0, 'range_rate_mps', cfg.V, ...
            'class', 'drone', 'rcs_dbsm', 0, 'swerling', 1);
    q = engine.entity.calibrateQ('Dt', 1.0, 'Dataset', localDataset());
    usesIntercept = ~strcmp(name, 'genuine');
    nominalK = cfg.bw / cfg.pw;

    for k = 1:cfg.nFrames
        if usesIntercept
            % STALE: one stored intercept, replayed every frame. Against a
            % fixed radar that is free; against an agile one it is the whole
            % point of the rung.
            tmpl = features.synthesizeTxPulse(chirp, C.fs, nominalK, ...
                        cfg.interceptNoise, rs, k);
        else
            tmpl = txPerFrame{k};   % genuine: reflects THIS frame's pulse
        end
        args = {'AmpScale', cfg.amp, 'NumPulses', cfg.nPulses, ...
                'FastTimeSamples', cfg.nFast, 'CarrierHz', cfg.carrier, ...
                'PrfHz', C.PRF, 'ChirpOverride', tmpl, 'RandStream', rs};
        if wantAngle
            [c, meta] = engine.entity.render(s, args{:});
            cube(:,:,k)  = c + localNoise(rs, cfg);
            delta(:,:,k) = c * 1i*tan(meta.monopulse_phi/2) + localNoise(rsD, cfg);
        else
            c = engine.entity.render(s, args{:});
            cube(:,:,k) = c + localNoise(rs, cfg);
        end
        s = engine.entity.propagate(s, 1.0, q, rs);
    end
end

function sched = localSchedule(agile, nFrames)
%LOCALSCHEDULE  Per-frame sweep direction. Fixed radars transmit all-up.
    if agile
        sched = (-1).^(0:nFrames-1);
    else
        sched = ones(1, nFrames);
    end
end

function fb = localJudge(cube, delta, C, cfg, screens, sched)
    S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', cfg.pw, ...
        'bandwidth_hz', cfg.bw, 'prf_hz', C.PRF, 'frame_interval_s', 1.0, ...
        'carrier_hz', cfg.carrier, 'sweep_schedule', sched);
    if ~isempty(delta); S.rx_frames_delta = delta; end
    f = [tempname '.mat']; save(f, '-struct', 'S');
    c = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f, 'EccmScreens', screens);
end

function chirp = localIdealChirp(cfg, C)
    n = round(cfg.pw * C.fs);
    t = (0:n-1)' / C.fs;
    chirp = exp(1i * pi * (cfg.bw / cfg.pw) * t.^2);
end

function nz = localNoise(rs, cfg)
    nz = 0.05 * (randn(rs, cfg.nFast, cfg.nPulses) + ...
             1i * randn(rs, cfg.nFast, cfg.nPulses)) / sqrt(2);
end

function D = localDataset()
    persistent cached
    if isempty(cached)
        root = fileparts(fileparts(mfilename('fullpath')));
        cached = data.loadRadChar(fullfile(root, 'data', 'RadChar-Tiny.h5'));
    end
    D = cached;
end
