"""Automated frame-by-frame diff between the Python twin's and the MATLAB
judge's results on the canonical scene fixtures. Run AFTER both
canonical_scene_crosscheck.py (Python) and canonical_scene_crosscheck.m
(MATLAB) have produced their JSON outputs in this directory.

Exits nonzero (and prints exactly what mismatched) if anything is out of
tolerance, for ANY scenario -- this is the repeatable version of the by-hand
comparison used to find and fix the chirp-time-reference bug and the
eccm_label combining-logic bug.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RANGE_TOL_M = 5.0
AMP_TOL_REL = 0.05

SCENARIOS = ["closing_real", "static_decoy"]


def compare_one(name: str) -> list:
    with open(os.path.join(HERE, f"{name}_python_result.json")) as f:
        py = json.load(f)
    with open(os.path.join(HERE, f"{name}_matlab_result.json")) as f:
        ml = json.load(f)

    problems = []
    n = len(py["true_range_m"])

    print(f"\n=== {name} ===")
    print(f"{'frame':>5} {'true_R':>9} {'py_det':>7} {'ml_det':>7} "
          f"{'py_range':>10} {'ml_range':>10} {'d_range':>8} "
          f"{'py_amp':>8} {'ml_amp':>8} {'d_amp%':>7}")

    for k in range(n):
        py_r, ml_r = py["range_est_m"][k], ml["range_est_m"][k]
        py_a, ml_a = py["amp_est"][k], ml["amp_est"][k]
        py_d, ml_d = bool(py["detected"][k]), bool(ml["detected"][k])

        d_range = (py_r - ml_r) if (py_r is not None and ml_r is not None) else float("nan")
        d_amp_pct = (100.0 * (py_a - ml_a) / ml_a) if (py_a and ml_a) else float("nan")

        print(f"{k+1:>5} {py['true_range_m'][k]:>9.1f} {str(py_d):>7} {str(ml_d):>7} "
              f"{py_r:>10.2f} {ml_r:>10.2f} {d_range:>8.2f} "
              f"{py_a:>8.3f} {ml_a:>8.3f} {d_amp_pct:>6.1f}%")

        if py_d != ml_d:
            problems.append(f"[{name}] frame {k+1}: detected mismatch (python={py_d}, matlab={ml_d})")
        if py_d and ml_d and abs(d_range) > RANGE_TOL_M:
            problems.append(f"[{name}] frame {k+1}: range_est differs by {d_range:.2f} m")
        if py_d and ml_d and abs(d_amp_pct) > AMP_TOL_REL * 100:
            problems.append(f"[{name}] frame {k+1}: amp_est differs by {d_amp_pct:.1f}%")

    print(f"confirmed:  python={py['confirmed']}  matlab={ml['confirmed']}")
    print(f"eccm_label: python={py['eccm_label']!r}  matlab={ml['eccm_label']!r}")

    if py["confirmed"] != ml["confirmed"]:
        problems.append(f"[{name}] confirmed mismatch: python={py['confirmed']}, matlab={ml['confirmed']}")
    if py["eccm_label"] != ml["eccm_label"]:
        problems.append(f"[{name}] eccm_label mismatch: python={py['eccm_label']!r}, matlab={ml['eccm_label']!r}")

    return problems


def main():
    all_problems = []
    for name in SCENARIOS:
        all_problems.extend(compare_one(name))

    print()
    if all_problems:
        print("MISMATCHES FOUND:")
        for p in all_problems:
            print(f"  - {p}")
        sys.exit(1)
    else:
        print(f"Twin and judge agree on all {len(SCENARIOS)} canonical scenarios within tolerance.")
        sys.exit(0)


if __name__ == "__main__":
    main()
