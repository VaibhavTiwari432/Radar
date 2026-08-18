# Is the core mathematics sound? — 12 August 2026

**The USP under test:** *the engine computes closed-form numerics — a range
trajectory, the amplitude that trajectory implies, and the carrier phase that
trajectory implies — and those numerics are what make a radar read the
resulting signal as a real target.*

This file tests the **mathematics**, not the signal. The question is not "does
something get detected" but "does every quantity the generator DERIVES come
back out of an independent measurement as the quantity it intended."

**Re-runnable:** `tests/test_generator_math_roundtrip.m` (7/7) and
`generator/tests/test_physics_projection.py` (12/12). Every number below is
printed by those files.

---

## Why the result is not circular — the only reason it is worth reading

The writer and the reader share no code. This is CLAUDE.md Rule 2, enforced
mechanically by `tests/test_package_separation.m` and GOVERNANCE.md's one-way
rule, not by convention:

| | |
|---|---|
| **WRITER** | `generator/physics_projection.py` — `cv_trajectory`, `amplitude_trajectory`, `phase_progression_rad`. Pure Python, closed form. |
| **READER** | `+engine/runJudge.m` — matched filter → CA-CFAR → `trackerGNN` → a slow-time FFT (`+radar/rangeDoppler.m`) that recovers range-rate from the Doppler bin. Pure MATLAB, and it has never heard of the generator. |

**The reader is never told the range-rate, the RCS, or the amplitude law.** It
receives complex samples and re-derives everything it reports. So agreement is
a genuine cross-validation of the physics.

**Every tolerance below is the instrument's own resolution** — one range cell,
one velocity bin — not a fitted number.

---

## Law 0 — the two constant tables are one table

`c`, `fs`, `PRF` are *facts*, not model parameters either side may choose. If
they diverged, every round-trip below would be comparing two different radars.

| constant | `+physics/Constants.m` | `common/constants.py` | agree |
|---|---|---|---|
| c | 2.99792458e8 | 2.99792458e8 | ✅ |
| fs | 3.2e6 | 3.2e6 | ✅ |
| PRF | 8000 | 8000 | ✅ |
| pulse width | 1.2e-5 | 1.2e-5 | ✅ |
| bandwidth | 2e6 | 2e6 | ✅ |
| carrier | 1e10 | 1e10 | ✅ |
| range/sample | 46.8426 | 46.8426 | ✅ |
| λ | 0.0299792 | 0.0299792 | ✅ |

All eight to `RelTol 1e-12`.

---

## Laws 1–3 — the round trip, through the real judge

One phantom, 6000 m closing at −50 m/s, 24 frames × 32 pulses.

| # | law | derivation | intended | **measured by the judge** | instrument resolution |
|---|---|---|---|---|---|
| 1 | delay → range | τ = 2R/c | trajectory | **max err 22.58 m** | one range cell **46.84 m** |
| 2 | phase → Doppler → range-rate | f_d = −2Ṙ/λ | −50.000 m/s | **−48.716 m/s** | one velocity bin **3.747 m/s** |
| 3 | amplitude | A ∝ √σ/R² | slope −2 | **slope −2.0718** | fit noise at this lever arm |

Range lands inside **half** a range cell. Range-rate lands inside **a third**
of a velocity bin. The amplitude exponent is within **3.6%** of the two-way
radar equation's −2.

**Law 3's other half is exact, not statistical.** Quadrupling RCS raises
amplitude by exactly **×2.000000** (`RelTol 1e-12`), because A ∝ √σ. Checked
directly on `amplitude_trajectory`, where there is no pipeline noise to hide
behind.

### The sign in law 2 is load-bearing, and it has been wrong once

`phase_progression_rad`'s sign was originally the Blueprint's illustrative
convention — the **opposite** of `runJudge`'s `f_d = −2Ṙ/λ` — and a genuine
phantom scored `decoy` until Gate A caught it. A magnitude-only check would
have passed throughout. So both directions are asserted separately:

| intended | measured |
|---|---|
| −50 m/s | **−48.716 m/s** |
| +50 m/s | **+48.716 m/s** |

---

## The negative control — proving the test can fail

Everything above is only worth reading if it could have come out otherwise.
The same trajectory is rendered with the phase **negated** — the wrong
convention that shipped once — and the judge is asked again:

| | measured range-rate |
|---|---|
| correct phase | **−48.716 m/s** |
| negated phase | **+48.716 m/s** |

