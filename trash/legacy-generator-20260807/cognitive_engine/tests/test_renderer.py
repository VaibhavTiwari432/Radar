"""
Physics tests for the renderer. Each asserts a falsifiable claim from the render
ledger (design doc Part 4). These are what make realism VERIFIABLE, not asserted.
Run with `pytest` or via `python run_tests.py`.
"""
import numpy as np
from cogengine.schema import RadarState, Phantom, C
from cogengine.renderer import (range_delay_samples, doppler_hz, blade_flash_hz,
                                slowtime_signal)


def test_range_to_delay():
    """tau (in samples) = 2R/c * fs."""
    val = range_delay_samples(1000.0, 3.2e6)
    assert np.isclose(val, 2 * 1000.0 / C * 3.2e6, atol=1e-9)
    assert np.isclose(val, 21.348, atol=0.01)


def test_doppler_matches_range_rate():
    """The rendered slow-time Doppler peak must equal f_d = 2 v_r / lambda —
    i.e. Doppler is consistent with radial velocity (kills the zero-Doppler tell)."""
    radar = RadarState()                      # X-band, lambda = 0.03 m, PRF 50 kHz, 512 pulses
    v = 150.0
    ph = Phantom(cls="fighter", range_m=1500.0, radial_vel_mps=v, micro=None, swerling=0)
    s = slowtime_signal(ph, radar, rng=None)

    spec = np.abs(np.fft.fft(s))
    freqs = np.fft.fftfreq(radar.n_pulses, d=radar.pri_s)
    f_peak = freqs[int(np.argmax(spec))]

    f_expected = doppler_hz(v, radar.wavelength_m)     # = 10 000 Hz
    dopp_bin = radar.prf_hz / radar.n_pulses           # ~97.7 Hz
    assert abs(f_peak - f_expected) <= dopp_bin, (f_peak, f_expected)


def test_microdoppler_line_spacing():
    """A drone's blade flash puts sidebands at +/- n_blades * f_rot around the
    Doppler carrier. Verify the dominant sideband offset = n_blades * (rpm/60)."""
    radar = RadarState()
    micro = {"type": "propeller", "n_blades": 2, "rpm": 12000, "blade_len_m": 0.12}
    ph = Phantom(cls="drone", range_m=1200.0, radial_vel_mps=100.0, micro=micro, swerling=0)
    s = slowtime_signal(ph, radar, rng=None)

    spec = np.abs(np.fft.fft(s))
    freqs = np.fft.fftfreq(radar.n_pulses, d=radar.pri_s)
    main = int(np.argmax(spec))

    spec_masked = spec.copy()
    for k in range(main - 2, main + 3):                # blank the carrier +/-2 bins
        spec_masked[k % radar.n_pulses] = 0.0
    side = int(np.argmax(spec_masked))

    offset = abs(freqs[side] - freqs[main])
    f_m = blade_flash_hz(micro)                         # = 400 Hz
    dopp_bin = radar.prf_hz / radar.n_pulses
    assert abs(offset - f_m) <= dopp_bin, (offset, f_m)


if __name__ == "__main__":
    test_range_to_delay(); test_doppler_matches_range_rate(); test_microdoppler_line_spacing()
    print("renderer tests passed")
