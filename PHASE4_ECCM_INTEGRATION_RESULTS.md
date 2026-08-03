# Phase 4 — ECCM integration attempt: residual-variance as Screen 3

**2 August 2026.** Follow-on to `PHASE3_VALIDATION_AND_SCREENS_RESULTS.md`.

> ## OUTCOME: integrated, measured, and **left OFF by default** — with a reason.
>
> The screen works. It is correctly implemented, veto-only, guarded, and its
> threshold is derived rather than picked. It still flags this project's
> **genuine** reference target **10/10**, and that is not a screen fault: both
> genuine arms render with `swerling = 0`, i.e. a non-fluctuating target whose
> amplitude follows 1/R² *exactly*. Zero scintillation is precisely the
> servo-driven-repeater signature the veto exists to catch.
>
> **The screen is right about a scene that is wrong.** Enabling it requires
> first rendering genuine reference targets with real fluctuation — which
> changes every reference scene and moves every published ECCM number again.
> That is a deliberate decision, not a side effect of an integration.
>
> **Also, a correction to my own Phase 1.5 report** — `test_vee_deception_check`
> has been failing since Phase 1's velocity retarget and I reported it as
> fixed. Details at the end. It is not caused by anything in this phase.

---

## Six errors in the brief, verified against the code before acting

| brief says | actually | consequence if followed |
|---|---|---|
| `+track/eccmDiscriminator.m` | `+track/discriminator.m` | file does not exist |
| "Screen 1: angle" lives there | **no angle screen in it** (grep = 0); co-bearing is in `runJudge.m` because it is inherently multi-track | would have added a screen alongside one that isn't there |
| `log(A) - (-2)*log(R) + intercept` | sign error — should be `- (-2*log(R) + intercept)` | wrong residuals |
| `expected_var` from thermal noise | validated screen scores against `calibrateQ`'s **measured scintillation floor** (0.233 dB / 0.491 dB) | a different, unvalidated screen |
| `flag if score_residual > threshold` | **inverts the new capability** — servo-perfect has residual σ = **0.000**, i.e. LOW | one-sided `>` catches nothing slope didn't already |
| "flag if ANY screen exceeds its threshold" | existing rule is `mean(scores) > 0.5` | with slope passing 12 % of genuine at 8 frames, an OR rule flags **~88 % of genuine targets** — the opposite of Step 2's stated goal |

Test-path corrections: everything named `+engine/tests/...` is in `tests/`, and
`cogengine/tests/test_tradeoff_sweep.py` is `tests/test_tradeoff_sweep.m` (MATLAB).

---

## Implementation

`+track/discriminator.m`, Screen 4 (numbered after the three already there:
amplitude slope, Doppler sign, micro-Doppler comb). Ablation name `'residual'`.

**Veto-only, never a positive score.** This was measured, not assumed. A first
integration let a healthy residual contribute `+1` to the average, and the full
deception suite caught two failures in one run:

| arm | 2-screen baseline | residual as averaged score |
|---|---|---|
| A-genuine (passes) | 10/10 | **5/10** |
| B-vee-phantom | 10/10 | 5/10 |
| D-vee-phantom-**static** | 0/10 deceived | **7/10** — a decoy the old judge caught |
| flat-gain hole | 14/20 | **20/20** — widened |

Two design errors, both mine:

1. **A `+1` dilutes other screens' failures.** A screen intended to *add*
   capability must never be able to raise a score.
2. **It fired where it has no meaning.** This is a screen about the
   amplitude-**range** law. With range constant the fit is degenerate — the
   residual becomes amplitude scatter about its own mean, which says nothing
   about 1/R². Worse, screen 1 also contributes nothing there (its range guard
   fails, and its flat-amplitude branch doesn't fire on a scintillating
   return), so `scores = [1]` alone and a **static repeater scored a clean
   pass**.

Fixed: veto-only, and it inherits screen 1's own `range(R) > 1e-9` guard.

