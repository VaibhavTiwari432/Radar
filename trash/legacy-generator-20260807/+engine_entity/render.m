function [cube, obs, cubeDelta] = render(s, varargin)
%RENDER  Emit ALL observables of one entity from THAT ONE STATE (VEE step 2).
%
%   [cube, obs] = engine.entity.render(s, 'Name', value, ...)
%
%       s    : engine.entity.EntityState struct
%       cube : [FastTimeSamples x NumPulses] complex baseband, one dwell
%              (fast time down, slow time across). The slow-time axis is
%              what makes Doppler an INDEPENDENTLY MEASURABLE observable --
%              see "why a cube" below.
%       obs  : the four observables and the state component each one came
%              from, so a caller (or a test) can check provenance instead of
%              trusting it:
%                 .delay_samples    <- s.range_m           (2R/c)
%                 .doppler_hz       <- s.range_rate_mps    (-2*Rdot/lambda)
%                 .amplitude        <- s.rcs_dbsm, s.range_m (sqrt(RCS)/R^2)
%                 .micro_doppler_hz <- s.class             (rate, 0 if n/a)
%                 .swerling_gain    the per-pulse RCS fluctuation actually drawn
%                 .wavelength_m, .provenance
%
%   Name-value (defaults are this project's canonical radar, the same one
%   +engine/runJudge.m matched-filters with: 12 us / 2 MHz / 50 kHz PRF)
%       'NumPulses'        32     pulses per dwell (slow-time length)
%       'FastTimeSamples'  400    receive-window length
%       'PulseWidth'       12e-6  [s]
%       'Bandwidth'        2e6    [Hz]
%       'CarrierHz'        10e9   [Hz]  X-band, cogengine fixtures' own value
%       'PrfHz'            50e3   [Hz]  -> slow-time spacing 1/PRF
%       'AmpScale'         1.0    dimensionless, renderer.py's amp_scale
%       'ReferenceRangeM'  1800   [m]   amplitude-law anchor, renderer.py's
%                                       REFERENCE_RANGE_M (see it for why)
%       'ChirpOverride'    []     use this pulse shape instead of the ideal
%                                 LFM (a feature-matched replica from
%                                 +features/synthesizeTxPulse.m, or a real
%                                 RadChar intercept)
%       'RandStream'       []     RandStream for reproducible Swerling draws
%
%   THE ONE RULE THIS FILE EXISTS TO ENFORCE
%   ----------------------------------------
%   Every observable below is computed from a component of `s` and from
%   nothing else. In particular DOPPLER IS DERIVED FROM s.range_rate_mps,
%   never from a difference of ranges. Before the VEE, both sides of this
%   project computed "Doppler" as diff(range)/dt -- cogengine/radar_twin.py
%   and +engine/runJudge.m both did -- which makes range and Doppler THE
%   SAME MEASUREMENT wearing two hats, and makes
%   +track/discriminator.m's Doppler/range-rate sign screen a tautology that
%   can never fail. Here they are two different functions of two different
%   state components, and tests/test_vee_entity.m asserts it by measurement,
%   not by reading this comment.
%
%   WHY A CUBE, NOT A COLUMN
%   ------------------------
%   A single fast-time column per dwell (what
%   cogengine.matlab_judge.export_scene_for_judge used to export) has no
%   slow-time axis, so there is physically nothing to Doppler-process -- it
%   is the structural reason the judge fell back to diff(range) in the first
%   place. NumPulses columns give radar.rangeDoppler something real to
%   transform.
%
%   MICRO-DOPPLER, AND AN HONEST OBSERVABILITY LIMIT
%   ------------------------------------------------
%   Blade flash is rendered as a shallow amplitude modulation at the
%   blade-passage rate, which puts sidebands at +/- that rate around the
%   entity's own Doppler line -- spectrally what micro-Doppler IS. But at
%   this project's default dwell (32 pulses at 50 kHz PRF = 640 us) the
%   Doppler resolution is PRF/NumPulses = 1562 Hz, while a real drone's
%   blade-passage rate is tens to a few hundred Hz. SO THE DEFAULT DWELL
%   CANNOT SEE IT. It is rendered correctly and is measurable only with a
%   CPI long enough to resolve the rate (NumPulses >= PRF/rate, e.g. >= 512
%   pulses for a 100 Hz rate); tests/test_vee_entity.m verifies it at that
%   length and records the limit rather than claiming an observable the
%   judge can't actually reach.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): this renders a signal. Whether
%   the radar confirms it is decided entirely by +radar/+track.

    C = physics.Constants();

    % Classes physically expected to show rotor/blade micro-Doppler --
    % mirrors cogengine/radar_twin.py's CLASSES_EXPECTING_MICRO. Kept in
    % sync by meaning, not by import (the two sides stay independent).
    CLASSES_EXPECTING_MICRO = {'drone'};

    % MICRO-DOPPLER IS NOW PHASE MODULATION, DERIVED (26 July 2026).
    %
    % It used to be  1 + 0.3*cos(2*pi*f_blade*t)  -- an AMPLITUDE modulation
    % with a tuned depth, carrying a ponytail comment admitting the flash
    % shape was not physically derived. That model is wrong in KIND, not just
    % in its constant: AM by a single tone produces EXACTLY TWO sidebands.
    %
    % The physics: a blade element at radius r on a rotor turning at Omega
    % has radial velocity Omega*r*cos(Omega*t), so the return's PHASE is
    % modulated, phi(t) = (4*pi*r/lambda)*sin(Omega*t). Jacobi-Anger,
    %
    %     exp(i*beta*sin(w t)) = SUM_n J_n(beta) * exp(i*n*w*t),
    %
    % expands that into a COMB at every harmonic of the blade rate, with
    % Bessel amplitudes. The modulation index is
    %
    %     beta = 2*v_tip / (lambda * f_blade)  =  f_d,max / f_blade
    %
    % and the comb's half-width is ~beta lines, i.e. ~2*beta+1 in total.
    %
    % MEASURED, two independent sensors, both from TSMS-Drone
    % (data/TSMS-Drone/README.md, results/tsms_cw_analysis.mat):
    %   * FMCW 24.125 GHz sample: extent 732 Hz / spacing 104 Hz -> beta 7.0,
    %     with 15 lines resolved -- against the 2 an AM model can make.
    %   * CW set, 4 drone types x 15 ranges: beta = extent/spacing = 6.2-10.5.
    %     beta is dimensionless, so it is usable even though that sensor's
    %     carrier is not documented in the files.
    % The corner-reflector control (rigid, no rotor) sits clearly below every
    % drone on line count, sideband power and extent, which is what says the
    % chain is measuring rotors rather than leakage.
    %
    % CONSEQUENCE WORTH KNOWING: beta scales as 1/lambda, so the SAME rotor
    % makes a narrower comb at this project's 10 GHz than at the 24 GHz it was
    % measured on. And once beta passes 2.405, J_0 goes through zero -- the
    % carrier line is SUPPRESSED below its own sidebands. That is real, and it
    % is why tests/test_vee_entity.m no longer asserts "sideband below main".

    p = inputParser;
    addParameter(p, 'NumPulses',        32,    @(x) isscalar(x) && x >= 1);
    addParameter(p, 'FastTimeSamples',  400,   @(x) isscalar(x) && x >= 1);
    addParameter(p, 'PulseWidth',       12e-6, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Bandwidth',        2e6,   @(x) isscalar(x) && x > 0);
    addParameter(p, 'CarrierHz',        10e9,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'PrfHz',            physics.Constants().PRF,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'AmpScale',         1.0,   @(x) isscalar(x) && x > 0);
    addParameter(p, 'ReferenceRangeM',  1800,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'ChirpOverride',    [],    @(x) isempty(x) || isvector(x));
    addParameter(p, 'RandStream',       [],    @(x) isempty(x) || isa(x,'RandStream'));
    % DRFM causality (RADAR_REALISM_AUDIT.md 1.3). Default NaN = no jammer
    % modelled = check does not run, which is what every caller written
    % before this existed gets. Pass JammerRangeM to enforce it.
    addParameter(p, 'JammerRangeM',     NaN,   @(x) isscalar(x));
    addParameter(p, 'DrfmMode',    'repeat',   @(x) ischar(x) || isstring(x));
    addParameter(p, 'RadarIsAgile',  false,    @(x) islogical(x) || isnumeric(x));
    % Monopulse subaperture separation [m]. Default D/2 for a 0.6 m aperture,
    % which at 10 GHz gives a beamwidth lambda/D ~ 2.9 deg and an unambiguous
    % monopulse sector asin(lambda/2d) = +/-2.9 deg -- the two coincide, which
    % is the physically coherent arrangement (monopulse resolves WITHIN a beam).
    addParameter(p, 'SubapertureSepM', 0.30,   @(x) isscalar(x) && x > 0);
    parse(p, varargin{:});
    o = p.Results;

    % A repeater cannot put a phantom closer to the radar than itself. Enforced
    % HERE because this is the single choke point every rendered phantom passes
    % through -- guarding it in each caller would leave the next caller free.
    [causalOk, causalWhy] = engine.entity.checkCausality( ...
        s.range_m, o.JammerRangeM, char(o.DrfmMode), logical(o.RadarIsAgile));
    if ~causalOk
        error('engine:entity:acausalPhantom', '%s', causalWhy);
    end

    nPulses = round(o.NumPulses);
    nFast   = round(o.FastTimeSamples);
    pri     = 1 / o.PrfHz;
    lambda  = C.c / o.CarrierHz;

    % ---------- observable 1: range delay, from s.range_m ONLY ----------
    delaySamples = round((2 * s.range_m / C.c) * C.fs);

    % ---------- observable 2: Doppler, from s.range_rate_mps ONLY -------
    % Two-way Doppler f_d = -(2/lambda)*dR/dt. Sign convention matches
    % cogengine/renderer.py's doppler_hz and +track/discriminator.m: a
    % CLOSING target (dR/dt < 0) gives POSITIVE f_d. This line does not
    % read s.range_m and must never be rewritten to.
    dopplerHz = -2 * s.range_rate_mps / lambda;

    % ---------- observable 3: amplitude, from s.rcs_dbsm and s.range_m --
    % Two-way radar equation in voltage terms: power ~ RCS/R^4, so
    % amplitude ~ sqrt(RCS)/R^2, anchored at ReferenceRangeM exactly as
    % cogengine/renderer.py's amplitude_law does (see its comment for why
    % the anchor exists at all).
    rcsLinear = 10^(s.rcs_dbsm / 10);
    amplitude = o.AmpScale * sqrt(rcsLinear) * (o.ReferenceRangeM / s.range_m)^2;

    % ---------- observable 4: micro-Doppler, from s.class ---------------
    % A class not expected to show blade flash gets NONE, whatever the state
    % field says. A drone with micro_doppler_hz == 0 gets none either -- and
    % that absence is itself the giveaway the ECCM screens for, so it is
    % rendered honestly rather than quietly faked.
    if ismember(s.class, CLASSES_EXPECTING_MICRO)
        microHz = s.micro_doppler_hz;
    else
        microHz = 0;
    end
    % Older EntityStates (and anything hand-built as a bare struct) predate
    % blade_tip_mps. Fall back to the measured default rather than to 0 --
    % a 0 would silently mean beta = 0, i.e. no micro-Doppler at all, which
    % is a quieter and worse failure than using a documented measurement.
    if isfield(s, 'blade_tip_mps')
        bladeTipMps = s.blade_tip_mps;
    else
        bladeTipMps = 4.55;
    end

    % ---------- assemble ----------
    if isempty(o.ChirpOverride)
        % Same definition as cogengine/renderer.py's lfm_chirp: phase 0 AT
        % t=0, NOT centred on the pulse. That is not cosmetic -- a centred
        % version is a different waveform from phased.LinearFMWaveform's and
        % correlates against the judge's own matched filter with a spurious
        % T/2 delay bias (renderer.py documents finding this the hard way).
        n = round(o.PulseWidth * C.fs);
        assert(n >= 1, 'engine:entity:shortPulse', 'PulseWidth*fs must be >= 1 sample');
        t = (0:n-1)' / C.fs;
        k = o.Bandwidth / o.PulseWidth;
        chirp = exp(1i * pi * k * t.^2);
    else
        chirp = o.ChirpOverride(:);
    end

    assert(numel(chirp) <= nFast, 'engine:entity:windowTooShort', ...
        'FastTimeSamples=%d cannot hold a %d-sample pulse', nFast, numel(chirp));
    assert(delaySamples >= 0 && delaySamples + numel(chirp) <= nFast, ...
        'engine:entity:rangeOutOfWindow', ...
        ['range_m=%.1f places its two-way delay at sample %d, outside the ' ...
         '%d-sample receive window'], s.range_m, delaySamples, nFast);

    slowT = (0:nPulses-1)' * pri;                      % slow-time axis [s]

    dopplerPhasor = exp(1i * 2*pi * dopplerHz * slowT);
    if microHz > 0
        % Bessel comb via Jacobi-Anger -- see the derivation in the header.
        % beta is computed from lambda, so the comb automatically narrows at a
        % longer wavelength instead of being a band-independent constant.
        microBeta = 2 * bladeTipMps / (lambda * microHz);
        microPhasor = exp(1i * microBeta * sin(2*pi * microHz * slowT));
    else
        microBeta = 0;
        microPhasor = ones(nPulses, 1);
    end
    swerlGain = localSwerlingGain(s.swerling, nPulses, o.RandStream);

    perPulse = amplitude * swerlGain .* dopplerPhasor .* microPhasor;   % [nPulses x 1]

    % ---------- observable 5: AZIMUTH, from s.azimuth_rad ONLY ----------
    % PHASE-COMPARISON MONOPULSE. Two subapertures separated by d see the same
    % echo with an electrical phase difference
    %       phi = 2*pi*d*sin(theta)/lambda
    % so the sum and difference channels carry
    %       Sigma ~ cos(phi/2),   Delta ~ 1i*sin(phi/2)
    % and therefore  Delta/Sigma = 1i*tan(phi/2), from which the judge recovers
    % theta. Note what is NOT here: no empirical "monopulse slope" constant.
    % The angle scale factor falls out of d and lambda, both physical -- the
    % textbook k_m ~ 1.6 for an amplitude-comparison feed would have been a
    % fitted number this project could not derive.
    %
    % UNAMBIGUOUS SECTOR: |sin(theta)| < lambda/(2d). At the default d=0.30 m
    % and 10 GHz that is +/-2.87 deg, essentially the beamwidth -- monopulse
    % resolves within a beam, it does not replace scanning.
    %
    % WHY THIS IS THE ANTI-DRFM OBSERVABLE: a repeater transmits from ONE
    % place, so every phantom it creates arrives on the jammer's bearing no
    % matter what range it claims. Range, Doppler and amplitude can all be
    % forged independently per phantom; azimuth cannot, because it is set by
    % where the transmitter physically is.
    if isfield(s, 'azimuth_rad'); azimuth = s.azimuth_rad; else; azimuth = 0; end
    phi = 2*pi * o.SubapertureSepM * sin(azimuth) / lambda;

    cube      = complex(zeros(nFast, nPulses));
    cubeDelta = complex(zeros(nFast, nPulses));
    rows = delaySamples + (1:numel(chirp));
    cube(rows, :)      = chirp * (cos(phi/2)      * perPulse).';
    cubeDelta(rows, :) = chirp * (1i*sin(phi/2)   * perPulse).';

    obs = struct( ...
        'delay_samples',    delaySamples, ...
        'doppler_hz',       dopplerHz, ...
        'amplitude',        amplitude, ...
        'micro_doppler_hz', microHz, ...
        'micro_beta',       microBeta, ...
        'blade_tip_mps',    bladeTipMps, ...
        'azimuth_rad',      azimuth, ...
        'monopulse_phi',    phi, ...
        'subaperture_sep_m', o.SubapertureSepM, ...
        'unambiguous_az_rad', asin(min(1, lambda/(2*o.SubapertureSepM))), ...
        'swerling_gain',    swerlGain, ...
        'wavelength_m',     lambda, ...
        'pri_s',            pri, ...
        'provenance', struct( ...
            'delay_samples',    'range_m', ...
            'doppler_hz',       'range_rate_mps', ...
            'amplitude',        'rcs_dbsm+range_m', ...
            'micro_doppler_hz', 'class+micro_doppler_hz', ...
            'azimuth_rad',      'azimuth_rad'));
