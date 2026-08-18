"""The /plan /score /run rewire onto the REBUILT generator (H4).

Until 12 Aug 2026 these three endpoints imported cogengine, archived on
7 Aug, and returned HTTP 500. CLAIMABLE_RESULTS.md H4 recorded that as "the
app cannot start" -- which was wrong in a way worth keeping visible: the
cogengine imports were function-local, so the app DID start and /health DID
answer 200. Only the four endpoints that reach for the engine failed, and
they failed at request time.

Split deliberately: everything above the MATLAB line runs everywhere and is
the real regression net; the two marked `slow` need a live matlab.engine and
prove the end-to-end path against the REAL judge (CLAUDE.md Rule 3 -- a
Python-side pass alone never demonstrates deception).
"""
import math

import pytest
from fastapi.testclient import TestClient

from common.constants import C
from generator.physics_projection import blind_range_m, unambiguous_range_m
from server.app import SPACING_M, app

client = TestClient(app, raise_server_exceptions=False)

SEPARATION_M = (20 + 4) * C.range_per_sample     # CA-CFAR train+guard, 1124.2 m


def _plan(**opts):
    return client.post("/plan", json={"opts": opts})


# --------------------------- no MATLAB needed -----------------------------

def test_health_and_constants_answer():
    assert client.get("/health").status_code == 200
    assert client.get("/constants").status_code == 200


def test_constants_report_the_corrected_8khz_radar():
    """The endpoint used to hardcode prf_hz = 50e3 and report R_ua = 2998 m.
    +physics/Constants.m and common/constants.py both say 8 kHz. A console
    drawing an unambiguous-range ring at 2998 m would be off by 6.2x."""
    d = client.get("/constants").json()
    assert d["prf_hz"] == C.PRF == 8000.0
    assert d["unambiguous_range_m"] == pytest.approx(unambiguous_range_m(C.PRF))
    assert d["unambiguous_range_m"] > 18_000.0
    assert d["range_per_sample_m"] == pytest.approx(C.range_per_sample)


def test_constants_satisfy_their_own_equations():
    """Every field the console renders, checked against the equation it claims
    to be -- not against a remembered number. Added 15 Aug 2026 after the
    console was found still typing prf_hz = 50000, pri_s = 20e-6 and a "10 GHz"
    string into its own radarState; the fix makes this payload the only source,
    so the payload has to be right."""
    d = client.get("/constants").json()
    c, fs = d["speed_of_light_mps"], d["sample_rate_hz"]
    lam = c / d["carrier_hz"]

    assert d["range_per_sample_m"] == pytest.approx(c / (2 * fs))          # c/(2 fs)
    assert d["unambiguous_range_m"] == pytest.approx(c / (2 * d["prf_hz"]))  # c/(2 PRF)
    assert d["unambiguous_velocity_mps"] == pytest.approx(lam * d["prf_hz"] / 4)  # lam PRF/4
    assert d["blind_range_m"] == pytest.approx(c * d["pulse_width_s"] / 2)   # c PW/2
    assert d["pri_s"] == pytest.approx(1.0 / d["prf_hz"])
    assert d["range_window_m"] == pytest.approx(C.Nsamples * d["range_per_sample_m"])
    # The stale copy's consequence, pinned so it cannot come back quietly.
    assert d["unambiguous_range_m"] / unambiguous_range_m(50e3) == pytest.approx(6.25)


def test_the_planner_starts_outside_the_blind_range_the_console_displays():
    """The console shows blind_range_m on the radar side; /plan's own start
    range is derived from the same function. Same number, both sides -- if
    they ever diverge the page is drawing a scene the backend did not build."""
    d = client.get("/constants").json()
    r0 = _plan(n_phantoms=1, range_rate_mps=-35.0, duration_s=8.0
               ).json()["scene"]["phantoms"][0]["range_m"]
    assert d["blind_range_m"] == pytest.approx(blind_range_m(C.pulse_width))
    assert r0 - 35.0 * 8.0 >= d["blind_range_m"]


@pytest.mark.parametrize("n", [1, 2, 4, 8])
def test_plan_lays_out_n_separated_feasible_phantoms(n):
    r = _plan(n_phantoms=n)
    assert r.status_code == 200, r.json()
    ph = r.json()["scene"]["phantoms"]
    assert len(ph) == n
    gaps = [ph[i + 1]["range_m"] - ph[i]["range_m"] for i in range(n - 1)]
    assert all(g >= SEPARATION_M for g in gaps), gaps
    assert SPACING_M >= SEPARATION_M


