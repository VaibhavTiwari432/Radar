"""Physically-derived constants for the generator rebuild.

Mirrors +physics/Constants.m exactly -- this is Rule 1 shared physics (CLAUDE.md):
c, fs, PRI etc. are facts about the simulated radar, not model parameters either
side of the judge/generator split gets to choose independently. If a number here
ever disagrees with +physics/Constants.m, that file is the one that's right.

Anchors are the RadChar dataset acquisition parameters (fs=3.2MHz, 512 samples,
PRI 17-23us) and this project's own declared radar waveform (PRF=8kHz -- NOT
50kHz; see +physics/Constants.m's own header for the three independent checks
that fixed this in Phase 4, most importantly that 50kHz gives 64 samples/PRI
against a 400-sample listening window while 8kHz gives exactly 400).
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Constants:
    # --- Fundamental physical constants (SI exact) ---
    c: float = 299_792_458.0            # speed of light [m/s]
    k_boltzmann: float = 1.380649e-23   # [J/K]
    T0_kelvin: float = 290.0            # [K] IEEE noise reference temperature

    # --- Acquisition parameters (RadChar dataset) ---
    fs: float = 3.2e6           # sampling rate [Hz]
    Nsamples: int = 512         # complex samples per record
    PRI_min: float = 17e-6      # [s]
    PRI_max: float = 23e-6      # [s]
    SNR_min_dB: float = -20.0
    SNR_max_dB: float = 20.0

    # --- This radar's own waveform (+physics/Constants.m Phase 4.1) ---
    PRF: float = 8e3             # pulse repetition frequency [Hz]
    pulse_width: float = 12e-6   # transmitted pulse length [s]
    bandwidth: float = 2e6       # LFM sweep bandwidth [Hz]
    carrier: float = 10e9        # X-band carrier [Hz]
    fast_time_samples: int = 400  # receive-window length [samples]

    @property
    def Ts(self) -> float:
        return 1.0 / self.fs

    @property
    def range_per_sample(self) -> float:
        """[m/sample] two-way range of one fast-time sample, ~46.84 m."""
        return self.c / (2.0 * self.fs)

    @property
    def range_window(self) -> float:
        """[m] ~23.98 km."""
        return self.Nsamples * self.range_per_sample

    @property
    def Rua_min(self) -> float:
        return self.c * self.PRI_min / 2.0

    @property
    def Rua_max(self) -> float:
        return self.c * self.PRI_max / 2.0

    @property
    def PRI(self) -> float:
        """[s] 125 us, derived from this radar's own PRF (not the dataset PRI)."""
        return 1.0 / self.PRF

    @property
    def pri_samples(self) -> float:
        return self.fs / self.PRF

    @property
    def duty_cycle(self) -> float:
        return self.pulse_width * self.PRF

    @property
    def lambda_m(self) -> float:
        """[m] carrier wavelength, ~0.03 m."""
        return self.c / self.carrier

    @property
    def R_unambiguous(self) -> float:
        """[m] ~18737 m, c/(2*PRF)."""
        return self.c / (2.0 * self.PRF)

    @property
    def v_unambiguous(self) -> float:
        """[m/s] +-60 m/s, lambda*PRF/4."""
        return self.lambda_m * self.PRF / 4.0

    @property
    def blind_range(self) -> float:
        """[m] ~1798.8 m, pulse eclipsing -- PRF-independent."""
        return self.c * self.pulse_width / 2.0


C = Constants()
