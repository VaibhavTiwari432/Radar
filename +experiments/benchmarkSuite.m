function R = benchmarkSuite(stage, varargin)
%BENCHMARKSUITE  Scientific benchmark harness (Benchmark Checklist, 25 Jul 2026).
%
%   R = experiments.benchmarkSuite('tier1')
%   R = experiments.benchmarkSuite('sweeps')
%   R = experiments.benchmarkSuite('generalization')
%
%   Name-value: 'Seeds' (default 20), 'OutDir' (default results/benchmark)
%
%   Run in stages, not all at once: a full pass is ~30 min of judge calls and
%   the MCP tool bridge aborts a silent run at 1800 s.
%
%   ================= THE SCENE, AND WHY IT HAS TWO OBJECTS =================
%   Every trial renders ONE GENUINE TARGET and ONE PHANTOM into the SAME
%   cube, 1800 m apart (far outside the tracker's 200 m assignment gate, so
%   track-to-truth attribution is unambiguous). Both are judged in one pass.
%
%   That is not cosmetic. A confusion matrix needs all four cells, and a
%   phantom-only scene can only ever produce two of them -- you cannot
%   measure the radar's false-alarm rate on REAL targets without real
%   targets present. Benchmarks that score phantoms alone silently report
%   recall as if it were F1.
%
%   ================= CONFUSION MATRIX: A CORRECTION =================
%   The checklist's own MATLAB snippet defines
%       TN = sum([results.flagged_as_decoy])   % "true negative (decoy flagged)"
%       FN = N_seeds - TP - FP - TN
%   Those are not right and would produce a meaningless F1: a flagged decoy
%   is a TRUE POSITIVE for decoy-detection (the radar correctly caught a
%   decoy), not a true negative; and FN cannot be recovered by subtracting
%   track counts from a SEED count -- different units.
%
%   Implemented here with "decoy" as the positive class, per CONFIRMED
%   TRACK, matched to the ground-truth object it actually came from:
%       TP  phantom -> labelled decoy   (radar caught it)
%       FN  phantom -> labelled real    (radar fooled == EVASION)
%       FP  genuine -> labelled decoy   (radar cried wolf on a real aircraft)
%       TN  genuine -> labelled real    (radar correct)
%   so precision = TP/(TP+FP), recall = TP/(TP+FN), and evasion = 1-recall,
%   which is the relationship the checklist itself states.
%
%   ================= WHAT IS NOT MEASURED, AND WHY =================
%   * Phantom ANGULAR spread sweep: impossible. This radar has no angle
%     channel at all -- the measurement handed to the tracker is
%     [range;0;0] (RADAR_REALISM_AUDIT.md 1.1). Reported as not-applicable
%     rather than faked.
%   * D3QN: its environment (+agent/buildEnvFeatureConditioned.m) is the
%     LEGACY 2-D pipeline with no slow-time axis, so its judge has no
%     Doppler screen. Its numbers are NOT comparable to anything here and
%     are reported separately via experiments.evalFeatureAgent.
%   * Learning-convergence curves: no retraining run this pass.

    p = inputParser;
    addParameter(p, 'Seeds',  20,  @(x) isscalar(x) && x >= 1);
    addParameter(p, 'OutDir', '',  @(x) ischar(x) || isstring(x));
    % Override any defaultConfig field, e.g. struct('nPulses',512). Unknown
    % names are rejected rather than silently ignored -- a typo'd override
    % that quietly runs the DEFAULT operating point is exactly the kind of
    % measurement error this harness records (see M1-M4 in the header).
    addParameter(p, 'Config', struct(), @isstruct);
    addParameter(p, 'Tag',    '',       @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});
    nSeeds = p.Results.Seeds;

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    outDir = char(p.Results.OutDir);
    if isempty(outDir); outDir = fullfile(root, 'results', 'benchmark'); end
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    cfg = defaultConfig();
    ov = p.Results.Config;
    for f = fieldnames(ov)'
        assert(isfield(cfg, f{1}), 'benchmarkSuite:badConfigField', ...
            'Config override ''%s'' is not a defaultConfig field', f{1});
        cfg.(f{1}) = ov.(f{1});
    end
    R = struct('stage', stage, 'n_seeds', nSeeds, 'config', cfg, ...
               'timestamp', datestr(now, 'yyyy-mm-ddTHH:MM:SS'));

    switch lower(char(stage))
        case 'tier1';          R.tier1 = runTier1(cfg, nSeeds, root);
        case 'sweeps';         R.sweeps = runSweeps(cfg, nSeeds, root);
        case 'generalization'; R.gen = runGeneralization(cfg, nSeeds, root);
        case 'fixups'
            % Re-runs only the three cells whose FIRST run was invalidated by
            % a method error found in this benchmark itself: the gate sweep
            % (wrong units) and the class/SNR sweeps (one pulse per cell).
            R.gate = sweep('Tracker gate [normalised]', 'gateM', ...
                {1, 2, 5, 10, 20, 50, 200}, cfg, nSeeds, root);
            R.waveClass = sweepWaveformClass(cfg, nSeeds, root);
            R.snr = sweepSnr(cfg, nSeeds, root);
        otherwise; error('benchmarkSuite:badStage', 'stage must be tier1|sweeps|generalization|fixups');
    end

    tag = char(p.Results.Tag);
    if isempty(tag)
        outFile = fullfile(outDir, sprintf('benchmark_%s.mat', lower(char(stage))));
    else
        % Tagged runs never overwrite the published baseline .mat files.
        outFile = fullfile(outDir, sprintf('benchmark_%s_%s.mat', lower(char(stage)), tag));
    end
    save(outFile, '-struct', 'R');
    fprintf('\n[benchmark] saved -> %s\n', outFile);
