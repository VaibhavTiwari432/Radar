function out = phaseControllability(varargin)
%PHASECONTROLLABILITY  Which signal phase moves which coordinate, and which
%   coordinate cannot be moved at all.
%
%   THE QUESTION. A drone transmits ONE signal from ONE aperture. What set of
%   apparent coordinates can it manufacture at the radar? Equivalently: of the
%   three numbers that fix a position -- range, azimuth, elevation -- how many
%   are actually under the adversary's control?
%
%   THERE ARE THREE DISTINCT PHASES IN THIS SYSTEM and conflating them is the
%   source of most confusion about what a repeater can do:
%
%     1. FAST-TIME phase, WITHIN one pulse -- the chirp itself. Delaying it by
%        tau moves the matched-filter peak, and R = c*tau/2. ADVERSARY-OWNED:
%        a DRFM delays what it received.
%
%     2. SLOW-TIME phase, PULSE TO PULSE -- the carrier phase progression
%        phi_k. Its rate is the Doppler, f_d = (1/2pi)*dphi/dt, and the radar
%        reads range-rate from it as Rdot = -lambda*f_d/2. ADVERSARY-OWNED:
%        this is just a per-pulse phase shift applied on retransmission.
%
%     3. SPATIAL phase, ACROSS THE RECEIVE APERTURES AT ONE INSTANT -- the
%        monopulse phase phi_ant = 2*pi*d*sin(theta)/lambda. NOT ADVERSARY-
%        OWNED, and the reason is that it is NOT IN THE TRANSMITTED SIGNAL AT
%        ALL. It is manufactured at the receiver by the path-length difference
%        between two subapertures. You cannot forge information your signal
%        does not carry.
%
%   THE CANCELLATION, WHICH IS THE WHOLE ANSWER. +generator/render.m builds
%   the two receive channels as
%
%       Sigma = sum_i A_i * exp(i*phi_i) * p(t - tau_i)
%       Delta = Sigma * i*tan(phi_ant/2)
%
%   -- one common scalar, because every phantom left the same aperture. The
%   radar measures angle from the RATIO, so
%
%       Delta/Sigma = i*tan(phi_ant/2)
%
%   and every adversary-controlled term -- every amplitude A_i, every phase
%   phi_i, every delay tau_i, for any number of phantoms -- divides out
%   EXACTLY. Not approximately, not at high SNR: identically. Part A below
%   measures it on real rendered samples rather than asserting the algebra.
%
%   SO THE REACHABLE SET IS A RAY, NOT A VOLUME. One aperture can place a
%   phantom anywhere along the line of bearing it already occupies, between
%   its own range (causality) and R_ua -- one degree of freedom out of three.
%   A real target has three. That asymmetry is this project's central result
%   and it is a statement about geometry, not about signal processing quality.
%
%   HOW TO ACHIEVE A DIFFERENT COORDINATE, then: break the assumption that
%   both channels carry the SAME signal, which needs a SECOND PHASE CENTRE.
%   Two radiators s1, s2 give
%
%       Delta/Sigma = i*[t1 + (s2/s1)*t2] / [1 + (s2/s1)]
%
%   in which the RELATIVE amplitude and phase of s2/s1 no longer cancel. That
%   is cross-eye jamming, and its feasibility against this exact estimator is
%   worked in +experiments/crossEyeSpike.m. It is not a better waveform -- it
%   is a second aperture, i.e. no longer "the same source signal".

    p = inputParser;
    p.addParameter('Seed', 5, @isscalar);
    p.addParameter('SourceAzRad', 0.01, @isscalar);
    p.parse(varargin{:});
    o = p.Results;

    C = physics.Constants();
    SUBSEP = 0.30;                 % render.m's default azimuth baseline [m]
    out = struct();

    % =====================================================================
    % PART A -- the cancellation, measured on real rendered samples
    % =====================================================================
    % Rendered at a noise floor 10 orders below the signal, so what is left is
    % the SIGNAL's own structure. Three phantoms at three ranges with three
    % different amplitudes and three different phase trajectories: if any of
    % them influenced the angle measurement, the ratio would vary across them.
    fprintf('\n=== A. DOES ANY TRANSMITTED PHASE REACH THE ANGLE CHANNEL? ===\n');
    rng(o.Seed, 'twister');
    mA = renderPhantomScene([3600 5200 6800], -50, 'NumFrames', 3, ...
        'SourceAzimuthRad', o.SourceAzRad, 'MotherRangeM', 2000, ...
        'NoiseAmplitude', 1e-12, 'Tag', 'phasectl_A');
    S = load(mA);
    sig = S.rx_frames(:, :, 1);
    dif = S.rx_frames_delta(:, :, 1);
    mask = abs(sig) > 1e-6;
    ratio = dif(mask) ./ sig(mask);
    phiAnt = 2*pi*SUBSEP*sin(o.SourceAzRad)/C.lambda;
    expected = 1i*tan(phiAnt/2);
    azRec = asin(2*atan(imag(mean(ratio))) * C.lambda / (2*pi*SUBSEP));

    fprintf('  %d samples carrying 3 phantoms (3 ranges, 3 amplitudes, 3 phases)\n', nnz(mask));
    fprintf('  Delta/Sigma spread across all of them: %.3e\n', ...
            max(abs(ratio - mean(ratio))));
    fprintf('  mean Delta/Sigma      = %+.15fi\n', imag(mean(ratio)));
    fprintf('  i*tan(phi_ant/2)      = %+.15fi\n', imag(expected));
    fprintf('  recovered azimuth     = %.15f rad\n', azRec);
    fprintf('  true source azimuth   = %.15f rad   (error %.2e)\n', ...
            o.SourceAzRad, abs(azRec - o.SourceAzRad));
    fprintf('  => the ratio is ONE constant set by geometry. Every A_i, phi_i\n');
    fprintf('     and tau_i cancelled identically.\n');
    out.ratio_spread = max(abs(ratio - mean(ratio)));
    out.az_recovered_rad = azRec;
    out.az_error_rad = abs(azRec - o.SourceAzRad);

    % =====================================================================
    % PART B -- the controllability matrix
    % =====================================================================
    % One knob at a time, everything else held. The point is not that each
    % knob works; it is WHICH COLUMN each knob is able to move.
    fprintf('\n=== B. CONTROLLABILITY: which knob moves which coordinate ===\n');
    fprintf('%-34s %10s %12s %14s\n', 'knob', 'range m', 'Rdot m/s', 'azimuth mrad');
    baseAz = o.SourceAzRad;
    rows = struct('label', {}, 'range', {}, 'rate', {}, 'az', {});

    % 1. FAST-TIME delay tau -> range. Adversary-owned.
    for r0 = [3600 5200]
        f = localJudge(o.Seed, r0, -50, 1.0, baseAz);
        rows(end+1) = localRow(sprintf('1. delay tau (R0=%d m)', r0), f); %#ok<AGROW>
    end
    % 2. SLOW-TIME phase progression -> range-rate. Adversary-owned.
    for rate = [-50 20]
        f = localJudge(o.Seed, 3600, rate, 1.0, baseAz);
        rows(end+1) = localRow(sprintf('2. slow-time phase (v=%+d)', rate), f); %#ok<AGROW>
    end
    % 3. Amplitude -> neither. It changes detectability, not position.
    for rcs = [0.3 3.0]
        f = localJudge(o.Seed, 3600, -50, rcs, baseAz);
        rows(end+1) = localRow(sprintf('3. amplitude (rcs=%.1f)', rcs), f); %#ok<AGROW>
    end
    % 4. SPATIAL phase -> azimuth. NOT a signal knob: this is the emitter
    %    physically moving. Included to show the column is reachable AT ALL,
    %    and by what.
    for azv = [0.005 0.020]
        f = localJudge(o.Seed, 3600, -50, 1.0, azv);
        rows(end+1) = localRow(sprintf('4. GEOMETRY (source az=%.3f)', azv), f); %#ok<AGROW>
    end
    for i = 1:numel(rows)
        fprintf('%-34s %10.1f %12.2f %14.4f\n', rows(i).label, rows(i).range, ...
                rows(i).rate, rows(i).az*1e3);
    end
    out.rows = rows;

    azSignalKnobs = [rows(1:6).az];        % rows 1-3: everything the adversary owns
    fprintf('\n  azimuth spread across ALL six adversary-controlled settings: %.4f mrad\n', ...
            (max(azSignalKnobs) - min(azSignalKnobs))*1e3);
    fprintf('  azimuth spread from MOVING THE DRONE 0.015 rad:              %.4f mrad\n', ...
            abs(rows(8).az - rows(7).az)*1e3);
    out.az_spread_signal_rad = max(azSignalKnobs) - min(azSignalKnobs);
    out.az_spread_geometry_rad = abs(rows(8).az - rows(7).az);

    % =====================================================================
    % PART C -- the residual IS noise, and that is falsifiable
    % =====================================================================
    % Part B's six signal settings do not give byte-identical azimuths, and an
    % honest reading has to say why. Two causes, neither of them control:
    % the phantom lands in a different RANGE BIN (so a different sample's
    % noise is read), and the two channels carry INDEPENDENT noise draws.
    %
    % The test that separates "noise" from "weak control": scale the noise. If
    % the variation is receiver noise it shrinks with the noise floor. If the
    % adversary had any authority over the angle it would not.
    fprintf('\n=== C. IS THE RESIDUAL CONTROL, OR NOISE? ===\n');
    fprintf('  same range trajectory, carrier phase NEGATED (the wrong-sign\n');
    fprintf('  convention), so ONLY phase differs -- swept against noise:\n\n');
    fprintf('%14s %16s %16s %14s\n', 'noise amp', 'az normal mrad', 'az negated mrad', '|diff| mrad');
    noiseAmps = [0.05 0.005 5e-4 5e-5];
    dAz = nan(size(noiseAmps));
    for i = 1:numel(noiseAmps)
        [a1, a2] = localPhaseFlipPair(o.Seed, noiseAmps(i), baseAz);
        dAz(i) = abs(a1 - a2);
        fprintf('%14.0e %16.6f %16.6f %14.3e\n', noiseAmps(i), a1*1e3, a2*1e3, dAz(i)*1e3);
    end
    fprintf('\n  noise falls 1000x, |diff| falls %.0fx => the residual is the\n', ...
            dAz(1)/max(dAz(end), eps));
    fprintf('  receiver''s own noise, NOT adversary control over the angle.\n');
    out.noise_amps = noiseAmps;
    out.az_diff_vs_noise = dAz;

    % =====================================================================
    % PART D -- so what IS reachable?
    % =====================================================================
    fprintf('\n=== D. THE REACHABLE COORDINATE SET FROM ONE APERTURE ===\n');
    Rm = 2000;
    rMin = max(Rm, C.blind_range);
    fprintf('  emitter at %.0f m, bearing %.4f rad\n', Rm, o.SourceAzRad);
    fprintf('  range     [%.1f, %.1f] m   -- causality floor to R_ua\n', rMin, C.R_unambiguous);
    fprintf('  azimuth   {%.4f} rad EXACTLY   -- zero freedom\n', o.SourceAzRad);
    fprintf('  elevation {emitter''s} EXACTLY  -- zero freedom\n');
    fprintf('  => a 1-D RAY. One degree of freedom out of three; a real target\n');
    fprintf('     has three. N phantoms are N points on ONE line, which is what\n');
    fprintf('     +track/emitterAttribution.m and the co-bearing screen read.\n');
    fprintf('\n  To reach a different bearing the adversary needs a SECOND PHASE\n');
    fprintf('  CENTRE -- a second drone (a second ray), or cross-eye (two\n');
    fprintf('  apertures, relative phase near 180 deg, which stops the common\n');
    fprintf('  factor being common). See +experiments/crossEyeSpike.m.\n');
    out.reachable_range_m = [rMin, C.R_unambiguous];
    out.reachable_az_rad = o.SourceAzRad;
