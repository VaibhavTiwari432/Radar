# Hardware bring-up — what the B210 actually does, and what it cannot yet claim

**18 August 2026**, branch `tier0-tier1-corrections`, commit `5e745036`. Every
number below was measured this date on a real USRP B210 (serial `32BBA63`) or is
labelled as a dry run. Raw output: `hardware/logs/` (git-ignored, per this
project's `results/*` convention).

This is the **drone/transmitter** half. The ground radar is an independent judge
on a separate machine; nothing here imports its code, reads its thresholds, or
scores itself — the same `+synth`-vs-`+radar` separation CLAUDE.md Rule 2
enforces in simulation, now physical.

---

## 0. State

| | |
|---|---|
| Board | USRP B210, serial `32BBA63`, `type=b200`, `product=B210` |
| Bus | USB 3.0 root hub, AMD USB 3.10 eXtensible Host Controller, no dock |
| Driver | `erllc_uhd_b200.inf` → `oem116.inf`, class `USRPs`, service `WINUSB` |
| UHD | 4.10.0.0-release, MSVC 1944, Boost 108500 |
| Python | 3.12.10 venv, numpy 1.26.4 |
| RX chain | **PASS** — 3/3 frames, ch1 RX2, 2450.000 MHz, 1.000 Msps, 30 dB |
| TX chain | **never keyed** — no antenna fitted, `usrp_test_tx_only.py` not run |
| Intercept | **never demonstrated** — no radar has been heard |

---

## 1. The RX chain works

`usrp_test_rx_only.py`, two runs, no transmission at any point.

```
[RX ] ch1 RX2  2450.000 MHz  1.000 Msps  30 dB
frame 1/3: 2000 samples, SNR 11.1 dB, peak 0.0009, mean power -70.3 dBFS
frame 2/3: 2000 samples, SNR  9.7 dB, peak 0.0008, mean power -70.4 dBFS
frame 3/3: 2000 samples, SNR 10.9 dB, peak 0.0009, mean power -70.6 dBFS
TEST 1 PASS
```

Full chain confirmed: driver → firmware (`usrp_b200_fw.hex`) → FPGA
(`usrp_b210_fpga.bin`) → CODEC → register loopback → RX stream → 2000-sample
frames, 3/3 and 2/2 captured with zero errors.

**Read those numbers as a noise floor, not a detection.** Peak `0.0009` and
`−70 dBFS` are thermal noise; nothing was heard, and nothing was expected to be.
The SNR figure does not contradict that — see §4.3.

**The link negotiated USB 2, not USB 3.** UHD reported `[B200] Operating over
USB 2` despite a USB 3.0 root hub, so the cable is USB-2-only. Harmless at
1 Msps (~4 MB/s needed against ~35 MB/s available) and it does not affect any
number here, but it caps the achievable sample rate and must be fixed before
raising `fs`. The test's own PASS line claims "USB 3.0 link"; it does not check,
and here it is wrong.

---

## 2. The toolchain, and why it is not negotiable

Two findings that cost the most time, recorded so they are never rediscovered.

**2.1 `pip install uhd` does not install UHD.** The wheel ships `libpyuhd.pyd`
and nothing else — no `uhd.dll`, no WinUSB INF, no FPGA image. A bare
`import uhd` therefore *succeeds while `uhd.find` does not exist*, which makes a
successful import worthless as evidence. `uhd.dll` and the images come from the
Ettus Win64 installer, which must match the wheel's version exactly (4.10.0.0
here). The installer also ships the WinUSB INFs but does **not** bind them:

```
pnputil /add-driver "C:\Program Files\UHD\share\uhd\usbdriver\erllc_uhd_b200.inf" /install
```

then replug — Windows only matches drivers at enumeration, so a device already
at Code 28 will not re-bind on its own. Zadig is not needed.

**2.2 Python 3.13 cannot run this at all.** `libpyuhd` is compiled against
NumPy 1.x:

```
A module that was compiled using NumPy 1.x cannot be run in NumPy 2.3.5
```