end

% =====================================================================
% Configuration -- every operating point is explicit (checklist Tier 4)
% =====================================================================
function cfg = defaultConfig()
    cfg.fs = 3.2e6; cfg.pulseWidth = 12e-6; cfg.bandwidth = 2e6;
    cfg.prf = physics.Constants().PRF; cfg.carrier = 10e9;
    cfg.nFast = 400; cfg.nPulses = 32; cfg.nFrames = 8; cfg.frameDt = 1.0;
    cfg.cfarPfa = 1e-4; cfg.cfarTrain = 20; cfg.cfarGuard = 4;
    cfg.gateM = 200; cfg.confirm = [3 5]; cfg.deletion = [5 5];
    cfg.filterModel = 'cv'; cfg.trackerType = 'gnn';
    cfg.eccmScreens = {'amplitude','doppler'};
    cfg.noiseAmp = 0.05; cfg.interceptNoise = 2.0;
    % Two objects, 1800 m apart -- 9x the 200 m assignment gate.
    cfg.genuineR0 = 3800; cfg.genuineV = -60; cfg.genuineAmp = 3.0;
    cfg.phantomR0 = 2000; cfg.phantomV = -60; cfg.phantomAmp = 3.0;
    % ---- rotorcraft threat model (T8) ----------------------------------
    % Defaults reproduce every published number exactly: fixed-wing, no
    % micro-Doppler expected, so the micro screen stays disarmed however
    % long the dwell is. Set these to arm it -- see runTier1's header note.
    cfg.genuineClass = 'fighter'; cfg.phantomClass = 'fighter';
    cfg.genuineMicroHz = 0; cfg.phantomMicroHz = 0;
    cfg.expectMicro = false;
    % Inject a PREVIOUSLY MEASURED BruteForce ceiling instead of re-searching
    % the 5x5 grid (25 cells x 3 seeds = 75 judge calls). At a 512-pulse
    % dwell that search alone is ~6 h. Empty = calibrate normally. When set,
    % the result is tagged reused=true so no report can silently present a
    % reused ceiling as a freshly measured one.
    cfg.bruteForce = [];
end

