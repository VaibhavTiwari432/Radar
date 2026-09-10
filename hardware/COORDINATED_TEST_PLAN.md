# Coordinated Structural Phantom Test — Option C
**Date:** 2026-08-22  
**Modification:** `TX_PEAK_AMPLITUDE` 0.30 → 0.45 (+3.5 dB), plus TX gain +3 dB  
**Expected Result:** Structural phantom at loopback's received power level

---

## Amplitude Boost Summary

| Parameter | Old | New | Change | dBFS (old) | dBFS (new) |
|-----------|-----|-----|--------|-----------|-----------|
| TX_PEAK_AMPLITUDE | 0.30 | 0.45 | +50% | -10.5 | -6.9 |
| TX Gain (dB) | 45 | 48 | +3 | — | — |
| **Total Power Increase** | — | — | **+6.5 dB** | — | — |
| Loopback reference | 0.63 | — | — | -4.0 | — |
| Gap to loopback after boost | — | — | **−2.9 dB** | — | — |

**Physics:** Power ∝ amplitude². A 0.30→0.45 boost is a factor of 1.5 in amplitude = **1.5² = 2.25× in power = +3.5 dB**.  
Plus +3 dB TX gain = **+6.5 dB total**, closing the gap from -6.4 dB to near-zero.

---

## Code Change Verification

**File:** `stage_e_structural_drfm.py` line 83–95

```python
# OLD
TX_PEAK_AMPLITUDE = 0.30

# NEW  
TX_PEAK_AMPLITUDE = 0.45
# 22 Aug 2026: raised from 0.30 to 0.45 (+3.5 dB) to compensate for 6.4 dB
# deficit vs loopback burst. Paired with +2-3 dB TX gain increase = ~6 dB total.
# DAC headroom: 0.45 x 1.0 = 0.45 peak, well under 0.9 ceiling.
```

**Safety check:** Highest amplitude in the walk is amplitude_scale × TX_PEAK_AMPLITUDE = 1.0 × 0.45 = 0.45 peak, **still ≪ 0.9 DAC ceiling**. ✓ No clipping.

---

## Pre-Test Checklist

**Windows (Radio/DRFM side):**
- [ ] Verify code change: `grep "TX_PEAK_AMPLITUDE = 0.45" stage_e_structural_drfm.py`
- [ ] Set TX gain to **48 dB** (up from 45 dB)
- [ ] Set RX gain to **20 dB** (unchanged from loopback reference)
- [ ] Antennas on RF A TX/RX and RF B RX2 (if using loopback, else just RF A TX/RX)
- [ ] Run `python stage_e_structural_drfm.py --demo` to verify no errors
- [ ] Pick a dwell count and range walk. **Suggested:** `--dwells 5 --rate 500` (25 second walk)
- [ ] Note UTC start time (to nearest second)

**Mac (Radar/Judge side):**
- [ ] Radar is running and listening on 2.45 GHz
- [ ] Capture software ready (should start **5 seconds BEFORE** Windows transmits)
- [ ] Plan to capture for **70 seconds** (covers 5-dwell 10ms PRI walk + margin)
- [ ] Post-capture: run judge on the frame, look for confirmed tracks labeled "real"

---

## Synchronized Test Execution

### Step 1: Agree on UTC time
**Windows:** Pick a time like `16:30:00 UTC` on 22 Aug 2026 (or nearest even minute).  
**Send to Mac:** "I transmit starting 16:30:00 UTC, 5 dwell ≈ 24 seconds, TX 48 dB"

### Step 2: Mac starts capture (5 seconds early)
**Mac:** At `16:29:55 UTC`, start the capture command, let it run until `16:31:05 UTC` (70 seconds).

### Step 3: Windows transmits
**Windows:** Run at exactly `16:30:00 UTC`:
```bash
python stage_e_structural_drfm.py --dwells 5 --rate 500 --tx-gain 48 --yes
```

