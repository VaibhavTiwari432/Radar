"""Sensing (Blueprint Part 3, Block 1): estimate the threat radar's waveform
parameters from a REAL intercepted record, with honest estimation error.

This closes the gap `generator/decision/env.py` documented when Phase C was
first built: the agent's state was engagement geometry only, because no
sensing layer existed, and the radar's waveform was taken as ASSUMED/known.
It is now MEASURED, per-episode, from the RadChar dataset
(Kaggle `abcxyzi/radchar-icassp-2023`, `data/RadChar-Tiny.h5`, 50k records).

WHAT IS TAKEN FROM THE DATA, AND WHAT DELIBERATELY IS NOT
---------------------------------------------------------
TAKEN (MEASURED, per record):
  pulse_width                10.0 - 16.0 us  -> sets the radar's BLIND RANGE
                             (c*PW/2 = 1499 - 2398 m): the receiver is deaf
                             while transmitting, so a phantom placed inside
                             it is never seen. A 899 m / 19-range-bin swing
                             driven entirely by real measured emitters.
  signal_to_noise_ratio      -20 .. +20 dB   -> how well the interceptor can
                             actually estimate the above (see below).
  signal_type, number_of_pulses, pulse_repetition_interval -> carried through
                             for provenance/inspection.

NOT TAKEN, and the reason stated rather than hidden:
  RadChar's pulse_repetition_interval (17-23 us) is NOT adopted as the
  simulated radar's PRI. At fs = 3.2 MHz that is a 54-74 sample receive
  window, while this project's judge runs a CA-CFAR needing
  2*(NumTraining+NumGuard)+1 = 2*(20+4)+1 = 49 cells and whose near-range
  blind zone alone consumes NumTraining+NumGuard = 24 cells at each edge
  (+radar/cfarDefaults.m, +radar/cfarDetect.m). Adopting it would leave the
  detector with essentially no testable cells -- the dataset's emitters are
  simply not the same class of radar as the one this project simulates
  (CLAUDE.md already warns that conflating RadChar's emitter PRI with this
  radar's own PRI is a mistake this project made once). The simulated
  radar keeps its own declared PRF (+physics/Constants.m, 8 kHz).

So: the pulse width and intercept SNR are real measured data; the PRF is
this project's own declared radar. Both facts travel with every result.
"""
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np

from common.constants import C
from common.provenance import Provenance, Tagged, tag

DEFAULT_RADCHAR_PATH = Path(__file__).resolve().parents[1] / "data" / "RadChar-Tiny.h5"


@dataclass
class SensedRadar:
    """One episode's threat radar, as the interceptor believes it to be.

    `*_true` fields are the dataset's ground truth and exist ONLY for
    scoring/diagnostics -- the agent is given the `*_est` fields. Handing
    the agent a `*_true` field would be exactly the perfect-front-end
    assumption Blueprint Risk 3 says not to make.
    """
    record_index: int
    signal_type: int
    snr_db: float                 # the interceptor CAN estimate its own SNR
    pulse_width_true_s: float
    pulse_width_est_s: float
    pulse_width_sigma_s: float    # the estimator's own stated uncertainty
    pri_true_s: float
    number_of_pulses: int

    @property
    def blind_range_true_m(self) -> float:
        """c*PW/2 -- where the radar is actually deaf. Ground truth; used to
        score the episode, never shown to the agent."""
        return C.c * self.pulse_width_true_s / 2.0

    @property
    def blind_range_est_m(self) -> float:
        """The agent's belief about the blind range, from its noisy PW
        estimate. This is what a policy can actually act on."""
        return C.c * self.pulse_width_est_s / 2.0


def pulse_width_sigma(snr_db: float, bandwidth_hz: float = C.bandwidth) -> float:
    """DERIVED estimation error on pulse width, from the standard
    time-delay-estimation scaling sigma_tau ~ 1/(B*sqrt(SNR)).

    A pulse width is the difference of two edge times, each estimated with
    that error, so the width's error is sqrt(2) larger; the sqrt(2) and the
    CRLB's own factor of sqrt(2) cancel to give sigma_PW ~ 1/(B*sqrt(SNR_lin)).
    Order-of-magnitude, not a calibrated instrument model -- the CONSTANT is
    approximate and is tagged as such; what matters for training is the
    SCALING, which makes low-SNR intercepts genuinely uninformative:

        SNR = +20 dB -> sigma = 0.05 us  (blind range known to ~7 m)
        SNR =   0 dB -> sigma = 0.5 us   (blind range known to ~75 m)
        SNR = -20 dB -> sigma = 5.0 us   (83% of the entire 10-16 us spread
                                          of real pulse widths: the estimate
                                          carries almost no information)

    Ref: standard CRLB for time-of-arrival estimation (e.g. Skolnik;
    Richards, Fundamentals of Radar Signal Processing).
    """
    snr_lin = 10.0 ** (snr_db / 10.0)
    return 1.0 / (bandwidth_hz * np.sqrt(snr_lin))


class RadCharSensor:
    """Samples real RadChar records and returns noisy parameter estimates.

    Train/eval splits are DISJOINT SETS OF REAL EMITTER RECORDS, which is
    what makes Blueprint 5.5's "train and evaluate on disjoint radar
    configurations" a real guarantee here rather than a naming convention:
    an eval episode's radar was never seen in training.
    """

    def __init__(self, h5_path: Optional[Path] = None, eval_fraction: float = 0.2,
                 split_seed: int = 12345):
        self.h5_path = Path(h5_path) if h5_path else DEFAULT_RADCHAR_PATH
        if not self.h5_path.exists():
            raise FileNotFoundError(
                f"RadChar not found at {self.h5_path}. See data/README.md "
                "(kaggle datasets download -d abcxyzi/radchar-icassp-2023)."
            )
        import h5py
        with h5py.File(self.h5_path, "r") as f:
            labels = f["labels"][:]
        self._labels = labels

        n = len(labels)
        rng = np.random.default_rng(split_seed)
        perm = rng.permutation(n)
        n_eval = int(eval_fraction * n)
        self.eval_indices = np.sort(perm[:n_eval])
        self.train_indices = np.sort(perm[n_eval:])

    def sample(self, rng: np.random.Generator, split: str = "train") -> SensedRadar:
        pool = self.train_indices if split == "train" else self.eval_indices
        idx = int(rng.choice(pool))
        return self.at(idx, rng)

    def at(self, record_index: int, rng: np.random.Generator) -> SensedRadar:
        rec = self._labels[record_index]
        pw_true = float(rec["pulse_width"])
        snr_db = float(rec["signal_to_noise_ratio"])
        sigma = pulse_width_sigma(snr_db)
        # The estimate is the truth plus estimator noise, clipped to remain
        # a physically possible pulse width -- an estimator that reports a
        # negative or absurd width would be a broken estimator, not a noisy
        # one, and would hand the agent an obviously-invalid input.
        pw_est = float(np.clip(pw_true + rng.normal(0.0, sigma), 1e-6, 100e-6))
        return SensedRadar(
            record_index=record_index,
            signal_type=int(rec["signal_type"]),
            snr_db=snr_db,
            pulse_width_true_s=pw_true,
            pulse_width_est_s=pw_est,
            pulse_width_sigma_s=sigma,
            pri_true_s=float(rec["pulse_repetition_interval"]),
            number_of_pulses=int(rec["number_of_pulses"]),
        )
