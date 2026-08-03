function U = simUnits(varargin)
%SIMUNITS  The ONE place where this simulation's amplitude units meet watts.
%
%   U = physics.simUnits('Name', value, ...)
%
%   Name-value (defaults are this project's own established operating point)
%       'BandwidthHz'   2e6   matched-filter / receiver noise bandwidth
%       'NoiseFigureDB' 3     receiver noise figure
%       'NoiseAmplitude' 0.05 THE simulation's noise convention (see below)
%
%   Returns
%       .noise_power_w        N = k*T0*B*F   [W]      -- the derived floor
%       .noise_power_dbw
%       .noise_amplitude      the simulation-side convention it anchors to
%       .noise_power_sim      that convention's power, = noise_amplitude^2
%       .watts_per_sim_power  the single conversion factor
%       .inputs
%
%   ================= WHY THIS EXISTS (Phase B1) =================
%   +physics/linkBudget.m derives a real thermal floor and then says, in its
%   own header, that it deliberately does NOT convert the simulation to
%   physical units -- with the consequence stated just as plainly: "SNR in
%   this project has no absolute meaning, and neither does any detection
%   range." That is the calibration gap this function closes.
%
%   Everywhere in this repo, receiver noise is generated as
%
%       noise = noise_amplitude * (randn + 1i*randn) / sqrt(2)
%
%   (cogengine/radar_twin.py, cogengine/matlab_judge.py, +agent/buildEnv*.m,
%   every test). That draw has complex variance exactly noise_amplitude^2, so
%   the simulation's noise POWER is noise_amplitude^2 = 0.0025 in whatever
%   dimensionless unit the rest of the sim works in. Setting that equal to
%   the derived thermal floor N fixes the unit system completely:
%
%       watts_per_sim_power = N / noise_amplitude^2
%
%   and nothing else needs to know. An SNR in sim units and an SNR in watts
%   are then THE SAME NUMBER, because both are ratios and the scale factor
%   cancels -- which is the point. The calibration does not move any existing
%   result; it makes existing results MEAN something absolute.
%
%   NOT a conversion of the simulation to SI. Every buffer in this repo still
%   carries sim-unit amplitudes; re-scaling them would move every published
%   number for no physical gain (linkBudget.m's own argument, unchanged).
%   This function is the dictionary between the two, used by
%   physics.wattsToSimAmplitude / physics.simAmplitudeToWatts.
%
%   VERIFIED: N = 1.5978e-14 W = -137.965 dBW at B = 2 MHz, F = 3 dB
%   (tests/test_link_budget.m, tests/test_sim_units.m).

    p = inputParser;
    addParameter(p, 'BandwidthHz',    2e6,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'NoiseFigureDB',  3,    @isscalar);
    % 0.05 is the simulation's own long-standing convention, NOT a derived
    % number -- it is the thing being CALIBRATED, so it is an input here, not
    % an output. Before this function it had no thermal derivation anywhere
    % (a repo-wide grep for kTB/boltzmann/thermal returned nothing).
    addParameter(p, 'NoiseAmplitude', 0.05, @(x) isscalar(x) && x > 0);
    parse(p, varargin{:});
    o = p.Results;

    C = physics.Constants();
    F = 10^(o.NoiseFigureDB/10);

    U.noise_power_w       = C.k_boltzmann * C.T0_kelvin * o.BandwidthHz * F;
    U.noise_power_dbw     = 10*log10(U.noise_power_w);
    U.noise_amplitude     = o.NoiseAmplitude;
    U.noise_power_sim     = o.NoiseAmplitude^2;
    U.watts_per_sim_power = U.noise_power_w / U.noise_power_sim;
    U.inputs              = o;
end
