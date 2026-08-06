"""Provenance tagging (Virtual Entity Engine Scientific Blueprint, provenance
discipline). Every quantitative claim in the generator rebuild carries exactly
one tag: MEASURED, DERIVED, ASSUMED, or UNVALIDATED. This module makes that a
runtime-checkable property instead of a comment convention that rots.
"""
from dataclasses import dataclass
from enum import Enum
from typing import Any, Generic, TypeVar

T = TypeVar("T")


class Provenance(str, Enum):
    MEASURED = "MEASURED"        # produced by a re-runnable test/simulation
    DERIVED = "DERIVED"          # computed from measured values via a stated formula
    ASSUMED = "ASSUMED"          # a design input (cite the source)
    UNVALIDATED = "UNVALIDATED"  # plausible but not yet tested


@dataclass(frozen=True)
class Tagged(Generic[T]):
    """A value plus its provenance tag and the reason/source, carried together
    so a claim can't get separated from what backs it as code moves around."""
    value: T
    provenance: Provenance
    source: str  # the formula, test name, or citation this value rests on

    def __repr__(self) -> str:
        return f"{self.value!r} [{self.provenance.value}: {self.source}]"


def tag(value: Any, provenance: Provenance, source: str) -> Tagged:
    return Tagged(value=value, provenance=provenance, source=source)