(If your setup doesn't support `--tx-gain` flag yet, manually set gain on USRP before running, then omit the flag.)

### Step 4: Windows logs diagnostics
Watch the console output. You should see:
```
[INFO] Emitting phantom on fixed schedule, dwell 0/5, range 89638 m, amplitude_scale 1.0000
PHANTOM TX BUFFER (dwell 0, pulse 0): peak=0.450000 (-6.9 dBFS), rms=0.450000, dtype=complex64, amplitude_scale=1.0000, range=89638 m
[INFO] Emitting phantom on fixed schedule, dwell 0/5, range 89638 m, amplitude_scale 0.9600...
...
```

**Key metric to verify:** First dwell's peak should show **-6.9 dBFS** (from 0.45 amplitude).

### Step 5: Mac processes capture
Once capture is done:
```bash
# Load the captured frame and run judge
judge_result = radar_judge_v2(capture_data)
# Look at: confirmed_tracks, labels (should see "real", not just "decoy" or "unscreened")
```

---

## Expected Outcome

### Before This Boost (for reference)
```
TX buffer:   0.30 peak (-10.5 dBFS)
TX gain:     45 dB
MF gain:     0.02–0.53 dB
Detected:    NO (below CFAR threshold)
Labeled:     (not applicable, not detected)
```

### After This Boost (target)
```
TX buffer:   0.45 peak (-6.9 dBFS)    ← NOW VISIBLE IN LOGS
TX gain:     48 dB
Expected MF gain:  should be at least 5 dB higher than before (6 dB boost)
Detected:    YES (should cross CFAR)
Labeled:     "real" or "decoy" (not "unscreened") — real detection/screening
```

**Success criteria:**
1. ✅ TX logs show `-6.9 dBFS` for the phantom
2. ✅ Mac's judge shows `confirmed_tracks ≥ 1` (detection happened)
3. ✅ Label is NOT "unscreened" (screening logic ran)
4. ✅ If label is "real" → **deception succeeded**; if "decoy" → **radar caught it**

Either outcome is progress: at least the phantom is now loud enough for the judge to *render a verdict* instead of drowning in noise.

---

## If Detection Still Fails

**Fallback troubleshooting:**

1. **Did TX amplitude actually change?**  
   Check Windows logs for `PHANTOM TX BUFFER: peak=0.450000 (-6.9 dBFS)`.  
   If it still shows `-10.5 dBFS`, the code change didn't take effect → reload/restart Python.

2. **Did TX gain actually change?**  
   Check USRP settings with `usrpctl`.  
   If it's still 45 dB, try manually setting it higher.

3. **Is the antenna connected?**  
   Loopback test (`usrp_loopback.py`) should hear its own burst. If that fails, antenna is the issue.

4. **Is Mac's gain set correctly?**  
   Loopback works at RX 20 dB. If Mac uses different gain, adjust or re-verify loopback works at that gain first.

---

## Logs and Post-Analysis

Both scripts now log TX buffer amplitudes:

**Windows logs** (from `stage_e_structural_drfm.py`):
```
PHANTOM TX BUFFER (dwell 0, pulse 0): peak=0.450000 (-6.9 dBFS), rms=0.450000, dtype=complex64, amplitude_scale=1.0000, range=89638 m
PHANTOM TX BUFFER (dwell 0, pulse 1): peak=0.450000 (-6.9 dBFS), rms=0.450000, dtype=complex64, amplitude_scale=1.0000, range=89638 m
...
```

**Loopback logs** (from `usrp_loopback.py`, if you re-run it with new gain):
```
LOOPBACK TX BUFFER: peak=0.630000 (-4.0 dBFS), rms=0.063000, dtype=complex64, samples=30000
```

**Compare post-run:**
```
Windows structural @ 48 dB: -6.9 dBFS
Loopback ref @ 48 dB:       -4.0 dBFS (should be slightly higher by 3 dB TX gain)
Difference:                 ~3 dB (expected)
```

---

## Final Checklist Before Transmission

- [ ] Code change merged and committed: `TX_PEAK_AMPLITUDE = 0.45`
- [ ] TX gain set to 48 dB
- [ ] RX gain set to 20 dB (or Mac's standard)
- [ ] Antennas connected and secured
- [ ] Run `--demo` once to confirm no errors
- [ ] UTC time agreed with Mac
- [ ] Mac will capture 5 seconds early, 70 seconds total
- [ ] Windows ready to run at exact UTC time
- [ ] Both sides have latest diagnostic logs enabled

---

## Command Ready to Run

Once pre-test checklist is complete:

```bash
# Windows, at agreed UTC time:
cd E:\Radar\hardware
python stage_e_structural_drfm.py --dwells 5 --rate 500 --yes
```

**Gain note:** If `--tx-gain` flag is not supported, set gain manually on USRP before running.

---

**Ready to execute?** Confirm UTC start time and we'll coordinate.
