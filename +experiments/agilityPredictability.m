function out = agilityPredictability(persistences, nSeeds, outDir)
%AGILITYPREDICTABILITY  How much does predicting the radar's agility schedule
%   actually buy a DRFM repeater -- as a function of how predictable that
%   schedule is?
%
%   out = experiments.agilityPredictability(persistences, nSeeds, outDir)
%
%   THE QUESTION, AND WHY IT NEEDS ASKING BEFORE IT NEEDS BUILDING.
%   The proposal was: "by analysing the frequency jumps of intercepted
%   pulses, predict the radar's next frequency and pre-tune the synthesiser,
%   neutralising frequency-hopping defences."
%
%   Against THIS project's radar that is not a hard problem, it is an
%   IMPOSSIBLE one, and the reason is information-theoretic rather than
%   architectural. tests/test_waveform_agility.m draws the schedule as
%
%       sched = sign(randn(schedRs, 1, N+1));
%
%   i.i.d. fair coin flips. For a memoryless source
%
%       H(X_{n+1} | X_1..X_n) = H(X_{n+1}) = 1 bit
%
%   the history carries ZERO mutual information about the next symbol, so
%   the Bayes-optimal predictor is 50% and no network, feature set or
%   training budget can beat it. Reporting a "learned frequency predictor"
%   at 50% on this radar would be reporting a coin.
%
%   What IS answerable, and is the useful form of the question: real agile
%   radars are not i.i.d. -- hop sequences come from PRNGs, m-sequences, or
%   sets constrained by synthesiser settling time, range/Doppler ambiguity
%   and blanking. Those constraints leave structure. So the honest
%   experiment parameterises the structure and measures where prediction
%   starts to pay:
%
%       schedule = 2-state Markov chain, P(next == current) = p
%           p = 0.5  -> i.i.d., the current model, unpredictable by proof
%           p -> 1   -> constant, the pre-agility radar
%           p -> 0   -> strict alternation, perfectly predictable too
%
%   The Bayes ceiling is max(p, 1-p). We give the repeater an order-1
%   empirical predictor (count transitions seen so far, predict the mode),
%   let it build its replay template from its PREDICTION, and score the
%   result with the REAL judge (+engine/runJudge). Two references bracket it:
%       oracle : knows the schedule (upper bound, = "fresh")
%       stale  : always replays last frame (lower bound, no prediction)
%
%   INPUTS
%       persistences : vector of p (default [0.5 0.6 0.7 0.8 0.9 1.0])
%       nSeeds       : seeds per cell (default 10, matching test_waveform_agility)
%
%   Everything scored here is scored by the independent judge. This function
%   renders and predicts; it never decides whether it succeeded.

    if nargin < 1 || isempty(persistences); persistences = [0.5 0.6 0.7 0.8 0.9 1.0]; end
    if nargin < 2 || isempty(nSeeds);       nSeeds = 10; end
    if nargin < 3 || isempty(outDir)
        here = fileparts(mfilename('fullpath'));
        outDir = fullfile(fileparts(here), 'results');
    end
    if ~isfolder(outDir); mkdir(outDir); end

    K = struct('PW_S',12e-6,'BW_HZ',2e6,'PRF_HZ',50e3,'CARRIER',10e9, ...
               'N_FRAMES',8,'N_PULSES',32,'N_FAST',400, ...
               'GEN_R0',3800,'PH_R0',2000,'AMP',3.0);

    modes = {'predict','oracle','stale'};
    nP = numel(persistences);
    dec  = zeros(nP, 3);          % deception rate (phantom confirmed AND labelled real)
    conf = zeros(nP, 3);          % phantom confirmed at all
    acc  = zeros(nP, 1);          % realised prediction accuracy
    ceil_ = max(persistences(:), 1 - persistences(:));

    fprintf('agilityPredictability: %d persistences x %d seeds x %d modes\n', nP, nSeeds, 3);
    t0 = tic;
    for ip = 1:nP
        p = persistences(ip);
        accAcc = 0; accN = 0;
        for m = 1:3
            for s = 1:nSeeds
                [d, cf, a, n] = localCell(p, modes{m}, s, K);
                dec(ip,m)  = dec(ip,m) + d;
                conf(ip,m) = conf(ip,m) + cf;
                if m == 1; accAcc = accAcc + a; accN = accN + n; end
            end
        end
        acc(ip) = accAcc / max(1, accN);
        fprintf('  p=%.2f | predAcc %.3f (ceiling %.3f) | deceived predict %d/%d oracle %d/%d stale %d/%d  [%.1f min]\n', ...
            p, acc(ip), ceil_(ip), dec(ip,1), nSeeds, dec(ip,2), nSeeds, dec(ip,3), nSeeds, toc(t0)/60);
    end

    out = struct('persistences', persistences(:), 'predAccuracy', acc, ...
        'bayesCeiling', ceil_, 'deceived', dec, 'phantomConfirmed', conf, ...
        'nSeeds', nSeeds, 'modes', {modes}, 'elapsedMin', toc(t0)/60);

    f = fullfile(outDir, 'agility_predictability.mat');
    save(f, '-struct', 'out');
    fprintf('agilityPredictability: saved -> %s\n', f);
end

