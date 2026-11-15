"""Behaviour tests for rep_counter.py (the Python mirror of rep_counter.dart).

Run from the tools folder:  python test_rep_counter.py   (or: pytest test_rep_counter.py)
The same sequences can be used for a Dart test so both counters provably agree.
"""
from rep_counter import COMING_UP, GOING_DOWN, READY, RepCounter


def feed(counter, values, step_ms=100):
    reps = []
    for i, v in enumerate(values):
        r = counter.update(v, {"main": v, "frame": i}, i * step_ms)
        if r:
            reps.append(r)
    return reps


def test_one_dip_rep():
    c = RepCounter("dip", 150, 160)
    reps = feed(c, [175, 170, 150, 140, 120, 100, 90, 100, 120, 150, 165, 175])
    assert c.count == 1 and len(reps) == 1
    r = reps[0]
    assert r.deepest == 90 and r.at_deepest["frame"] == 6      # values captured at the deepest frame
    assert r.start_ms == 300 and r.end_ms == 1000 and r.duration_ms == 700


def test_jitter_between_thresholds_is_not_a_rep():
    c = RepCounter("dip", 150, 160)
    feed(c, [175, 165, 155, 158, 152, 157, 155, 159, 151])
    assert c.count == 0 and c.stage == READY


def test_hysteresis_small_dip_still_counts():
    # Below 150 then above 160 counts, however small the dip (by design of the two thresholds).
    c = RepCounter("dip", 150, 160)
    reps = feed(c, [170, 149, 155, 161])
    assert c.count == 1 and reps[0].deepest == 149


def test_stuck_between_thresholds_waits():
    c = RepCounter("dip", 150, 160)
    feed(c, [170, 100, 140, 155, 158])
    assert c.count == 0 and c.stage == COMING_UP


def test_two_reps():
    c = RepCounter("dip", 150, 160)
    reps = feed(c, [175, 120, 80, 120, 170, 175, 130, 70, 130, 171])
    assert c.count == 2 and [r.deepest for r in reps] == [80, 70]


def test_turnaround_marks_bottom_passed():
    c = RepCounter("dip", 150, 160)
    feed(c, [175, 140, 100, 104])
    assert c.stage == GOING_DOWN            # moved back 4, less than 5
    feed(c, [106])
    assert c.stage == COMING_UP             # moved back 6
    feed(c, [95])
    assert c.stage == GOING_DOWN            # went deeper again


def test_hill_direction():
    c = RepCounter("hill", 150, 140)
    reps = feed(c, [120, 130, 155, 170, 175, 165, 150, 138])
    assert c.count == 1 and reps[0].deepest == 175


def test_reset_drops_rep_in_progress():
    c = RepCounter("dip", 150, 160)
    feed(c, [175, 120, 90])
    c.reset(keep_count=True)
    feed(c, [165, 170])
    assert c.count == 0 and c.stage == READY


def test_invalid_thresholds_rejected():
    for args in (("dip", 160, 150), ("hill", 140, 150)):
        try:
            RepCounter(*args)
        except AssertionError:
            continue
        raise AssertionError(f"accepted invalid thresholds {args}")


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  passed  {t.__name__}")
    print(f"All {len(tests)} rep counter tests passed.")
