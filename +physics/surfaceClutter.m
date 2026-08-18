function S = surfaceClutter(varargin)
%SURFACECLUTTER  Ground return per range cell, from the area radar equation.
%
%   S = physics.surfaceClutter('RangesM', r, ...)
%
%   Name-value (defaults are this project's own operating point, matching
%   +physics/linkBudget.m so the two cannot drift):
%       'RangesM'         range of each cell [m], vector -- REQUIRED
%       'GammaDB'        -15    terrain constant-gamma coefficient [CITED]
%       'RadarHeightM'    10     antenna height above the surface [m]
%       'TransmitPowerW'  60
%       'AntennaGainDBi'  30
%       'CarrierHz'       10e9
%       'BandwidthHz'     2e6
%       'NoiseFigureDB'   3
%       'NoiseAmplitude'  0.05   the simulation's noise convention
%       'SystemLossDB'    0
%
%   Returns
%       .grazing_rad        asin(h/R), the depression onto a flat surface
%       .sigma0             DERIVED: gamma*sin(psi), the constant-gamma model
%       .cell_area_m2       R*theta_az*deltaR*sec(psi)
%       .clutter_rcs_m2     sigma0 * cell_area
%       .clutter_power_w    the area radar equation, per cell
%       .cnr_db             clutter-to-noise ratio per cell
%       .sim_amplitude      per-RAW-SAMPLE amplitude in this project's units
%       .beamwidth_rad, .range_resolution_m, .inputs
%
%   ================= WHY THIS EXISTS =================
%   This project has never had a clutter model. A grep for clutter across
%   +radar/, +engine/, +track/ and +generator/ returns one COMMENT and no
%   code. Every detection number in the repo is therefore a thermal-noise-only
%   number -- which for a counter-UAS problem is the wrong limit entirely,
%   because detecting a small slow low-flying target in ground return IS the
%   problem. A judge that finds a 0.01 m^2 drone at 2000 m in thermal noise is
%   not modelling the hard part.
%
%   ================= EVERY NUMBER IS DERIVED EXCEPT ONE =================
%   The area radar equation for distributed surface return is
%
%       Pc = Pt*G^2*lambda^2*sigma0*Ac / ((4pi)^3 * R^4 * L)
%
%   which is the SAME equation as +physics/linkBudget.m's point-target form
%   with sigma replaced by sigma0*Ac. The clutter patch the radar competes
%   with in one range cell is
%
%       Ac = R * theta_az * deltaR * sec(psi)
%
%   THE RANGE EXPONENT DEPENDS ON WHICH sigma0 MODEL IS USED, and the two
%   standard answers differ. With sigma0 held CONSTANT the patch growth wins
%   and Pc falls as 1/R^3, which is the exponent usually quoted. Under the
%   CONSTANT-GAMMA model used here sigma0 = gamma*sin(psi) = gamma*h/R itself
%   falls as 1/R on a flat earth, which exactly cancels the patch growth:
%
%       sigma0 * Ac = constant   =>   Pc ~ 1/R^4
%
%   So the clutter RCS a target competes with is the SAME at every range, and
%   the signal-to-clutter ratio is FLAT -- both target and clutter fall as
%   1/R^4 together. That is a sharper statement than "clutter grows with
%   range" and it is the one this model actually makes. (An earlier version of
%   this header asserted 1/R^3 while the code computed 1/R^4; the test suite
%   caught the contradiction.)
%
%   theta_az is DERIVED from the antenna gain, not typed in: a pencil beam has
%   G ~ 4*pi/(theta_az*theta_el), and taking a symmetric beam gives
%   theta = sqrt(4*pi/G) = 0.1121 rad = 6.42 deg at this project's 30 dBi.
%   That agrees with the lambda/D beamwidth of the 0.30 m aperture the
%   monopulse baseline assumes, which is a genuine cross-check rather than a
%   coincidence.
%
%   deltaR is the RANGE RESOLUTION c/(2B) = 74.96 m, NOT the sample spacing
%   c/(2*fs) = 46.84 m. Clutter competes over a resolution cell; the sampling
%   grid is finer than the resolution here, which is a property of this
%   project's own operating point worth stating rather than tripping over.
%
%   THE ONE CITED NUMBER IS GAMMA. sigma0 is not a constant of nature -- it
%   depends on terrain, frequency, polarisation and grazing angle. The
%   constant-gamma model sigma0 = gamma*sin(psi) is the standard low-grazing
%   approximation, and gamma = -15 dB is the conventional value for rural
%   terrain at X-band (Nathanson's land-clutter tables; Ulaby's handbook gives
%   the same order). It is exposed as a parameter precisely because it is the
%   assumption, and every result that depends on it must say so.
%
%   ================= WHAT THIS DOES NOT MODEL =================
%   Deliberately, and each omission makes the clutter EASIER than reality:
%     * Amplitude statistics are Rayleigh (complex Gaussian scatterer field).
%       Real high-resolution, low-grazing land clutter is heavier-tailed
%       (Weibull / K-distribution), which produces more CFAR false alarms than
%       this model will.
%     * No spatial texture -- no discretes, no shadowing, no terrain relief.
%     * No sea clutter, no rain, no chaff.
%     * The internal-motion Doppler spread is applied as a bulk figure rather
%       than a spectrum. See +generator/render.m for how the zero-Doppler
%       concentration is realised.
%
%   Ref: Skolnik, Radar Handbook, ch. on surface clutter; Nathanson, Radar
%   Design Principles, land-clutter tables.

    p = inputParser;
    addParameter(p, 'RangesM',        [],    @(x) isnumeric(x) && ~isempty(x));
    addParameter(p, 'GammaDB',        -15,   @isscalar);
    addParameter(p, 'RadarHeightM',   10,    @(x) isscalar(x) && x > 0);
    addParameter(p, 'TransmitPowerW', 60,    @(x) isscalar(x) && x > 0);
    addParameter(p, 'AntennaGainDBi', 30,    @isscalar);
    addParameter(p, 'CarrierHz',      10e9,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'BandwidthHz',    2e6,   @(x) isscalar(x) && x > 0);
    addParameter(p, 'NoiseFigureDB',  3,     @isscalar);
    addParameter(p, 'NoiseAmplitude', 0.05,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'SystemLossDB',   0,     @isscalar);
    parse(p, varargin{:});
    o = p.Results;
    assert(~isempty(o.RangesM), 'physics:surfaceClutter:noRanges', ...
        'RangesM is required -- clutter is a per-range-cell quantity');

    C = physics.Constants();
    R = double(o.RangesM(:))';
    lambda = C.c / o.CarrierHz;
    G      = 10^(o.AntennaGainDBi/10);
    Lsys   = 10^(o.SystemLossDB/10);
    gamma  = 10^(o.GammaDB/10);

    % Beamwidth from gain, symmetric pencil beam: G = 4*pi/(th_az*th_el).
    thetaAz = sqrt(4*pi / G);
    % Range RESOLUTION, not sample spacing -- see the header.
    deltaR = C.c / (2 * o.BandwidthHz);

    % Grazing onto a flat surface. Clipped at the horizon-free case: a cell
    % nearer than the antenna height is not a surface-clutter geometry at all.
    sinPsi = min(1, o.RadarHeightM ./ max(R, o.RadarHeightM));
    psi = asin(sinPsi);

    % CONSTANT-GAMMA. The one cited assumption in this file.
    sigma0 = gamma * sinPsi;

    % The patch competing with a target in one range cell.
    Ac = R .* thetaAz .* deltaR ./ cos(psi);      % sec(psi) = 1/cos(psi)

    clutterRcs = sigma0 .* Ac;
    Pc = (o.TransmitPowerW * G^2 * lambda^2 .* clutterRcs) ./ ...
         ((4*pi)^3 .* R.^4 .* Lsys);

    U = physics.simUnits('BandwidthHz', o.BandwidthHz, ...
                          'NoiseFigureDB', o.NoiseFigureDB, ...
                          'NoiseAmplitude', o.NoiseAmplitude);
    N = U.noise_power_w;

    % PER-RAW-SAMPLE amplitude, which is what +generator/render.m adds to
    % rx_frames. The judge pulse-compresses afterwards, and a white-in-range
    % scatterer field picks up exactly the same matched-filter gain E_p as the
    % target echoes and the thermal noise do -- so the compressed
    % clutter-to-noise ratio is just (c/noise_amplitude)^2 and the gain
    % cancels. That is why this returns a raw amplitude and not a compressed
    % one: adding it post-compression would double-count the gain.
    cnr = Pc ./ N;
    simAmp = o.NoiseAmplitude .* sqrt(cnr);

    S = struct( ...
        'ranges_m',           R, ...
        'grazing_rad',        psi, ...
        'sigma0',             sigma0, ...
        'sigma0_db',          10*log10(max(sigma0, realmin)), ...
        'cell_area_m2',       Ac, ...
        'clutter_rcs_m2',     clutterRcs, ...
        'clutter_power_w',    Pc, ...
        'cnr_db',             10*log10(max(cnr, realmin)), ...
        'sim_amplitude',      simAmp, ...
        'beamwidth_rad',      thetaAz, ...
        'range_resolution_m', deltaR, ...
        'noise_power_w',      N, ...
        'inputs',             o);
end
