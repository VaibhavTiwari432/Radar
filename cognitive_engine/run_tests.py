#!/usr/bin/env python3
"""Self-contained test runner (no pytest needed).
Usage:  python run_tests.py
"""
import sys, traceback, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tests import test_schema, test_renderer, test_planner, test_features

TESTS = [
    ("schema.roundtrip",            test_schema.test_scene_roundtrip),
    ("schema.derived",              test_schema.test_radarstate_derived),
    ("schema.feedback",             test_schema.test_feedback_roundtrip),
    ("renderer.range_delay",        test_renderer.test_range_to_delay),
    ("renderer.doppler==rangerate", test_renderer.test_doppler_matches_range_rate),
    ("renderer.microdoppler",       test_renderer.test_microdoppler_line_spacing),
    ("planner.cem_beats_naive",     test_planner.test_cem_beats_naive_copy),
    ("features.chirp_rate",         test_features.test_chirp_rate_recovered),
    ("features.matched>mismatch",   test_features.test_matched_replica_beats_mismatched),
    ("features.classify",           test_features.test_waveform_classified),
    ("features.realism_metric",     test_features.test_feature_space_orders_realism),
]

def main():
    passed = 0
    for name, fn in TESTS:
        try:
            fn()
            print(f"  PASS  {name}")
            passed += 1
        except Exception:
            print(f"  FAIL  {name}")
            traceback.print_exc()
    print(f"\n{passed}/{len(TESTS)} tests passed")
    sys.exit(0 if passed == len(TESTS) else 1)

if __name__ == "__main__":
    main()
