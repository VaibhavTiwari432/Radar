"""Stage F gate F0.6: `unscreened` must pay 0, and the counter must be honest.

WHY THIS EXISTS AS A TEST AND NOT A CODE READ. The archived
+agent/buildEnvEntity.m paid +0.5 for an `unscreened` outcome -- the SAME
bonus it paid for being caught outright as a `decoy` -- so "the judge never
evaluated you" and "the judge rejected you" were worth the same to a learner.
A policy can farm that: degenerate scenes that never produce two usable track
points are cheap to make and pay as well as a near-miss. The live rebuild
(generator/decision/env.py) does not have the bug, but nothing was asserting
that, and the loophole is invisible on a code read the moment the rule stops
being one line.

The gate's wording is "`unscreened` pays 0; a counter records every firing".
The counter half is +engine/runJudge.m's own condition (numel(rSeq) >= 2,
line 603) surfaced through feedback.track_label -- there is no second place
`unscreened` can be produced, so counting the label IS counting the firings.
"""
import pytest

from generator.decision.env import is_success


# (confirmed_tracks, eccm_label). Every label runJudge.m can actually emit:
# "" (nothing confirmed), "real", "decoy", "unscreened", "mixed".
PAYING = [(1, "real"), (4, "real")]
NOT_PAYING = [
    (0, ""),             # nothing confirmed at all
    (1, "unscreened"),   # THE loophole: screens never ran
    (3, "unscreened"),
    (1, "decoy"),        # screens ran and caught it
    (2, "mixed"),        # confirmed tracks disagreed
    (0, "real"),         # label without a confirmed track pays nothing either
]


@pytest.mark.parametrize("confirmed,label", PAYING)
def test_only_a_confirmed_real_track_pays(confirmed, label):
    assert is_success({"confirmed_tracks": confirmed, "eccm_label": label})


@pytest.mark.parametrize("confirmed,label", NOT_PAYING)
def test_everything_else_pays_nothing(confirmed, label):
    assert not is_success({"confirmed_tracks": confirmed, "eccm_label": label})


def test_unscreened_is_worth_exactly_what_decoy_is_worth():
    """The specific inversion the archived env had: these two must not differ.

    Asserted as an equality rather than as two separate zeros, because the bug
    was never "unscreened pays too much in absolute terms" -- it was that it
    paid MORE than being screened and failing, which is what makes farming it
    a better strategy than deceiving.
    """
    unscreened = is_success({"confirmed_tracks": 1, "eccm_label": "unscreened"})
    decoy = is_success({"confirmed_tracks": 1, "eccm_label": "decoy"})
    assert unscreened == decoy is False
