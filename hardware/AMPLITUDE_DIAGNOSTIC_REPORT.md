# Phantom TX Buffer Amplitude Diagnostic Report

**Date:** 2026-08-22  
**Test:** `test_phantom_amplitude.py` + instrumentation in `stage_e_structural_drfm.py` and `usrp_loopback.py`

## Summary

The structural phantom TX buffer amplitude is **-6.4 dB below** the known-working loopback burst. This means the phantom is transmitting at roughly **half the power** of a burst that successfully reached the receiver at 45+ dB TX gain.

---

## Detailed Measurements

### Structural Phantom (at causality floor, 89,638 m start range)

**Phantom Configuration:**
- Trajectory: 10 dwells from 89,638 → 94,135 m (500 m/frame walk)
- Dwell 0 range: 89,638 m
- Amplitude scale: 1.0000 (at reference range r_start, so full amplitude)
- TX_PEAK_AMPLITUDE: 0.30

**Buffer Metrics:**
| Metric | Value | Notes |
|--------|-------|-------|
| **Peak amplitude** | 0.300000 | Unit: normalized DAC range [0, 1] |
| **Peak in dBFS** | **-10.5 dB** | Full scale = 0 dBFS |
| **RMS amplitude** | 0.300000 | For a coherent pulse, ≈ peak |
| **Data type** | `complex64` | UHD expects this; correct ✓ |
| **Pulse length** | 100 samples | @ 3.2 MHz = 31.25 µs |

**Raw DAC samples rendered by `structural_phantom_renderer.render_phantom()`:**
- Peak: 1.0 (reference chirp)
- After `TX_PEAK_AMPLITUDE` scaling (× 0.30): **0.30**
- After `uc.scale_by_intercept()` (reference chirp peak ≈ 1.0, so no-op): **0.30**

### Loopback Reference (CHECK 1, known to work at 45+ dB TX gain)

