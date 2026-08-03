function a = wattsToSimAmplitude(powerW, varargin)
%WATTSTOSIMAMPLITUDE  Received power [W] -> this simulation's amplitude unit.
%
%   a = physics.wattsToSimAmplitude(powerW)
%   a = physics.wattsToSimAmplitude(powerW, 'BandwidthHz', ..., ...)
%       (extra arguments are forwarded to physics.simUnits)
%
%   Amplitude is a VOLTAGE-like quantity and power goes as its square, so
%   this is sqrt(P / watts_per_sim_power) -- the same 1/R^2-amplitude /
%   1/R^4-power convention +track/discriminator.m and cogengine/renderer.py
%   already screen for (CLAUDE.md Rule 1's amplitude-law row).
%
%   Sanity anchor, by construction: a target arriving at exactly the thermal
%   noise floor converts to the simulation's own noise amplitude, 0.05.

    U = physics.simUnits(varargin{:});
    a = sqrt(powerW / U.watts_per_sim_power);
end
