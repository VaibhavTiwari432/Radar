"""Persistent MATLAB engine bridge for D3QN training.

Blueprint Part 6.1 / Gate C hygiene: the agent trains and evaluates against
the REAL independent judge (+engine/runJudge.m), never a twin -- see the
design discussion this module resulted from (no twin was built for this
first version; every reward in generator/decision/env.py is a real judge
verdict). The only thing this module optimizes is NOT re-paying MATLAB's
process-startup cost (~5-10s) on every training step: one `matlab.engine`
process is started once and reused for the whole run. Render+judge
computation itself (~3-6s/episode warm, measured directly --
generator/decision/tests/test_bridge_timing.py) is NOT something this module
tries to hide or shortcut; it is the real cost of scoring against the real
instrument, which is the whole point of not building a twin.
"""
import os
import tempfile
import time
from pathlib import Path
from typing import Optional

import matlab.engine

_PROJECT_ROOT = Path(__file__).resolve().parents[2]


class MatlabBridge:
    """One persistent MATLAB engine, reused across an entire training run.

    Usage:
        with MatlabBridge() as bridge:
            judge_mat = bridge.render(pre_render_mat, render_kwargs)
            feedback = bridge.run_judge(judge_mat, judge_kwargs)
    """

    def __init__(self, project_root: Optional[str] = None, scratch_dir: Optional[str] = None):
        self.project_root = project_root or str(_PROJECT_ROOT)
        self.scratch_dir = scratch_dir or tempfile.mkdtemp(prefix="d3qn_bridge_")
        self._eng = None

    def __enter__(self) -> "MatlabBridge":
        t0 = time.time()
        self._eng = matlab.engine.start_matlab()
        self._eng.addpath(self.project_root, nargout=0)
        self.startup_seconds = time.time() - t0
        return self

    def __exit__(self, exc_type, exc, tb):
        if self._eng is not None:
            self._eng.quit()
            self._eng = None

    def render(self, pre_render_mat_path: str, judge_mat_path: Optional[str] = None,
               **render_kwargs) -> str:
        """Calls generator.render(preRenderMatPath, judgeMatPath, Name, value, ...).
        render_kwargs keys/values are passed through as MATLAB name-value pairs
        (e.g. IncludeAngleChannel=True, PhantomSweepSchedule=[1,-1,...])."""
        if judge_mat_path is None:
            judge_mat_path = os.path.join(self.scratch_dir, "judge.mat")
        nv = _flatten_name_value(render_kwargs)
        self._eng.generator.render(pre_render_mat_path, judge_mat_path, *nv, nargout=0)
        return judge_mat_path

    def run_judge(self, judge_mat_path: str, **judge_kwargs) -> dict:
        """Calls generator.judgeSummary (NOT engine.runJudge directly --
        see +generator/judgeSummary.m for why: engine.runJudge's
        feedback.frame_log can contain a non-scalar nested struct array,
        which MATLAB Engine API for Python cannot auto-convert at all,
        crashing the WHOLE call with "only a scalar struct can be
        returned" -- found by a real training run failing after ~75
        episodes, not by inspection) and returns a plain Python dict."""
        nv = _flatten_name_value(judge_kwargs)
        fb = self._eng.generator.judgeSummary(judge_mat_path, *nv, nargout=1)
        return {
            "confirmed_tracks": int(fb["confirmed_tracks"]),
            "false_tracks_surviving": int(fb["false_tracks_surviving"]),
            "flagged_decoys": int(fb["flagged_decoys"]),
            "eccm_label": str(fb["eccm_label"]),
            "track_label": str(fb["track_label"]).split(",") if fb["track_label"] else [],
        }


def _flatten_name_value(kwargs: dict) -> list:
    """{'IncludeAngleChannel': True} -> ['IncludeAngleChannel', True], with
    Python bool/list converted to MATLAB-friendly types (matlab.engine
    handles Python bool/float/str natively; lists need matlab.double)."""
    import matlab as _matlab
    out = []
    for k, v in kwargs.items():
        out.append(k)
        if isinstance(v, list) and v and all(isinstance(x, str) for x in v):
            # A list of STRINGS is a cell array, not a numeric array.
            # matlab.double() on ['amplitude','bearing'] raises, and this bit
            # the EccmScreens wiring the moment it was added -- the numeric
            # branch below had been the only one because every list until now
            # was a bearing or sweep schedule.
            out.append(list(v))
        elif isinstance(v, list):
            out.append(_matlab.double(v))
        else:
            out.append(v)
    return out
