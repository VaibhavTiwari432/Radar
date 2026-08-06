# RadChar Three-Arm Judge Validation

**Task:** 5 (`PHASE2_COMPLETION_POA.md`) · **Date:** 24 July 2026 · **Test:**
`tests/test_radchar_three_arm.m` (re-runnable, committed)

**Dataset:** Kaggle `abcxyzi/radchar-icassp-2023`, `RadChar-Tiny.h5` (50,000
signals, 5 waveform classes × 10,000 each, SNR ∈ [-20, +20] dB). Loaded via
the project's own already-validated `+data/loadRadChar.m` — schema verified,
not assumed. N=5 pulses sampled per class (25 total), reproducible seed.

## Method (all three arms share identical kinematics: R0=1800m, v=-60 m/s
closing, 8 frames @ 1 Hz — this project's own canonical scene — so kinematics
never confounds the comparison; only the transmitted waveform differs)

- **Arm A (genuine):** the raw real RadChar pulse, used as-is, as if a real
  target genuinely reflected exactly this real-world waveform.
- **Arm B (phantom):** `features.characterizeInterceptDechirp` +
  `features.coherentReplica` run on the SAME real pulse (treated as the
  noisy intercept) — this project's actual feature-matched synthesis
  pipeline, exercised on real data for the first time.
- **Arm C (negative control):** structureless complex noise, no pulse at
  all (`Stage3_Test.m`'s own "noise almost never confirms" pattern, reused).

Every arm is run through the real, unmodified judge (`+radar` → `+track`,
`+engine/runJudge.m`), which always matched-filters against this project's
OWN fixed LFM template (12 µs / 2 MHz / 50 kHz PRF) — the judge never adapts
to the input's waveform class, by design (this project's radar is LFM-only;
see `cogengine/planner_cem.py`'s own `CEMConfig` comment).

## Results

| Class | N | Arm A (genuine) | Arm B (phantom) | Arm C (rejected) |
|---|---|---|---|---|
| Coherent pulse train | 5 | 0% | 100% | 100% |
| Barker | 5 | 20% | 80% | 100% |
| Polyphase Barker | 5 | 0% | 80% | 100% |
| Frank | 5 | 20% | 80% | 100% |
| **LFM** | 5 | **20%** | **80%** | 100% |

**No negative-control failures** (Arm C rejected 5/5 in every class — the
CFAR/tracker/ECCM chain never confirmed pure noise as a real track).

## Reading this table honestly (no cherry-picking, no hidden confound)

**Only the LFM row is a meaningful, non-confounded Arm A-vs-B comparison for
this project's radar.** `characterizeInterceptDechirp` is *intentionally*
designed (its own header comment, pre-dating this task) to default to
`wclass='lfm'` and reconstruct an LFM-shaped replica regardless of the true
input class — matching this project's "the mother drone knows the radar is
LFM-only" premise. So for Barker/Frank/coherent-pulse-train inputs, Arm B
isn't replicating THAT class's true waveform; it's substituting an LFM
chirp, which then naturally compresses well against this project's own
LFM-only matched filter. The near-uniform 80-100% across non-LFM classes is
that substitution working as designed, not a new capability being
validated — reported here for completeness (the mission's own "no
cherry-picking" rule), not as a believable-phantom result for those classes.

**Arm A's low rate (0-20%, all classes) is itself a reproduction of an
already-established finding, not a new problem.** Real RadChar pulses carry
their own embedded receiver noise (SNR spans the dataset's full -20..+20 dB
range); replaying one verbatim with no denoising is exactly the "a noisy
verbatim replay's raw matched-filter peak is a WORSE CFAR statistic than a
clean rebuild" finding `Integration_Report.md` already established with
synthetic noise. This is the first time it's been reproduced on **real**
receiver noise instead of synthetic Gaussian noise.

**The one honest, non-confounded headline number:** for LFM (the only class
this project's synthesis is actually designed to model), genuine confirms
20% of the time; the feature-matched phantom confirms 80% of the time — a
+60-point delta, reproducing this project's core thesis (feature-matched
synthesis beats verbatim replay under realistic noise) grounded in real
intercepted waveform data for the first time, not just synthetic chirps.

## Boundary statement (state this whenever these numbers are quoted)

**Waveform physics** (pulse shape, real receiver noise): from real RadChar
data. **Kinematics** (range/velocity trajectory over the engagement): from
this project's own synthetic truth model, unchanged — RadChar itself is
baseband with no ground-truth target motion (`data/README.md`'s own note:
"treat it as a realistic waveform source, not ground-truth ranges"). This is
not a validation against real target *tracks* — only against real
intercepted *pulses*.

## Re-run 25 July 2026 after the judge's Doppler tautology was removed

`+engine/runJudge.m` used to hand `track.discriminator` a "Doppler" series it
had computed as `diff(range)/dt`, which made the discriminator's
Doppler/range-rate sign screen true by construction — a free pass for every
confirmed track. That is fixed (see CLAUDE.md's "Judge fix" section). This
test was re-run unchanged: **every number in the table above is identical,
cell for cell.**

That is not luck, and the reason is checkable. This test builds its own 2-D
`rx_frames`, so the fix takes screen 2 from *always-pass* to *disabled*, and
the verdict falls entirely to the amplitude-range screen — which is decisive
on its own here, because `localRenderArm` applies an exact `(R0/Rk)^2`
amplitude law, so a detected track fits a slope right at the physical −2. The
0% cells were never failing their label; they were failing to be **detected**.

**The +60-point LFM Arm A-vs-B headline therefore stands, and now stands
without a tautological screen behind it.** Task 5 is the only published result
in this project the fix did not move.

## Honest limits, not fixed this pass

- Only N=5 pulses/class sampled (25 total) — a wider sweep (Task 3-style,
  more seeds/pulses) would tighten the confidence interval on each rate.
- Arm B's LFM-only substitution behavior for non-LFM classes is a known,
  by-design property, not something this task attempted to change (doing so
  would mean building a multi-waveform-class synthesis pipeline, out of
  scope for a project whose own premise is a single known LFM radar).