% =====================================================================
% TIER 1
% =====================================================================
function T = runTier1(cfg, nSeeds, root)
    fprintf('\n########## TIER 1 (%d seeds) ##########\n', nSeeds);
    gens = {'vee', 'naive'};

    % --- BruteForce ceiling: best NON-ADAPTIVE (amp, vel) found on the judge
    if isfield(cfg, 'bruteForce') && ~isempty(cfg.bruteForce)
        bf = cfg.bruteForce; bf.reused = true;
        fprintf('\n[tier1] BruteForce ceiling REUSED (not recalibrated): amp=%.1f v=%+.0f m/s\n', ...
            bf.amp, bf.vel);
    else
        fprintf('\n[tier1] calibrating BruteForce non-adaptive ceiling...\n');
        bf = calibrateBruteForce(cfg, root); bf.reused = false;
        fprintf('[tier1] BruteForce best: amp=%.1f v=%+.0f m/s -> evasion %.0f%% on %d calibration seeds\n', ...
            bf.amp, bf.vel, 100*bf.rate, bf.nCal);
    end
    T.bruteforce_params = bf;

    allGens = [gens, {'bruteforce'}];
    for g = 1:numel(allGens)
        name = allGens{g};
        gcfg = cfg;
        if strcmp(name, 'bruteforce')
            gcfg.phantomAmp = bf.amp; gcfg.phantomV = bf.vel;
        end
        acc = newAccumulator();
        nis = []; whiteRho = []; whiteP = [];
        for s = 1:nSeeds
            [out, diag] = oneTrial(name, s, gcfg, root);
            acc = accumulate(acc, out);
            nis(end+1) = diag.nisInBand; %#ok<AGROW>
            whiteRho(end+1) = diag.lag1Rho; %#ok<AGROW>
            whiteP(end+1) = diag.adP; %#ok<AGROW>
        end
        m = finalize(acc, nSeeds);
        m.nis_in_band_mean = mean(nis);
        m.innov_lag1_rho_mean = mean(whiteRho);
        m.innov_ad_pvalue_mean = mean(whiteP);
        T.(name) = m;
        printMetrics(name, m, nSeeds);
    end

    % --- regret vs the non-adaptive ceiling ---
    bfRate = T.bruteforce.evasion_rate;
    if bfRate > 0
        T.regret_vee = (bfRate - T.vee.evasion_rate) / bfRate;
    else
        T.regret_vee = NaN;
    end
    fprintf('\n[tier1] Regret (VEE vs BruteForce ceiling): %s\n', ...
        ternary(isnan(T.regret_vee), 'undefined (ceiling evasion = 0)', ...
                sprintf('%.1f%% of ceiling forfeited', 100*T.regret_vee)));

    % --- sim-to-judge gap: the twin's own prediction of the SAME phantom ---
    T.twin = twinGap(cfg, nSeeds, root, T.vee.evasion_rate);

    % --- distributional realism: synthesized vs REAL RadChar pulses ---
    T.wasserstein = wassersteinToRadChar(cfg, root);
end

% =====================================================================
% TIER 2 -- threshold sweeps
% =====================================================================
function S = runSweeps(cfg, nSeeds, root)
    fprintf('\n########## TIER 2 SWEEPS (%d seeds) ##########\n', nSeeds);

    S.pfa = sweep('CFAR Pfa', 'cfarPfa', {1e-6,1e-5,1e-4,1e-3,1e-2}, cfg, nSeeds, root);
    % UNITS CORRECTION -- do not "restore" this to 50..300.
    % trackerGNN's AssignmentThreshold is a NORMALISED (Mahalanobis-like)
    % distance, NOT metres, despite this project's own comments in
    % +track/runTracker.m and +engine/runJudge.m (ASSIGNMENT_GATE_M = 200)
    % treating it as metres. Verified directly: a target stepping 60 m per
    % frame fails to confirm at gate = 1,2,5,10 and confirms at 50 and 200.
    % If the parameter were metres the transition would sit at ~60; it sits
    % between 10 and 50. So the checklist's [50..300] sweep is ENTIRELY
    % above the interesting region and moves nothing -- measured, all six
    % values gave identical 100% evasion. Swept here over the range where
    % the gate actually binds.
    S.gate = sweep('Tracker gate [normalised]', 'gateM', ...
        {1, 2, 5, 10, 20, 50, 200}, cfg, nSeeds, root);
    S.confirm = sweep('M-of-N confirmation', 'confirm', ...
        {[2 3],[3 4],[3 5],[4 5],[5 6]}, cfg, nSeeds, root);
    S.eccm = sweep('ECCM screens enabled', 'eccmScreens', ...
        {{'amplitude','doppler'}, {'amplitude'}, {'doppler'}, {}}, cfg, nSeeds, root);
end

% =====================================================================
% TIER 2 -- generalization
% =====================================================================
function G = runGeneralization(cfg, nSeeds, root)
    fprintf('\n########## TIER 2 GENERALIZATION (%d seeds) ##########\n', nSeeds);

    G.tracker = sweep('Tracker model', 'filterModel', {'cv','imm','ca'}, cfg, nSeeds, root);
    G.trackerType = sweep('Tracker association', 'trackerType', {'gnn','jpda'}, cfg, nSeeds, root);
    G.range = sweep('Phantom initial range [m]', 'phantomR0', {2000,3000,4000,5000}, cfg, nSeeds, root);
    G.waveClass = sweepWaveformClass(cfg, nSeeds, root);
    G.snr = sweepSnr(cfg, nSeeds, root);
end

