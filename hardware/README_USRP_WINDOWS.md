# USRP B210 drone payload — Windows side

Team HAC-2026-1166. This folder is the **drone/transmitter** half of the
hardware demo: it listens for the ground radar's pulse, builds phantom
targets from it, and transmits them back.

The ground radar (Mac, MATLAB) is an **independent judge**. Nothing here
imports its code, reads its thresholds, or scores itself — the only channel
between the two sides is real RF over the air. That is the same
`+synth`-vs-`+radar` separation the simulation enforces (`CLAUDE.md` Rule 2),
now made physical.

```
hardware/
  usrp_common.py            device discovery, streams, logging, measurements
  structural_generator.py   the phantom generator (DRFM repeat-back) + self-check
  usrp_test_rx_only.py      TEST 1 — receive only, no transmission
  usrp_test_tx_only.py      TEST 2 — transmit a dummy chirp
  usrp_drone_payload.py     TEST 3 — the listen → generate → transmit loop
  requirements.txt
  logs/                     created on first run: .log and .csv files
```

---

## 1. Install

### 1.1 Python packages

```powershell
cd E:\Radar\hardware
pip install -r requirements.txt
```

### 1.2 UHD (the USRP driver + Python bindings)

Two halves, and they must be the **same version** (4.10.0.0 here):

* the **Python bindings** (`libpyuhd.pyd`) come from the pip wheel, built for
  your exact Python (cp313 for Python 3.13);
* `uhd.dll` and the B210 FPGA images come from the Ettus binary installer.

The wheel does **not** ship `uhd.dll`, and the installer's own bindings are
built for whatever Python Ettus chose — usually not yours. Take one half from
each; do not put the installer's `lib\site-packages` on `PYTHONPATH`, it will
collide with the wheel.

1. Bindings — **in a Python 3.12 venv, not system Python 3.13.**

   ```powershell
   winget install --id Python.Python.3.12 -e --scope user
   & "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" -m venv E:\Radar\hardware\.venv312
   $vpy = 'E:\Radar\hardware\.venv312\Scripts\python.exe'
   & $vpy -m pip install "numpy==1.26.4" "scipy>=1.10"
   & $vpy -m pip install --only-binary=:all: --no-deps uhd==4.10.0.0
   ```

   The 3.12 venv is **required, not a preference.** `libpyuhd` is compiled
   against NumPy 1.x; under Python 3.13 the only installable NumPy is 2.x and
   the import fails with *"A module that was compiled using NumPy 1.x cannot
   be run in NumPy 2.3.5"*. NumPy 1.26.4 publishes no cp313 wheel, so there is
   no fix on 3.13 — 3.12 is the newest Python with both halves available.
   Measured 18 Aug 2026: 3.13 + numpy 2.3.5 errors on import; 3.12 +
   numpy 1.26.4 imports clean and `uhd.find` works.

   `--no-deps` is still needed: the wheel's `numpy<2.0` pin is correct but
   pip resolves it badly here.

   **Run every script in this folder with `.venv312\Scripts\python.exe`**,
   never a bare `python`.

2. Driver + images: download the **Win64** installer whose version matches the
   wheel from <https://files.ettus.com/binaries/uhd/> (folder
   `uhd_004.010.000.000-release`, file named like
   `uhd_4.10.0.0-release_Win64_VS2022.exe`) and run it. It installs to
   `C:\Program Files\UHD` and sets `UHD_PKG_PATH`, which is how `import uhd`
   finds `uhd.dll`. The installer bundles the B210 FPGA image, so
   `uhd_images_downloader` is not needed.

3. Verify — a clean import prints no DLL warning, and `find` lists the board:

   ```powershell
   python -c "import uhd; print(uhd.__version__); print(uhd.find(''))"
   ```

   `WARNING: Failed to add uhd.dll path to DLL search` means step 2 did not
   take: `uhd.dll` is missing, its version does not match the wheel, or
   `UHD_PKG_PATH` is unset in this shell (re-open PowerShell after installing).
   The module still imports in that state but `uhd.find` does not exist, so a
   bare `import uhd` succeeding proves nothing.

