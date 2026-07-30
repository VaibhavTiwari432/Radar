# TSMS-Drone — sample files (attribution + what actually transfers)

## Attribution (CC BY 4.0 — required)

> *Time-Synchronized Multi-Sensor Drone Dataset (TSMS-Drone)*, figshare+,
> DOI **10.25452/figshare.plus.30027313.v1**, published 2026-01-07.
> Licensed **CC BY 4.0** (https://creativecommons.org/licenses/by/4.0/).
> Companion paper: *A Time-Synchronized Multi-Sensor drone dataset acquired
> from multiple radars and RF receiver*, **Scientific Data**,
> https://www.nature.com/articles/s41597-026-06802-6

CC BY 4.0 permits redistribution **with attribution**. This folder holds only
the small example/sample files (~15.5 MB of 392.81 GB). All 8 were verified
against figshare's published MD5s at download time.

## What is here

| file | bytes | what it is |
|---|---|---|
| `FMCW_RawData.mat` | 15,428,525 | one raw FMCW IF capture + full processing config |
| `FMCW_Sample_Reconstruction_Code.m` | 2,931 | raw IF -> range-Doppler, two-stage FFT |
| `Example_FMCW_radar_processing.m` | 3,256 | loads a pre-made `RD` map from the full set |
| `Example_CW_radar_processing.m` | 3,508 | CW complex I/Q -> micro-Doppler spectrum |
| `Example_RF_Receiver_processing.m` | 2,445 | RF receiver path |
| `CNN_Training_Script.m` | 4,488 | authors' classifier |
| `Crop_Based_Image_Fusion.m` | 2,710 | multi-sensor fusion example |
| `RGB_Channel_Based_Image_Fusion.m` | 2,252 | multi-sensor fusion example |

## Measured configuration — read out of `FMCW_RawData.mat`, not from the paper

The sensor is an **Analog Devices / INRAS TinyRad** (the saved `Brd` object),
4 Rx channels. From `Cfg`:

| quantity | value |
|---|---|
| sweep | 24.000 -> 24.250 GHz (`fStrt`/`fStop`) |
| carrier | 24.125 GHz, lambda = **12.43 mm** |
| sweep bandwidth | 250 MHz |
| range resolution | c/2B = **0.600 m** |
| ramp up / period | 512 us / 600 us (`TRampUp`, `Perd`) |
| fast-time samples | N = 512 |
| chirps per frame | `FrmMeasSiz` = 64 |
| Rx channels | 4 (`Data` is [32768 x 4], **real** IF samples) |
| cropped range axis | 2.02 - 11.99 m, 134 bins |
| velocity axis | +-5.18 m/s |

## What transfers to this project, and what does not

**Does NOT transfer — do not quote these across.**

| | TSMS-Drone FMCW | this project |
|---|---|---|
| carrier | 24.125 GHz | 10 GHz |
| lambda | 12.43 mm | 30.0 mm |
| waveform | FMCW, 250 MHz sweep | LFM pulse, 2 MHz |
| range resolution | 0.600 m | 46.84 m |
| range | 2 - 30 m | 1800 - 3800 m |
| velocity | +-5.18 m/s | +-120 m/s |

The absolute link budget, the range cell and the Doppler scale are all
different. Any number carried across without conversion is wrong.

**DOES transfer — and this is why the set is worth having.**

1. **A corner reflector at known range is the control this project has never
   had.** The full set measures a **Corner Reflector** alongside four drones
   at the *same* 2-30 m stations, 500 repetitions each. A corner reflector has
   stable known RCS and no rotor modulation, so it isolates the
   amplitude-vs-range law and the receiver's own scintillation from target
   modulation. That is exactly the measurement
   `+engine/+entity/calibrateQ.m` documents it could not make -- it could only
   derive an amplitude **floor** (0.233 dB) from RadChar, which is an
   emitter's own pulse train with no target and no motion.

2. **Drone minus corner reflector = the micro-Doppler contribution**, measured
   rather than tuned. `+engine/+entity/render.m` currently carries a
   `ponytail:` comment admitting its blade-flash *shape* is not physically
   derived, and `micro_doppler_hz` is invented. Blade rates convert cleanly
   between bands (f_d proportional to 1/lambda, so a 24.125 GHz rate scales by
   12.43/30.0 = **0.414** to this project's 10 GHz).

3. **Four Rx channels means real angle data.** `DATASET_SURVEY.md` ranked the
   automotive sets as the only surveyed source with an angle channel; the
   TinyRad's 4-element receive array also gives azimuth. Relevant if the
   monopulse path in `+engine/+entity/render.m` is ever validated against
   measurement rather than against its own model.

## First measurement out of the sample — vs what this project assumes

Reconstructed the RD map from `FMCW_RawData.mat` (figure:
`results/figures/tsms_fmcw_sample_rd.png`). A hovering body sits at 8.09 m /
+0.01 m/s with a symmetric comb of **15 blade-flash sidebands** out to
+-4.55 m/s.

| quantity | MEASURED here | project's current value | ratio |
|---|---|---|---|
| modulation depth | **0.115** (-18.8 dB) | `render.m:90` `MICRO_DEPTH = 0.3` | project **2.6x too deep** |
| blade passage rate | **~104 Hz** | `test_vee_entity.m:133` `micro_doppler_hz = 400` | project **~3.8x too high** |
| blade-tip radial velocity | **4.55 m/s** | not modelled | — |
| Doppler extent @ 24.125 GHz | 732 Hz | — | — |
| Doppler extent scaled to 10 GHz | **303 Hz** | — | — |

**Watch the scaling rule -- two of these do NOT convert between bands.** Blade
passage rate and blade-tip velocity are MECHANICAL (set by RPM and rotor
radius), so they are carrier-independent: the same rotor emits lines 104 Hz
apart at 10 GHz just as at 24.125 GHz. Only the Doppler *extent* scales, via
f_d = 2v/lambda. Converting the 104 Hz line spacing by the lambda ratio would
be wrong.

**The model FORM is also wrong, not just the constants.** `render.m:187` applies
`1 + MICRO_DEPTH*cos(2*pi*microHz*slowT)` -- a single-tone amplitude
modulation, which produces exactly two sidebands. The measurement shows a
**comb of ~15 lines with 29% spacing scatter** (mean 0.645 m/s, std 0.185).
A single cosine cannot produce that.

**Honest limits of this number.** One capture, one unidentified target, one
range, one Rx channel; peak-count depends on the prominence threshold used.
Indicative, not definitive -- the full CW bundle (5 targets x 15 ranges x 500
repetitions) is what would actually pin these constants.

## Not downloaded, deliberately

* The **392.81 GB** bulk (85 files; ~5 GB per drone/distance `.7z`). Pull
  selectively, never wholesale.
* **`CW Radar.7z` (2.43 GB)** is the next sensible increment: the CW path is
  complex I/Q (`Example_CW_radar_processing.m` reads `data` as the I/Q vector,
  downsamples by 16 to 4096 Hz) and is the micro-Doppler source. Its carrier is
  **not** recorded in any file downloaded here -- read it from the paper or the
  bundle before using it.
* **DIAT-uSAT** (the 10 GHz set, an exact carrier match) is **email-request
  only, not open-licensed**. `DATASET_SURVEY.md` says plainly: do not script a
  download. It has not been fetched and must not be committed here.
