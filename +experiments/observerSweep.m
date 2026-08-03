function out = observerSweep(nEp, seed, outMat)
%OBSERVERSWEEP  Domain randomization over the OBSERVER: does the engine
%   degrade gracefully when the radar is not the one it assumed?
%
%   out = experiments.observerSweep(nEp, seed, outMat)   % 40, 7, results/observer_sweep.mat
%
%   THE QUESTION. Every deception number in this project is against ONE
%   radar configuration. The known-radar assumption is stated as an honest
%   limit (CLAUDE.md, "Honest Limits (Phase 2)") but has never been swept:
%   nobody has measured whether being wrong about the adversary costs a few
%   points or falls off a cliff. A cliff would mean the headline rate is an
%   artifact of one lucky Pfa; graceful degradation would mean it is a
%   property of the generator.
%
%   METHOD, AND WHY IT IS PAIRED. Roll the structural CV-coherent generator
%   out ONCE per episode with keepCube on, then score that SAME received
%   cube through engine.runJudge under every observer configuration in the
%   grid before discarding it. Detection noise, the emitted signal and the
%   entity's kinematics are therefore IDENTICAL across every row of the
%   table -- a difference between two rows cannot be a different draw. The
%   alternative (an independent run per config) would confound the observer
%   change with the noise change at exactly the sample sizes that make this
%   affordable.
%
%   WHY runJudge's NAME-VALUE ARGUMENTS ARE THE RIGHT LEVER. Phase A1 moved
%   every judge knob -- Pfa, NumTraining, NumGuard, AssignmentThreshold,
%   ConfirmationThreshold, EccmScreens -- out of the .mat the adversary
%   writes and into arguments only a MATLAB caller can set, precisely so the
%   judge could be swept without the adversary being able to reach it. This
%   experiment is the first thing to use that seam for its intended purpose.
%   The engine is NOT told which configuration it is facing; its inline
%   belief is computed from its own fixed screens exactly as always. That is
%   what makes this a domain-randomization measurement and not a re-tuning.
%
%   THE GRID IS ONE-AT-A-TIME, NOT A CROSS PRODUCT. Each row moves a single
%   knob off the nominal, so a change is attributable to that knob. A full
%   cross product multiplies the judge calls without answering a question
%   this experiment asks; if an interaction is suspected later, that is a
%   targeted follow-up, not a reason to pay for every cell now.

    if nargin < 1 || isempty(nEp);  nEp  = 40; end
    if nargin < 2 || isempty(seed); seed = 7;  end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 3 || isempty(outMat)
        outMat = fullfile(root, 'results', 'observer_sweep.mat');
    end

    C = physics.Constants();

    % --- the observer grid. Nominal first, so every later row is read as a
    % delta against it. Each entry is a name-value cell handed to runJudge.
    cfgs = { ...
        'nominal',            {}; ...
        'Pfa 1e-6 (strict)',  {'Pfa', 1e-6}; ...
        'Pfa 1e-2 (loose)',   {'Pfa', 1e-2}; ...
        'training 10',        {'NumTraining', 10}; ...
        'training 32',        {'NumTraining', 32}; ...
        'guard 2',            {'NumGuard', 2}; ...
        'guard 8',            {'NumGuard', 8}; ...
        'gate 100 m',         {'AssignmentThreshold', [100 inf]}; ...
        'gate 400 m',         {'AssignmentThreshold', [400 inf]}; ...
        'confirm [2 3]',      {'ConfirmationThreshold', [2 3]}; ...
        'confirm [4 5]',      {'ConfirmationThreshold', [4 5]}; ...
        'amplitude screen only', {'EccmScreens', {'amplitude'}}; ...
        'doppler screen only',   {'EccmScreens', {'doppler'}}; ...
    };
    nCfg = size(cfgs, 1);

    [env, spec] = agent.buildEnvEntity(C, struct('shaping', false, ...
                        'keepCube', true, 'swerling', 1));
    nVel = numel(spec.velOptionsMps);
    nRcs = numel(spec.rcsOptionsDbsm);
    zeroVel = find(abs(spec.velOptionsMps) < 1e-9);   % see t4JudgeGap's header

    nReal = zeros(1, nCfg); nConf = zeros(1, nCfg);
    nInlineReal = 0;

    rng(seed);
    fprintf('observerSweep: %d episodes x %d observer configs, paired on the same cube\n\n', nEp, nCfg);
    for e = 1:nEp
        reset(env);
        vi = zeroVel;
        while vi == zeroVel; vi = randi(nVel); end
        a = sub2ind([nVel nRcs], vi, randi(nRcs));
        lg = [];
        for k = 1:spec.framesPerEpisode
            [~, ~, ~, lg] = step(env, a);          % HELD -- one state, 8 frames
        end
        nInlineReal = nInlineReal + double(strcmp(char(lg.eccmLabel), 'real'));

        % One cube, written once, scored nCfg times.
        f = localWriteCube(lg.cubeFrames, C, spec);
        cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
        for c = 1:nCfg
            args = cfgs{c, 2};
            if isempty(args) || ~any(strcmp(args(1:2:end), 'EccmScreens'))
                % Default screen mask matches t4JudgeGap/t6JudgeGap so the
                % nominal row is comparable to the published gaps.
                args = [args, {'EccmScreens', {'amplitude', 'doppler'}}]; %#ok<AGROW>
            end
            fb = engine.runJudge(f, args{:});
            if isfield(fb, 'eccm_label') && strlength(string(fb.eccm_label)) > 0
                nConf(c) = nConf(c) + 1;
                nReal(c) = nReal(c) + double(strcmp(char(fb.eccm_label), 'real'));
            end
        end
        clear cleanup
        if mod(e, 10) == 0; fprintf('  %d/%d episodes\n', e, nEp); end
    end

    pInline = nInlineReal / nEp;
    pReal   = nReal / nEp;
    pConf   = nConf / nEp;
    nominal = pReal(1);

    fprintf('\n  engine inline belief (fixed, never told which observer): %5.1f%% real\n\n', 100*pInline);
    fprintf('  %-24s %10s %10s %12s %10s\n', 'observer config', 'confirmed', 'real', 'vs nominal', 'gap pp');
    for c = 1:nCfg
        [lo, hi] = localWilson(nReal(c), nEp);
        fprintf('  %-24s %9.1f%% %9.1f%% [%.0f,%.0f] %+11.1f %+9.1f\n', ...
            cfgs{c,1}, 100*pConf(c), 100*pReal(c), 100*lo, 100*hi, ...
            100*(pReal(c) - nominal), 100*(pInline - pReal(c)));
    end

    % Graceful degradation = no config drops the rate by more than half the
    % nominal. A threshold, stated up front rather than chosen after seeing
    % the numbers; a FAIL here is a real finding about the known-radar
    % assumption, not a reason to move the line.
    worst = min(pReal);
    cliff = worst < nominal / 2;
    fprintf('\n  nominal %.1f%%, worst config %.1f%% -> %s\n', 100*nominal, 100*worst, ...
        ternary(cliff, 'CLIFF (a single knob more than halves the rate)', 'GRACEFUL'));

    out = struct('nEp', nEp, 'seed', seed, 'configNames', {cfgs(:,1)'}, ...
        'inlineReal', pInline, 'judgeReal', pReal, 'judgeConfirmed', pConf, ...
        'nominalReal', nominal, 'worstReal', worst, 'cliff', cliff, ...
        'gapPp', 100*(pInline - pReal));
    save(outMat, '-struct', 'out');
    fprintf('\nsaved -> %s\n', outMat);
end

% ------------------------------------------------------------------------
function f = localWriteCube(cubeFrames, C, spec)
%LOCALWRITECUBE  Signal description only -- the judge's own configuration
%   never crosses this seam (Phase A1); it arrives as runJudge arguments.
    S = struct('rx_frames', cubeFrames, 'fs', C.fs, ...
        'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', C.PRF, ...
        'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz);
    f = [tempname '.mat']; save(f, '-struct', 'S');
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end

% ------------------------------------------------------------------------
function s = ternary(c, a, b)
    if c; s = a; else; s = b; end
end