% ========================================================================
function [deceived, phConfirmed, nCorrect, nPred] = localCell(p, mode, seed, K)
%LOCALCELL  One (persistence, mode, seed) cell, scored by the real judge.
%   Mirrors tests/test_waveform_agility.m's runCell, with the repeater's
%   template chosen by PREDICTION instead of by a fixed fresh/stale rule.

    C = physics.Constants();
    rs = RandStream('twister', 'Seed', 7000 + seed);

    % ---- radar's secret schedule: 2-state Markov with persistence p ----
    schedRs = RandStream('twister', 'Seed', 424242 + seed + round(1000*p));
    n = K.N_FRAMES + 1;
    sched = zeros(1, n);
    sched(1) = 1 - 2*(rand(schedRs) < 0.5);          % +1 or -1
    for k = 2:n
        if rand(schedRs) < p; sched(k) = sched(k-1); else; sched(k) = -sched(k-1); end
    end

    % Every sweep sign the radar could transmit, precomputed once.
    tmplUp = []; tmplDn = [];
    [~, tmplUp] = radar.agileWaveform(+1, C.fs, K.PW_S, K.PRF_HZ, K.BW_HZ);
    [~, tmplDn] = radar.agileWaveform(-1, C.fs, K.PW_S, K.PRF_HZ, K.BW_HZ);
    tmplOf = @(sgn) localPick(sgn, tmplUp, tmplDn);

    q = struct('sigma_accel_mps2', 0.05*9.80665, 'rcs_process_std_db', 0.233);
    sg = engine.entity.EntityState('range_m', K.GEN_R0, 'range_rate_mps', -60, ...
            'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
    sp = engine.entity.EntityState('range_m', K.PH_R0, 'range_rate_mps', -60, ...
            'class', 'fighter', 'rcs_dbsm', 0, 'swerling', 0);
    genRange = zeros(K.N_FRAMES,1); phRange = zeros(K.N_FRAMES,1);
    cube = complex(zeros(K.N_FAST, K.N_PULSES, K.N_FRAMES));

    nCorrect = 0; nPred = 0;
    for k = 1:K.N_FRAMES
        genRange(k) = sg.range_m; phRange(k) = sp.range_m;

        % A REAL target reflects whatever the radar is transmitting NOW.
        cg = engine.entity.render(sg, 'AmpScale', K.AMP, 'NumPulses', K.N_PULSES, ...
                'FastTimeSamples', K.N_FAST, 'CarrierHz', K.CARRIER, 'PrfHz', K.PRF_HZ, ...
                'PulseWidth', K.PW_S, 'Bandwidth', K.BW_HZ, ...
                'ChirpOverride', tmplOf(sched(k)), 'RandStream', rs);

        % ---- the repeater picks the sweep sign it will TRANSMIT ----
        % It has intercepted frames 1..k-1 and must commit before hearing
        % frame k. That causality is the whole point: a repeater that could
        % read sched(k) first would not need to predict at all.
        switch mode
            case 'oracle'
                guess = sched(k);                        % upper bound
            case 'stale'
                if k == 1; guess = sched(1); else; guess = sched(k-1); end
            otherwise                                    % 'predict'
                guess = localPredict(sched(1:k-1));
                nPred = nPred + 1;
                nCorrect = nCorrect + double(guess == sched(k));
        end

        cp = engine.entity.render(sp, 'AmpScale', K.AMP, 'NumPulses', K.N_PULSES, ...
                'FastTimeSamples', K.N_FAST, 'CarrierHz', K.CARRIER, 'PrfHz', K.PRF_HZ, ...
                'PulseWidth', K.PW_S, 'Bandwidth', K.BW_HZ, ...
                'ChirpOverride', tmplOf(guess), 'RandStream', rs);

        nz = 0.05 * (randn(rs, K.N_FAST, K.N_PULSES) + ...
                1i*randn(rs, K.N_FAST, K.N_PULSES)) / sqrt(2);
        cube(:,:,k) = cg + cp + nz;
        sg = engine.entity.propagate(sg, 1.0, q, rs);
        sp = engine.entity.propagate(sp, 1.0, q, rs);
    end

    fb = localJudge(cube, sched(1:K.N_FRAMES), K);
    deceived = false; phConfirmed = false;
    for i = 1:fb.confirmed_tracks
        rSeq = fb.track_range_m{i};
        if isempty(rSeq); continue; end
        est = mean(rSeq);
        if min(abs(phRange - est)) < min(abs(genRange - est))
            phConfirmed = true;
            deceived = deceived || strcmp(fb.track_label{i}, 'real');
        end
    end
end

% ------------------------------------------------------------------------
function g = localPredict(hist)
%LOCALPREDICT  Order-1 empirical predictor: given the last symbol, predict
%   the transition seen most often after it. This is the maximum-likelihood
%   estimate of the Markov chain the schedule actually is, so it converges to
%   the Bayes-optimal rule max(p,1-p) -- there is nothing a deeper model
%   could extract that this misses, because the source has no higher-order
%   structure to find. Using a D3QN here would not raise the ceiling; it
%   would only take longer to reach it.
    if numel(hist) < 2; g = 1; if ~isempty(hist); g = hist(end); end; return; end
    last = hist(end);
    idx = find(hist(1:end-1) == last);
    if isempty(idx); g = last; return; end
    nxt = hist(idx + 1);
    stay = sum(nxt == last); flip = sum(nxt ~= last);
    if stay >= flip; g = last; else; g = -last; end
end

% ------------------------------------------------------------------------
function t = localPick(sgn, up, dn)
    if sgn >= 0; t = up; else; t = dn; end
end

% ------------------------------------------------------------------------
function fb = localJudge(cube, sched, K)
    C = physics.Constants();
    S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', K.PW_S, ...
        'bandwidth_hz', K.BW_HZ, 'prf_hz', K.PRF_HZ, 'cfar_pfa', 1e-4, ...
        'cfar_num_training', 20, 'cfar_num_guard', 4, 'frame_interval_s', 1.0, ...
        'carrier_hz', K.CARRIER, 'sweep_schedule', sched);
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f);
end