% =====================================================================
% One trial: render genuine + phantom, judge, attribute, score
% =====================================================================
function [out, diag] = oneTrial(genName, seed, cfg, root)
    C = physics.Constants();
    rs = RandStream('twister', 'Seed', 5000 + seed);
    cube = complex(zeros(cfg.nFast, cfg.nPulses, cfg.nFrames));

    q = cachedQ(root);
    cleanChirp = idealChirp(cfg, C);
    nominalK = cfg.bandwidth / cfg.pulseWidth;
    lambda = C.c / cfg.carrier;
    slow = (0:cfg.nPulses-1)' / cfg.prf;

    % ---- genuine target: reflects the radar's ACTUAL pulse ----
    sg = engine.entity.EntityState('range_m', cfg.genuineR0, 'range_rate_mps', cfg.genuineV, ...
            'class', cfg.genuineClass, 'rcs_dbsm', 0, 'swerling', 0, ...
            'micro_doppler_hz', cfg.genuineMicroHz);
    genRange = zeros(cfg.nFrames,1);

    % ---- phantom ----
    sp = engine.entity.EntityState('range_m', cfg.phantomR0, 'range_rate_mps', cfg.phantomV, ...
            'class', cfg.phantomClass, 'rcs_dbsm', 0, 'swerling', 0, ...
            'micro_doppler_hz', cfg.phantomMicroHz);
    phRange = zeros(cfg.nFrames,1);

    interceptTemplate = [];   % filled per frame for phantom generators
    for k = 1:cfg.nFrames
        genRange(k) = sg.range_m; phRange(k) = sp.range_m;

        cg = engine.entity.render(sg, 'AmpScale', cfg.genuineAmp, 'NumPulses', cfg.nPulses, ...
                'FastTimeSamples', cfg.nFast, 'CarrierHz', cfg.carrier, 'PrfHz', cfg.prf, ...
                'PulseWidth', cfg.pulseWidth, 'Bandwidth', cfg.bandwidth, ...
                'ChirpOverride', cleanChirp, 'RandStream', rs);

        switch genName
            case {'vee','bruteforce'}
                interceptTemplate = features.synthesizeTxPulse(cleanChirp, C.fs, nominalK, ...
                        cfg.interceptNoise, rs, k);
                if isfield(cfg,'classTemplate') && ~isempty(cfg.classTemplate)
                    % Per-waveform-class sweep. NORMALISE TO UNIT RMS first.
                    % Raw RadChar records are not amplitude-normalised: their
                    % pulse RMS spans 1.5x to 9.8x the ideal chirp's, a 6.5:1
                    % spread WITHIN a single class. Used raw, this sweep
                    % measures "how loud was that record" rather than "what
                    % waveform class was it" -- and measurably so: a ~10x
                    % phantom lifted the CA-CFAR noise floor enough to
                    % suppress the GENUINE target in the same cube, which is
                    % how the first run of this sweep produced trials with no
                    % confirmed tracks at all. AmpScale must stay the only
                    % amplitude control.
                    interceptTemplate = cfg.classTemplate / max(rms(cfg.classTemplate), eps);
                end
                cp = engine.entity.render(sp, 'AmpScale', cfg.phantomAmp, 'NumPulses', cfg.nPulses, ...
                        'FastTimeSamples', cfg.nFast, 'CarrierHz', cfg.carrier, 'PrfHz', cfg.prf, ...
                        'PulseWidth', cfg.pulseWidth, 'Bandwidth', cfg.bandwidth, ...
                        'ChirpOverride', interceptTemplate, 'RandStream', rs);
            case 'naive'
                tmpl = cleanChirp;
                delay = round(2*sp.range_m/C.c * C.fs);
                cp = complex(zeros(cfg.nFast, cfg.nPulses));
                cp(delay + (1:numel(tmpl)), :) = tmpl * (cfg.phantomAmp * ones(1, cfg.nPulses));
            otherwise
                error('unknown generator %s', genName);
        end

        nz = cfg.noiseAmp * (randn(rs, cfg.nFast, cfg.nPulses) + ...
                1i*randn(rs, cfg.nFast, cfg.nPulses)) / sqrt(2);
        cube(:,:,k) = cg + cp + nz;
        sg = engine.entity.propagate(sg, cfg.frameDt, q, rs);
        sp = engine.entity.propagate(sp, cfg.frameDt, q, rs);
    end

    fb = judgeCube(cube, cfg);
    out = attribute(fb, genRange, phRange);

    % ---- VEE consistency diagnostics from the shadow filter ----
    diag = shadowDiagnostics(phRange, q, cfg, C);
end