def test_whole_engagement_clears_the_blind_range_not_just_frame_zero():
    """The bug this guards is subtle and already exists upstream:
    generator/tests/build_n_phantom_scenes.py omits pulse_width_s from its
    project_action call, so the eclipse veto never evaluates, and its
    1900 m / -35 m/s trajectories end at 1654.9 m -- 143.9 m inside the
    1798.75 m blind range. Checking only the t=0 range would pass that
    scene. Check the CLOSEST approach."""
    rate, dur = -35.0, 8.0
    r = _plan(n_phantoms=1, range_rate_mps=rate, duration_s=dur)
    assert r.status_code == 200, r.json()
    r0 = r.json()["scene"]["phantoms"][0]["range_m"]
    assert r0 + rate * dur > blind_range_m(C.pulse_width)


def test_infeasible_scene_is_422_with_the_reason_not_500_and_not_clamped():
    """A veto is the adversary's constraint answering. It must reach the
    caller intact -- silently pulling the phantom out to a legal range would
    turn 'you cannot do that' into a result that looks like success."""
    r = client.post("/score", json={"scene": {
        "duration_s": 8.0,
        "phantoms": [{"range_m": 1000.0, "radial_vel_mps": 0.0, "rcs_dbsm": 0.0}]}})
    assert r.status_code == 422
    assert r.json()["detail"]["reason"]


def test_a_stationary_mother_plans_exactly_what_the_scalar_range_used_to():
    """S1's back-compat guarantee at the API boundary. `mother_range_m` was a
    bare float here until the platform became a track; with both speeds at
    zero the plan must be identical, or every published console result has
    quietly moved."""
    default = _plan(n_phantoms=4).json()
    explicit_zero = _plan(n_phantoms=4, mother_cross_speed_mps=0.0,
                          mother_closing_speed_mps=0.0).json()
    assert default == explicit_zero


def test_a_receding_mother_can_veto_a_scene_that_was_legal_at_t0():
    """The time dependence that did not exist before. Causality is
    R_phantom(t) >= R_mother(t) + c*tau/2 at EVERY sample; with a stationary
    platform that is one comparison for the whole engagement, so the veto
    either always holds or never does -- PHASE_C_RESULTS.md section 1's
    finding that it refused 0% of the action grid. A mother OPENING while the
    phantom CLOSES makes the margin erode within a single run."""
    ok = _plan(n_phantoms=1, range_rate_mps=-35.0, duration_s=8.0)
    assert ok.status_code == 200, ok.json()

    # Same scene, mother backing away fast enough to overtake the phantom's
    # own closing trajectory before the last frame.
    vetoed = _plan(n_phantoms=1, range_rate_mps=-35.0, duration_s=8.0,
                   mother_closing_speed_mps=-260.0)
    assert vetoed.status_code == 422, vetoed.json()
    assert "causality" in vetoed.json()["detail"]["reason"]


def test_engine_off_plans_nothing():
    r = _plan(engine_mode="OFF")
    assert r.status_code == 200
    assert r.json()["scene"]["phantoms"] == []


def test_plan_is_deterministic_across_seeds():
    """The rebuild has no CEM search, so `seed` no longer perturbs the SCENE
    -- it selects render.m's noise draw in /score. Asserted so nobody reads
    seed-invariance here as a broken RNG."""
    a = _plan(n_phantoms=2, seed=1).json()
    b = _plan(n_phantoms=2, seed=99).json()
    assert a == b


def test_rcs_round_trips_through_dbsm():
    r = _plan(n_phantoms=1, rcs_m2=4.0).json()
    assert r["scene"]["phantoms"][0]["rcs_dbsm"] == pytest.approx(10 * math.log10(4.0))


# ------------------------- needs a live MATLAB ----------------------------

