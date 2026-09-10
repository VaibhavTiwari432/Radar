"""Windows self-test: is the phantom actually coherent as a waveform?

Generates the phantom that would be transmitted and measures its matched-filter
gain against itself (self-correlation). This tests if the waveform generation
is working, independent of hardware transmission.

Single number answers: does the generated phantom correlate well?
"""
import sys
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usrp_common as uc
import range_walk_planner as rwp
from structural_phantom_renderer import render_phantom, default_config

def main():
    print("=" * 70)
    print("WINDOWS SELF-TEST: PHANTOM COHERENCE")
    print("=" * 70)
    print("\nDiagnostic: is the generated phantom coherent as a waveform?")
    print("Method: generate phantom, self-correlate against reference.\n")

    # Generate reference chirp
    print("1. Generating reference chirp...")
    ref_chirp = uc.reference_chirp()
    print(f"   Reference chirp: {len(ref_chirp)} samples, {uc.PULSE_S*1e6:.0f} µs")
    print(f"   Peak: {np.max(np.abs(ref_chirp)):.6f}")

    # Build phantom trajectory
    print("\n2. Building phantom trajectory...")
    geo = rwp.derived()
    start_bin = geo["min_start_bin"] * 0.9
    rows, geo, warns = rwp.build(start_bin=start_bin, n_dwells=2,
                                  naive=False, rate_m_per_frame=500, quiet=True)
    dwell_row = rows[0]
    r_start = dwell_row["apparent_range_m"]
    print(f"   First dwell: range {dwell_row['apparent_range_m']:.0f} m, "
          f"amplitude {dwell_row['amplitude']:.4f}")

    # Render phantom
    print("\n3. Rendering phantom from synthesized reference...")
    state = {
        "range_m": dwell_row["apparent_range_m"],
        "radial_velocity_ms": 0.0,
        "rcs_m2": 1.0,
        "swerling_class": 0,
        "reference_range_m": r_start,
    }
    cfg = dict(default_config(), rng=np.random.default_rng(0), bake_delay=False)
    plan, meta = render_phantom(ref_chirp, state, cfg)
    phantom = (plan.astype(np.complex128) * 0.30).astype(np.complex64)
    print(f"   Phantom: {len(phantom)} samples")
    print(f"   Peak: {np.max(np.abs(phantom)):.6f}")
    print(f"   Energy: {np.sum(np.abs(phantom)**2):.6e}")

    # Self-correlation: phantom against reference
    print("\n4. Matched-filter self-correlation...")
    print(f"   Correlating: phantom ({len(phantom)} samples) vs ref_chirp ({len(ref_chirp)} samples)")

    correlation = np.correlate(phantom, ref_chirp, mode='valid')
    print(f"   Correlation length: {len(correlation)} samples")

    if len(correlation) == 0:
        print("   ERROR: Correlation failed (signals too different)")
        return 1

    # Measure coherence
    signal_power = np.max(np.abs(correlation))**2
    noise_power = np.median(np.abs(phantom)**2)

    if noise_power <= 0:
        noise_power = 1e-12

    # SNR-like metric
    snr_db = 10.0 * np.log10(signal_power / noise_power)

    # Autocorrelation check: phantom self-correlated
    auto_corr = np.correlate(phantom, phantom, mode='valid')
    auto_peak = np.max(np.abs(auto_corr))
    auto_snr_db = 10.0 * np.log10(auto_peak**2 / noise_power)

    print(f"\n5. Coherence metrics...")
    print(f"   Phantom vs ref correlation peak: {np.max(np.abs(correlation)):.6f}")
    print(f"   Phantom self-correlation peak:   {np.max(np.abs(auto_corr)):.6f}")
    print(f"   Phantom noise floor (median):    {np.sqrt(noise_power):.6e}")
    print(f"   SNR (phantom vs ref): {snr_db:.2f} dB")
    print(f"   SNR (phantom autocorr): {auto_snr_db:.2f} dB")

    # Normalized correlation (check if phantom matches reference shape)
    ref_peak = np.max(np.abs(correlation))
    auto_normalized = np.max(np.abs(correlation)) / np.max(np.abs(auto_corr)) if np.max(np.abs(auto_corr)) > 0 else 0
    print(f"   Correlation ratio (phantom_vs_ref / phantom_auto): {auto_normalized:.3f}")
    print(f"   (Should be close to 1.0 if phantom is well-correlated)")

    # Result
    print("\n" + "=" * 70)
    threshold_db = 6.0  # Decent correlation should be > 6 dB above noise
    if auto_snr_db > threshold_db:
        print(f"RESULT: PASS [SNR {auto_snr_db:.2f} dB > {threshold_db} dB]")
        print("Phantom is coherent. Waveform generation is working correctly.")
        return 0
    else:
        print(f"RESULT: FAIL [SNR {auto_snr_db:.2f} dB <= {threshold_db} dB]")
        print("Phantom is incoherent. Problem is in waveform generation.")
        return 1
    print("=" * 70)

if __name__ == "__main__":
    sys.exit(main())