% =====================================================================
% Attribution: each confirmed track -> genuine | phantom, then the 2x2
% =====================================================================
function out = attribute(fb, genRange, phRange)
    out = struct('TP',0,'FP',0,'TN',0,'FN',0,'evasion',false, ...
                 'confirmed',fb.confirmed_tracks);
    for i = 1:fb.confirmed_tracks
        rSeq = fb.track_range_m{i};
        if isempty(rSeq); continue; end
        est = mean(rSeq);
        dGen = min(abs(genRange - est));
        dPh  = min(abs(phRange  - est));
        isPhantom = dPh < dGen;
        isDecoyLabel = strcmp(fb.track_label{i}, 'decoy');
        if isPhantom
            if isDecoyLabel; out.TP = out.TP + 1; else; out.FN = out.FN + 1; out.evasion = true; end
        else
            if isDecoyLabel; out.FP = out.FP + 1; else; out.TN = out.TN + 1; end
        end
    end
end

% =====================================================================
% Shadow-filter consistency diagnostics (NIS in-band, innovation whiteness)
% =====================================================================
function d = shadowDiagnostics(rangeTruth, q, cfg, C)
    quant = @(R) round(2*R/C.c * C.fs) * C.range_per_sample;
    f = engine.track.shadowEKF([], quant(rangeTruth(1)), cfg.frameDt, ...
            'Class', 'fighter', 'SigmaAccelMps2', q.sigma_accel_mps2);
    nis = zeros(numel(rangeTruth)-1,1); nuN = zeros(size(nis));
    for k = 2:numel(rangeTruth)
        [f, o] = engine.track.shadowEKF(f, quant(rangeTruth(k)), cfg.frameDt);
        nis(k-1) = o.nis; nuN(k-1) = o.nu / sqrt(o.S);
    end
    gate = 2*erfinv(0.99)^2;
    d.nisInBand = mean(nis > 0.001 & nis <= gate);
    if numel(nuN) >= 3
        rr = corrcoef(nuN(1:end-1), nuN(2:end));
        d.lag1Rho = rr(1,2);
    else
        d.lag1Rho = NaN;
    end
    % Anderson-Darling normality of the normalised innovations. adtest warns
    % ("P is less than the smallest tabulated value") whenever it clamps to
    % 0.0005; that is a floor on the reported p, not an error, and it fires
    % often enough here to drown the console.
    ws = warning('off', 'stats:adtest:OutOfRangePLow');
    wsHi = warning('off', 'stats:adtest:OutOfRangePHigh');
    restore = onCleanup(@() warning([ws wsHi])); %#ok<NASGU>
    try
        [~, d.adP] = adtest(nuN);
    catch
        d.adP = NaN;
    end
end

% =====================================================================
% Sweeps
% =====================================================================
function T = sweep(label, field, values, cfg, nSeeds, root)
    fprintf('\n--- SWEEP: %s ---\n', label);
    % Built field-by-field, NOT via struct(...) with cell values: struct()
    % expands a cell into a struct ARRAY (one element per cell entry), which
    % would silently turn this one result into numel(values) empty ones.
    T.label = label; T.field = field; T.values = values; T.rows = {};
    for v = 1:numel(values)
        c = cfg; c.(field) = values{v};
        acc = newAccumulator();
        for s = 1:nSeeds
            acc = accumulate(acc, oneTrial('vee', s, c, root));
        end
        m = finalize(acc, nSeeds);
        m.value = values{v};
        T.rows{end+1} = m;
        fprintf('  %-22s evasion %5.1f%% [%4.1f,%5.1f]  F1 %.3f  P %.3f  R %.3f  (TP%d FP%d TN%d FN%d)\n', ...
            valueLabel(values{v}), 100*m.evasion_rate, 100*m.evasion_ci(1), 100*m.evasion_ci(2), ...
            m.f1, m.precision, m.recall, m.TP, m.FP, m.TN, m.FN);
    end
end

