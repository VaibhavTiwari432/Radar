"""
schema.py — the DATA CONTRACT between the cognitive engine (Python) and the
radar pipeline / judge (MATLAB).

Everything that crosses the language boundary is one of these four objects.
Mirror of `matlab_integration/scene_contract.m`.

Design doc: Part 4 (Data contracts).
"""
from __future__ import annotations
from dataclasses import dataclass, field, asdict
from typing import List, Optional, Tuple, Dict, Any

# Speed of light (m/s). The one physical constant everything derives from.
C = 2.99792458e8

# Kinematic envelopes per platform class (max radial speed m/s, max accel m/s^2).
# Used by the truth model to keep every phantom physically possible.
CLASS_ENVELOPES: Dict[str, Dict[str, float]] = {
    "drone":    {"v_max": 55.0,  "a_max": 12.0},
    "fighter":  {"v_max": 600.0, "a_max": 90.0},
    "airliner": {"v_max": 260.0, "a_max": 8.0},
    "missile":  {"v_max": 900.0, "a_max": 300.0},
    "decoy":    {"v_max": 300.0, "a_max": 40.0},
}


@dataclass
class RadarState:
    """What the engine believes about the (known) victim radar RIGHT NOW.

    Because the mother drone knows the radar, most of this is prior knowledge;
    the runtime-varying parts are `mode`, `scan_phase`, the gate positions and
    `doubt_cue`. See design doc Part 3.1.
    """
    mode: str = "track"
    prf_hz: float = 50_000.0
    carrier_hz: float = 10.0e9      # X-band assumption (RadChar is baseband -> carrier is assumed)
    fs_hz: float = 3.2e6            # matches RadChar sampling
    n_pulses: int = 512            # slow-time (Doppler) dimension
    n_fast: int = 512              # fast-time (range) samples
    range_gate_m: Tuple[float, float] = (0.0, 3000.0)
    vel_gate_mps: Tuple[float, float] = (-375.0, 375.0)
    scan_phase: float = 0.0
    doubt_cue: float = 0.0          # in [0,1]: observable hint the radar distrusts a track

    @property
    def pri_s(self) -> float:
        return 1.0 / self.prf_hz

    @property
    def wavelength_m(self) -> float:
        return C / self.carrier_hz

    @property
    def unambiguous_range_m(self) -> float:
        return C * self.pri_s / 2.0

    @property
    def unambiguous_vel_mps(self) -> float:
        return self.wavelength_m * self.prf_hz / 4.0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "RadarState":
        d = dict(d)
        for k in ("range_gate_m", "vel_gate_mps"):
            if k in d and d[k] is not None:
                d[k] = tuple(d[k])
        return cls(**d)


@dataclass
class Phantom:
    """One virtual identity. NOT signal knobs (A, tau, phi) — a physical intent.
    Layers 1-2 render it coherently so every observable is mutually consistent.
    """
    cls: str = "drone"
    range_m: float = 1000.0
    radial_vel_mps: float = 30.0
    accel_mps2: float = 0.0
    rcs_dbsm: float = 0.0
    swerling: int = 1               # 0 nonfluct; 1/2 Rayleigh; 3/4 chi-sq-4 (odd scan, even pulse)
    micro: Optional[Dict[str, Any]] = None   # {"type","n_blades","rpm","blade_len_m"}
    amp_scale: float = 1.0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Phantom":
        return cls(**d)


@dataclass
class Scene:
    """The engine's OUTPUT = the 'action'. A whole phantom swarm + how to fly it."""
    phantoms: List[Phantom] = field(default_factory=list)
    maneuver: str = "swarm"         # static | rgpo | vgpo | swarm
    eirp_budget_dbw: float = 10.0
    t0_s: float = 0.0
    duration_s: float = 0.05

    def to_dict(self) -> Dict[str, Any]:
        return {
            "phantoms": [p.to_dict() for p in self.phantoms],
            "maneuver": self.maneuver,
            "eirp_budget_dbw": self.eirp_budget_dbw,
            "t0_s": self.t0_s,
            "duration_s": self.duration_s,
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Scene":
        d = dict(d)
        d["phantoms"] = [Phantom.from_dict(p) for p in d.get("phantoms", [])]
        return cls(**d)


@dataclass
class Feedback:
    """What the INDEPENDENT judge (MATLAB) reports back — closes the learn loop."""
    confirmed_tracks: int = 0
    false_tracks_surviving: int = 0
    flagged_decoys: int = 0
    mean_track_lifetime_frames: float = 0.0
    eirp_used_dbw: float = 0.0
    per_phantom_status: List[str] = field(default_factory=list)  # undetected|detected|confirmed|flagged

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Feedback":
        return cls(**d)


@dataclass
class WaveformParams:
    """What FEATURE EXTRACTION recovers from an intercepted pulse — the bridge
    from 'perceive' to 'synthesize'. These parameters are what let the DRFM build
    a COHERENT, matched replica (one that pulse-compresses in the victim's matched
    filter). Without them, a copy smears and fails. See features.py.
    """
    wclass: str = "unknown"        # lfm | coded | tone | unknown
    f0_hz: float = 0.0             # spectral centroid (center frequency)
    bandwidth_hz: float = 0.0      # occupied bandwidth (90% energy)
    chirp_rate_hz_s: float = 0.0   # LFM sweep rate k = B/T
    pulse_width_s: float = 0.0
    n_samples: int = 0
    confidence: float = 0.0        # linear-IF fit quality in [0,1]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "WaveformParams":
        return cls(**d)