NumPy 1.26.4 publishes no cp313 wheel, so there is no fix on 3.13 — not a
preference, a dead end. 3.12 is the newest Python with both halves available,
and a cp312 `uhd` wheel exists. Measured: 3.13 + numpy 2.3.5 errors on import;
3.12 + numpy 1.26.4 imports clean and `uhd.find` returns the board.

---

## 3. Consistency — the radio now uses the simulation's own physics

`hardware/consistent_plan.py` calls `generator/physics_projection.py`'s
`project_action()`. It does not reimplement it.

**What was wrong before.** `structural_generator` takes delay, amplitude and
phase as three **independent** arguments, and the payload fed it three hardcoded
lists: delays `[100,200,300]`, amplitudes `[0.5,0.3,0.2]`, random phase. That is
the per-frame-knob design `physics_projection.py` exists to replace, and it
fails by construction on every screen that matters — hand-set amplitude does not
obey 1/R², random phase bears no relation to range, and nothing checked the
claimed range was reachable at all.

**What holds now.** Delay, amplitude and phase all descend from **one range
trajectory**, which is the exact property `DECEPTION_MAP_RESULTS.md`'s
single-phantom result rests on. Dry run, phantom at 2200 m closing at 35 m/s,
drone at 900 m:

```
delays      [9, 8, 8, 7] samples          <- closing
amplitudes  [0.4091, 0.4364, 0.4666, 0.5] <- brightening, DERIVED from 1/R^2
```

**What deliberately does not cross over.** λ is the **hardware** wavelength
(c / 2.45 GHz = 0.1224 m), never the sim's X-band `C.carrier = 10 GHz` — using
the sim's would put the Doppler out by 4×. Absolute amplitude does not cross
either: `sim_amplitude_for_range` is calibrated to the simulation's
`noise_amplitude = 0.05` convention, and the B210 has no absolute power
reference in this setup. Only the 1/R² **shape** and the inter-phantom **ratio**
are claimed.

---

## 4. Three constraints the integration surfaced

### 4.1 OPEN — latency binds, and this payload fails it

`R_min = R_mother + c·τ/2`. The drone's own processing latency sets a hard floor
on how near a phantom can be claimed:

| latency | closest claimable range (drone at 900 m) |
|---|---|
| 1 µs | 1 049.9 m |
| 10 µs | 2 399.0 m |
| 1 ms | **150 796.2 m** |

On the real configuration the payload **refuses to transmit**:

```
[PLAN] latency 1000.0 us -> closest claimable range 150796.2 m
ERROR  Physics Projection VETOED this phantom: causality violated: apparent
       range would be 148701.2 m closer than physically receivable
```

Measured generate→transmit latency, per iteration: **0.299, 0.184, 0.185,
0.168 ms**. Against a 1 µs budget that is 25–45 km of physical inconsistency,
which the payload now reports per iteration rather than hiding.

**This is a lower bound.** Those timings were taken in `--dry-run`, where RX is
synthetic; a real capture adds more. A software listen→generate→transmit loop
cannot place a causally-consistent phantom at tactical range. **Closing this
needs FPGA-side retransmission, not more Python** — it is not a tuning problem,
because 1 µs buys 150 m and 1 ms buys 150 km.

`min_latency_s` therefore has **no default anywhere**. `causality_veto` calls it
"an ASSUMED design input — cite your hardware budget when you set it", and a
silent wrong guess moves every phantom.

### 4.2 Range quantisation freezes slow geometries

One delay sample is **149.9 m** at 1 Msps. A phantom closing at 35 m/s covers
28 m over 8 frames at 0.1 s — under a fifth of one bin. Its apparent range sits
frozen while its phase keeps advancing: "moving in Doppler, static in range",
precisely the disagreement discriminator screen 2 exists to catch. `build_plans`
now warns rather than emitting it silently. Fixes are a higher `fs`, a longer
plan, or fractional-delay resampling; the resampler is **not** built.

### 4.3 The RX test's SNR guard could never fire