The sign flips. The judge is genuinely reading phase, so law 2 is a
measurement and not an artefact.

**One instructive failure on the way to this control, kept because it is a
real property of the instrument.** The obvious implementation — conjugating
`rx_frames` — flips f_d *and* turns the up-chirp into a down-chirp, costing
the matched filter 14.2 dB (`tests/test_generator_agility.m`) and losing the
target entirely: `confirmed_tracks` went to **0**, leaving nothing to measure.
The flip has to be applied to the **pre-render plan**, so only
`phase_progression_rad`'s output changes and the waveform does not — which is
also exactly the shape of the original bug.

---

## Law 4 — the vetoes are arithmetic, not opinion

| veto | closed form | value | matches |
|---|---|---|---|
| eclipse (blind range) | c·PW/2 | **1798.75 m** | ✅ `RelTol 1e-12` |
| range ambiguity | c/(2·PRF) | **18737.03 m** | ✅ `RelTol 1e-12` |
| causality | R_phantom ≥ R_mother + c·τ/2 | — | ✅ |
| **velocity ambiguity** (added 12 Aug) | λ·PRF/4 | **59.9585 m/s** | ✅ `RelTol 1e-12` |

The fourth veto is the only one that is not a constraint on range, and it is
the one that was missing. Past R_ua a phantom merely **folds** to the wrong
range; past v_ua its Doppler **flips sign**, so it presents as range-closing
and Doppler-opening — the exact RGPO/VGPO signature screen 2 exists to catch.

**And each is exercised from the illegal side**, because a constraint that
never fires is indistinguishable from one that is not wired: a phantom inside
the blind range, one beyond R_ua, and one nearer than the mother platform are
each **refused**, not clamped.

---

## What this does and does not establish

**Established.** The chain from an action to a rendered signal is
mathematically consistent end to end, and consistent *with the judge's own
independently-derived measurement* of every quantity in it. The amplitude law
is the two-way radar equation, the phase is the analytic consequence of the
range trajectory in the judge's own Doppler convention, and the three
feasibility vetoes are the closed-form physical limits they claim to be. The
generator cannot express a phantom whose range and Doppler disagree — that
object is not representable, which is why `test_judge_measured_doppler` has to
hand-build one to have an adversary to screen against.

**Not established, and stated plainly.**

- **This is a consistency proof, not a realism proof.** It shows the numerics
  are internally right and are read back correctly. It does not show a real
  radar would be fooled — no result in this project does, and
  `CLAIMABLE_RESULTS.md` is the ledger for what is claimable.
- **Kinematics remain synthetic.** RadChar grounds the waveform physics; it
  carries no target motion, so the CV trajectory is this project's own model
  (`data/DATASET_SURVEY.md`).
- ~~**Two capabilities are absent from the rebuilt generator**~~ — **half of
  this is now CLOSED (12 Aug 2026).** **Swerling target fluctuation is built**
  (`physics_projection.swerling_rcs_factor` / `apply_swerling`, 17/17 in
  `generator/tests/test_swerling.py`, closed forms measured at 5.53 dB against
  5.571 predicted and 3.54 against 3.487). Amplitude *variance* is therefore in
  reach, and `tests/test_swerling_scale.m` is un-skipped at 3/3. **Micro-Doppler
  remains absent** — no blade-comb rendering anywhere in the rebuild — so
  `tests/test_drone_models.m` stays Class C, as does one method of
  `tests/test_amplitude_residual_screen.m` until it is re-pointed at the new
  fluctuation path.
- ~~**The generator has no v_ua veto**~~ — **CLOSED the same day.** Found while
  rewiring `tests/test_trajectory_envelope_audit.m`: `project_action`'s three
  vetoes all constrained **range**, and nothing checked `range_rate_mps`
  against v_ua = λ·PRF/4 = **59.958 m/s**. Measured consequence: a genuine
  −60 m/s target folds to **+59.96 m/s**, contradicts its own range walk, and
  the judge labels it **`decoy`** — the generator condemning itself with its
  own action space. Law 4 now has a **fourth veto**, refusing at and past the
  bound (`velocity_ambiguity_veto`, 10/10). See `trash/BROKEN_DOWNSTREAM.md`.
- **The monopulse wall is untouched by any of this.** Getting the mathematics
  right does not buy angle survivability — it puts the phantom at a genuine
  target's SNR, which is where monopulse works best (`PHASE_B_RESULTS.md`
  F2/F3, reproduced through the HTTP API on 12 Aug).
