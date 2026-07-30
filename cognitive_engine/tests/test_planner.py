"""
The decisive test: the model-based planner must BEAT the naive DRFM copy on the
radar twin. This is the scaffold's proof that the cognitive engine adds value —
it plans phantoms that survive the ECCM screens the naive copy dies to.
(Design doc Part 7 — the demo money-shot, at unit-test scale.)
"""
from cogengine.schema import RadarState
from cogengine.radar_twin import RadarTwin
from cogengine.planner_cem import naive_copy_scene, cem_plan


def test_cem_beats_naive_copy():
    radar = RadarState()
    twin = RadarTwin(radar)

    naive = naive_copy_scene(radar, n=4)
    naive_survivors = twin.score(naive)["survivors"]

    best_scene, best_reward, history = cem_plan(radar, twin, n_phantoms=4,
                                                iters=8, pop=48, seed=0)
    cem_survivors = twin.score(best_scene)["survivors"]

    # The naive copy is flagged by the zero-Doppler / missing-micro-Doppler screens.
    assert naive_survivors == 0, naive_survivors
    # The planner learns to add matched Doppler + micro-Doppler -> phantoms survive.
    assert cem_survivors > naive_survivors
    assert cem_survivors >= 3, cem_survivors
    # CEM elite reward should be non-decreasing overall (learning signal).
    assert history[-1] >= history[0]


if __name__ == "__main__":
    test_cem_beats_naive_copy()
    print("planner test passed")
