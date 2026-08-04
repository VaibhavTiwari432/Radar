"""cogengine.schema -- the data contract crossing the Python/MATLAB seam.

RadarState, Phantom, Scene, Feedback: defined once here, mirrored in
+engine/sceneContract.m (Phase 2 build-order step 6). See
AI_Cognitive_Engine_Detailed_Design.md Part 4.

Every type validates its own fields at construction (fail fast, no
downstream surprises -- CLAUDE.md Rule 7) and round-trips through JSON,
since JSON is what crosses into MATLAB via jsonencode/jsondecode.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, asdict, field
from typing import List, Optional, Tuple

PHANTOM_CLASSES = ("fighter", "airliner", "drone", "missile", "decoy")
MANEUVERS = ("static", "rgpo", "vgpo", "swarm")
PER_PHANTOM_STATUSES = ("undetected", "detected", "confirmed", "flagged")


@dataclass
class RadarState:
    """Perceive-stage output (engine input). Design doc §3.1, §4."""
    mode: str
    prf_hz: float
    pri_s: float
    carrier_hz: float
    range_gate_m: Tuple[float, float]
    vel_gate_mps: Tuple[float, float]
    scan_phase: float
    doubt_cue: float = 0.0

    def __post_init__(self):
        # Coerce to float: a value round-tripped through JSON (e.g. from
        # MATLAB's jsonencode, engine.decideScene's seam) that happens to be
        # a whole number arrives as a Python int, not float -- harmless in
        # pure Python arithmetic, but scipy.io.savemat then writes it as an
        # int64 .mat array, which phased.LinearFMWaveform's strict type
        # checking (SampleRate/PRF must be double) rejects outright. Verified
        # via tests/test_decideScene.m: prf_hz=50000 (whole, from JSON) broke
        # engine.runJudge with "Expected PRF ... double. Instead ... int64."
        self.prf_hz = float(self.prf_hz)
        self.pri_s = float(self.pri_s)
        self.carrier_hz = float(self.carrier_hz)
        self.scan_phase = float(self.scan_phase)
        self.doubt_cue = float(self.doubt_cue)
        self.range_gate_m = tuple(float(x) for x in self.range_gate_m)
        self.vel_gate_mps = tuple(float(x) for x in self.vel_gate_mps)
        if not (0.0 <= self.doubt_cue <= 1.0):
            raise ValueError(f"doubt_cue must be in [0,1], got {self.doubt_cue}")
        if len(self.range_gate_m) != 2 or self.range_gate_m[0] > self.range_gate_m[1]:
            raise ValueError(f"range_gate_m must be [lo,hi] with lo<=hi, got {self.range_gate_m}")
        if len(self.vel_gate_mps) != 2 or self.vel_gate_mps[0] > self.vel_gate_mps[1]:
            raise ValueError(f"vel_gate_mps must be [lo,hi] with lo<=hi, got {self.vel_gate_mps}")
        if self.prf_hz <= 0 or self.pri_s <= 0 or self.carrier_hz <= 0:
            raise ValueError("prf_hz, pri_s, carrier_hz must be positive")
        # pri_s IS 1/prf_hz -- they are one physical fact carried in two
        # fields, and nothing used to make them agree. They silently drifted:
        # +engine/sceneContract.m kept pri_s=20e-6 (the old 50 kHz PRI) after
        # prf_hz was retargeted to 8 kHz, a 6.25x disagreement. renderer.py
        # builds its Doppler phasor from pri_s while the MATLAB judge measures
        # Doppler from prf_hz, so every scene exported across that seam
        # carried a Doppler 6.25x too small and slow phantoms were labelled
        # `decoy` for a contradiction the units bug invented.
        #
        # Checked here rather than derived (pri_s stays a field) because every
        # existing caller already passes a consistent pair, so validation is
        # the smaller change and it fails LOUDLY at the boundary instead of
        # quietly correcting a caller that believes something false. The
        # reference implementation (cognitive_engine/) made pri_s a derived
        # @property and never had this bug -- that is the other valid answer.
        if abs(self.pri_s - 1.0 / self.prf_hz) > 1e-9 * max(self.pri_s, 1.0 / self.prf_hz):
            raise ValueError(
                f"pri_s ({self.pri_s:g} s) contradicts prf_hz ({self.prf_hz:g} Hz), "
                f"which implies pri_s = {1.0/self.prf_hz:g} s. They are the same "
                f"physical quantity; renderer.py takes Doppler from pri_s and the "
                f"MATLAB judge takes it from prf_hz, so a mismatch scales every "
                f"rendered Doppler by {(1.0/self.prf_hz)/self.pri_s:g}x."
            )

    def to_dict(self) -> dict:
        d = asdict(self)
        d["range_gate_m"] = list(self.range_gate_m)
        d["vel_gate_mps"] = list(self.vel_gate_mps)
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "RadarState":
        return cls(**d)

    def to_json(self) -> str:
        return json.dumps(self.to_dict())

    @classmethod
    def from_json(cls, s: str) -> "RadarState":
        return cls.from_dict(json.loads(s))


@dataclass
class MicroMotion:
    """e.g. a drone's rotor blade flash. Phantom.micro, may be absent."""
    type: str
    n_blades: int
    rpm: float
    blade_len_m: float

    def __post_init__(self):
        # See RadarState.__post_init__'s comment: coerce so a whole-number
        # value round-tripped through JSON doesn't silently arrive as int.
        self.n_blades = int(self.n_blades)
        self.rpm = float(self.rpm)
        self.blade_len_m = float(self.blade_len_m)
        if self.n_blades <= 0:
            raise ValueError(f"n_blades must be positive, got {self.n_blades}")
        if self.rpm < 0:
            raise ValueError(f"rpm must be non-negative, got {self.rpm}")
        if self.blade_len_m <= 0:
            raise ValueError(f"blade_len_m must be positive, got {self.blade_len_m}")

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "MicroMotion":
        return cls(**d)