end

% ===================== file-local helpers =============================
function g = localSwerlingGain(swerling, nPulses, rs)
%LOCALSWERLINGGAIN  Per-pulse RCS-fluctuation AMPLITUDE multiplier,
%   normalised so E[g^2] == 1 (it supplies fluctuation only, never absolute
%   scale). Same model as cogengine/renderer.py's
%   swerling_amplitude_samples, implemented independently here:
%     0    non-fluctuating
%     1/2  many small scatterers  -> RCS ~ chi-square, 2 dof
%     3/4  one dominant + small   -> RCS ~ chi-square, 4 dof
%     odd  (1,3) correlated across the dwell (one draw, scan-to-scan)
%     even (2,4) decorrelated pulse-to-pulse (one draw per pulse)
    if swerling == 0
        g = ones(nPulses, 1);
        return;
    end
    dof = 2 + 2*any(swerling == [3 4]);
    nDraws = nPulses * any(swerling == [2 4]) + 1 * any(swerling == [1 3]);

    % chi-square with `dof` dof == sum of dof squared standard normals.
    if isempty(rs)
        z = randn(nDraws, dof);
    else
        z = randn(rs, nDraws, dof);
    end
    powerDraws = sum(z.^2, 2) / dof;                 % E[powerDraws] == 1
    if nDraws == 1
        powerDraws = repmat(powerDraws, nPulses, 1);
    end
    g = sqrt(powerDraws);
end
