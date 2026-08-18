"""The standard engagement: one frozen scenario the whole project maps against.

WHY THIS EXISTS. Every scene in this repo has been chosen per call --
`tests/renderPhantomScene.m` takes ranges and rates as arguments, and each
experiment picks its own. That is right for a test whose subject IS a
particular geometry, and wrong for the question this module serves: *where are
the real targets, where are the fake ones, and which fakes did the radar
fail to identify?* That question needs a fixed reference, or no two answers are
comparable.

It also needs a scene that is legal. This project has twice published numbers
from scenes that quietly broke one of the radar's own bounds -- the N-phantom
sweep ended 143.9 m inside the blind range (CLAIMABLE_RESULTS.md H6), and a
4-phantom scene once put three phantoms past R_ua at the old 50 kHz PRF. So
`validate()` below asserts EVERY bound from the constants themselves rather
than trusting the numbers were chosen well.

THE GEOMETRY, AND WHY EACH NUMBER IS WHAT IT IS
------------------------------------------------
    radar     origin, boresight +x, subaperture d = 0.30 m
    drone     p0 = (2000, 0, 0) m   v = (0, 3, 0) m/s
    phantoms  3600 / 5200 / 6800 m  @ -50 m/s closing
    dwell     8 frames @ 1 Hz

  DRONE AT 2000 m, not closer, because c*PW/2 = 1798.75 m is the blind range
  and a platform inside it has NO SKIN RETURN AT ALL -- the receiver is deaf
  while transmitting, and the eclipse veto refuses to render one. Outside it
  the drone reflects the radar's own pulse like any object, which is the only
  thing that turns the emitter's measured BEARING into a measured POSITION.
  (Hiding inside the blind range is a real counter-tactic, not a gap; it is
  what the UNDETERMINED case in the map exists to show.)

  DRONE CROSSING AT 3 m/s, not stationary, because cross-range motion is what
  gives the platform a bearing rate at all -- and the bearing rate is the one
  quantity a repeater cannot forge per phantom. 3 m/s sweeps 21 m over the
  dwell: 0.6 deg, comfortably inside the +-2.8640 deg monopulse unambiguous
  sector, outside which the phase WRAPS and every bearing result would be
  measuring the wrap.

  PHANTOMS 1600 m APART, and 1600 m clear of the drone, because two returns
  closer than the CA-CFAR's own training+guard half-window share a training
  window and collapse into ONE local max. That width is 1124.2 m here and is
  read from `radar.cfarDefaults()` on the MATLAB side, never restated.

  -50 m/s, inside v_ua = 59.958 m/s. Past it the Doppler aliases, the measured
  range-rate flips sign, and the phantom self-flags on the judge's screen 2 --
  which would make the map measure a fold rather than an attribution.

  8 FRAMES because that is this project's established dwell everywhere else.
  Note the cost, recorded rather than discovered later: over 8 s a phantom at
  6800 m changes range by 350 m, 5% of its own range, so `theta` linear in 1/R
  and `theta` linear in t converge and the PER-TRACK bearing screen
  (+track/bearingRateScreen.m) weakens badly at the far end. That is precisely
  why attribution is multi-track.

NOTHING HERE IS TUNED. Every bound is derived in `validate()` from
`common.constants` and `generator.platform`; the scenario's own numbers are
the only free choices, and each is justified above against the bound it clears.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Tuple

import numpy as np

from common.constants import C
from generator.platform import MotherTrack, unambiguous_sector_rad


@dataclass(frozen=True)
class Engagement:
    """One fully specified scenario. Frozen: this is a reference, not a knob."""
    name: str
    drone_position0_m: Tuple[float, float, float]
    drone_velocity_mps: Tuple[float, float, float]
    phantom_ranges_m: Tuple[float, ...]
    phantom_rate_mps: float
    num_frames: int = 8
    num_pulses_per_frame: int = 32
    frame_interval_s: float = 1.0
    include_platform_skin_return: bool = True
    platform_rcs_m2: float = 1.0
    phantom_rcs_m2: float = 1.0
    subaperture_sep_m: float = 0.30

    # -- derived --------------------------------------------------------------

    @property
    def track(self) -> MotherTrack:
        return MotherTrack(position0_m=self.drone_position0_m,
                            velocity_mps=self.drone_velocity_mps)

    @property
    def frame_times_s(self) -> np.ndarray:
        return np.arange(self.num_frames, dtype=float) * self.frame_interval_s

    @property
    def dwell_s(self) -> float:
        return float((self.num_frames - 1) * self.frame_interval_s)

    def phantom_range_at(self, t_s: float) -> np.ndarray:
        return np.asarray(self.phantom_ranges_m, dtype=float) + self.phantom_rate_mps * t_s

    def cfar_separation_m(self) -> float:
        """The CA-CFAR training+guard half-window, in metres.

        MIRRORS +radar/cfarDefaults.m, which that file's own caller calls "the
        ONE declaration of these values". Restated here only because Python
        cannot read it; the numbers are asserted against MATLAB's by
        tests/test_emitter_attribution.m rather than trusted.
        """
        num_training, num_guard = 20, 4
        return (num_training + num_guard) * C.c / (2.0 * C.fs)

    # -- the part that matters ------------------------------------------------

    def validate(self) -> dict:
        """Assert every bound this radar imposes. Raises on the first breach.

        Returns the margins, so a caller can report HOW clear the scene is
        rather than only that it passed -- a scene 1 m inside a bound is a
        different thing from one 1 km inside it.
        """
        t = self.frame_times_s
        drone_r = self.track.range_m(t)
        near = self.phantom_range_at(self.dwell_s)      # closing: last frame is nearest
        far = self.phantom_range_at(0.0)
        margins = {}

        # 1. ECLIPSE. Every PHANTOM must clear c*PW/2 at every frame or it
        #    cannot be rendered at all.
        blind = C.c * C.pulse_width / 2.0
        if float(near.min()) <= blind:
            raise ValueError(
                f"{self.name}: a phantom reaches {near.min():.1f} m, inside the "
                f"{blind:.2f} m blind range")
        margins["eclipse_m"] = float(near.min()) - blind

        # The DRONE is held to that bound only when a skin return is asked
        # for. A drone inside the blind range is not an illegal scenario -- it
        # is a TACTIC, and the one that denies the radar a position fix. What
        # is illegal is claiming a skin echo the receiver is deaf to.
        margins["drone_eclipse_m"] = float(drone_r.min()) - blind
        if self.include_platform_skin_return and float(drone_r.min()) <= blind:
            raise ValueError(
                f"{self.name}: skin return requested but the drone reaches "
                f"{drone_r.min():.1f} m, inside the {blind:.2f} m blind range")

        # 2. RANGE AMBIGUITY. Beyond c/(2*PRF) a phantom folds to a different
        #    range than intended.
        r_ua = C.c / (2.0 * C.PRF)
        if far.max() >= r_ua:
            raise ValueError(f"{self.name}: {far.max():.1f} m is past R_ua = {r_ua:.1f} m")
        margins["ambiguity_m"] = r_ua - float(far.max())

        # 3. VELOCITY AMBIGUITY. Past lambda*PRF/4 the Doppler aliases and the
        #    measured range-rate flips SIGN.
        v_ua = C.lambda_m * C.PRF / 4.0
        if abs(self.phantom_rate_mps) >= v_ua:
            raise ValueError(
                f"{self.name}: |{self.phantom_rate_mps}| m/s is at or past "
                f"v_ua = {v_ua:.3f} m/s")
        margins["velocity_mps"] = v_ua - abs(self.phantom_rate_mps)

        # 4. CFAR SEPARATION, at every frame, drone included. Checked across
        #    the whole dwell rather than at t=0: a closing phantom walks toward
        #    whatever is in front of it.
        sep_req = self.cfar_separation_m()
        worst_sep = np.inf
        for k, tk in enumerate(t):
            rs = np.sort(np.append(self.phantom_range_at(float(tk)), drone_r[k]))
            worst_sep = min(worst_sep, float(np.min(np.diff(rs))))
        if worst_sep <= sep_req:
            raise ValueError(
                f"{self.name}: returns close to {worst_sep:.1f} m apart, inside "
                f"the {sep_req:.1f} m CFAR train+guard window")
        margins["cfar_sep_m"] = worst_sep - sep_req

        # 5. CAUSALITY. A repeater cannot plant a phantom in front of itself.
        if float(near.min()) < float(drone_r.max()):
            raise ValueError(
                f"{self.name}: a phantom reaches {near.min():.1f} m, nearer "
                f"than the drone's {drone_r.max():.1f} m")
        margins["causality_m"] = float(near.min()) - float(drone_r.max())

        # 6. MONOPULSE SECTOR. Outside it the measured phase wraps, and every
        #    bearing-derived quantity in the map would be measuring the wrap.
        half = unambiguous_sector_rad(self.subaperture_sep_m, C.lambda_m)
        if not self.track.within_unambiguous_sector(t, self.subaperture_sep_m, C.lambda_m):
            raise ValueError(
                f"{self.name}: the drone leaves the +-{np.degrees(half):.4f} deg "
                f"unambiguous sector during the dwell")
        margins["sector_rad"] = half - float(np.max(np.abs(self.track.azimuth_rad(t))))

        return margins

    # -- the one way to build it ---------------------------------------------

    def build_kwargs(self) -> dict:
        """Exactly the keyword arguments `generator.tests.build_scene.build`
        takes. One definition, so the MATLAB side cannot drift from this one."""
        return {
            "ranges_m": list(self.phantom_ranges_m),
            "rates_mps": [self.phantom_rate_mps],
            "rcs_m2": [self.phantom_rcs_m2],
            "num_frames": self.num_frames,
            "num_pulses_per_frame": self.num_pulses_per_frame,
            "frame_interval_s": self.frame_interval_s,
            "mother_range_m": float(np.linalg.norm(self.drone_position0_m)),
            "mother_velocity_mps": list(self.drone_velocity_mps),
            "include_platform_skin_return": self.include_platform_skin_return,
            "platform_rcs_m2": self.platform_rcs_m2,
        }


STANDARD_ENGAGEMENT = Engagement(
    name="standard",
    drone_position0_m=(2000.0, 0.0, 0.0),
    drone_velocity_mps=(0.0, 3.0, 0.0),
    phantom_ranges_m=(3600.0, 5200.0, 6800.0),
    phantom_rate_mps=-50.0,
)

# The counterpoint, and the reason the map has an UNDETERMINED category. Same
# drone track pulled inside the blind range: no skin return exists, so the
# radar gets the emitter's bearing and a causality bound and nothing more.
# NOT validated with a skin return -- asking for one raises, which is the
# point.
HIDDEN_DRONE_ENGAGEMENT = Engagement(
    name="hidden-drone",
    drone_position0_m=(1400.0, 0.0, 0.0),
    drone_velocity_mps=(0.0, 3.0, 0.0),
    phantom_ranges_m=(3600.0, 5200.0, 6800.0),
    phantom_rate_mps=-50.0,
    include_platform_skin_return=False,
)


def demo() -> None:
    """Smallest check that fails if a bound is breached or a guard rots."""
    m = STANDARD_ENGAGEMENT.validate()
    for k, v in sorted(m.items()):
        print(f"  {k:>16s}  margin {v:12.4f}")
    assert all(v > 0 for v in m.values()), m

    # The hidden-drone case is legal only WITHOUT a skin return.
    HIDDEN_DRONE_ENGAGEMENT.validate()
    try:
        Engagement(**{**HIDDEN_DRONE_ENGAGEMENT.__dict__,
                       "include_platform_skin_return": True}).validate()
    except ValueError as e:
        assert "blind range" in str(e), e
    else:
        raise AssertionError("a drone at 1400 m must not be allowed a skin return")

    # The validator must actually be able to fail, on each bound it claims to
    # check -- a validator that passes everything is decoration.
    for bad, needle in [
        (dict(phantom_ranges_m=(1900.0, 5200.0, 6800.0)), "blind range"),
        (dict(phantom_ranges_m=(3600.0, 5200.0, 19000.0)), "R_ua"),
        (dict(phantom_rate_mps=-70.0), "v_ua"),
        (dict(phantom_ranges_m=(3600.0, 4000.0, 6800.0)), "CFAR"),
        # 2400 -> 2050 m: clears the blind range and clears causality by 50 m,
        # so CFAR separation against the drone is the bound that must fire.
        (dict(phantom_ranges_m=(2400.0, 5200.0, 6800.0)), "CFAR"),
        (dict(drone_velocity_mps=(0.0, 40.0, 0.0)), "unambiguous sector"),
    ]:
        try:
            Engagement(**{**STANDARD_ENGAGEMENT.__dict__, **bad}).validate()
        except ValueError as e:
            assert needle in str(e), f"{bad} raised the wrong thing: {e}"
        else:
            raise AssertionError(f"{bad} should have been refused")

    print("engagement.demo OK")


if __name__ == "__main__":
    demo()
