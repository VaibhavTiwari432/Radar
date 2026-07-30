# Real radar dataset survey — what could close this project's data gaps

**Date:** 25 July 2026. **Why this exists:** RadChar (already in use,
`data/README.md`) grounds **waveform physics only**. Its own boundary
statement — repeated in `cogengine/results/radchar_analysis.md` and Task 5 —
is that **kinematics remain synthetic**, because RadChar is the *emitter's own*
baseband pulse train with no target, no target return, and no motion. Two
consequences this project has been carrying:

1. Every range/velocity trajectory in every result is from the project's own
   truth model. Nothing has ever been validated against a real target track.
2. `+engine/+entity/calibrateQ.m` could measure only an amplitude **floor**
   (0.233 dB) from RadChar, and had to take kinematic Q from a stated
   assumption (0.05 g) rather than from data.

The survey below is aimed squarely at those two gaps, plus the micro-Doppler
observable `+engine/+entity/render.m` emits but has never checked against
reality.

---

## Best matches for this project, ranked

### 1. TSMS-Drone — time-synchronized CW + FMCW radar + RF, raw I/Q *and* range-Doppler maps

Three heterogeneous sensors (CW radar, FMCW radar, RF receiver), time-aligned,
five target types (four commercial drones plus one non-drone control), at
**controlled ground-truth ranges from 2 m to 30 m in 2 m steps** with repeated
trials. Ships **unprocessed raw I/Q and range-Doppler maps**, explicitly so
users can apply their own signal processing.

- **What it closes:** this is the only dataset found that pairs *real* raw
  radar returns with *known* target range — i.e. the exact thing needed to stop
  saying "kinematics are synthetic". It would let `calibrateQ` derive a real
  amplitude-vs-range law and real scintillation from measured target returns
  rather than from an emitter's own stable pulse train.
- **Mismatch to be honest about:** CW/FMCW at 2–30 m is a short-range sensing
  geometry, not an X-band pulse-Doppler air-defence engagement at 1–5 km. The
  *statistics* (scintillation, range-amplitude behaviour, micro-Doppler) are
  transferable; the absolute link budget is not.
- **Access:** figshare, open. `https://plus.figshare.com/articles/dataset/Time-Synchronized_Multi-Sensor_Drone_Dataset_TSMS-Drone_/30027313`

### 2. DIAT-µSAT — X-band 10 GHz measured drone micro-Doppler

4,849 micro-Doppler signature records from an **X-band (10 GHz) CW radar**,
covering RC planes, rotors, quadcopters, bionic birds and mini-helicopters,
with rotor speeds 200–1740 RPM and flapping rates 2–4 Hz.

- **Why it is the sharpest match on paper:** 10 GHz is *exactly* this project's
  carrier (`test_vee_entity.m`'s `CARRIER = 10e9`, every cogengine fixture's
  `carrier_hz`). And micro-Doppler is the one observable `render.m` emits from
  entity class that has **never been validated against real data** — the VEE
  currently models blade flash as a tuned shallow modulation with a
  `ponytail:` comment admitting the flash *shape* is not physically derived.
  Real rotor RPM ranges would also replace the invented `micro_doppler_hz`.
- **Catch:** the headline release is micro-Doppler **signature images**, not
  raw I/Q. Raw `.mat` access is by email request to the DIAT authors for
  educational use — **not an open licence**, so it cannot simply be committed
  or scripted into CI the way RadChar was.
- **Access:** `https://ieee-dataport.org/documents/diat-msat-micro-doppler-signature-dataset-small-unmanned-aerial-vehicle-suav`

### 3. Millimeter-wave 60 GHz radar measurements: UAS and birds — open access

Open-access on IEEE DataPort, drones vs birds. Useful as a **discrimination**
control (the classic "is it a drone or a bird" problem is the real-world
analogue of this project's "is it a target or a phantom"), but 60 GHz is four
octaves off this project's band.

### 4. Automotive range-azimuth-Doppler sets — CARRADA, RADDet, RaDelft

FMCW automotive radar with **annotated range-angle AND range-Doppler**
representations of real moving cars, pedestrians and cyclists.

- **Why they matter here specifically:** these are the only surveyed sets with a
  real **angle** channel. `RADAR_REALISM_AUDIT.md` §1.1 identifies the total
  absence of angle as this project's single biggest realism gap — the one that
  makes the deception result "true of a range-only radar". If an angle channel
  is ever built, these are where real range-azimuth-Doppler statistics come
  from.
- **Mismatch:** automotive FMCW, ~77 GHz, ground targets, tens of metres.
  Structure transfers; physics does not.
- Curated index of these and others:
  `https://github.com/ZHOUYI1023/awesome-radar-perception`

---

## The gap nothing fills: there is no public DRFM/ECM benchmark

Searched specifically for a deceptive-jamming / DRFM false-target benchmark.
**None exists publicly.** The literature on DRFM jamming recognition
(multi-pulse fusion, STFT + CNN classifiers, MIMO anti-jamming) uniformly
builds and evaluates on **its own simulated jamming datasets**; no standardised
public corpus of real DRFM false targets was found.

This is worth stating plainly rather than treating as a failed search:
**this project's reliance on simulated ECM is the field norm, not a shortcut
peculiar to it.** It also means the honest ceiling on validation is
"real waveforms + real target statistics, synthetic deception" — which is
already where Task 5's boundary statement sits.

---

## Recommended use, in order

1. **TSMS-Drone → `calibrateQ`.** Replace the RadChar-derived amplitude *floor*
   with real target-return scintillation and a measured amplitude-vs-range
   trend. This is the first time kinematically-grounded numbers could enter the
   VEE at all, and it directly attacks `calibrateQ`'s documented
   "NOT grounded, and it cannot be" section.
2. **DIAT-µSAT → micro-Doppler validation.** Replace `render.m`'s tuned
   `MICRO_DEPTH` and invented blade rates with measured rotor signatures at
   this project's own carrier frequency. Requires an email licence request
   first — do not script a download.
3. **CARRADA/RADDet → only if an angle channel is built.** No value until then.
4. **Keep RadChar for what it is good at** — waveform physics — and keep
   quoting its boundary statement unchanged.

**Licensing note:** RadChar's credentials already live outside the repo
(`~/.kaggle/kaggle.json`, never committed). DIAT-µSAT is *not* open-licensed
and must not be redistributed inside this repo; TSMS-Drone and the IEEE
DataPort open-access sets should still have their licence terms read before any
file is committed rather than downloaded on demand.
