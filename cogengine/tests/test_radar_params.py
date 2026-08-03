"""Phase A2: the Python and MATLAB constant tables must not drift.

`cogengine/radar_params.py` and `+physics/Constants.m` declare the same
physical facts for two languages. Nothing enforced that they agreed -- and
before A2 the Python side did not even have a table, just literals scattered
across three modules. This test parses the MATLAB source directly (no MATLAB
process needed, so it runs in plain pytest) and compares value for value.

Parsing the .m file rather than hardcoding the expected numbers here is the
point: a copy of 299792458.0 in this test would be a sixth independent copy
of the fact, which is what A2 removed.
"""
from __future__ import annotations

import pathlib
import re

import pytest

from cogengine import radar_params as rp

CONSTANTS_M = pathlib.Path(__file__).resolve().parents[2] / "+physics" / "Constants.m"


def _matlab_scalar(name: str) -> float:
    """Value assigned to `C.<name>` in +physics/Constants.m."""
    src = CONSTANTS_M.read_text()
    m = re.search(rf"^\s*C\.{name}\s*=\s*([0-9eE\.\+\-]+)\s*;", src, re.MULTILINE)
    assert m, f"C.{name} not found in {CONSTANTS_M}"
    return float(m.group(1))


def test_constants_m_is_readable():
    assert CONSTANTS_M.exists(), f"missing {CONSTANTS_M}"


def test_speed_of_light_matches_matlab():
    assert rp.SPEED_OF_LIGHT_MPS == _matlab_scalar("c")


def test_sample_rate_matches_matlab():
    assert rp.SAMPLE_RATE_HZ == _matlab_scalar("fs")


def test_range_per_sample_matches_matlab_derivation():
    # Constants.m derives it (C.c / (2*C.fs)) rather than assigning a literal,
    # so re-derive from the parsed anchors instead of parsing the result.
    expected = _matlab_scalar("c") / (2 * _matlab_scalar("fs"))
    assert rp.RANGE_PER_SAMPLE_M == expected
    assert rp.range_per_sample_m() == expected
    # The number the web client used to carry as a typed literal.
    assert rp.RANGE_PER_SAMPLE_M == pytest.approx(46.8426, abs=1e-4)


def test_range_per_sample_tracks_a_swept_fs():
    assert rp.range_per_sample_m(6.4e6) == pytest.approx(rp.RANGE_PER_SAMPLE_M / 2)


def test_thermal_constants_are_the_si_exact_values():
    # B1's link budget rests on these; wrong k or T0 silently moves every SNR.
    assert rp.BOLTZMANN_J_PER_K == 1.380649e-23
    assert rp.REFERENCE_TEMPERATURE_K == 290.0


def test_no_module_still_carries_its_own_speed_of_light():
    """The A2 regression guard: a re-typed literal anywhere in the active
    package puts the two tables back out of sync silently."""
    pkg = pathlib.Path(__file__).resolve().parents[1]
    offenders = []
    for py in pkg.rglob("*.py"):
        if "historical_baseline" in py.parts:
            continue  # frozen fixtures are deliberately preserved as-was
        if py.name in ("radar_params.py", pathlib.Path(__file__).name):
            continue  # the declaration itself, and this checker's own pattern
        for lineno, line in enumerate(py.read_text().splitlines(), 1):
            if "299792458" in line and not line.lstrip().startswith("#"):
                offenders.append(f"{py.name}:{lineno}: {line.strip()}")
    assert not offenders, "re-typed speed of light:\n" + "\n".join(offenders)
