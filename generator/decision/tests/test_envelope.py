"""RL v2 Step 1: envelope.py's pure logic, no MATLAB."""
from generator.decision.env import NUM_FRAMES
from generator.decision.envelope import HELDOUT, SUITE, classify, summarise_rows


def test_heldout_radars_exist_and_differ_from_every_train_radar():
    train = [v for k, v in SUITE.items() if k not in HELDOUT]
    assert set(HELDOUT) <= set(SUITE) and len(train) == 7
    for name in HELDOUT:
        assert SUITE[name] not in train


def test_every_schedule_covers_every_frame():
    for radar in SUITE.values():
        if "sweep_schedule" in radar:
            assert len(radar["sweep_schedule"]) == NUM_FRAMES
        sched = radar.get("render", {}).get("PhantomSweepSchedule")
        if sched is not None:
            assert len(sched) == NUM_FRAMES


def _row(stage, action, seed, reward, radar="base", mr=1400.0):
    return {"stage": stage, "radar": radar, "mother_range_m": str(mr), "cross_mps": "1.5",
            "action": str(action), "seed": str(seed), "reward": str(reward)}


def test_best_cell_ignores_the_selecting_seed_and_picks_the_best_rate():
    rows = [_row("A", 3, 0, 1.0), _row("A", 7, 0, 1.0)]
    rows += [_row("B", 3, s, 0.0) for s in range(1, 11)]                       # 0/10
    rows += [_row("B", 7, s, 1.0 if s <= 8 else 0.0) for s in range(1, 11)]    # 8/10
    cells, radars = summarise_rows(rows)
    assert cells[0]["best_action"] == 7 and (cells[0]["k"], cells[0]["n"]) == (8, 10)
    assert radars[0]["ceiling"] == 0.8 and radars[0]["class"] == "candidate"


def test_context_with_no_stage_a_winner_scores_zero():
    cells, radars = summarise_rows([_row("A", a, 0, 0.0) for a in range(5)])
    assert cells[0]["best_action"] == -1 and cells[0]["p"] == 0.0
    assert radars[0]["class"] == "wall"


def test_classify_thresholds():
    assert classify(0.95) == "ceiling" and classify(0.05) == "wall" and classify(0.5) == "candidate"