@dataclass
class Phantom:
    """One virtual identity in a Scene. Design doc §4.

    `class_` holds the value serialized under the JSON key "class" (a
    reserved word in Python, so the attribute can't be named that directly).
    """
    class_: str
    range_m: float
    radial_vel_mps: float
    accel_mps2: float
    rcs_dbsm: float
    swerling: int
    amp_scale: float
    micro: Optional[MicroMotion] = None

    def __post_init__(self):
        # See RadarState.__post_init__'s comment: coerce so a whole-number
        # value round-tripped through JSON doesn't silently arrive as int.
        self.range_m = float(self.range_m)
        self.radial_vel_mps = float(self.radial_vel_mps)
        self.accel_mps2 = float(self.accel_mps2)
        self.rcs_dbsm = float(self.rcs_dbsm)
        self.swerling = int(self.swerling)
        self.amp_scale = float(self.amp_scale)
        if self.class_ not in PHANTOM_CLASSES:
            raise ValueError(f"class must be one of {PHANTOM_CLASSES}, got {self.class_!r}")
        if self.swerling not in (0, 1, 2, 3, 4):
            raise ValueError(f"swerling must be in 0..4, got {self.swerling}")
        if self.range_m <= 0:
            raise ValueError(f"range_m must be positive, got {self.range_m}")
        if self.amp_scale <= 0:
            raise ValueError(f"amp_scale must be positive, got {self.amp_scale}")

    def to_dict(self) -> dict:
        return {
            "class": self.class_,
            "range_m": self.range_m,
            "radial_vel_mps": self.radial_vel_mps,
            "accel_mps2": self.accel_mps2,
            "rcs_dbsm": self.rcs_dbsm,
            "swerling": self.swerling,
            "amp_scale": self.amp_scale,
            "micro": self.micro.to_dict() if self.micro is not None else None,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Phantom":
        d = dict(d)
        micro = d.pop("micro", None)
        class_ = d.pop("class")
        return cls(class_=class_, micro=MicroMotion.from_dict(micro) if micro else None, **d)


@dataclass
class Scene:
    """Decide-stage output (the engine's "action"). Design doc §3.3, §4."""
    phantoms: List[Phantom]
    maneuver: str
    eirp_budget_dbw: float
    t0_s: float
    duration_s: float

    def __post_init__(self):
        # See RadarState.__post_init__'s comment: coerce so a whole-number
        # value round-tripped through JSON doesn't silently arrive as int.
        self.eirp_budget_dbw = float(self.eirp_budget_dbw)
        self.t0_s = float(self.t0_s)
        self.duration_s = float(self.duration_s)
        if self.maneuver not in MANEUVERS:
            raise ValueError(f"maneuver must be one of {MANEUVERS}, got {self.maneuver!r}")
        if self.duration_s <= 0:
            raise ValueError(f"duration_s must be positive, got {self.duration_s}")

    def to_dict(self) -> dict:
        return {
            "phantoms": [p.to_dict() for p in self.phantoms],
            "maneuver": self.maneuver,
            "eirp_budget_dbw": self.eirp_budget_dbw,
            "t0_s": self.t0_s,
            "duration_s": self.duration_s,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Scene":
        return cls(
            phantoms=[Phantom.from_dict(p) for p in d["phantoms"]],
            maneuver=d["maneuver"],
            eirp_budget_dbw=d["eirp_budget_dbw"],
            t0_s=d["t0_s"],
            duration_s=d["duration_s"],
        )

    def to_json(self) -> str:
        return json.dumps(self.to_dict())

    @classmethod
    def from_json(cls, s: str) -> "Scene":
        return cls.from_dict(json.loads(s))


@dataclass
class Feedback:
    """Judge -> engine, closes the loop. Design doc §3.5, §4."""
    confirmed_tracks: int
    false_tracks_surviving: int
    flagged_decoys: int
    mean_track_lifetime_frames: float
    eirp_used_dbw: float
    per_phantom_status: List[str]
    # Feature-matched synthesis's internal safety net (radar_twin.predict,
    # cogengine.features.synthesize_tx_pulse): each entry is
    # {"frame": int, "reason": str, "confidence": float} for a frame where
    # characterization failed structurally (the known-radar dechirp still
    # aliased) and synthesis fell back to a raw noisy replay. MUST be
    # visible here, not silent -- an empty list is the claim "no fallback
    # fired," which is itself a checkable fact, not an absence of logging.
    degraded_events: List[dict] = field(default_factory=list)

    def __post_init__(self):
        # See RadarState.__post_init__'s comment: coerce so a whole-number
        # value round-tripped through JSON doesn't silently arrive as int
        # (or vice versa -- a count arriving as a JSON float).
        self.confirmed_tracks = int(self.confirmed_tracks)
        self.false_tracks_surviving = int(self.false_tracks_surviving)
        self.flagged_decoys = int(self.flagged_decoys)
        self.mean_track_lifetime_frames = float(self.mean_track_lifetime_frames)
        self.eirp_used_dbw = float(self.eirp_used_dbw)
        bad = [s for s in self.per_phantom_status if s not in PER_PHANTOM_STATUSES]
        if bad:
            raise ValueError(f"per_phantom_status entries must be one of {PER_PHANTOM_STATUSES}, got {bad}")
        if self.confirmed_tracks < 0 or self.false_tracks_surviving < 0 or self.flagged_decoys < 0:
            raise ValueError("counts must be non-negative")

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "Feedback":
        return cls(**d)

    def to_json(self) -> str:
        return json.dumps(self.to_dict())

    @classmethod
    def from_json(cls, s: str) -> "Feedback":
        return cls.from_dict(json.loads(s))
