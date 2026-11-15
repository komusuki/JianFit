"""Form judge tests, ported from test/engine/form_judge_test.dart (Member A).

Run from the tools folder:  python test_form_judge.py
"""
from form_judge import FormCheck, judge_rep
from rep_counter import RepResult


def limits(beginner, standard, strict):
    return (("beginner", beginner), ("standard", standard), ("strict", strict))


DEPTH = FormCheck("depth", "range", "knee_angle", "bottom", "max", limits(100, 100, 100),
                  "Go lower.", 2)
TORSO_LEAN = FormCheck("torso_lean", "cleanliness", "torso_lean", "bottom", "max",
                       limits(50, 45, 40), "Keep your chest up.", 3)
HEELS_DOWN = FormCheck("heels_down", "cleanliness", "heel_lift", "throughout", "max",
                       limits(0.08, 0.05, 0.03), "Keep your heels down.", 4)
KNEES_OUT = FormCheck("knee_safety", "safety", "hip_angle", "bottom", "min",
                      limits(40, 40, 40), "Stop and reset.", 9)
CHECKS = [DEPTH, TORSO_LEAN, HEELS_DOWN]


def rep(knee=90, lean=30, hip=80, heel_max=0.01, heel_tracked=True):
    return RepResult(
        deepest=knee,
        at_deepest={"knee_angle": knee, "torso_lean": lean, "hip_angle": hip},
        duration_ms=1500, end_ms=3000,
        min_during={"knee_angle": knee, **({"heel_lift": 0.0} if heel_tracked else {})},
        max_during={"knee_angle": 175, **({"heel_lift": heel_max} if heel_tracked else {})},
    )


def test_a_rep_that_passes_every_check_is_correct():
    v = judge_rep(rep(), CHECKS, "standard")
    assert v.correct and v.failed == [] and v.top_failed is None


def test_a_failed_range_check_makes_the_rep_attempted():
    v = judge_rep(rep(knee=120), CHECKS, "standard")
    assert not v.correct and v.failed == [DEPTH] and v.top_failed.cue == "Go lower."


def test_a_failed_cleanliness_check_makes_the_rep_attempted():
    assert judge_rep(rep(lean=48), CHECKS, "standard").failed == [TORSO_LEAN]


def test_a_failed_safety_check_makes_the_rep_attempted():
    assert judge_rep(rep(hip=30), CHECKS + [KNEES_OUT], "standard").failed == [KNEES_OUT]


def test_strictness_changes_the_result_of_a_cleanliness_check():
    r = rep(lean=42)                       # limits: 50, 45, 40
    assert judge_rep(r, CHECKS, "beginner").correct
    assert judge_rep(r, CHECKS, "standard").correct
    assert not judge_rep(r, CHECKS, "strict").correct


def test_strictness_does_not_change_a_range_check():
    for s in ("beginner", "standard", "strict"):
        assert not judge_rep(rep(knee=105), [DEPTH], s).correct


def test_throughout_uses_the_worst_value_during_the_rep():
    # At the bottom the heel could be down, but it lifted 0.07 at some point.
    assert judge_rep(rep(heel_max=0.07), CHECKS, "standard").failed == [HEELS_DOWN]


def test_a_measurement_with_no_value_is_skipped_not_failed():
    v = judge_rep(rep(heel_tracked=False), CHECKS, "standard")
    assert v.correct and v.skipped == [HEELS_DOWN]


def test_top_cue_safety_first_then_lowest_priority_number():
    v = judge_rep(rep(knee=120, lean=60, hip=30), CHECKS + [KNEES_OUT], "standard")
    assert len(v.failed) == 3 and v.top_failed == KNEES_OUT    # safety, even with priority 9
    assert judge_rep(rep(knee=120, lean=60), CHECKS, "standard").top_failed == DEPTH  # 2 beats 3


def test_a_value_exactly_at_the_limit_passes():
    assert judge_rep(rep(knee=100), [DEPTH], "standard").correct
    assert judge_rep(rep(hip=40), [KNEES_OUT], "standard").correct


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  passed  {t.__name__}")
    print(f"All {len(tests)} form judge tests passed.")
