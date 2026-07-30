function C = Constants()
%CONSTANTS  Physically-derived constants for the radar-deception simulation.
%
%   C = physics.Constants() returns a struct in which EVERY quantity is
%   either a fundamental physical constant or is DERIVED from one. There are
%   no magic numbers (see CLAUDE.md Rule 1 and POA Part 3). Downstream code
%   (radar, synth, tracker, tests) must pull its numbers from here so the
%   whole project stays internally consistent and physically honest.
%
%   Anchors are taken from the RadChar dataset acquisition parameters:
%       fs = 3.2 MHz, 512 complex samples/record, PRI 17-23 us,
%       SNR -20..+20 dB.
%
%   Key derivations
%   ---------------
%       range_per_sample = c / (2*fs)        % two-way range of one sample
%       range_window     = N * range_per_sample
%       R_unambiguous    = c * PRI / 2
%
%   Example
%       C = physics.Constants();
%       fprintf('%.2f m per range sample\n', C.range_per_sample);

    % --- Fundamental physical constant (SI exact) ---
    C.c = 299792458;            % speed of light [m/s]
                                % (POA quotes the ~3e8 approximation, which
                                %  gives 46.9 m/sample; the exact value gives
                                %  46.84 m/sample -- a 0.07% difference that
                                %  does not change any range-bin conclusion.)

    % --- Acquisition parameters (RadChar dataset) ---
    C.fs        = 3.2e6;        % sampling rate [Hz]
    C.Nsamples  = 512;          % complex samples per record
    C.PRI_min   = 17e-6;        % min pulse repetition interval [s]
    C.PRI_max   = 23e-6;        % max pulse repetition interval [s]
    C.SNR_min_dB = -20;         % dataset SNR floor [dB]
    C.SNR_max_dB =  20;         % dataset SNR ceiling [dB]

    % --- DERIVED quantities (the "honest axes") ---
    C.Ts               = 1 / C.fs;                       % time per sample [s]
    C.range_per_sample = C.c / (2 * C.fs);               % [m/sample]  ~46.84 m
    C.range_window     = C.Nsamples * C.range_per_sample;% [m]         ~23.98 km
    C.Rua_min          = C.c * C.PRI_min / 2;            % [m]         ~2.55 km
    C.Rua_max          = C.c * C.PRI_max / 2;            % [m]         ~3.45 km

    % --- Signal-type integer map (RadChar label convention) ---
    C.signal_types = { ...
        0, 'Coherent pulse train'; ...
        1, 'Barker code'; ...
        2, 'Polyphase Barker code'; ...
        3, 'Frank code'; ...
        4, 'Linear frequency-modulated (LFM)' };
end
