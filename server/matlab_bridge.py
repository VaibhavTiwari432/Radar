"""server.matlab_bridge -- the only place Python is allowed to talk to MATLAB.

Holds ONE warm matlab.engine session. Measured on this machine: 68 s cold
start, then **0.75 s per call** -- which is why the session is kept warm and
not started per request. A `matlab -batch` shell-out per call would be
10-20 s each and unusable behind a slider.

HONESTY PROPERTY (CLAUDE.md guardrail 4, AC-6). If MATLAB cannot run, this
module raises JudgeUnavailable and the API returns 503. It NEVER returns a
fabricated feedback dict. That is the single most important behaviour here:
a console that invents a verdict when the judge is offline is worse than a
console that shows nothing, because it looks the same as a real one.
"""
from __future__ import annotations

import os
import threading
from typing import Any, Dict, Optional

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class JudgeUnavailable(RuntimeError):
    """MATLAB (the judge) cannot be reached. Callers must surface this, never
    substitute a result for it."""


class MatlabBridge:
    def __init__(self, project_root: str = PROJECT_ROOT, autostart: bool = True):
        self.project_root = project_root
        self._eng = None
        self._lock = threading.Lock()   # matlab.engine sessions are not reentrant
        self._last_error: Optional[str] = None
        if autostart:
            try:
                self.start()
            except JudgeUnavailable:
                pass    # stay offline; /score will 503 and say why

    # ---------------- lifecycle ----------------

    def start(self) -> None:
        try:
            import matlab.engine
        except ImportError as e:
            self._last_error = (
                "matlab.engine not installed. Install with: "
                "pip install \"<matlabroot>/extern/engines/python\"")
            raise JudgeUnavailable(self._last_error) from e

        try:
            eng = matlab.engine.start_matlab()
            eng.cd(self.project_root, nargout=0)
            eng.startup(nargout=0)          # project + pyenv paths
            self._eng = eng
            self._last_error = None
        except Exception as e:              # noqa: BLE001 -- report anything
            self._last_error = f"MATLAB failed to start: {e}"
            raise JudgeUnavailable(self._last_error) from e

    @property
    def online(self) -> bool:
        return self._eng is not None

    @property
    def last_error(self) -> Optional[str]:
        return self._last_error

    def _require(self):
        if self._eng is None:
            raise JudgeUnavailable(self._last_error or "judge unavailable")
        return self._eng

    def close(self) -> None:
        if self._eng is not None:
            try:
                self._eng.quit()
            finally:
                self._eng = None

    # ---------------- calls ----------------

    def score_scene(self, mat_path: str, include_frame_log: bool = False) -> Dict[str, Any]:
        """Run the real judge on an exported .mat and return its feedback.

        Takes a PATH, not a scene: the .mat is written by
        cogengine.matlab_judge.export_scene_for_judge, which is the seam this
        project already validates. Re-marshalling a Scene through the engine
        API would be a second, unvalidated contract.

        Goes via engine.runJudgeJson rather than calling engine.runJudge
        directly. matlab.engine can only return a SCALAR struct, and feedback
        carries frame_log -- a cell of struct ARRAYS. That marshals at 1
        confirmed track and raises "only a scalar struct can be returned from
        MATLAB" at 3, i.e. it fails precisely on the multi-phantom scenes this
        console exists to show. Found by the live browser test, not by
        inspection.
        """
        import json

        eng = self._require()
        with self._lock:
            try:
                raw = eng.feval("engine.runJudgeJson", mat_path,
                                bool(include_frame_log), nargout=1)
            except Exception as e:          # noqa: BLE001
                raise JudgeUnavailable(f"judge call failed: {e}") from e
        try:
            return json.loads(raw)
        except (TypeError, ValueError) as e:
            raise JudgeUnavailable(f"judge returned unparseable JSON: {e}") from e

    def feature_distance(self, iq_a, iq_b) -> float:
        """54-D PFB realism metric, from the project's OWN validated
        +features/featureDistance.m. Exposed here rather than reimplemented in
        Python on purpose -- see CLAUDE.md's cognitive_engine audit row."""
        import matlab
        eng = self._require()
        with self._lock:
            a = matlab.double([complex(v) for v in iq_a], is_complex=True)
            b = matlab.double([complex(v) for v in iq_b], is_complex=True)
            return float(eng.feval("features.featureDistance", a, b, nargout=1))

    def eval(self, expr: str):
        """Escape hatch for diagnostics (link budget, constants). Not a
        general-purpose RPC -- the API surface is score_scene."""
        eng = self._require()
        with self._lock:
            return eng.eval(expr, nargout=1)


_bridge: Optional[MatlabBridge] = None


def get_bridge() -> MatlabBridge:
    global _bridge
    if _bridge is None:
        _bridge = MatlabBridge()
    return _bridge