function T = sweepWaveformClass(cfg, nSeeds, root)
    fprintf('\n--- SWEEP: intercepted waveform class (REAL RadChar pulses) ---\n');
    D = cachedRadChar(root);
    names = {'CoherentPulseTrain','Barker','PolyBarker','Frank','LFM'};
    T.label = 'Waveform class (RadChar)'; T.rows = {};
    % PULSE DIVERSITY, not just render-noise diversity. A first version of
    % this sweep drew ONE real pulse per class and varied only the render
    % seed, so all 20 trials measured that single pulse -- and it showed:
    % one LFM record gave 95% evasion while a different LFM record (drawn in
    % the SNR sweep) gave 0%. The between-pulse variance dominates the
    % between-seed variance, so the budget is now split across pulses.
    nPulse = 5; seedsPer = max(1, floor(nSeeds/nPulse));
    rng(2026);
    for cls = 0:4
        idx = find(D.signal_type == cls);
        picks = idx(randperm(numel(idx), nPulse));
        acc = newAccumulator(); nTrials = 0; snrs = zeros(1,nPulse);
        for pi = 1:nPulse
            c = cfg; c.classTemplate = extractPulse(D, picks(pi), cfg.fs);
            snrs(pi) = D.signal_to_noise_ratio(picks(pi));
            for s = 1:seedsPer
                acc = accumulate(acc, oneTrial('vee', 1000*pi + s, c, root));
                nTrials = nTrials + 1;
            end
        end
        m = finalize(acc, nTrials); m.value = names{cls+1};
        m.n_pulses = nPulse; m.n_trials = nTrials; m.snr_db_mean = mean(snrs);
        T.rows{end+1} = m;
        fprintf('  %-20s evasion %5.1f%% [%4.1f,%5.1f]  F1 %.3f  (%d pulses x %d seeds, mean SNR %.0f dB, TP%d FP%d TN%d FN%d)\n', ...
            names{cls+1}, 100*m.evasion_rate, 100*m.evasion_ci(1), 100*m.evasion_ci(2), ...
            m.f1, nPulse, seedsPer, m.snr_db_mean, m.TP, m.FP, m.TN, m.FN);
    end
end

function T = sweepSnr(cfg, nSeeds, root)
    fprintf('\n--- SWEEP: intercept SNR (REAL RadChar LFM pulses, binned) ---\n');
    D = cachedRadChar(root);
    lfm = find(D.signal_type == 4);
    edges = [-20 -10; -10 0; 0 10; 10 20];
    T.label = 'Intercept SNR bin [dB]'; T.rows = {};
    rng(2026);
    for e = 1:size(edges,1)
        inBin = lfm(D.signal_to_noise_ratio(lfm) >= edges(e,1) & ...
                    D.signal_to_noise_ratio(lfm) <  edges(e,2));
        if isempty(inBin); continue; end
        nPulse = 5; seedsPer = max(1, floor(nSeeds/nPulse));   % pulse diversity, see sweepWaveformClass
        picks = inBin(randperm(numel(inBin), min(nPulse, numel(inBin))));
        acc = newAccumulator(); nTrials = 0;
        for pi = 1:numel(picks)
            c = cfg; c.classTemplate = extractPulse(D, picks(pi), cfg.fs);
            for s = 1:seedsPer
                acc = accumulate(acc, oneTrial('vee', 2000*pi + s, c, root));
                nTrials = nTrials + 1;
            end
        end
        m = finalize(acc, nTrials);
        m.value = sprintf('[%d,%d)', edges(e,1), edges(e,2));
        m.n_pulses = numel(picks); m.n_trials = nTrials;
        T.rows{end+1} = m;
        fprintf('  SNR %-12s evasion %5.1f%% [%4.1f,%5.1f]  F1 %.3f  (%d pulses x %d seeds, TP%d FP%d TN%d FN%d)\n', ...
            m.value, 100*m.evasion_rate, 100*m.evasion_ci(1), 100*m.evasion_ci(2), m.f1, ...
            numel(picks), seedsPer, m.TP, m.FP, m.TN, m.FN);
    end
end

% =====================================================================
% BruteForce ceiling + twin gap + distributional realism
% =====================================================================
function bf = calibrateBruteForce(cfg, root)
    amps = [1 2 3 4 5]; vels = [-120 -90 -60 -30 -15];
    nCal = 3; best = struct('amp',3,'vel',-60,'rate',-1);
    for a = amps
        for v = vels
            c = cfg; c.phantomAmp = a; c.phantomV = v;
            n = 0;
            for s = 1:nCal
                o = oneTrial('vee', 100+s, c, root);
                n = n + o.evasion;
            end
            if n/nCal > best.rate
                best.amp = a; best.vel = v; best.rate = n/nCal;
            end
        end
    end
    bf = best; bf.nCal = nCal; bf.grid = sprintf('%d amps x %d vels', numel(amps), numel(vels));
end

