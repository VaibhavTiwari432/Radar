# Virtual Entity Engine — Code Governance

**7 August 2026.** The old signal-generation/cognitive-agent pipeline was
archived to `trash/legacy-generator-20260807/` (full git history preserved,
rollback tag `archive-point-20260807`). The judge was not touched. This file
is the dependency rule for the rebuild described in the Virtual Entity Engine
Scientific Blueprint (physics-projection-bounded generator, D3QN state that
includes sensed radar waveform parameters).

## Dependency rule
- **Judge → generator:** the judge (`+radar/`, `+track/`, `+engine/runJudge.m`,
  `+engine/runJudgeJson.m`) may *read* generator output (a rendered signal) to
  score it. One-way.
- **Generator → judge:** FORBIDDEN. The new generator package must never
  `import`/reference judge code or judge-owned thresholds. This is
  `CLAUDE.md`'s existing Rule 2 (the Golden Rule) — restated here because it
  now applies to a generator being built from scratch, not retrofitted.
- **`+physics/`** (c, fs, PRI, derivations) is shared FACTS, not model
  parameters — both sides may read it, per Rule 1.
- **`trash/`** is archive only. Nothing in the active tree imports from it.

## Enforcement
- Grep check before any commit that touches the generator:
  `grep -rE "judge\.|runJudge|runJudgeJson" <new-generator-path>/` should
  return nothing outside of comments explaining the exclusion (the pattern
  `+track/discriminator.m` and `+track/getFilterState.m` already use, per
  `CLAUDE.md`'s Rule 2 enforcement section).
- A reward or internal score the generator computes about its own scene is
  never a reported result — only the judge's `confirmed`/`decoy` verdict is
  (Rule 3/5).

## Provenance
Every number the rebuild produces carries one tag: `MEASURED` | `DERIVED` |
`ASSUMED` | `UNVALIDATED` — per the Blueprint's provenance discipline and
`CLAUDE.md` Rule 1.

## Known broken downstream (not silently ignored — see below)
Sixteen judge-side tests and all of `+missionsim/` built their test/demo
scenes via the now-archived `engine.entity.render`/`EntityState`/`propagate`.
They are left broken deliberately, to be rewired against the new generator's
render path as it's built, not patched with a compatibility shim (that would
reintroduce the archived code). Full list: `trash/BROKEN_DOWNSTREAM.md`.
