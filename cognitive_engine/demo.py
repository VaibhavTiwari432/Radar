#!/usr/bin/env python3
"""
demo.py — the hackathon money-shot at scaffold scale.

Compares, on the SAME radar twin:
    (A) the "standard method" — a naive DRFM copy swarm (zero Doppler, no micro-D)
    (B) the model-based cognitive engine — CEM-planned phantoms

and prints the surviving-false-track counts. In the real pipeline you replace the
twin's score with the INDEPENDENT MATLAB judge (phased.CFARDetector + trackerGNN).

Usage:  python demo.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from cogengine.schema import RadarState
from cogengine.radar_twin import RadarTwin
from cogengine.planner_cem import naive_copy_scene, cem_plan


def describe(scene):
    lines = []
    for i, p in enumerate(scene.phantoms):
        m = "on" if p.micro else "off"
        lines.append(f"    #{i}: R={p.range_m:6.0f} m  v_r={p.radial_vel_mps:+7.1f} m/s  micro-Doppler={m}")
    return "\n".join(lines)


def main():
    radar = RadarState()
    twin = RadarTwin(radar)
    print(f"Radar (known): X-band  PRF={radar.prf_hz/1e3:.0f} kHz  "
          f"unamb range={radar.unambiguous_range_m/1e3:.2f} km  "
          f"unamb vel=+/-{radar.unambiguous_vel_mps:.0f} m/s\n")

    # (A) baseline
    naive = naive_copy_scene(radar, n=4)
    a = twin.score(naive)
    print("(A) NAIVE DRFM COPY SWARM  [the standard method]")
    print(describe(naive))
    print(f"    -> detected={a['detected']}/4  survivors={a['survivors']}  "
          f"flagged_by_ECCM={a['flagged']}\n")

    # (B) cognitive engine
    best, reward, hist = cem_plan(radar, twin, n_phantoms=4, iters=8, pop=48, seed=0)
    b = twin.score(best)
    print("(B) MODEL-BASED COGNITIVE ENGINE  [CEM plans against the radar twin]")
    print(describe(best))
    print(f"    -> detected={b['detected']}/4  survivors={b['survivors']}  "
          f"flagged_by_ECCM={b['flagged']}")
    print(f"    CEM elite-reward trajectory: {[round(h,2) for h in hist]}\n")

    print("HEADLINE (twin-predicted):  naive survivors = "
          f"{a['survivors']}   vs   cognitive-engine survivors = {b['survivors']}")
    print("Next: run BOTH scenes through the independent MATLAB judge; the gap")
    print("between this twin and that judge is the number to report honestly.")


if __name__ == "__main__":
    main()
