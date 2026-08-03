function out = t6JudgeGap(nEp, seed, outDir)
%T6JUDGEGAP  Measure the SIM-TO-JUDGE GAP for the trained D3QN agents.
%   (POA Phase 3, T6.)
%
%   out = experiments.t6JudgeGap(nEp, seed, outDir)
%
%   THE PROBLEM T6 EXISTS FOR. agent.buildEnvDoppler scores an episode with
%   an INLINE chain: radar.cfarDetect -> track.runTracker -> track.discriminator.
%   It never calls engine.runJudge. So every real-rate this project has
%   published for the D3QN -- 8.5%, 22.5%, 44.0%, 100.0% -- is against a
%   two-screen inline judge, and none of them is comparable to
%   BENCHMARK_RESULTS.md. The POA's Rule 5 is explicit: MEASURE the gap, do
%   not assume it is small.
%
%   That assumption is now known to be unsafe. T8 measured a sim-to-judge gap
%   of +40.0 pp at a 512-pulse dwell (twin 100% vs judge 60%), up from +0.0 pp
%   at the published operating point.
%
%   METHOD. Roll out the agent in its own environment with keepCube on, so
%   the SAME received cube the inline chain scored is retained, then re-score
%   that identical signal through engine.runJudge. Nothing is re-rendered:
%   a fresh render would draw different noise and confound the gap with a
%   different draw.
%
%   WHAT THIS IS NOT. This does not train against runJudge -- that is the
%   expensive half of T6, and whether it is worth doing depends on this
%   number. If the gap is small the retrain is unnecessary; if it is large,
%   that is the finding and the retrain is the follow-on.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): the agent never sees either
%   verdict. Both labels are computed after the episode is complete.

    if nargin < 1 || isempty(nEp);  nEp  = 100; end
    if nargin < 2 || isempty(seed); seed = 7;   end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 3 || isempty(outDir); outDir = fullfile(root, 'results'); end

    C = physics.Constants();
    arms = {'shaped', 'stats'};          % the two that reached a real rate

    out = struct('armName', {{}}, 'inlineReal', [], 'judgeReal', [], ...
                 'gapPp', [], 'judgeConfirmed', [], 'nEp', nEp);

    fprintf('t6JudgeGap: %d episodes/arm, identical cube scored both ways\n\n', nEp);
    for a = 1:numel(arms)
        name = arms{a};
        f = fullfile(root, 'results', ['doppler_agent_' name '.mat']);
        if ~isfile(f)
            fprintf('  %-8s SKIPPED (no agent on disk)\n', name); continue;
        end
        S = load(f);
        useStats = (S.spec.obsDim == 9);
        env = agent.buildEnvDoppler(C, [], struct( ...
                'shaping', false, 'useFeatures', ~useStats, ...
                'useStats', useStats, 'keepCube', true));

        rng(seed);
        nInline = 0; nJudge = 0; nConf = 0;
        for e = 1:nEp
            obs = reset(env); lg = [];
            for k = 1:S.spec.framesPerEpisode
                act = getAction(S.agnt, {obs});
                if iscell(act); act = act{1}; end
                [obs, ~, ~, lg] = step(env, double(act));
            end
            nInline = nInline + double(strcmp(char(lg.eccmLabel), 'real'));
            [jLabel, confirmed] = localJudge(lg.cubeFrames, C, S.spec);
            nConf  = nConf  + double(confirmed);
            nJudge = nJudge + double(confirmed && strcmp(jLabel, 'real'));
        end

        pI = nInline/nEp; pJ = nJudge/nEp;
        out.armName{end+1} = name;
        out.inlineReal(end+1) = pI;
        out.judgeReal(end+1)  = pJ;
        out.gapPp(end+1)      = 100*(pI - pJ);
        out.judgeConfirmed(end+1) = nConf/nEp;
        fprintf(['  %-8s inline real %5.1f%%  |  runJudge real %5.1f%%  ' ...
                 '|  GAP %+5.1f pp  (runJudge confirmed %5.1f%%)\n'], ...
            name, 100*pI, 100*pJ, 100*(pI-pJ), 100*nConf/nEp);
    end

    f = fullfile(outDir, 't6_judge_gap.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s\n', f);
end

% ------------------------------------------------------------------------
function [label, confirmed] = localJudge(cubeFrames, C, spec)
%LOCALJUDGE  Score a retained cube through engine.runJudge. Mirrors
%   benchmarkSuite's judgeCube field-for-field, with the environment's own
%   waveform constants so the two judges see the same radar.
    label = ""; confirmed = false;
    if isempty(cubeFrames); return; end
    % Signal description only; the judge runs on its OWN defaults (Phase A1)
    % apart from the ECCM screen mask this experiment deliberately selects.
    S = struct('rx_frames', cubeFrames, 'fs', C.fs, ...
        'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', physics.Constants().PRF, ...
        'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz);
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f, 'EccmScreens', {'amplitude','doppler'});
    % runJudge's aggregate: eccm_label is "" when nothing confirmed, the
    % unanimous label when all tracks agree, 'mixed' otherwise. The env's
    % scene holds ONE object, so 'mixed' should not arise; if it does, it is
    % a spurious second track and is counted as not-real rather than hidden.
    if isfield(fb, 'eccm_label') && strlength(string(fb.eccm_label)) > 0
        confirmed = true;
        label = string(fb.eccm_label);
    end
end
