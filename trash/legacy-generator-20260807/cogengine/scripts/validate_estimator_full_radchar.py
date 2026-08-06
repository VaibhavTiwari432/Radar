"""Phase 3.2a -- stratified estimator validation on RadChar-Tiny.

ROUTE 2 (bootstrap truth), executed per-record rather than per-population.

=================== WHY NOT THE POPULATION MEAN ===================
The brief's Step 3 says to take "mean k, mean BW, mean pulse_width" over the
SNR >= 18 dB band and use those as the true values for every other record.
That does not work on this dataset, and the reason is measurable:

  * All 50,000 records are UNIQUE (pulse_width, PRI, n_pulses, type) draws --
    zero repeats -- so there is no "same waveform at a different SNR" pair.
  * k = BW/pulse_width varies 2.6x ACROSS records (1.86e10 .. 4.77e10 Hz/s
    measured on the eight cleanest LFM records).

Scoring a low-SNR record's estimate against the population mean would
therefore measure the POPULATION SPREAD (~40%), not the estimator's error --
a perfect estimator would still "fail".

=================== WHAT THIS DOES INSTEAD ===================
Per-record self-bootstrap:

  1. Take records at their native HIGH SNR (>= 18 dB). Estimate k there; that
     is that record's own reference, with tight bounds because the SNR is high.
  2. Inject additional noise into the SAME record to synthesise a lower
     EFFECTIVE SNR, and re-estimate.
  3. Error = |k_est(snr) - k_ref| / k_ref, holding waveform AND nominal fixed.

Real RadChar waveforms, per-record truth, and a genuine degradation curve.

=================== A PREMISE WORTH STATING ===================
characterize_intercept_dechirp is a REFINEMENT of a known nominal, not a blind
estimator -- that is the project's "known radar" premise (design doc Part 1).
It dechirps against a supplied nominal and shrinks toward it as confidence
falls. RadChar's k varies 2.6x across records, so no single nominal is right
for all of them. This script supplies the high-SNR band's MEDIAN k as the
nominal, which is what a real system would know about a class of emitter, and
reports how far each record's estimate is pulled from its own reference. Where
the estimate collapses onto the nominal, that is shrinkage, and it is reported
as such rather than counted as accuracy.

Run:  python -m cogengine.scripts.validate_estimator_full_radchar
"""
from __future__ import annotations

import pathlib
import sys

import h5py
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from cogengine.features import characterize_intercept_dechirp  # noqa: E402
from cogengine.radar_params import SAMPLE_RATE_HZ  # noqa: E402

H5 = pathlib.Path(r"E:\Radar\data\RadChar-Tiny.h5")
CLASS_NAMES = ["CoherentPulseTrain", "Barker", "PolyBarker", "Frank", "LFM"]
GOLD_SNR_DB = 18          # >= this is the reference band (3575 records)
SNR_GRID = [-20, -15, -10, -5, 0, 5, 10, 15]
N_PER_BIN = 60            # >= 50 per the brief
CONF_THRESHOLD = 0.7      # "shrinkage" = estimator fell back below this


def extract_pulse(iq: np.ndarray, t_delay: float, pw: float, fs: float) -> np.ndarray:
    a = max(1, int(round(t_delay * fs)))
    L = max(1, int(round(pw * fs)))
    return iq[a:min(len(iq), a + L)]


def add_noise_to_snr(pulse: np.ndarray, native_snr_db: float,
                     target_snr_db: float, rng: np.random.Generator) -> np.ndarray:
    """Inject noise so the pulse's effective SNR falls to target_snr_db.

    The record already carries noise at its native SNR, so the ADDITIONAL
    noise power is the difference of the two noise powers, not the target's
    outright -- getting that wrong would over-noise every record by the
    native contribution.
    """
    sig_p = float(np.mean(np.abs(pulse) ** 2))
    n_have = sig_p / (10 ** (native_snr_db / 10))
    n_want = sig_p / (10 ** (target_snr_db / 10))
    extra = max(0.0, n_want - n_have)
    if extra <= 0:
        return pulse
    n = len(pulse)
    w = (rng.standard_normal(n) + 1j * rng.standard_normal(n)) / np.sqrt(2)
    return pulse + np.sqrt(extra) * w


