"""Quick diagnostic: measure phantom TX buffer amplitude at 90 km range."""
import sys
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import usrp_common as uc
import range_walk_planner as rwp
import stage_e_naive_drfm as naive
from structural_phantom_renderer import (
    render_phantom, default_config,
)

# Build a trajectory that starts at ~90 km (the causality floor)
geo = rwp.derived()
start_bin = geo["min_start_bin"] * naive.SAFETY_FACTOR
rows, geo_out, warns = rwp.build(start_bin=start_bin, n_dwells=10,
                                 naive=False, rate_m_per_frame=500.0,
                                 quiet=True)

r_start = rows[0]["apparent_range_m"]
print(f"\nTRAJECTORY: {len(rows)} dwells, {r_start:.0f} -> {rows[-1]['apparent_range_m']:.0f} m")
print(f"Start range: {r_start:.0f} m (causality floor check)")
print("")

# Render the FIRST dwell's phantom at the start range
TX_PEAK_AMPLITUDE = 0.30
synthesized_pulse = uc.reference_chirp()
print(f"Reference chirp: {len(synthesized_pulse)} samples, peak={np.max(np.abs(synthesized_pulse)):.6f}")
print("")

dwell_row = rows[0]
state = {
    "range_m": dwell_row["apparent_range_m"],
    "radial_velocity_ms": 0.0,
    "rcs_m2": 1.0,
    "swerling_class": 0,
    "reference_range_m": r_start,
}
cfg = dict(default_config(), rng=np.random.default_rng(0), bake_delay=False)
plan, meta = render_phantom(synthesized_pulse, state, cfg)

print(f"Phantom from render_phantom():")
print(f"  amplitude_scale: {meta['amplitude_scale']:.6f}")
print(f"  peak before TX scaling: {np.max(np.abs(plan)):.6f}")
print(f"  rms before TX scaling: {np.sqrt(np.mean(np.abs(plan)**2)):.6f}")
print("")

# Apply TX_PEAK_AMPLITUDE scaling, exactly as stage_e_structural_drfm does
boosted = (plan.astype(np.complex128) * TX_PEAK_AMPLITUDE).astype(np.complex64)
scaled, _factor = uc.scale_by_intercept(boosted, synthesized_pulse)

peak_amplitude = np.max(np.abs(scaled))
rms_amplitude = np.sqrt(np.mean(np.abs(scaled)**2))
peak_dbfs = 20 * np.log10(peak_amplitude) if peak_amplitude > 0 else -999

print(f"STRUCTURAL PHANTOM after TX scaling (this is what gets transmitted):")
print(f"  dtype: {scaled.dtype}")
print(f"  peak amplitude: {peak_amplitude:.6f}")
print(f"  peak in dBFS: {peak_dbfs:.1f}")
print(f"  rms amplitude: {rms_amplitude:.6f}")
print(f"  samples: {len(scaled)}")
print("")

# Compare to known-working loopback burst
# This is exactly what usrp_loopback.py transmits in CHECK 1:
# one = (make_train() * 0.9).astype(np.complex64)
# where make_train() returns a 3-pulse train with each pulse at reference_chirp * 0.7
print(f"--- COMPARISON TO LOOPBACK BURST ---")

def make_train_loopback(n_pulses=3, rate=uc.RX_RATE):
    """Loopback's reference train."""
    from usrp_loopback import reference_chirp as ref_chirp_loopback
    pulse = ref_chirp_loopback(rate=rate) * 0.7
    step = int(round(uc.PRI_S * rate))
    out = np.zeros(step * n_pulses, dtype=np.complex64)
    for k in range(n_pulses):
        out[k * step:k * step + pulse.size] = pulse
    return out

one_train = (make_train_loopback() * 0.9).astype(np.complex64)
loopback_peak = np.max(np.abs(one_train))
loopback_rms = np.sqrt(np.mean(np.abs(one_train)**2))
loopback_dbfs = 20 * np.log10(loopback_peak) if loopback_peak > 0 else -999

print(f"LOOPBACK CHECK 1 burst (known to transmit at 45+ dB TX gain):")
print(f"  dtype: {one_train.dtype}")
print(f"  peak amplitude: {loopback_peak:.6f}")
print(f"  peak in dBFS: {loopback_dbfs:.1f}")
print(f"  rms amplitude: {loopback_rms:.6f}")
print(f"  samples: {len(one_train)} (3-pulse train, {len(one_train)//3} per pulse)")
print(f"  (each pulse is reference_chirp * 0.7, then whole train * 0.9)")
print("")

ratio_db = peak_dbfs - loopback_dbfs
print(f"DIAGNOSTIC:")
print(f"  Structural phantom vs Loopback: {ratio_db:+.1f} dB")
if ratio_db < -20:
    print(f"  ^ CRITICAL: phantom is {abs(ratio_db):.1f} dB BELOW loopback")
    print(f"    This suggests the phantom buffer is too weak to detect at 45 dB TX gain")
elif ratio_db < -10:
    print(f"  ^ WARNING: phantom is {abs(ratio_db):.1f} dB below loopback")
elif ratio_db > 3:
    print(f"  ^ NOTE: phantom is {ratio_db:.1f} dB ABOVE loopback (may saturate)")
else:
    print(f"  ^ OK: within 3 dB of loopback burst")