**The floor is derived per track, not picked.** A flat 0.15 dB false-vetoed
genuine targets — the measured genuine distribution has mean 0.227 dB but
**p5 = 0.133**, so 0.15 sits inside the real population's lower tail. The sample
standard deviation of a standard deviation is ≈ σ/√(2(N−1)), so a genuine track
can legitimately measure low by chance on a short dwell. Taking a 3σ lower bound:

```
floor(N) = SCINT_FLOOR_DB * max(0, 1 - 3/sqrt(2(N-1)))

  N =  8  ->  0.046 dB     N = 16  ->  0.105 dB     N = 32  ->  0.144 dB
```

It tightens as the track lengthens, which is correct, and at N ≤ 4 it goes to
zero — the veto disarms itself rather than guessing on a track too short to know
anything about.

**Rule 2 respected.** `SCINT_FLOOR_DB = 0.233` is the *judge's own* declared
constant with its provenance cited. It is **not** read from
`engine.entity.calibrateQ` — `+track` may not reference `+engine`
(`tests/test_package_separation.m`, which passes).

---

## Why it is off by default — the measurement

Veto-only and correctly guarded, the screen still produced:

```
arm                       confirmed      flagged       DECEIVED
A-genuine                     10/10        10/10           0/10  (  0%)
B-vee-phantom                 10/10        10/10           0/10  (  0%)
```

The genuine arm is vetoed every time. Cause, found by reading the scenes rather
than the screen:

```
tests/test_vee_deception_check.m:244   'class','fighter','rcs_dbsm',0,'swerling',0
tests/test_angle_channel.m:296         'swerling', 0, 'azimuth_rad', azs(i)
```

**`swerling = 0` is a non-fluctuating target.** Its amplitude follows 1/R²
exactly, so its residual scatter is ~0 — indistinguishable from a servo-driven
repeater, which is exactly what the veto is designed to catch. The screen is
behaving correctly on a physically unrealistic reference scene.

`+track/discriminator.m`'s default mask is therefore
`{'amplitude','doppler','micro'}` — the screen is implemented, documented and
tested, and enabling it is one word (`'residual'` in `screensEnabled`). It is
not deleted, because the capability is real and the blocker is external to it.

**Prerequisite for enabling:** render genuine reference targets with
`swerling >= 1`. That changes every reference scene and every published ECCM
number, so it needs to be decided deliberately.

---

## Steps 2–4 — not reached

The gate is Step 2 (TEST 3 green before Arm A′). TEST 3 itself passes, but the
suite it shares a judge with does not, and the reason had to be established
before regenerating any baseline. Steps 3 (Arm A′, 20 seeds) and 4 (trade-off
sweeps) were not run: regenerating baselines against a judge whose integration
is disabled would produce numbers identical to the existing ones, at ~2 hours of
compute, and would then have to be discarded when the screen is switched on.

---

## Correction to my own Phase 1.5 report

I wrote that "**10 of the 13** broken tests now pass" and listed three
remaining. That was wrong. `test_vee_deception_check` (2 failures) was among the
13 and I never re-ran it after the −40 m/s retarget — the runs I did were
targeted subsets that excluded it. The correct figure was **8 of 13**, with
`test_vee_deception_check` still failing.

Evidence that it predates this phase: the Phase 1 blast-radius full-suite log,
captured **before** any residual-screen work, already shows

```
A-genuine    10/10 confirmed   10/10 flagged   0/10 deceived
```

Confirmed again with the residual screen off by default — the numbers are
unchanged from that pre-Phase-4 state, so the screen is not implicated.

Likely mechanism, consistent with everything else measured this phase: the
−40 m/s retarget shortened the range walk from 420 m to 280 m over 8 frames,
further weakening screen 1's already-short lever arm. Not yet isolated
per-screen; that diagnosis is the natural next step.

**Current state of that file:** 2 failures —
`test_does_the_phantom_actually_deceive` and
`test_which_eccm_screen_is_actually_load_bearing`.

---

## Suite state

