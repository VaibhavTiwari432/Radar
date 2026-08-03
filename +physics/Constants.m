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

    C.k_boltzmann = 1.380649e-23;   % [J/K] SI exact since the 2019 redefinition
    C.T0_kelvin   = 290;            % [K] IEEE standard noise reference temperature.
                                    % NOT room temperature -- the convention that
                                    % makes a stated noise figure mean something.
                                    % Both were locals inside +physics/linkBudget.m
                                    % until Phase B1; the noise floor is now a
                                    % project-wide fact, not one function's detail.

    % --- Acquisition parameters (RadChar dataset) ---
    C.fs        = 3.2e6;        % sampling rate [Hz]
    C.Nsamples  = 512;          % complex samples per record
    C.PRI_min   = 17e-6;        % min pulse repetition interval [s]
    C.PRI_max   = 23e-6;        % max pulse repetition interval [s]
    C.SNR_min_dB = -20;         % dataset SNR floor [dB]
    C.SNR_max_dB =  20;         % dataset SNR ceiling [dB]

    % =====================================================================
    % THIS RADAR'S OWN WAVEFORM (Phase 4.1 -- previously nowhere)
    % =====================================================================
    % These describe the radar THIS PROJECT SIMULATES. They are NOT the
    % RadChar acquisition parameters above: RadChar's PRI_min/PRI_max are
    % properties of the EMITTERS IN THE DATASET, and conflating the two is
    % part of how the inconsistency below survived so long.
    %
    % ------------- WHY THE PRF IS 8 kHz AND NOT 50 kHz -------------------
    % Until Phase 4 there was NO declared PRF anywhere in this file. The
    % value 50e3 was re-typed as a literal in ~20 files, and it was not
    % self-consistent with the 400-sample listening window those same files
    % use. Three independent checks, all favouring 8 kHz:
    %
    %   (a) samples per PRI at fs = 3.2 MHz
    %         50 kHz -> 64 samples   -- does NOT match the 400-sample window
    %          8 kHz -> 400 samples  -- MATCHES exactly
    %   (b) duty cycle at the 12 us pulse in use
    %         50 kHz -> 60.0%        -- not a pulsed radar; that is nearly CW
    %          8 kHz ->  9.6%        -- plausible solid-state
    %   (c) unambiguous range c*PRI/2
    %         50 kHz -> 2997.9 m     -- 6.25x SHORTER than the window listened to
    %          8 kHz -> 18737.0 m    -- EQUAL to the 400-sample window span,
    %                                    which is the same identity seen twice
    %
    % The cost is real and is not hidden: at 8 kHz the unambiguous VELOCITY
    % falls from +-375 m/s to +-60 m/s. That is the range-Doppler ambiguity
    % trade being paid honestly for the first time -- the project had been
    % taking 50 kHz's velocity coverage AND the 400-sample window's range
    % coverage simultaneously, which no single radar can do.
    % See PHASE4_RESULTS.md Phase 1 and tests/test_prf_consistency.m.
    C.PRF         = 8e3;         % pulse repetition frequency [Hz]
    C.pulse_width = 12e-6;       % transmitted pulse length [s]
    C.bandwidth   = 2e6;         % LFM sweep bandwidth [Hz]
    C.carrier     = 10e9;        % X-band carrier [Hz]
    C.fast_time_samples = 400;   % receive-window length [samples]

    % --- DERIVED quantities (the "honest axes") ---
    C.Ts               = 1 / C.fs;                       % time per sample [s]
    C.range_per_sample = C.c / (2 * C.fs);               % [m/sample]  ~46.84 m
    C.range_window     = C.Nsamples * C.range_per_sample;% [m]         ~23.98 km
    C.Rua_min          = C.c * C.PRI_min / 2;            % [m]         ~2.55 km
    C.Rua_max          = C.c * C.PRI_max / 2;            % [m]         ~3.45 km

    % --- DERIVED from THIS radar's waveform (Phase 4.1) ---
    C.PRI              = 1 / C.PRF;                      % [s]         125 us
    C.pri_samples      = C.fs / C.PRF;                   % [samples]   400
    C.duty_cycle       = C.pulse_width * C.PRF;          % [-]         0.096
    C.lambda           = C.c / C.carrier;                % [m]         0.03
    C.R_unambiguous    = C.c / (2 * C.PRF);              % [m]         18737 m
    C.v_unambiguous    = C.lambda * C.PRF / 4;           % [m/s]       +-60 m/s
    C.blind_range      = C.c * C.pulse_width / 2;        % [m]         1798.8 m
                                                         % pulse eclipsing: the
                                                         % receiver is deaf while
                                                         % transmitting. PRF-
                                                         % independent.

    % --- Signal-type integer map (RadChar label convention) ---
    C.signal_types = { ...
        0, 'Coherent pulse train'; ...
        1, 'Barker code'; ...
        2, 'Polyphase Barker code'; ...
        3, 'Frank code'; ...
        4, 'Linear frequency-modulated (LFM)' };
end