function T = twinGap(cfg, nSeeds, root, judgeRate) %#ok<INUSD>
    % The twin's own prediction for the SAME phantom, via pyenv.
    T = struct('available', false, 'twin_evasion', NaN, 'gap_pp', NaN);
    try
        rsSt = engine.sceneContract().radarState;
        ph = engine.sceneContract().phantom;
        ph.range_m = cfg.phantomR0; ph.radial_vel_mps = cfg.phantomV;
        ph.accel_mps2 = 0; ph.amp_scale = cfg.phantomAmp;
        sc = struct('phantoms', ph, 'maneuver', 'static', 'eirp_budget_dbw', 17.8, ...
                    't0_s', 0, 'duration_s', cfg.nFrames * cfg.frameDt);
        js = engine.sceneStructToJson(sc);
        pyScene = py.cogengine.schema.Scene.from_json(js);
        pyRadar = py.cogengine.schema.RadarState.from_json(jsonencode(rsSt));
        twcfg = py.cogengine.radar_twin.TwinConfig();
        nEvade = 0;
        for s = 1:nSeeds
            rngPy = py.numpy.random.default_rng(int32(5000+s));
            fbp = py.cogengine.radar_twin.predict(pyScene, pyRadar, twcfg, rngPy);
            % NOTE the parentheses: `a + b > 0` parses as `(a+b) > 0`, which
            % silently makes every trial count as an evasion.
            nEvade = nEvade + (double(fbp.false_tracks_surviving) > 0);
        end
        T.available = true;
        T.twin_evasion = nEvade / nSeeds;
        T.gap_pp = 100*(T.twin_evasion - judgeRate);
        fprintf('\n[tier1] twin evasion %.1f%% vs judge %.1f%% -> sim-to-judge gap %+.1f pp\n', ...
            100*T.twin_evasion, 100*judgeRate, T.gap_pp);
    catch ME
        fprintf('\n[tier1] twin gap UNAVAILABLE (%s): %s\n', ME.identifier, ME.message);
    end
end

function W = wassersteinToRadChar(cfg, root)
    % 1-D Wasserstein per feature dimension between the SYNTHESIZED transmit
    % pulse and REAL RadChar pulses of the same class, in the project's own
    % 54-D hardware-realizable feature space (+features/featureVector.m).
    C = physics.Constants();
    D = cachedRadChar(root);
    pfb = features.buildChannelizer();
    clean = idealChirp(cfg, C);
    nominalK = cfg.bandwidth / cfg.pulseWidth;
    rs = RandStream('twister','Seed',31337);

    nSamp = 40;
    synth = zeros(nSamp, 54); realF = zeros(nSamp, 54);
    lfm = find(D.signal_type == 4);
    pick = lfm(randperm(numel(lfm), nSamp));
    for i = 1:nSamp
        tx = features.synthesizeTxPulse(clean, C.fs, nominalK, cfg.interceptNoise, rs, i);
        synth(i,:) = features.featureVector(tx, pfb).';
        realF(i,:) = features.featureVector(extractPulse(D, pick(i), cfg.fs), pfb).';
    end
    qs = linspace(0, 1, 51);
    wd = zeros(1,54);
    for d = 1:54
        a = quantile(synth(:,d), qs); b = quantile(realF(:,d), qs);
        sc = max(std([synth(:,d); realF(:,d)]), 1e-12);
        wd(d) = mean(abs(a-b)) / sc;          % normalised, so dims are comparable
    end
    W.per_dim_normalised = wd;
    W.mean = mean(wd); W.median = median(wd); W.max = max(wd);
    W.n_samples = nSamp;
    fprintf(['\n[tier1] Wasserstein (synth vs REAL RadChar LFM), 54-D feature space, ' ...
             'std-normalised: mean %.3f median %.3f max %.3f (n=%d each)\n'], ...
             W.mean, W.median, W.max, nSamp);
end

% =====================================================================
% Metric plumbing
% =====================================================================
function a = newAccumulator()
    a = struct('TP',0,'FP',0,'TN',0,'FN',0,'evasions',0,'confirmed',0);
end

function a = accumulate(a, o)
    a.TP = a.TP + o.TP; a.FP = a.FP + o.FP;
    a.TN = a.TN + o.TN; a.FN = a.FN + o.FN;
    a.evasions = a.evasions + o.evasion;
    a.confirmed = a.confirmed + o.confirmed;
end

function m = finalize(a, nSeeds)
    m = a;
    m.evasion_rate = a.evasions / nSeeds;
    [lo, hi] = wilsonCI(a.evasions, nSeeds, 1.96);
    m.evasion_ci = [lo hi];
    m.precision = safeDiv(a.TP, a.TP + a.FP);
    m.recall    = safeDiv(a.TP, a.TP + a.FN);
    if (m.precision + m.recall) > 0
        m.f1 = 2*m.precision*m.recall / (m.precision + m.recall);
    else
        m.f1 = 0;
    end
    m.mean_confirmed = a.confirmed / nSeeds;
