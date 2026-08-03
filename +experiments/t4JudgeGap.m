function out = t4JudgeGap(nEp, seed, swerling)
%T4JUDGEGAP  Inline-vs-runJudge real-rate for the STRUCTURAL CV-coherent
%   generator (agent.buildEnvEntity), on the IDENTICAL received cube.
%
%   out = experiments.t4JudgeGap(nEp, seed)
%
%   WHY THIS FILE EXISTS. The T4 gap has been quoted from results/t4_gap.log,
%   which was produced by an ad-hoc script that was never committed -- so the
%   number was re-runnable in principle and not in practice (CLAUDE.md Rule
%   3). It is the acceptance measurement for Tier 0.2 (MeasurementNoise) and
%   is needed again for Tier 0.4's consolidated table, so it is a file now.
%
%   METHOD, mirroring experiments.t6JudgeGap exactly so the two gaps are read
%   on the same scale: roll out with keepCube on, so the SAME received cube
%   the inline chain scored is re-scored by engine.runJudge. Nothing is
%   re-rendered -- a fresh render would draw different noise and confound the
%   gap with a different draw.
%
%   POLICY: CV-coherent and NON-STATIONARY. One (range-rate, RCS) action is
%   drawn per episode and HELD for all 8 frames, which is what "structural CV"
%   means -- one object, one velocity, one identity. The zero-velocity index
%   is excluded: a stationary phantom's range never varies, so discriminator
%   screen 1 falls through to its "range AND amplitude both dead flat" branch
%   and screen 2 has no direction to check. Being flagged there is the ECCM
%   working as designed, so blending those episodes in would understate the
%   generator for a reason that is not about the generator.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): both labels are computed after
%   the episode is complete and neither is visible to the policy.

    if nargin < 1 || isempty(nEp);  nEp  = 100; end
    if nargin < 2 || isempty(seed); seed = 7;   end
    % Tier 1.3: swerling is a stated parameter now. Default follows
    % agent.buildEnvEntity's own default (1, fluctuating); pass 0 to reproduce
    % the Tier 0 numbers, which were measured on a non-fluctuating entity.
    if nargin < 3 || isempty(swerling); swerling = 1; end

    C = physics.Constants();
    [env, spec] = agent.buildEnvEntity(C, struct('shaping', false, ...
                        'keepCube', true, 'swerling', swerling));
    nVel = numel(spec.velOptionsMps);
    nRcs = numel(spec.rcsOptionsDbsm);
    zeroVel = find(abs(spec.velOptionsMps) < 1e-9);   % excluded, see header

    rng(seed);
    nInline = 0; nJudge = 0; nConf = 0;
    for e = 1:nEp
        reset(env);
        vi = zeroVel;
        while vi == zeroVel; vi = randi(nVel); end
        a = sub2ind([nVel nRcs], vi, randi(nRcs));
        lg = [];
        for k = 1:spec.framesPerEpisode
            [~, ~, ~, lg] = step(env, a);          % HELD -- one state, 8 frames
        end
        nInline = nInline + double(strcmp(char(lg.eccmLabel), 'real'));
        [jLabel, confirmed] = localJudge(lg.cubeFrames, C, spec);
        nConf  = nConf  + double(confirmed);
        nJudge = nJudge + double(confirmed && strcmp(jLabel, 'real'));
    end

    pI = nInline/nEp; pJ = nJudge/nEp;
    [iLo, iHi] = localWilson(nInline, nEp);
    [jLo, jHi] = localWilson(nJudge,  nEp);
    out = struct('nEp', nEp, 'seed', seed, 'swerling', swerling, ...
        'inlineReal', pI, 'inlineCI', [iLo iHi], ...
        'judgeReal',  pJ, 'judgeCI',  [jLo jHi], ...
        'gapPp', 100*(pI - pJ), 'judgeConfirmed', nConf/nEp);

    fprintf('\n  (swerling = %d)', swerling);
    fprintf(['\nT4 CV-coherent, NON-STATIONARY, n=%d, seed=%d\n' ...
             '  inline real %5.1f%% [%.1f, %.1f]  |  runJudge real %5.1f%% [%.1f, %.1f]' ...
             '  |  GAP %+5.1f pp  (runJudge confirmed %5.1f%%)\n'], ...
        nEp, seed, 100*pI, 100*iLo, 100*iHi, 100*pJ, 100*jLo, 100*jHi, ...
        100*(pI-pJ), 100*nConf/nEp);
end

% ------------------------------------------------------------------------
function [label, confirmed] = localJudge(cubeFrames, C, spec)
%LOCALJUDGE  Field-for-field copy of experiments.t6JudgeGap's localJudge, so
%   the T4 and T6 gaps are measured by the same judge under the same screens.
    label = ""; confirmed = false;
    if isempty(cubeFrames); return; end
    S = struct('rx_frames', cubeFrames, 'fs', C.fs, ...
        'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', C.PRF, ...
        'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz);
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f, 'EccmScreens', {'amplitude','doppler'});
    if isfield(fb, 'eccm_label') && strlength(string(fb.eccm_label)) > 0
        confirmed = true;
        label = string(fb.eccm_label);
    end
end

% ------------------------------------------------------------------------
function [lo, hi] = localWilson(k, n)
    if n == 0; lo = NaN; hi = NaN; return; end
    z = 1.959963984540054;
    p = k/n; den = 1 + z^2/n; c = p + z^2/(2*n);
    hw = z*sqrt(p*(1-p)/n + z^2/(4*n^2));
    lo = (c-hw)/den; hi = (c+hw)/den;
end