### 1.3 Windows USB driver

If Device Manager shows the B210 as an unknown device, install the WinUSB
driver for it with [Zadig](https://zadig.akeo.ie/): select the USRP device,
choose **WinUSB**, click *Replace Driver*.

---

## 2. Wiring — do this before any transmit

| Port | Use | Channel |
|---|---|---|
| **RF A · TX/RX** | transmit (antenna required) | 0 |
| **RF B · RX2** | receive | 1 |

Two separate ports so transmitting does not desensitise the receiver. **Never
transmit into a bare port** — fit an antenna or a 50 Ω load, or the PA can be
damaged. Every script that transmits asks you to confirm this first
(`--yes` skips the prompt; only use it once the bench is set up).

---

## 3. Serial number detection

You do not need to type the serial anywhere. Every script calls
`uhd.find("type=b200")` and reads the serial off the first board it finds. If
more than one B210 is attached, it logs all of them and uses the first:

```
2026-08-18 14:02:11 INFO    [INFO] Opened B210 serial=31ABCDE
```

To see it yourself: `uhd_find_devices`.

---

## 4. Running the tests, in order

### TEST 1 — receive only (safe, transmits nothing)

```powershell
python usrp_test_rx_only.py
python usrp_test_rx_only.py --frames 10 --save capture.npy
```

**Pass:** 2000 samples captured and an SNR printed.

```
[RX ] ch1 RX2  2450.000 MHz  1.000 Msps  30 dB
[RX ] frame 1/1: 2000 samples, SNR 18.4 dB, peak 0.1132, mean power -34.2 dBFS
[INFO] TEST 1 PASS - USB 3.0 link and RX chain are working.
```

An SNR at or below 0 dB means the link is fine but nothing is being heard —
expected if the ground radar is not transmitting. Re-run while it is.

### TEST 2 — transmit only (needs an antenna on RF A)

```powershell
python usrp_test_tx_only.py
python usrp_test_tx_only.py --bursts 5 --duration-ms 10
```

Sends a 100–500 kHz LFM chirp, 10 ms, raised-cosine ramped at both ends.
**Pass:** the burst is sent with zero underruns.

### TEST 3 — the payload loop

```powershell
python usrp_drone_payload.py                     # 5 iterations
python usrp_drone_payload.py --iterations 20
python usrp_drone_payload.py --mat plan.mat      # phantom plan from MATLAB
python usrp_drone_payload.py --dry-run           # no radio at all, see below
```

Each iteration: capture (1 s timeout) → generate → normalise to 0.8 peak →
transmit → one CSV row.

**`--dry-run` needs no hardware and no UHD.** It feeds the loop a synthetic
chirp-in-noise frame and discards the transmit, so you can check the
generator, normalisation, CSV and error paths on a laptop with no B210
attached. Its numbers are not measurements and the log says so.

---

## 5. The generator

`usrp_drone_payload.py` resolves a generator in this order:

1. `--mat plan.mat` — a MATLAB-exported phantom plan. Export it with
   `save('plan.mat','delays_samples','amplitudes','phases')`; `phases` is
   optional. The plan supplies the geometry, this side still cuts the samples
   from the pulse it just intercepted.
2. `structural_generator.py` in this folder (the default).
3. Neither → **test 3 skips with a message and exits 0.** Tests 1 and 2 do
   not need a generator and still run.

`structural_generator(captured_iq, n_targets, delays_samples, amplitudes,
phases)` returns an array the same length as its input, holding N delayed,
scaled, phase-rotated copies of the intercepted pulse. Because the copies are
cut from the radar's **own** transmitted pulse, they compress in the radar's
matched filter exactly as a genuine echo does — this side never needs to know
the waveform.

Physics it enforces (mirroring `generator/physics_projection.py`'s
`causality_veto`):

* **Delay ≥ 0.** A repeater only ever *adds* path length, so a phantom can
  never appear closer than the platform carrying the repeater.
* **Range per sample = c/(2·fs) = 149.9 m** at fs = 1 MHz. The default plan
  `[100, 200, 300]` samples is three phantoms about 15, 30 and 45 km beyond
  this platform. Pick delays to suit the range scale you actually want.

Check it without hardware:

```powershell
python structural_generator.py
```

---

## 6. Output

Logs and CSVs land in `hardware/logs/`, timestamped per run.

CSV columns (one row per iteration, flushed immediately so Ctrl-C keeps the
data):

| Column | Meaning |
|---|---|
| `timestamp` | ISO-8601, local time |
| `iteration` | 1-based loop index |
| `rx_samples` | samples actually captured (< 2000 means a short capture) |
| `rx_snr_db` | peak-to-noise-floor estimate, dB |
| `tx_samples` | samples accepted by the transmitter |
| `generator_status` | `python`, `mat:<file>`, `skipped_rx`, `generator_error`, `buffer_mismatch` |
| `tx_power_dbm` | **mean power in dBFS, not calibrated dBm** — see below |
| `tx_underruns` | underruns reported by the FPGA for that burst |
| `norm_scale` | the factor applied to reach a 0.8 peak |
| `note` | free text for whatever went wrong |

---

## 7. What these numbers are, and are not

Stated up front so nobody quotes them as more than they are:

* **`tx_power_dbm` is dBFS.** The column keeps that name for schema
  compatibility, but the B210 has no absolute power reference in this setup
  and the antenna/cable losses are unmeasured. It is mean power relative to
  full scale (|x| = 1). Calibrating it needs a power meter in the line.
* **`rx_snr_db` is an estimate**, peak power over the median-power noise
  floor. With no pulse present it reports the crest factor of noise (a few
  dB), not 0 dB.
* **The hardware is not the simulation.** Different band, different sample
  rate, therefore a different range scale:

  | | Simulation | This hardware |
  |---|---|---|
  | Carrier | 10 GHz | 2.45 GHz (ISM) |
  | Sample rate | 3.2 MHz | 1 MHz |
  | Range per sample | 46.84 m | 149.9 m |

  A phantom delay of *N* samples means a different apparent range on each
  side. Do not carry a delay value across without converting it.
* **Timing is software-paced.** The listen→generate→transmit turnaround is
  a Python loop over USB, so it lands in the 1–10 ms range, not the 125 µs a
  real DRFM achieves. The ground radar's PRF must be relaxed to match.

---

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `The 'uhd' Python module is not installed` | §1.2 — install UHD and put its `site-packages` on `PYTHONPATH`. |
| `No USRP B210 found` | Blue (USB 3.0) port, powered board, WinUSB driver (§1.3). Cross-check with `uhd_find_devices`. |
| `timeout waiting for samples` every iteration | The ground radar is not being heard: check the RX2 antenna on RF B and that the Mac is transmitting at 2.450 GHz. Raise `RX_GAIN` in `usrp_common.py`. |
| `[RX ] overflow` | The host fell behind. Close other USB traffic, use USB 3.0, set the Windows power plan to High Performance. |
| `[TX ] UNDERRUN` | Same causes as overflow. Also try a shorter burst (`--duration-ms 5`). |
| `[RX ] ADC near saturation` | Too close to the radar, or `RX_GAIN` too high. Lower it. |
| `buffer_mismatch` in the CSV | The generator returned a different length than it was given. It must return exactly `len(captured_iq)` samples. |
| `Firmware/FPGA image not found` | Run `uhd_images_downloader` once with internet access. |
| Serial detected but `MultiUSRP` throws | Another process still holds the board (a stale Python or `uhd_usrp_probe`). Close it and re-plug. |

---

## 9. Changing the constants

All of them live at the top of `usrp_common.py`. They are matched to the Mac
MATLAB radar — **change one side without the other and the demo silently
stops working**, because the sample rates will not agree.

```python
RX_RATE = 1e6           TX_RATE = 1e6
CENTER_FREQ = 2.45e9    RX_GAIN = 30    TX_GAIN = 30
FRAME_SIZE = 2000       RX_TIMEOUT_SEC = 1.0
```