@pytest.mark.slow
def test_the_judge_measures_the_mother_platform_moving():
    """S1+S2 end to end, against the REAL judge.

    The whole plan rests on one physical claim: a phantom is radiated from
    the mother, so it inherits the MOTHER's bearing trajectory rather than
    one implied by its own claimed range. Nothing downstream is worth
    building unless the judge -- which has never heard of the generator --
    can actually SEE that trajectory in the monopulse channel.

    Measured both ways, because a one-sided version would pass on a broken
    renderer that simply emitted noise in the azimuth series.
    """
    body = {"opts": {"n_phantoms": 1, "seed": 1}}
    still = client.post("/run", json=body)
    if still.status_code == 503:
        pytest.skip("judge offline: " + str(still.json()))
    assert still.status_code == 200, still.json()

    body["opts"]["mother_cross_speed_mps"] = 5.0
    moving = client.post("/run", json=body)
    assert moving.status_code == 200, moving.json()

    def az_spread_deg(resp):
        az = resp.json()["feedback"]["track_azimuth_rad"]
        series = az[0] if isinstance(az[0], list) else az
        vals = [math.degrees(v) for v in series if v is not None]
        assert len(vals) >= 3, f"too few azimuth samples to judge a rate: {vals}"
        return max(vals) - min(vals)

    # A parked platform: spread is measurement scatter only. 0.0726 deg is the
    # worst within-track sigma tests/test_monopulse_snr_boundary.m measured.
    assert az_spread_deg(still) < 0.5

    # 5 m/s across an 8 s dwell at 900 m is ~2.5 deg of real bearing change,
    # and MotherTrack.sector_dwell_s says that stays inside the +-2.8640 deg
    # unambiguous sector for the whole run, so this measures bearing and not
    # phase wrap.
    assert az_spread_deg(moving) > 1.5

    # ...and the platform's own truth track is on the payload to compare against.
    m = moving.json()["mother"]
    assert m["within_unambiguous_sector"] is True
    assert max(m["azimuth_rad"]) - min(m["azimuth_rad"]) > math.radians(1.5)


@pytest.mark.slow
def test_truth_track_amplitude_obeys_the_inverse_square_law():
    """The console's amp column was permanently "—": the scene dict carries no
    amp_scale, because the rebuilt generator DERIVES amplitude at projection
    time. /run now sends the derived series, so it has to be the real law --
    amplitude ~ 1/R^2 (two-way radar equation is 1/R^4 in POWER), the exact
    trend +track/amplitudeResidualScreen.m screens for. Checked as a RATIO, so
    it tests the law and not the link-budget constants."""
    r = client.post("/run", json={"opts": {"n_phantoms": 2, "seed": 1}})
    if r.status_code == 503:
        pytest.skip("judge offline: " + str(r.json()))
    tt = r.json()["truth_track"]
    rng, amp = tt["range_m"], tt["amplitude_sim"]
    assert len(amp) == len(rng) == 2

    for ranges, amps in zip(rng, amp):
        assert len(amps) == len(ranges)
        # closing target: later frames are nearer, so amplitude must RISE
        assert amps[-1] > amps[0]
        for r0, r1, a0, a1 in zip(ranges, ranges[1:], amps, amps[1:]):
            assert a1 / a0 == pytest.approx((r0 / r1) ** 2, rel=1e-9)

    # ...and across phantoms at the same RCS, purely a range effect.
    assert amp[0][0] / amp[1][0] == pytest.approx((rng[1][0] / rng[0][0]) ** 2, rel=1e-9)


@pytest.mark.slow
def test_run_reaches_the_real_judge():
    r = client.post("/run", json={"opts": {"n_phantoms": 1, "seed": 1}})
    if r.status_code == 503:
        pytest.skip("judge offline: " + str(r.json()))
    assert r.status_code == 200, r.json()
    fb = r.json()["feedback"]
    # doppler_source proves the pulse CUBE reached the judge, not a legacy
    # 2-D export -- on which the Doppler screen self-disables entirely.
    assert fb["doppler_source"] == "measured"
    assert fb["angle_source"] == "monopulse"
    assert fb["confirmed_tracks"] == 1
    assert len(r.json()["truth_track"]["range_m"]) == 1


@pytest.mark.slow
def test_monopulse_wall_reproduces_through_the_api():
    """F2/F3 (PHASE_B_RESULTS.md) end to end: two phantoms from one aperture
    are structurally co-bearing, so turning the difference channel on takes
    survivors to zero. If this passes, the rewire carries the project's
    central result, not merely valid JSON."""
    body = {"opts": {"n_phantoms": 2, "seed": 1, "include_angle_channel": False}}
    off = client.post("/run", json=body)
    if off.status_code == 503:
        pytest.skip("judge offline")
    body["opts"]["include_angle_channel"] = True
    on = client.post("/run", json=body).json()["feedback"]
    off = off.json()["feedback"]

    assert off["angle_source"] == "none" and on["angle_source"] == "monopulse"
    assert on["confirmed_tracks"] == off["confirmed_tracks"] == 2
    assert on["flagged_decoys"] == 2          # every phantom, because one aperture
    assert off["flagged_decoys"] < 2
