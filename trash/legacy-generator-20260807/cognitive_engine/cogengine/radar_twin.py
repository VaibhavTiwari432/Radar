"""
radar_twin.py — the engine's INTERNAL model of the known radar (its imagination).

A fast, simplified replica of the known victim radar's chain:
    matched filter -> range-Doppler -> CFAR-style detection -> ECCM screens
It returns the PREDICTED number of phantoms that would survive as false tracks.

*** THE GOLDEN RULE (design doc Part 1) ***
This twin is the engine's BELIEF about the radar and is used only for PLANNING.
It must stay a SEPARATE object from the independent MATLAB judge that SCORES the
engine (phased.CFARDetector + trackerGNN + ECCM). The gap between twin and judge
is a first-class experimental result, not something to hide.
"""
from __future__ import annotations
from typing import Dict, List
import numpy as np
from .schema import Scene, RadarState
from .renderer import render_scene, default_tx_template, range_delay_samples, doppler_hz


class RadarTwin:
    def __init__(self, radar: RadarState,
                 cfar_alpha: float = 8.0,      # threshold = alpha * median(|RD|)  (CA-CFAR-like)
                 noise_std: float = 0.05,
                 v_eps_mps: float = 2.0):       # |v| below this reads as a stationary copy
        self.radar = radar
        self.tx = default_tx_template(radar)
        self.L = len(self.tx)
        self.cfar_alpha = cfar_alpha
        self.noise_std = noise_std
        self.v_eps_mps = v_eps_mps

    # -- signal processing ---------------------------------------------------
    def _range_doppler(self, cube: np.ndarray) -> np.ndarray:
        """Matched-filter every pulse, then FFT across pulses -> |RD| map
        of shape [doppler, fast]. Doppler axis is fftshifted (centre = 0 Hz).

        Matched filter = convolution with the conjugate time-reversed template
        h[n] = conj(tx[L-1-n]); its peak lands at delay + (L-1). (Explicit form
        avoids numpy.correlate's complex-conjugation ambiguity.)"""
        h = np.conj(self.tx[::-1])
        width = cube.shape[1]
        mf = np.empty_like(cube)
        for m in range(cube.shape[0]):
            mf[m] = np.convolve(cube[m], h)[:width]
        rd = np.fft.fftshift(np.fft.fft(mf, axis=0), axes=0)
        return np.abs(rd)

    def _doppler_freqs(self) -> np.ndarray:
        return np.fft.fftshift(np.fft.fftfreq(self.radar.n_pulses, d=self.radar.pri_s))

    # -- the scorer ----------------------------------------------------------
    def score(self, scene: Scene, rng_seed: int = 0) -> Dict:
        """Detect + screen every phantom. Returns predicted survivors and a
        per-phantom status list. Deterministic given rng_seed."""
        rng = np.random.default_rng(rng_seed)
        cube = render_scene(scene, self.radar, tx_template=self.tx,
                            rng=rng, noise_std=self.noise_std)
        mag = self._range_doppler(cube)
        thresh = self.cfar_alpha * np.median(mag)
        dfreqs = self._doppler_freqs()

        statuses: List[str] = []
        survivors = 0
        flagged = 0
        for ph in scene.phantoms:
            # expected cell: matched-filter 'full' peak sits at delay + (L-1)
            rb = int(round(range_delay_samples(ph.range_m, self.radar.fs_hz))) + (self.L - 1)
            f_d = doppler_hz(ph.radial_vel_mps, self.radar.wavelength_m)
            db = int(np.argmin(np.abs(dfreqs - f_d)))

            r0, r1 = max(0, rb - 3), min(mag.shape[1], rb + 4)
            d0, d1 = max(0, db - 2), min(mag.shape[0], db + 3)
            peak = mag[d0:d1, r0:r1].max() if (r1 > r0 and d1 > d0) else 0.0

            if peak <= thresh:
                statuses.append("undetected")
                continue

            # ---- ECCM screens (the radar's defenses = what realism must beat) ----
            flag = False
            # 1) zero-Doppler screen: a static delayed copy has no radial motion.
            if abs(ph.radial_vel_mps) < self.v_eps_mps:
                flag = True
            # 2) micro-Doppler presence: a real drone shows blade lines; a bare copy doesn't.
            if ph.cls == "drone" and ph.micro is None:
                flag = True
            # 3) kinematic sanity is guaranteed upstream by the truth model (Layer 1).

            if flag:
                flagged += 1
                statuses.append("flagged")
            else:
                survivors += 1
                statuses.append("confirmed")

        return {
            "survivors": survivors,
            "flagged": flagged,
            "detected": sum(s != "undetected" for s in statuses),
            "n_phantoms": len(scene.phantoms),
            "per_phantom_status": statuses,
            "threshold": float(thresh),
        }