```
tests/test_vee_deception_check.m        2 FAILED  (predates this phase)
tests/test_angle_channel.m              PASS
tests/Stage5_Test.m                     PASS
tests/test_package_separation.m         PASS
tests/test_amplitude_residual_screen.m  PASS (4/4)
tests/test_multi_target_judge.m         PASS
                                        PASSED 16  FAILED 2
```

## Honest caveats

- **The three-screen judge is NOT the authoritative judge.** The brief's closing
  note assumes the integration lands; it did not. The two-screen judge remains
  authoritative, and every published number stands as-is rather than being
  superseded.
- The residual screen's own validation (Phase 3.2b) is unaffected and still
  holds: 90 % genuine pass at 8 frames vs slope's 12 %, 10 vs 21 points of
  dwell variation, RCS-independent to 1e-12. Those were measured on scenes
  rendered *with* scintillation, which is why they did not surface this.
- The constant-ERP blindness stands: residual catches servo-perfect, slope
  catches wrong-law, neither catches both.
- Nothing in `runJudge.m` changed; the frame log does not yet carry per-screen
  scores. Step 1.2's "write all three screen scores to the frame log" was not
  done, since the screen it would report is disabled.

---

# Addendum — `test_vee_deception_check` diagnosed and FIXED (2 August 2026)

The failure flagged at the end of this document is resolved. It was a missed
retarget site, not a chain fault.

## Chain walk — the failure was not where the brief expected

A single genuine track, full chain, at −40 m/s:

| stage | result |
|---|---|
| **1. Render** | `amp × R²` constant to 4 d.p. across all 8 frames; range monotonic ↓, amplitude monotonic ↑ — exact 1/R² |
| **3. CFAR** | detection in **8/8** frames |
| **2. Gate** | **0/6** hits outside the 200 m gate; residuals 1.7–14.6 m |
| **4. M-of-N** | confirms, history 6 of 8 frames, first hit t = 2 s |
| **5. Screens** | slope **−1.954** → 0.977 · Doppler → 1.000 · mean **0.9885** → **"real"** |

So the hand-built genuine track **passed cleanly**, with a 0.4885 margin. That
ruled out render, CFAR, gating and M-of-N in one pass and pointed at the arm
construction rather than the chain.

## Root cause: one missed constant

```matlab
tests/test_vee_deception_check.m:43    V_MPS = -60;      % closing
```

The Phase 1.5 retarget matched `run2x2`'s inline
`struct('R0',1800,'v',-60,'F',8)` but **not this class constant**, which is what
`buildArm` (arms A–E, the headline test) uses. So the 2×2 moved to −40 m/s while
the deception arms stayed at −60.

At −60 m/s with v_ua = 59.958: f_d = +4002.8 Hz aliases to −3997.2 Hz, the judge
reads **+59.9 m/s** — range closing, Doppler opening. Screen 2 scores 0, the
mean lands at ≈0.49, and the genuine arm is labelled decoy **10/10**. Exactly
the fold mechanism measured in `PHASE4_RESULTS.md` §1.3; it had simply not
reached this constant.

## After the fix — 2/2 green

```
arm                       confirmed      flagged       DECEIVED
A-genuine                     10/10         1/10           9/10  ( 90%)
B-vee-phantom                 10/10         2/10           8/10  ( 80%)
C-naive-drfm                  10/10        10/10           0/10  (  0%)
D-vee-phantom-static          10/10         9/10           1/10  ( 10%)
E-noise-only                   0/10         0/10           0/10  (  0%)

HEADLINE: VEE phantom deceived the radar in 8/10 seeds (80%); naive DRFM 0/10 (0%)
PASSED 2 FAILED 0
```

## Two assertions re-baselined, and one of them is a degradation

| | at −60 m/s (old) | at −40 m/s (now) |
|---|---|---|
| A-genuine deceived | 10/10 | **9/10** |
| 2×2 correct-Doppler/correct-gain | 10/10, 10/10 | **9/10, 8/10** |

Both move for one reason: the retarget shortens the 8-frame range walk from
420 m to **234 m**, and screen 1 fits a log–log slope across that walk. A
shorter lever arm means a noisier fit — measured std **2.67** against a decision
half-width of 1.0.

