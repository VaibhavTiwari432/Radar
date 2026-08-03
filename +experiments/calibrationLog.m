function T = calibrationLog(nEp, seeds, outCsv, observers)
%CALIBRATIONLOG  Per-episode (twin-belief, judge-actual) pairs -- the
%   calibration set the Assurance Layer's conformal predictor is fitted on.
%
%   T = experiments.calibrationLog(nEp, seeds, outCsv, observers)
%       % 20, 1:5, results/calibration_data.csv, {'nominal', {}}
%
%   THE OBSERVER AXIS, AND WHY IT EXISTS. Conformal's coverage guarantee is
%   conditional on EXCHANGEABILITY between the calibration set and what is
%   seen at deployment, and experiments.observerSweep measured a violation of
%   exactly that condition: at CFAR NumTraining 32 the judge's real rate falls
%   23.0% -> 8.0% (Wilson intervals disjoint) while the engine's inline belief
%   does not move at all. A calibration set drawn from ONE radar configuration
%   therefore cannot support a coverage claim about a radar whose training
%   length is unknown. `observers` is an Nx2 cell {name, runJudge args} and
%   each episode's SAME retained cube is scored under every one of them, so a
%   difference between two observer rows cannot be a different noise draw --
%   the same pairing observerSweep uses. Default is nominal alone, which
%   reproduces the single-configuration CSV exactly apart from one constant
%   `observer` column. experiments.exchangeability is what consumes it.
%
%   WHY THIS FILE EXISTS. experiments.t4JudgeGap and experiments.t6JudgeGap
%   already run exactly the right measurement -- roll an arm out with
%   keepCube on, so the SAME received cube the inline chain scored is
%   re-scored by engine.runJudge, and nothing is re-rendered -- but they
%   accumulate counters and discard the per-episode pairs. A conformal
%   predictor needs the pairs, not the rate. This is those two loops with
%   one row written per episode instead of three counters incremented, and
%   the arms/recipes are copied from them field for field so the rates this
%   file produces are comparable to the ones commit 6121e7ae (Tier 0 + Tier
%   1) records: structural 36.0% inline / 22.0% judge (+14.0 pp), shaped
%   10.5% inline after the retrain.
%
%   DO NOT COMPARE AGAINST results/t4_gap.log OR results/t6.log. Both are
%   untracked artefacts predating that commit (git ls-files returns nothing
%   for either) and both are stale by a wide margin -- t4_gap.log's 100.0%
%   inline / 76.0% judge was measured on swerling=0, a non-fluctuating
%   target the commit message itself calls "a target that cannot exist",
%   and t6.log's agent rates predate the Tier 0.3 retrain. This file's
%   printed per-arm summary reproduced the CORRECTED numbers (35.0%/19.0%
%   structural, 11.0% shaped inline) on first run, which is how the
%   staleness was caught.
%
%   THE PREDICTOR VARIABLE IS THE INLINE DISCRIMINATOR'S CONFIDENCE, not its
%   label. track.discriminator returns [label, conf]; both environments'
%   localReward drop the conf on the floor ([label, ~]). A binary belief
%   makes a degenerate conformal predictor -- every episode gets the same
%   nonconformity score and the interval is the whole outcome space. The
%   confidence is the graded signal that makes a prediction set worth
%   emitting, so it is recomputed here from the same rangeHist/ampHist/
%   rateHist evidence the environment's own screen saw.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2). The inline label is the
%   ADVERSARY's belief about itself and is never the ground truth; the
%   ground truth is engine.runJudge's verdict alone. Neither is visible to
%   any policy -- both are computed after the episode is complete. The two
%   are logged side by side precisely so the gap between them is measured
%   rather than assumed (Rule 2), and per episode rather than as a mean, so
%   the Assurance Layer can quantify it instead of quoting it.
%
%   ARMS. The three the report already characterises:
%     structural  agent.buildEnvEntity, one CV action HELD for all 8 frames,
%                 zero-velocity excluded -- t4JudgeGap's arm verbatim.
%     shaped      trained D3QN, results/doppler_agent_shaped.mat  } t6JudgeGap's
%     stats       trained D3QN, results/doppler_agent_stats.mat   } two arms
%   An arm with no agent on disk is SKIPPED with a printed line, not
%   silently omitted.

    if nargin < 1 || isempty(nEp);   nEp   = 20;    end
    if nargin < 2 || isempty(seeds); seeds = 1:5;   end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 3 || isempty(outCsv)
        outCsv = fullfile(root, 'results', 'calibration_data.csv');
    end
    if nargin < 4 || isempty(observers); observers = {'nominal', {}}; end

    C = physics.Constants();
    rows = {};

    % ---- arm 1: the structural CV-coherent generator (t4JudgeGap's recipe)
    [env, spec] = agent.buildEnvEntity(C, struct('shaping', false, ...
                        'keepCube', true, 'swerling', 1));
    nVel = numel(spec.velOptionsMps);
    nRcs = numel(spec.rcsOptionsDbsm);
    zeroVel = find(abs(spec.velOptionsMps) < 1e-9);   % see t4JudgeGap's header
    for s = seeds(:)'
        rng(s);
        for e = 1:nEp
            reset(env);
            vi = zeroVel;
            while vi == zeroVel; vi = randi(nVel); end
            ri = randi(nRcs);
            a  = sub2ind([nVel nRcs], vi, ri);
            lg = [];
            for k = 1:spec.framesPerEpisode
                [~, ~, ~, lg] = step(env, a);      % HELD -- one state, 8 frames
            end
            rows{end+1} = localRow('structural', s, e, lg, C, spec, observers, ...
                                    spec.velOptionsMps(vi), spec.rcsOptionsDbsm(ri)); %#ok<AGROW>
        end
        fprintf('structural seed %d: %d episodes\n', s, nEp);
    end

    % ---- arms 2-3: the trained D3QN agents (t6JudgeGap's recipe)
    for name = {'shaped', 'stats'}
        f = fullfile(root, 'results', ['doppler_agent_' name{1} '.mat']);
        if ~isfile(f)
            fprintf('  %-10s SKIPPED (no agent on disk)\n', name{1}); continue;
        end
        S = load(f);
        useStats = (S.spec.obsDim == 9);
        envD = agent.buildEnvDoppler(C, [], struct('shaping', false, ...
                    'useFeatures', ~useStats, 'useStats', useStats, 'keepCube', true));
        for s = seeds(:)'
            rng(s);
            for e = 1:nEp
                obs = reset(envD); lg = [];
                for k = 1:S.spec.framesPerEpisode
                    act = getAction(S.agnt, {obs});
                    if iscell(act); act = act{1}; end
                    [obs, ~, ~, lg] = step(envD, double(act));
                end
                % The agent chooses a fresh action every frame, so there is no
                % single held (vel, rcs) to log. NaN, not a fabricated value.
                rows{end+1} = localRow(name{1}, s, e, lg, C, S.spec, observers, NaN, NaN); %#ok<AGROW>
            end
            fprintf('%-10s seed %d: %d episodes\n', name{1}, s, nEp);
        end
    end

    T = struct2table([rows{:}]);
    writetable(T, outCsv);
    fprintf('\nwrote %d rows -> %s\n', height(T), outCsv);

    % Summary per arm, on the SAME scale t4/t6 print, so this file's numbers
    % can be checked against the already-published ones rather than trusted.
    for a = unique(T.arm)'
        for o = unique(T.observer)'
            m = strcmp(T.arm, a{1}) & strcmp(T.observer, o{1});
            if ~any(m); continue; end
            fprintf('  %-10s %-16s inline real %5.1f%%  |  runJudge real %5.1f%%  |  GAP %+5.1f pp  (confirmed %5.1f%%)\n', ...
                a{1}, o{1}, 100*mean(T.inline_real(m)), 100*mean(T.judge_real(m)), ...
                100*(mean(T.inline_real(m)) - mean(T.judge_real(m))), ...
                100*mean(T.judge_confirmed(m)));
        end
    end
end

% ------------------------------------------------------------------------
function r = localRow(arm, seed, ep, lg, C, spec, observers, velMps, rcsDbsm)
%LOCALROW  One calibration pair PER OBSERVER: what the adversary's own inline
%   screen believed, and what the independent judge actually did to the same
%   cube under each observer configuration. The inline belief is computed once
%   and repeated across the observer rows -- deliberately, and it is the whole
%   point of the measurement: the engine is never told which radar it faces,
%   so its belief CANNOT vary with the observer. Rows that share (arm, seed,
%   episode) are paired on one cube.
    [iLabel, iScore, sAmp, sDop] = localInline(lg, C);
    nObs = size(observers, 1);
    f = localWriteCube(lg.cubeFrames, C, spec);
    cleanup = onCleanup(@() localDelete(f)); %#ok<NASGU>
    r = repmat(struct( ...
        'arm', arm, 'observer', '', 'seed', seed, 'episode', ep, ...
        'vel_mps', velMps, 'rcs_dbsm', rcsDbsm, ...
        'inline_label', char(iLabel), 'inline_score', iScore, ...
        'inline_s_amp', sAmp, 'inline_s_dop', sDop, ...
        'inline_real', double(strcmp(char(iLabel), 'real')), ...
        'judge_confirmed', 0, 'judge_label', '', 'judge_real', 0), 1, nObs);
    for c = 1:nObs
        [jLabel, jConfirmed] = localJudge(f, observers{c, 2});
        r(c).observer        = observers{c, 1};
        r(c).judge_confirmed = double(jConfirmed);
        r(c).judge_label     = char(jLabel);
        r(c).judge_real      = double(jConfirmed && strcmp(char(jLabel), 'real'));
    end
end

% ------------------------------------------------------------------------
function localDelete(f)
    if ~isempty(f) && isfile(f); delete(f); end
end

% ------------------------------------------------------------------------
function [label, score, sAmp, sDop] = localInline(lg, C)
%LOCALINLINE  The environment's own ECCM verdict, the combined signed score,
%   and EACH SCREEN'S OWN SCORE separately.
%
%   WHY THE PER-SCREEN SCORES EXIST. The combined score is `mean(scores)`
%   over the enabled screens, and measurement showed that mean is close to
%   information-free on this project's arms: it is pinned at EXACTLY 0.500
%   for most episodes (the stats arm took only 8 distinct values across 100
%   episodes), because the Doppler screen scores 1.0 while the amplitude
%   screen scores 0.0 and the two cancel dead on the discriminator's own
%   `> 0.5` boundary. Averaging destroys the very quantity that separates
%   episodes. A conformal predictor built on that mean produces valid but
%   near-useless prediction sets (1.81 of a possible 2), and a Simplex guard
%   built on it is nearly a constant function (94% fallback). Neither is
%   fixable by tuning a threshold -- the predictor VARIABLE is lossy.
%
%   HOW THEY ARE OBTAINED WITHOUT TOUCHING THE JUDGE. track.discriminator
%   already accepts a `screensEnabled` mask (the same interface
%   engine.runJudge's 'EccmScreens' option and experiments.screenAttribution
%   use), so calling it once per screen returns that screen's own score --
%   no third output argument added to a heavily-validated judge function, and
%   no forked copy of it that could drift.
%
%   An UNINFORMATIVE screen correctly reads 0.5: with its only screen
%   skipped, discriminator's `scores` is empty and it returns 0.5,
%   "nothing informative either way". That is a real reading, not a missing
%   value, and must not be confused with NaN (no track at all).
%
%   track.discriminator's second output is a CONFIDENCE, abs(score-0.5)*2 --
%   a distance from the decision boundary, so 0.09 next to label "real" and
%   0.09 next to label "decoy" are opposite beliefs wearing the same number.
%   Un-folded here to the score itself (score = 0.5 +/- conf/2, the same
%   inversion both environments' localPotential already performs), because a
%   predictor that cannot tell a barely-real track from a barely-decoy one
%   is not a predictor.
%
%   Mirrors both environments' private localTrackStruct: measurements only,
%   .doppler is the MEASURED range-rate (never diff(range)), and
%   .dopplerMeasured is true so screen 2's contradiction branch is armed.
    label = lg.eccmLabel; score = NaN; sAmp = NaN; sDop = NaN;
    m = ~isnan(lg.rangeHist) & ~isnan(lg.ampHist) & ~isnan(lg.rateHist);
    if nnz(m) < 2; return; end     % unscreened/unconfirmed: no score exists
    ts = struct('range', lg.rangeHist(m), 'amplitude', lg.ampHist(m), ...
                'doppler', lg.rateHist(m), 'dopplerMeasured', true);
    [label, score] = localScore(ts, C);                       % both screens
    tsA = ts; tsA.screensEnabled = {'amplitude'};
    [~, sAmp] = localScore(tsA, C);
    tsD = ts; tsD.screensEnabled = {'doppler'};
    [~, sDop] = localScore(tsD, C);
end

% ------------------------------------------------------------------------
function [label, score] = localScore(ts, C)
%LOCALSCORE  discriminator's verdict with its confidence un-folded back into
%   the signed score. `confidence` is abs(score-0.5)*2, a distance from the
%   boundary, so 0.09 beside "real" and 0.09 beside "decoy" are opposite
%   beliefs wearing the same number. Same inversion both environments'
%   localPotential already performs.
    [label, conf] = track.discriminator(ts, C);
    if label == "real"; score = 0.5 + conf/2; else; score = 0.5 - conf/2; end
end

% ------------------------------------------------------------------------
function f = localWriteCube(cubeFrames, C, spec)
%LOCALWRITECUBE  Signal description only -- the judge's own configuration
%   never crosses this seam (Phase A1); it arrives as runJudge arguments.
%   Written ONCE per episode and scored under every observer, so the observer
%   rows are paired on one cube (observerSweep's method).
    f = '';
    if isempty(cubeFrames); return; end
    S = struct('rx_frames', cubeFrames, 'fs', C.fs, ...
        'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', C.PRF, ...
        'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz);
    f = [tempname '.mat']; save(f, '-struct', 'S');
end

% ------------------------------------------------------------------------
function [label, confirmed] = localJudge(f, args)
%LOCALJUDGE  Field-for-field copy of t4JudgeGap's/t6JudgeGap's localJudge, so
%   the pairs logged here sit on the same scale as the published gaps -- plus
%   the observer's own runJudge arguments.
    label = ""; confirmed = false;
    if isempty(f); return; end
    if isempty(args) || ~any(strcmp(args(1:2:end), 'EccmScreens'))
        % Default screen mask matches t4JudgeGap/t6JudgeGap so the nominal
        % rows stay comparable to the published gaps.
        args = [args, {'EccmScreens', {'amplitude', 'doppler'}}];
    end
    fb = engine.runJudge(f, args{:});
    if isfield(fb, 'eccm_label') && strlength(string(fb.eccm_label)) > 0
        confirmed = true;
        label = string(fb.eccm_label);
    end
end
