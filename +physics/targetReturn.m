function T = targetReturn(varargin)
%TARGETRETURN  What a GENUINE target actually puts into the receiver.
%
%   T = physics.targetReturn('Name', value, ...)
%
%   Name-value
%       'TransmitPowerW'  1e3    transmit power [W]        (see WHY 1 kW below)
%       'AntennaGainDBi'  30     one-way antenna gain [dBi]
%       'CarrierHz'       10e9   X-band
%       'RcsM2'           1.0    target RCS [m^2]
%       'RangeM'          1800   [m]
%       'BandwidthHz'     2e6    matched-filter bandwidth
%       'PulseWidthS'     12e-6  pulse length
%       'NoiseFigureDB'   3      receiver noise figure
%
%   Returns
%       .received_power_w         Pr = Pt*G^2*lambda^2*sigma/((4pi)^3 R^4)
%       .noise_power_w            N  = k*T0*B*F              (physics.simUnits)
%       .snr_pre_compression_db   Pr/N
%       .compression_gain_db      10*log10(B*T), the time-bandwidth product
%       .snr_at_detector_db       the two summed
%       .sim_amplitude            what that Pr IS, in this simulation's units
%       .wavelength_m, .inputs
%
%   ================= WHY THIS EXISTS (Phase B2) =================
%   cogengine/renderer.py's REFERENCE_RANGE_M comment and
%   cogengine/planner_cem.py's REFERENCE_SINGLE_PHANTOM_AMP_SCALE comment
%   both state plainly that amp_scale has NO link budget behind it: the
%   amplitude scale was anchored so that a validated single-phantom scene
%   came out at amp_scale = 3.0, and everything else is a linear share of
%   that. The 1/R^2 SHAPE was always exact physics; the absolute SCALE was
%   a convention. This function supplies the missing absolute scale, so
%   "is this target detectable" is a question with a real answer.
%
%   COMPRESSION GAIN is the time-bandwidth product B*T, not the number of
%   pulses. B*T = 2e6 * 12e-6 = 24 = 13.80 dB is what MATCHED FILTERING one
%   pulse buys. Coherent integration across the 32-pulse dwell is a further,
%   separate gain and is deliberately NOT folded in here -- +engine/runJudge.m
%   takes a max over Doppler bins rather than a clean coherent sum, which
%   lifts the noise floor it sees too; CLAUDE.md's own ablation measured that
%   combination as ~4.4 dB, not the naive 10*log10(32) = 15 dB. Quoting a
%   number this function cannot honestly derive would be exactly the habit
%   Phase B exists to end.
%
%   ================= THE 30 dB DISCREPANCY, RESOLVED =================
%   Phase B2's brief specified "P_t = 1 kW, G = 30 dB" AND three verification
%   targets (Pr = 4.320e-14 W, SNR pre-comp = 4.32 dB, SNR at detector =
%   18.1 dB). Those two specifications are inconsistent by EXACTLY 30.00 dB:
%   the stated targets reproduce to 0.00 dB at Pt = 1 W and are missed by
%   30.00 dB at the stated Pt = 1 kW. The three targets agree with each
%   other, so transmit power was the single inconsistent quantity. Work
%   stopped there and the conflict was reported rather than resolved by
%   quietly adjusting a target (the brief's own rule).
%
%   RESOLVED IN FAVOUR OF Pt = 1 kW (1 August 2026): the stated radar is
%   authoritative and the three targets were mis-stated. So the verification
%   targets for this function are:
%       Pr = 4.320e-11 W | SNR pre-comp 34.32 dB | B*T 24 = 13.80 dB
%                        | SNR at detector 48.12 dB
%
%   THE CONSEQUENCE IS THE INTERESTING PART, and it is a good-news result.
%   Converting this project's own amplitude anchor (amp_scale = 3.0) into
%   watts and asking what RCS it implies at 1800 m gives sigma = 1.33 m^2 --
%   i.e. the convention that had "no link budget behind it" turns out to have
%   been very nearly right all along, only +1.24 dB hot for a 1 m^2 target.
%   (At the other reading it would have implied sigma = 1331 m^2 and a
%   31.2 dB error running through every published number.) The anchor is
%   vindicated, not overturned.
%
%   tests/test_sim_units.m asserts BOTH readings so the 30 dB question stays
%   visible in the test output rather than becoming folklore.
%
%   Ref: standard monostatic radar range equation; Skolnik.

    p = inputParser;
    addParameter(p, 'TransmitPowerW', 1e3,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'AntennaGainDBi', 30,   @isscalar);
    addParameter(p, 'CarrierHz',      10e9, @(x) isscalar(x) && x > 0);
    addParameter(p, 'RcsM2',          1.0,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'RangeM',         1800, @(x) isscalar(x) && x > 0);
    addParameter(p, 'BandwidthHz',    2e6,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'PulseWidthS',    12e-6,@(x) isscalar(x) && x > 0);
    addParameter(p, 'NoiseFigureDB',  3,    @isscalar);
    parse(p, varargin{:});
    o = p.Results;

    C = physics.Constants();
    lambda = C.c / o.CarrierHz;
    G      = 10^(o.AntennaGainDBi/10);

    % --- two-way monostatic radar equation ---
    Pr = (o.TransmitPowerW * G^2 * lambda^2 * o.RcsM2) / ...
         ((4*pi)^3 * o.RangeM^4);

    U = physics.simUnits('BandwidthHz', o.BandwidthHz, ...
                          'NoiseFigureDB', o.NoiseFigureDB);

    compGain = o.BandwidthHz * o.PulseWidthS;      % time-bandwidth product

    T.wavelength_m           = lambda;
    T.received_power_w       = Pr;
    T.received_power_dbw     = 10*log10(Pr);
    T.noise_power_w          = U.noise_power_w;
    T.snr_pre_compression_db = 10*log10(Pr / U.noise_power_w);
    T.compression_gain       = compGain;
    T.compression_gain_db    = 10*log10(compGain);
    T.snr_at_detector_db     = T.snr_pre_compression_db + T.compression_gain_db;
    T.sim_amplitude          = physics.wattsToSimAmplitude(Pr, ...
                                  'BandwidthHz', o.BandwidthHz, ...
                                  'NoiseFigureDB', o.NoiseFigureDB);
    T.inputs                 = o;
end