`estimate_snr_db` reports the **crest factor of noise** when no pulse is
present — measured 9.7–11.1 dB over 2000-sample frames with nothing
transmitting — while the guard tested `snr <= 0`, a condition unreachable in
practice. At the bench that reads as "receiver hears the radar" when it hears
nothing. Now tested against a measured `NOISE_ONLY_SNR_DB = 15.0`:

```
WARNING  SNR 9.9 dB is at the noise-only floor (<= 15.0 dB): the RX chain
         works but NOTHING is being heard.
```

---

## 5. Boundaries

Each changes how a number above may be quoted.

* **No transmission has occurred.** The TX chain is configured but has never
  been keyed, no antenna is fitted, and `usrp_test_tx_only.py` has not been run.
  Every TX figure in §3 and §4.1 is from `--dry-run`, where TX is discarded.
* **No radar has been heard.** The intercept path is unproven end to end. Until
  SNR rises decisively above 15 dB with a radar transmitting, the receiver is
  demonstrated only against thermal noise.
* **`tx_power_dbm` in the CSV is dBFS**, not calibrated dBm. Column name kept
  for schema compatibility; the B210 has no absolute power reference here and
  antenna/cable losses are unmeasured.
* **The hardware and simulation radars are not the same radar.** Payload runs at
  fs = 1 MHz, 2.45 GHz, 2000-sample frames; the simulation runs fs = 3.2 MHz,
  PRF = 8 kHz, 10 GHz. Range-per-sample is 149.9 m here against 46.8 m there.
  **No number from `DECEPTION_MAP_RESULTS.md` transfers to this bench**, and the
  Mac's true sample rate and PRI are still unconfirmed.
* **One B210 is a single-bearing emitter.** Every phantom it radiates leaves one
  physical antenna, which is the co-bearing case this project's own results call
  fatal — 0 survivors at N = 2, 4 and 8. The hardware demo can only demonstrate
  deception against a **single-aperture** ground radar (§4.2 of the deception
  map: 8/8 phantoms survive at 100%). State this before someone asks.
* **Station-keeping is assumed.** The radiated phase is the phantom's own
  progression, correct only while the drone's range to the radar is constant.
  A manoeuvring drone must have its own phase progression subtracted first.

---

## 6. Reproduce

```powershell
# toolchain (once)
winget install --id Python.Python.3.12 -e --scope user
& "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" -m venv E:\Radar\hardware\.venv312
$vpy = 'E:\Radar\hardware\.venv312\Scripts\python.exe'
& $vpy -m pip install "numpy==1.26.4" "scipy>=1.10"
& $vpy -m pip install --only-binary=:all: --no-deps uhd==4.10.0.0
# then the Ettus UHD 4.10.0.0 Win64 installer, and (admin):
pnputil /add-driver "C:\Program Files\UHD\share\uhd\usbdriver\erllc_uhd_b200.inf" /install

# checks that need no radio
& $vpy E:\Radar\hardware\structural_generator.py
& $vpy E:\Radar\hardware\consistent_plan.py

# the board
& $vpy -c "import uhd; print(uhd.find(''))"
& $vpy E:\Radar\hardware\usrp_test_rx_only.py --frames 3

# the loop, offline
& $vpy E:\Radar\hardware\usrp_drone_payload.py --dry-run --consistent --iterations 4 `
       --latency 1e-6 --frame-period 2.0
```

---

## Bottom line

The drone's receiver end works, and what it would radiate is now physically
consistent in the same sense the simulation means — delay, amplitude and phase
derived from one range trajectory, through the simulation's own Physics
Projection rather than a copy of it.

Two things stand between this and a demonstration, and neither is a bug:

1. **Nothing has been transmitted or intercepted.** The bench has never had a
   radar on the other end.
2. **A software loop cannot satisfy causality at tactical range.** 0.17–0.30 ms
   of measured latency puts the nearest honest phantom 150 km out. The payload
   correctly refuses to transmit rather than radiating a phantom that claims a
   range no repeater could produce — which is the right failure, and the reason
   the next step is FPGA-side retransmission rather than more Python.