end

function [lo, hi] = wilsonCI(k, n, z)
%WILSONCI  Wilson score interval -- correct at the 0% and 100% ends where
%   the normal approximation degenerates to a zero-width interval. The
%   checklist asks for Wilson specifically, and this benchmark hits 0% and
%   100% often enough that it matters.
    if n == 0; lo = 0; hi = 1; return; end
    ph = k/n; d = 1 + z^2/n;
    c = (ph + z^2/(2*n)) / d;
    h = z * sqrt(ph*(1-ph)/n + z^2/(4*n^2)) / d;
    lo = max(0, c-h); hi = min(1, c+h);
end

function y = safeDiv(a, b)
    if b == 0; y = NaN; else; y = a/b; end
end

function printMetrics(name, m, nSeeds)
    fprintf(['\n[%s]  evasion %.1f%% CI[%.1f%%, %.1f%%] (n=%d) | F1 %.3f  P %.3f  R %.3f\n' ...
             '        confusion TP=%d FP=%d TN=%d FN=%d | mean confirmed/trial %.2f\n' ...
             '        NIS in-band %.1f%% | innovation lag-1 rho %+.3f | AD p %.3f\n'], ...
        name, 100*m.evasion_rate, 100*m.evasion_ci(1), 100*m.evasion_ci(2), nSeeds, ...
        m.f1, m.precision, m.recall, m.TP, m.FP, m.TN, m.FN, m.mean_confirmed, ...
        100*m.nis_in_band_mean, m.innov_lag1_rho_mean, m.innov_ad_pvalue_mean);
end

% =====================================================================
% Small helpers
% =====================================================================
function fb = judgeCube(cube, cfg)
    C = physics.Constants();
    % The .mat DESCRIBES THE SIGNAL only. The radar's operating point is
    % passed to the judge as explicit arguments (Phase A1) -- it must not be
    % reachable through a file the adversary's exporter also writes.
    S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', cfg.pulseWidth, ...
        'bandwidth_hz', cfg.bandwidth, 'prf_hz', cfg.prf, ...
        'frame_interval_s', cfg.frameDt, 'carrier_hz', cfg.carrier);
    judgeArgs = {'Pfa', cfg.cfarPfa, 'NumTraining', cfg.cfarTrain, ...
        'NumGuard', cfg.cfarGuard, 'AssignmentThreshold', [cfg.gateM inf], ...
        'ConfirmationThreshold', cfg.confirm, 'DeletionThreshold', cfg.deletion, ...
        'FilterModel', cfg.filterModel, 'TrackerType', cfg.trackerType};
    if ~isempty(cfg.eccmScreens)
        judgeArgs = [judgeArgs, {'EccmScreens', cfg.eccmScreens}];
    else
        judgeArgs = [judgeArgs, {'EccmScreens', {''}}];
    end
    % Arms the micro-Doppler veto. Without it discriminator.m's expectMicro
    % gate is false and the screen is inert at ANY dwell length (T8).
    if isfield(cfg, 'expectMicro') && cfg.expectMicro
        judgeArgs = [judgeArgs, {'ExpectMicroDoppler', true}];
    end
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f, judgeArgs{:});
end

function chirp = idealChirp(cfg, C)
    n = round(cfg.pulseWidth * C.fs);
    t = (0:n-1)' / C.fs;
    chirp = exp(1i * pi * (cfg.bandwidth / cfg.pulseWidth) * t.^2);
end

function pulse = extractPulse(D, idx, fs)
    a = max(1, round(D.time_delay(idx)*fs) + 1);
    L = max(1, round(D.pulse_width(idx)*fs));
    x = D.iq(:, idx);
    pulse = x(a : min(numel(x), a+L-1));
end

function q = cachedQ(root)
    persistent Q
    if isempty(Q)
        Q = engine.entity.calibrateQ('Dt', 1.0, 'Dataset', cachedRadChar(root));
    end
    q = Q;
end

function D = cachedRadChar(root)
    persistent DS
    if isempty(DS)
        DS = data.loadRadChar(fullfile(root, 'data', 'RadChar-Tiny.h5'));
    end
    D = DS;
end

function s = valueLabel(v)
    if ischar(v) || isstring(v); s = char(v);
    elseif iscell(v)
        if isempty(v); s = '(none)'; else; s = strjoin(cellfun(@char, v, 'uni', 0), '+'); end
    elseif isscalar(v); s = sprintf('%g', v);
    else; s = mat2str(v);
    end
end

function y = ternary(c, a, b)
    if c; y = a; else; y = b; end
end
