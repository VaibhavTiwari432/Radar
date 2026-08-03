function L = linkBudget(varargin)
%LINKBUDGET  The real radar equation and a real thermal-noise floor.
%
%   L = physics.linkBudget('Name', value, ...)
%
%   Name-value (defaults are THIS project's own established numbers)
%       'TransmitPowerW'  60      average power [W] -- the GaN budget in
%                                 cogengine/planner_cem.py
%       'AntennaGainDBi'  30      one-way antenna gain [dBi]
%       'CarrierHz'       10e9    X-band, every cogengine fixture's value
%       'RcsM2'           1.0     target radar cross-section [m^2]
%       'RangeM'          1800    REFERENCE_RANGE_M (cogengine/renderer.py)
%       'BandwidthHz'     2e6     matched-filter bandwidth
%       'NoiseFigureDB'   3       receiver noise figure
%       'SystemLossDB'    0       everything else (scan, beam-shape, radome)
%       'NumPulses'       32      coherent integration length per dwell
%
%   Returns (all SI, plus dB conveniences)
%       .noise_power_w        N = k*T0*B*F
%       .received_power_w     Pr = Pt*G^2*lambda^2*sigma / ((4pi)^3 * R^4 * L)
%       .snr_single_pulse_db
%       .snr_integrated_db    + 10*log10(NumPulses)
%       .detection_range_m    range at which integrated SNR hits SnrThresholdDB
%       .wavelength_m, .inputs
%
%   ================= WHY THIS EXISTS =================
%   This project has never had a noise model. `noise_amplitude = 0.05`
%   (cogengine/radar_twin.py, +agent/buildEnv.m, every test) is a bare
%   convention with no thermal-noise derivation behind it -- a grep for
%   noiseFigure/boltzmann/kTB/thermal across the repo returns NOTHING. That
%   makes it the largest outstanding violation of CLAUDE.md Rule 1 ("no magic
%   numbers"), and unlike the amplitude anchor -- which
%   cogengine/renderer.py's REFERENCE_RANGE_M comment documents honestly --
%   it was not flagged anywhere. Consequence: SNR in this project has no
%   absolute meaning, and neither does any detection range.
%
%   ================= WHAT THIS DOES *NOT* DO =================
%   It does NOT convert the simulation to physical units. Doing that would
%   move every number in CLAUDE.md again, for a second time in one day. This
%   is a REPORTING and SANITY-CHECK layer: it answers "is the geometry this
%   project has been using physically sensible, and what SNR does it actually
%   imply?" -- and the answer turns out to be yes, which is worth knowing.
%   Converting `amp_scale` into watts for real is the follow-on job.
%
%   Ref: standard monostatic radar range equation; Skolnik.

    p = inputParser;
    addParameter(p, 'TransmitPowerW', 60,   @(x) isscalar(x) && x > 0);
    addParameter(p, 'AntennaGainDBi', 30,   @isscalar);
    addParameter(p, 'CarrierHz',      10e9, @(x) isscalar(x) && x > 0);
    addParameter(p, 'RcsM2',          1.0,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'RangeM',         1800, @(x) isscalar(x) && x > 0);
    addParameter(p, 'BandwidthHz',    2e6,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'NoiseFigureDB',  3,    @isscalar);
    addParameter(p, 'SystemLossDB',   0,    @isscalar);
    addParameter(p, 'NumPulses',      32,   @(x) isscalar(x) && x >= 1);
    addParameter(p, 'SnrThresholdDB', 13,   @isscalar);   % ~Pd 0.9 / Pfa 1e-4, Swerling 0
    parse(p, varargin{:});
    o = p.Results;

    C = physics.Constants();

    % --- fundamental constants (SI exact / defined) ---
    % Phase B1: these were locals here. They now live in physics.Constants()
    % because the thermal floor is a project-wide fact -- physics.simUnits()
    % needs the same two numbers to anchor the simulation's amplitude units.
    BOLTZMANN   = C.k_boltzmann;
    T0_KELVIN   = C.T0_kelvin;

    lambda = C.c / o.CarrierHz;
    G      = 10^(o.AntennaGainDBi/10);
    F      = 10^(o.NoiseFigureDB/10);
    Lsys   = 10^(o.SystemLossDB/10);

    % --- thermal noise floor: N = k*T0*B*F ---
    N = BOLTZMANN * T0_KELVIN * o.BandwidthHz * F;

    % --- two-way radar equation ---
    Pr = (o.TransmitPowerW * G^2 * lambda^2 * o.RcsM2) / ...
         ((4*pi)^3 * o.RangeM^4 * Lsys);

    snr1  = Pr / N;
    snrN  = snr1 * o.NumPulses;          % coherent integration: SNR ~ N

    % --- detection range: solve snrN(R) = threshold for R (Pr ~ 1/R^4) ---
    thr = 10^(o.SnrThresholdDB/10);
    Rdet = o.RangeM * (snrN / thr)^(1/4);

    L.wavelength_m         = lambda;
    L.noise_power_w        = N;
    L.noise_power_dbw      = 10*log10(N);
    L.received_power_w     = Pr;
    L.received_power_dbw   = 10*log10(Pr);
    L.snr_single_pulse_db  = 10*log10(snr1);
    L.snr_integrated_db    = 10*log10(snrN);
    L.detection_range_m    = Rdet;
    L.inputs               = o;
end