end


% -------------------------------------------------------------------------
function fb = localJudge(seed, r0, rate, rcs, azRad)
%LOCALJUDGE  One phantom through the real generator and the real judge.
    rng(seed, 'twister');
    m = renderPhantomScene(r0, rate, 'Rcs', rcs, 'NumFrames', 8, ...
        'SourceAzimuthRad', azRad, 'MotherRangeM', 2000, ...
        'Tag', sprintf('phasectl_%d_%d_%d', round(r0), round(rate), round(rcs*10)));
    fb = engine.runJudge(m);
end


function row = localRow(label, fb)
    if fb.confirmed_tracks < 1
        row = struct('label', label, 'range', NaN, 'rate', NaN, 'az', NaN);
        return
    end
    row = struct('label', label, ...
                 'range', mean(fb.track_range_m{1}), ...
                 'rate',  mean(fb.track_range_rate_mps{1}), ...
                 'az',    mean(fb.track_azimuth_rad{1}, 'omitnan'));
end


function [azNormal, azNegated] = localPhaseFlipPair(seed, noiseAmp, azRad)
%LOCALPHASEFLIPPAIR  The same scene rendered twice, differing ONLY in the sign
%   of the carrier phase.
%
%   Isolating phase from range needs this detour, and the detour is itself
%   informative: generator/physics_projection.py DERIVES phase from the range
%   trajectory (Blueprint 2.3), so there is no legitimate path that varies one
%   without the other. Patching the pre-render plan is the only way to build
%   the counterfactual -- the same lever
%   tests/test_generator_math_roundtrip.m uses for its negative control, and
%   for the same reason.
    tag = sprintf('phasectl_flip_%d', round(-log10(noiseAmp)*10));
    rng(seed, 'twister');
    mNormal = renderPhantomScene(3600, -50, 'NumFrames', 8, ...
        'SourceAzimuthRad', azRad, 'MotherRangeM', 2000, ...
        'NoiseAmplitude', noiseAmp, 'Tag', tag);
    azNormal = localFirstAz(engine.runJudge(mNormal));

    planPath = fullfile(tempdir, sprintf('%s_plan.mat', tag));
    P = load(planPath);
    P.phantom_phase_rad = -P.phantom_phase_rad;
    save(planPath, '-struct', 'P');
    judgeNeg = fullfile(tempdir, sprintf('%s_neg_judge.mat', tag));
    rng(seed, 'twister');       % the SAME noise draw, so only phase differs
    generator.render(planPath, judgeNeg, 'IncludeAngleChannel', true, ...
        'SourceAzimuthRad', azRad, 'NoiseAmplitude', noiseAmp);
    azNegated = localFirstAz(engine.runJudge(judgeNeg));
end


function a = localFirstAz(fb)
    if fb.confirmed_tracks < 1; a = NaN; return; end
    a = mean(fb.track_azimuth_rad{1}, 'omitnan');
end
