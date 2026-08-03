"""Shared physical facts for the Python side, declared ONCE.

CLAUDE.md Rule 1 (no magic numbers) applies to `cogengine/` exactly as it
does to `+physics/`, but until Phase A2 there was no Python equivalent of
`+physics/Constants.m`: the speed of light was re-typed as a literal
`299792458.0` in `radar_twin.py`, `planner_cem.py` and
`fixtures/canonical_scene_crosscheck.py`, `fs` was re-declared as a
dataclass default in `radar_twin.py`, and `range_per_sample` was recomputed
inline in three places -- plus typed as the finished number `46.8426` in
`web/src/Console.jsx`. Five independent copies of two facts.

These are FACTS, not model parameters, so sharing them across the twin/judge
boundary does not violate Rule 2 -- the same reasoning by which
`+physics/Constants.m` is read by both `+synth/` and `+radar/`. What must
never be shared is a *decision*: a CFAR threshold, a tracker gate, an ECCM
boundary. See `+engine/runJudge.m`'s Phase A1 header for that split.

`tests/test_radar_params.py` asserts every value here equals
`+physics/Constants.m`'s to the last bit, so the two languages cannot drift.
"""

import numpy as np

# --- Fundamental physical constants (SI exact / CODATA) ---
SPEED_OF_LIGHT_MPS = 299792458.0
"""[m/s] exact SI value. Matches +physics/Constants.m's C.c."""

BOLTZMANN_J_PER_K = 1.380649e-23
"""[J/K] exact SI value since the 2019 redefinition. Thermal noise, N = kTBF."""

REFERENCE_TEMPERATURE_K = 290.0
"""[K] IEEE standard noise reference temperature T0. Not room temperature --
the convention that makes a stated noise figure mean something."""

# --- Acquisition parameters (RadChar dataset anchors) ---
SAMPLE_RATE_HZ = 3.2e6
"""[Hz] RadChar's acquisition rate. Matches +physics/Constants.m's C.fs."""

# --- THIS RADAR's own waveform (Phase 4.1) ---
# Mirrors +physics/Constants.m; cogengine/tests/test_radar_params.py pins the
# two together so they cannot drift.
#
# WHY 8 kHz AND NOT 50 kHz: the value 50e3 was a literal in ~20 files and was
# not self-consistent with the 400-sample listening window those same files
# used. Three independent checks all favour 8 kHz -- samples/PRI (400 vs 64),
# duty cycle at the 12 us pulse (9.6% vs a non-pulsed 60%), and R_ua matching
# the window span exactly (18737 m). See +physics/Constants.m's own header and
# tests/test_prf_consistency.m.
PRF_HZ = 8e3
"""[Hz] pulse repetition frequency."""

PULSE_WIDTH_S = 12e-6
"""[s] transmitted pulse length."""

CARRIER_HZ = 10e9
"""[Hz] X-band carrier."""

FAST_TIME_SAMPLES = 400
"""[samples] receive-window length. Equals fs/PRF exactly -- see above."""

# --- Derived ---
RANGE_PER_SAMPLE_M = SPEED_OF_LIGHT_MPS / (2.0 * SAMPLE_RATE_HZ)
"""[m] two-way range of one fast-time sample, c/(2*fs) ~= 46.84 m."""


# --- Phase B1: the simulation's amplitude units, anchored to real watts ---
#
# See +physics/simUnits.m for the full argument; the short version is that
# every noise draw in this repo is
#     noise = SIM_NOISE_AMPLITUDE * (randn + 1j*randn) / sqrt(2)
# whose complex variance is exactly SIM_NOISE_AMPLITUDE**2. Equating that to
# the derived thermal floor N = k*T0*B*F fixes the whole unit system, so an
# SNR quoted in sim units and one quoted in watts are the same number.
#
# This mirrors the MATLAB side rather than owning it separately -- and
# cogengine/tests/test_sim_units.py asserts the two agree, the same way
# test_radar_params.py pins the constant tables together.

SIM_NOISE_AMPLITUDE = 0.05
"""The simulation's long-standing noise convention. NOT derived -- it is the
quantity being calibrated. It had no thermal derivation anywhere before B1."""

NOISE_BANDWIDTH_HZ = 2e6
"""[Hz] matched-filter / receiver noise bandwidth at this project's waveform."""

NOISE_FIGURE_DB = 3.0
"""[dB] receiver noise figure."""


def thermal_noise_power_w(bandwidth_hz: float = NOISE_BANDWIDTH_HZ,
                          noise_figure_db: float = NOISE_FIGURE_DB) -> float:
    """N = k*T0*B*F [W]. 1.5978e-14 W = -137.965 dBW at the defaults."""
    return (BOLTZMANN_J_PER_K * REFERENCE_TEMPERATURE_K * bandwidth_hz
            * 10.0 ** (noise_figure_db / 10.0))


def watts_per_sim_power(**kw) -> float:
    """The single conversion factor between sim power units and watts."""
    return thermal_noise_power_w(**kw) / SIM_NOISE_AMPLITUDE**2


def watts_to_sim_amplitude(power_w: float, **kw) -> float:
    """Received power [W] -> sim amplitude. Amplitude is voltage-like."""
    return float(np.sqrt(power_w / watts_per_sim_power(**kw)))


def sim_amplitude_to_watts(amplitude: float, **kw) -> float:
    """Sim amplitude -> received power [W]."""
    return float(amplitude**2 * watts_per_sim_power(**kw))


# --- Phase C1: range ambiguity ---

def unambiguous_range_m(prf_hz: float) -> float:
    """R_ua = c/(2*PRF) [m]. 2997.9 m at this project's declared 50 kHz."""
    return SPEED_OF_LIGHT_MPS / (2.0 * prf_hz)


def unambiguous_velocity_mps(prf_hz: float = PRF_HZ,
                              carrier_hz: float = CARRIER_HZ) -> float:
    """v_ua = lambda*PRF/4 [m/s] -- the +/- radial velocity beyond which
    Doppler folds. 60 m/s at 8 kHz / 10 GHz, down from 375 m/s at the old
    (non-physical) 50 kHz reading. This is the price paid for the range
    coverage; no single PRF gives both (Phase 4.1)."""
    return (SPEED_OF_LIGHT_MPS / carrier_hz) * prf_hz / 4.0


def apparent_range_m(range_m: float, prf_hz: float) -> float:
    """Where a beyond-R_ua echo ACTUALLY appears: mod(R, R_ua).

    A pulse radar re-arms its range gate every PRI, so an echo arriving after
    the next pulse went out is timed from the wrong transmission. Mirrors
    +physics/apparentRange.m -- see its header for why this was missing and
    for the PRF-vs-receive-window contradiction it exposed.
    """
    rua = unambiguous_range_m(prf_hz)
    return float(range_m - np.floor(range_m / rua) * rua)


def range_per_sample_m(fs_hz: float = SAMPLE_RATE_HZ) -> float:
    """Range resolution of one fast-time sample at an arbitrary `fs`.

    The module constant above covers this project's own `fs`; this exists for
    the callers that legitimately carry their own (a swept `TwinConfig.fs`),
    so they still derive the value instead of re-typing `c / (2 * fs)`.
    """
    return SPEED_OF_LIGHT_MPS / (2.0 * fs_hz)