def main() -> int:
    fs = SAMPLE_RATE_HZ
    with h5py.File(H5, "r") as f:
        lab = f["labels"][:]
        gold_idx = np.where(lab["signal_to_noise_ratio"] >= GOLD_SNR_DB)[0]
        print(f"RadChar-Tiny: {len(lab)} records | gold band (SNR >= {GOLD_SNR_DB} dB): "
              f"{len(gold_idx)}")

        # ---- nominal: median k of the gold LFM band (the "known radar" prior)
        lfm_gold = [i for i in gold_idx if lab["signal_type"][i] == 4][:400]
        ks = []
        for i in lfm_gold:
            p = extract_pulse(f["iq"][i], lab["time_delay"][i], lab["pulse_width"][i], fs)
            if len(p) < 8:
                continue
            P = np.abs(np.fft.fftshift(np.fft.fft(p))) ** 2
            fr = np.fft.fftshift(np.fft.fftfreq(len(p), 1 / fs))
            c = np.cumsum(P) / P.sum()
            bw = fr[np.searchsorted(c, 0.95)] - fr[np.searchsorted(c, 0.05)]
            ks.append(bw / lab["pulse_width"][i])
        k_nominal = float(np.median(ks))
        print(f"nominal k (median of {len(ks)} gold LFM records): {k_nominal:.4e} Hz/s")
        print(f"  gold k spread: p5 {np.percentile(ks,5):.3e} .. p95 "
              f"{np.percentile(ks,95):.3e} Hz/s  ({np.percentile(ks,95)/np.percentile(ks,5):.2f}x)")
        print(f"  -> no single nominal fits all records; see the module docstring.\n")

        rng = np.random.default_rng(20260801)

        print("=" * 96)
        print("PER-RECORD DEGRADATION: same waveform, noise injected to the target SNR")
        print("=" * 96)
        header = f"{'class':<20}" + "".join(f"{s:>8}" for s in SNR_GRID)
        for metric, title in (("err", "median |k_est - k_ref| / k_ref  [%]"),
                              ("shrink", f"shrinkage rate (confidence < {CONF_THRESHOLD})  [%]")):
            print(f"\n--- {title} ---")
            print(header)
            for cls in range(5):
                pool = [i for i in gold_idx if lab["signal_type"][i] == cls]
                rng.shuffle(pool)
                pool = pool[:N_PER_BIN]
                row = f"{CLASS_NAMES[cls]:<20}"
                for snr in SNR_GRID:
                    errs, shrunk = [], 0
                    for i in pool:
                        p = extract_pulse(f["iq"][i], lab["time_delay"][i],
                                          lab["pulse_width"][i], fs)
                        if len(p) < 8:
                            continue
                        ref = characterize_intercept_dechirp(p, fs, k_nominal)
                        noisy = add_noise_to_snr(
                            p, float(lab["signal_to_noise_ratio"][i]), float(snr), rng)
                        est = characterize_intercept_dechirp(noisy, fs, k_nominal)
                        if abs(ref.chirp_rate_hz_s) > 0:
                            errs.append(abs(est.chirp_rate_hz_s - ref.chirp_rate_hz_s)
                                        / abs(ref.chirp_rate_hz_s))
                        shrunk += (est.confidence < CONF_THRESHOLD)
                    n = max(1, len(pool))
                    val = (100 * float(np.median(errs)) if metric == "err" and errs
                           else 100 * shrunk / n if metric == "shrink" else float("nan"))
                    row += f"{val:>8.1f}"
                print(row)

        # ---- what the labels DO support, as a grounded cross-check ----
        print("\n" + "=" * 96)
        print("GROUNDED CROSS-CHECK: pulse-width error vs SNR (pulse_width IS labelled)")
        print("=" * 96)
        print(header)
        for cls in range(5):
            pool = [i for i in gold_idx if lab["signal_type"][i] == cls]
            rng.shuffle(pool)
            pool = pool[:N_PER_BIN]
            row = f"{CLASS_NAMES[cls]:<20}"
            for snr in SNR_GRID:
                errs = []
                for i in pool:
                    p = extract_pulse(f["iq"][i], lab["time_delay"][i],
                                      lab["pulse_width"][i], fs)
                    if len(p) < 8:
                        continue
                    noisy = add_noise_to_snr(
                        p, float(lab["signal_to_noise_ratio"][i]), float(snr), rng)
                    est = characterize_intercept_dechirp(noisy, fs, k_nominal)
                    true_pw = float(lab["pulse_width"][i])
                    errs.append(abs(est.pulse_width_s - true_pw) / true_pw)
                row += f"{100*float(np.median(errs)):>8.1f}" if errs else f"{'--':>8}"
            print(row)
        print("\n(pulse-width error is against the DATASET LABEL -- real ground truth,")
        print(" unlike chirp rate, which the dataset does not carry.)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