**This is re-baselining after a deliberate physics change, not loosening a
threshold to hide a failure.** The distinction matters, so the consequence is
stated rather than absorbed: **the judge now rejects a genuine target roughly 1
seed in 10.** That is a real loss of instrument quality, and it is the price of
making the radar physically self-consistent. It is the same screen-1 weakness
measured throughout Phases 3 and 4 (12 % genuine pass at 8 frames on real
pipeline tracks); the retarget simply pushed it over the edge here. Both
assertions are now floors, so a further slide still fails.

## Standing tally corrected again

With this fixed, Phase 1's blast radius is **10 of 13 fixed, 3 remaining** —
which is what I originally claimed, but only accidentally: the claim was made
before this test was ever re-run, and it was false at the time. The three that
remain are `test_angle_channel`'s genuine-formation case (now passing after
Phase 1.5 TEST 3), `test_drone_models` (fixed, TEST 1) and
`test_far_phantom_range_correction` (still open, deferred by decision).

---

# Addendum 2 — the Swerling prerequisite is REFUTED (2 August 2026)

This document states above that enabling the residual screen "requires first
rendering genuine reference targets with real fluctuation (`swerling >= 1`)".
**That is wrong, and measuring it disproves it.** Correction recorded here
rather than silently edited above.

## Measurement

Identical construction to `test_vee_deception_check`'s `buildArm` (same chirp,
same `synthesizeTxPulse` path for the phantom, same judge), changing **only**
the swerling parameter. 10 seeds/arm, v = −40 m/s, 8 frames.

```
swerling  arm             accepted      conf slope score    resid dB  veto fires
0         A-genuine            9/10      10/10       0.752       0.554         0/10
0         B-phantom            8/10      10/10       0.383       1.012         0/10
1         A-genuine            4/10      10/10       0.185       4.222         0/10
1         B-phantom            2/10      10/10       0.068       5.222         0/10
```

## Three answers, all negative for Path A

**1. The residual veto never fires at Swerling 1 — on either arm.** Its floor is
~0.05–0.15 dB; measured residual σ is **4.222 dB (genuine)** and **5.222 dB
(phantom)**, 30–100× above it. Swerling-1 fluctuation is ~5.6 dB scan-to-scan,
which swamps the entire measurement. **Enabling the screen after a Swerling fix
would deliver exactly zero discrimination.**

**2. Screen 1 degrades sharply.** Genuine slope score **0.752 → 0.185**
(−0.566). The same 5.6 dB of amplitude scatter that swamps the residual screen
also destroys the log–log slope fit — the two screens fail together, not in
complement.

**3. The headline gets much worse.** Genuine acceptance **9/10 → 4/10**: the
judge would reject a real target **6 times in 10**, against 1 in 10 today.

## What this actually tells us about the screen

The residual-variance screen has a **narrow operating regime**, now measured: it
discriminates only when the genuine target's scintillation is *small and
well-characterised* (near the 0.233 dB RadChar floor) **and** the adversary is
servo-perfect. Against a realistically fluctuating target it is inert, because
every return — real or forged — has residual σ far above any floor that would
still catch σ = 0.

That is a legitimate and useful characterisation rather than a failure. It means
the screen is a tool for **stable-RCS targets** (the corner-reflector /
low-fluctuation regime), not a general-purpose ECCM screen. It stays
implemented, tested and off by default, and the prerequisite for enabling it is
**not** a Swerling change — it is a scenario in which genuine targets are
genuinely low-fluctuation.

## Consequence for the plan

**Path A is refuted and should not be run.** It would spend 2–3 hours to make
the instrument substantially worse (genuine acceptance 9/10 → 4/10) while
enabling a capability that measurement shows would not activate. The
`swerling = 0` reference scenes are not the blocker they appeared to be.

Note also that the deception conclusion is unchanged in *kind* at either
setting — 9/10 vs 8/10 and 4/10 vs 2/10 both overlap heavily at n = 10, so a
phantom remains statistically indistinguishable from a genuine target. Swerling
lowers both arms together; it does not separate them.
