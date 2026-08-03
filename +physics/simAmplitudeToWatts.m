function powerW = simAmplitudeToWatts(amplitude, varargin)
%SIMAMPLITUDETOWATTS  This simulation's amplitude unit -> received power [W].
%
%   powerW = physics.simAmplitudeToWatts(amplitude)
%
%   Inverse of physics.wattsToSimAmplitude; see physics.simUnits for the one
%   anchor both rest on. Use this to answer "what does amp_scale = 3.0
%   actually claim, in watts?" -- a question this project could not ask
%   before Phase B1.

    U = physics.simUnits(varargin{:});
    powerW = (amplitude.^2) * U.watts_per_sim_power;
end
