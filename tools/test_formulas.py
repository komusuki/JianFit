"""Checks formulas.py against the formula document's test cases.

The cases live in test/fixtures/formula_cases.json (shared with the Dart test).
Run either way, from the tools folder:
    python test_formulas.py
    pytest test_formulas.py        (if pytest is installed)
"""
import json
import math
from pathlib import Path

import formulas as f

CASES_PATH = Path(__file__).resolve().parent.parent / "test" / "fixtures" / "formula_cases.json"
TOL = 0.01
CASES = json.loads(CASES_PATH.read_text())


def close(actual, expected):
    if expected == "nan":
        return math.isnan(actual)
    return abs(actual - expected) <= TOL


def test_joint_angle():
    for c in CASES["joint_angle"]:
        assert close(f.joint_angle(c["a"], c["b"], c["c"]), c["expected"]), c


def test_lean():
    for c in CASES["lean"]:
        assert close(f.lean(c["shoulder"], c["hip"]), c["expected"]), c


def test_hip_sag():
    for c in CASES["hip_sag"]:
        assert close(f.hip_sag(c["shoulder"], c["hip"], c["end"]), c["expected"]), c


def test_head_drop():
    for c in CASES["head_drop"]:
        value, dropping = f.head_drop(c["ear"], c["shoulder"], c["hip"])
        assert close(value, c["expected"]) and dropping == c["dropping"], c


def test_align():
    for c in CASES["align"]:
        L = f.body_length(c["shoulder"], c["hip"])
        assert close(f.align(c["p"], c["q"], c["facing"], L), c["expected"]), c


def test_heel_lift():
    for c in CASES["heel_lift"]:
        assert close(f.heel_lift(c["base_heel_y"], c["heel_y"], c["L"]), c["expected"]), c


def test_smoothing():
    for c in CASES["smoothing"]:
        s = f.Smoother(c["n"])
        out = [s.push(v) for v in c["inputs"]]
        assert all(close(a, e) for a, e in zip(out, c["expected"])), (out, c)


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  passed  {t.__name__}")
    print(f"All {len(tests)} formula tests passed (tolerance {TOL}).")
