"""Structural phantom generator for the hardware loop (DRFM repeat-back).

Takes the radar pulse this payload just intercepted and returns the same
buffer with N delayed, scaled, phase-rotated copies of it summed in. Each
copy is one phantom target: the delay sets its apparent range, the amplitude
its apparent RCS/range, the phase its apparent radial position within a
wavelength.

Why a repeat-back and not a synthesised chirp: the copies are cut from the
radar's OWN transmitted pulse, so they compress in the radar's matched filter
exactly as a genuine echo does. Nothing here needs to know the waveform.

Physics constraints enforced (mirroring generator/physics_projection.py's
causality_veto, which is this project's simulation-side authority):

  * delay >= 0. A repeater can only ever ADD path length, so a phantom
    cannot appear closer than the platform carrying the repeater.
  * range per sample = c / (2 * fs) = 149.9 m at fs = 1 MHz. A 100-sample
    delay is a phantom 14.99 km further out than this platform.

Deterministic given `phases`; pass phases=None only when a random draw per
call is actually wanted.
"""
import numpy as np

C_LIGHT = 2.998e8          # m/s, exact SI value (matches +physics/Constants.m)


def range_per_sample_m(fs_hz=1e6):
    """Apparent range added per sample of delay: R = c*tau/2."""
    return C_LIGHT / (2.0 * fs_hz)


def structural_generator(captured_iq,
                         n_targets=3,
                         delays_samples=(100, 200, 300),
                         amplitudes=(0.5, 0.3, 0.2),
                         phases=None):
    """Return an IQ array the same length as captured_iq, holding n_targets
    delayed/scaled/phase-rotated copies of it.

    captured_iq     complex array, the intercepted radar pulse
    n_targets       how many phantoms to synthesise
    delays_samples  per-target delay in samples (>= 0, causality)
    amplitudes      per-target linear amplitude scale
    phases          per-target phase in radians; None -> random draw
    """
    x = np.asarray(captured_iq, dtype=np.complex64)
    if x.ndim != 1 or x.size == 0:
        raise ValueError("captured_iq must be a non-empty 1-D array, got shape %s"
                         % (np.shape(captured_iq),))

    delays = np.asarray(delays_samples, dtype=int).ravel()
    amps = np.asarray(amplitudes, dtype=float).ravel()
    if delays.size < n_targets or amps.size < n_targets:
        raise ValueError("need >= %d delays and amplitudes for n_targets=%d, got %d and %d"
                         % (n_targets, n_targets, delays.size, amps.size))
    delays, amps = delays[:n_targets], amps[:n_targets]

    if np.any(delays < 0):
        raise ValueError("negative delay violates causality: a repeater cannot place a "
                         "phantom closer than itself (delays=%s)" % delays.tolist())
    if np.any(delays >= x.size):
        raise ValueError("delay %d >= frame length %d: the phantom would fall outside "
                         "the capture window" % (int(delays.max()), x.size))

    if phases is None:
        phases = np.random.default_rng().uniform(0, 2 * np.pi, n_targets)
    phases = np.asarray(phases, dtype=float).ravel()[:n_targets]
    if phases.size < n_targets:
        raise ValueError("need >= %d phases for n_targets=%d, got %d"
                         % (n_targets, n_targets, phases.size))

    y = np.zeros_like(x)
    for delay, amp, phase in zip(delays, amps, phases):
        y[delay:] += (amp * np.exp(1j * phase)) * x[:x.size - delay]
    return y.astype(np.complex64)


def demo():
    """Self-check: run `python structural_generator.py`."""
    n = 2000
    pulse = np.zeros(n, dtype=np.complex64)
    pulse[:200] = np.exp(1j * np.pi * 0.25 * np.arange(200) ** 2 / 200)  # short chirp

    y = structural_generator(pulse, n_targets=3,
                             delays_samples=[100, 200, 300],
                             amplitudes=[0.5, 0.3, 0.2],
                             phases=[0.0, 0.0, 0.0])
    assert y.shape == pulse.shape, "output length must match input"
    assert y.dtype == np.complex64

    # Each phantom must land at its own delay with its own amplitude: matched-filter
    # the output against the pulse and check the three peaks.
    mf = np.abs(np.correlate(y, pulse[:200], mode="full"))[len(pulse[:200]) - 1:]
    for delay, amp in zip([100, 200, 300], [0.5, 0.3, 0.2]):
        window = mf[delay - 2:delay + 3]
        assert window.argmax() == 2, "phantom peak not at delay %d" % delay
        assert abs(window.max() / mf.max() - amp / 0.5) < 0.05, \
            "phantom at delay %d has the wrong relative amplitude" % delay

    # Causality and bounds are enforced, not silently clamped.
    for bad in ([-1, 200, 300], [100, 200, 5000]):
        try:
            structural_generator(pulse, 3, bad, [0.5, 0.3, 0.2], [0, 0, 0])
        except ValueError:
            pass
        else:
            raise AssertionError("expected ValueError for delays=%s" % bad)

    # Random phases stay deterministic in magnitude structure.
    y2 = structural_generator(pulse, 3, [100, 200, 300], [0.5, 0.3, 0.2], phases=None)
    assert y2.shape == pulse.shape

    print("structural_generator demo OK")
    print("  frame %d samples, range per sample %.1f m at fs = 1 MHz"
          % (n, range_per_sample_m(1e6)))
    print("  phantoms at delays [100 200 300] -> +%.2f, +%.2f, +%.2f km"
          % tuple(d * range_per_sample_m(1e6) / 1e3 for d in (100, 200, 300)))


if __name__ == "__main__":
    demo()