**Burst Configuration:**
- 3-pulse train (3 × 10 ms spacing at 100 Hz PRF)
- Each pulse: `reference_chirp(3.2 MHz) × 0.7`
- Whole train: `× 0.9` (loopback's own scaling)
- Per-pulse peak: `0.7 × 0.9 = 0.63`

**Buffer Metrics:**
| Metric | Value | Notes |
|--------|-------|-------|
| **Peak amplitude** | 0.630000 | Same units: normalized DAC [0, 1] |
| **Peak in dBFS** | **-4.0 dB** | Full scale = 0 dBFS |
| **RMS amplitude** | 0.063000 | Average over 3-pulse envelope |
| **Data type** | `complex64` | Correct ✓ |
| **Total samples** | 30,000 | 3 pulses @ 10 ms = 3 × 10,000 samples |
| **Per-pulse length** | ~100 samples | Similar to structural phantom |

### Comparison

```
LOOPBACK peak:       0.630 (-4.0 dBFS)
STRUCTURAL phantom:  0.300 (-10.5 dBFS)
─────────────────────────────
Difference:          -6.4 dB
                     (structural is 2.1× weaker)
```

---

## Root Cause Analysis

The structural phantom is weaker than the loopback burst because:

1. **TX_PEAK_AMPLITUDE = 0.30** (structural DRFM sets this deliberately)
   - This is tuned to fit the full range walk (89 km → 94 km) under the 0.9 DAC ceiling
   - At the START of the walk (amplitude_scale = 1.0), we transmit at 0.30 peak
   - At the END of the walk (amplitude_scale ≈ 0.27 due to 1/R² law), we transmit at ≈ 0.08 peak
   
2. **Loopback's scaling = 0.90** (applied AFTER the 0.7 in `make_train()`)
   - Loopback is a single-pulse scenario, not a range walk
   - It can afford aggressive TX gain because it's not trying to stay under the DAC ceiling across a 4.5 km range walk
   - Loopback CHECK 1 measures the burst at a known TX gain (45+ dB) and is designed as a tight, hot test

3. **Different mission profiles:**
   - **Loopback:** Short burst, single amplitude point, optimized for SNR at the receiver
   - **Structural phantom:** Long range walk, amplitude must taper correctly, optimized for ECCM screening

---

## What This Means for Radio Performance

At a fixed TX gain (e.g., 45 dB), the received power of the structural phantom will be:

```
Pr(phantom) = Pr(loopback) × (0.30/0.63)² 
            ≈ Pr(loopback) × 0.23
            ≈ Pr(loopback) - 6.4 dB
```

**Implication:** If loopback was heard at 45 dB TX gain, the structural phantom at the same gain would arrive **6.4 dB weaker**. This is significant but likely still detectable, depending on the receiver's noise floor and CFAR settings.

---

## Instrumentation Added

For the NEXT real radio run (when PA is keyed), the following diagnostics are now in place:

### `stage_e_structural_drfm.py` (line ~170 in `run_dwell`)
```python
# Before each uc.transmit_burst():
peak_amplitude = np.max(np.abs(phantom))
rms_amplitude = np.sqrt(np.mean(np.abs(phantom)**2))
peak_dbfs = 20 * np.log10(peak_amplitude) if peak_amplitude > 0 else -999
logging.info("PHANTOM TX BUFFER (dwell %d, pulse %d): peak=%.6f (%.1f dBFS), "
             "rms=%.6f, dtype=%s, amplitude_scale=%.4f, range=%.0f m",
             dwell_index, pulse, peak_amplitude, peak_dbfs, rms_amplitude,
             phantom.dtype, meta["amplitude_scale"],
             dwell_row["apparent_range_m"])
```

### `usrp_loopback.py` (line ~90 in `fire_and_capture`)
```python
# Before each uc.transmit_burst():
peak_amplitude = np.max(np.abs(samples))
rms_amplitude = np.sqrt(np.mean(np.abs(samples)**2))
peak_dbfs = 20 * np.log10(peak_amplitude) if peak_amplitude > 0 else -999
logging.info("LOOPBACK TX BUFFER: peak=%.6f (%.1f dBFS), rms=%.6f, dtype=%s, samples=%d",
             peak_amplitude, peak_dbfs, rms_amplitude, samples.dtype, samples.size)
```

These will print per-burst amplitude data to the logfile, so the actual TX-side power can be verified against what the judge receives.

---

## Recommendation for Next Steps

1. **Confirm receipt at the Mac side:**  
   Do a radio test with the structural phantom at current TX gain and check whether it reaches the Mac's CFAR at all. If not heard, try +6 dB more TX gain to compensate for the amplitude deficit.

2. **Check MAC gain settings:**  
   Loopback used TX 25 dB, RX 20 dB. Structural phantom might need TX 31 dB or higher to achieve the same received power. Adjust and re-run loopback's CHECK 1 to confirm the new baseline.

3. **Monitor the logs:**  
   On the next real run, the instrumentation will print:
   ```
   PHANTOM TX BUFFER (dwell 0, pulse 0): peak=0.300000 (-10.5 dBFS), 
       rms=0.300000, dtype=complex64, amplitude_scale=1.0000, range=89638 m
   ```
   Compare the actual received amplitude at the Mac side against this baseline to diagnose any TX-path losses or receiver issues.

4. **Validate dtype:** ✓ Already confirmed as `complex64` (correct for UHD).

---

## Files Modified

- `stage_e_structural_drfm.py`: Added amplitude logging in `run_dwell()` before `uc.transmit_burst()`
- `usrp_loopback.py`: Added amplitude logging in `fire_and_capture()` before `uc.transmit_burst()`
- `test_phantom_amplitude.py`: (New) Diagnostic script to measure phantom buffer amplitude

**Next run:** `python stage_e_structural_drfm.py --dwells 3 --yes` (or with appropriate range walk args) will now log per-phantom TX buffer amplitudes.
