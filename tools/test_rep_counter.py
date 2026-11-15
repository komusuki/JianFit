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
    reps = feed(c, [170, 149, 155, 161], step_ms=300)
    assert c.count == 1 and reps[0].deepest == 149


def test_stuck_between_thresholds_waits():
    c = RepCounter("dip", 150, 160)
    feed(c, [170, 100, 140, 155, 158])
    assert c.count == 0 and c.stage == COMING_UP


def test_two_reps():
    c = RepCounter("dip", 150, 160)
    reps = feed(c, [175, 120, 80, 120, 170, 175, 130, 70, 130, 171], step_ms=250)
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


def test_too_short_rep_is_dropped():
    # Below 150 and back above 160 within 300 ms (under MIN_REP_MS = 500): not a rep.
    c = RepCounter("dip", 150, 160)
    reps = feed(c, [175, 145, 165, 175], step_ms=150)
    assert c.count == 0 and not reps and c.stage == READY
    # The real rep right after it still counts.
    reps = feed(c, [175, 140, 100, 80, 100, 140, 170], step_ms=150)
    assert c.count == 1 and reps[0].deepest == 80


def test_invalid_thresholds_rejected():
    for args in (("dip", 160, 150), ("hill", 140, 150)):
        try:
            RepCounter(*args)
        except AssertionError:
            continue
        raise AssertionError(f"accepted invalid thresholds {args}")


# Ported from test/engine/rep_counter_test.dart (Member A).

def test_rep_of_exactly_min_rep_ms_still_counts():
    c = RepCounter("dip", 150, 160)
    assert c.update(175, {}, 0) is None
    assert c.update(140, {}, 100) is None       # leaves Ready
    assert c.update(120, {}, 300) is None
    assert c.update(165, {}, 600) is not None   # 500 ms long
    assert c.count == 1


def test_records_lowest_and_highest_value_of_each_measurement():
    c = RepCounter("dip", 150, 160)
    frames = [(175.0, 0.00), (140.0, 0.02), (100.0, 0.06), (130.0, 0.01), (165.0, 0.00)]
    done = None
    for i, (knee, heel) in enumerate(frames):
        done = c.update(knee, {"knee_angle": knee, "heel_lift": heel}, i * 300) or done
    assert done is not None
    assert done.min_during["knee_angle"] == 100 and done.max_during["knee_angle"] == 165
    assert done.max_during["heel_lift"] == 0.06 and done.min_during["heel_lift"] == 0.0


def test_next_rep_starts_its_ranges_fresh():
    c = RepCounter("dip", 150, 160)
    last = None
    for i, knee in enumerate([175.0, 140.0, 60.0, 165.0, 175.0, 140.0, 110.0, 165.0]):
        last = c.update(knee, {"knee_angle": knee}, i * 300) or last
    assert c.count == 2
    assert last.min_during["knee_angle"] == 110       # not 60 from the first rep


def test_text_values_are_not_tracked():
    # Python only: replay_check passes front_leg ("L"/"R") with the numbers.
    c = RepCounter("dip", 150, 160)
    done = None
    for i, knee in enumerate([175.0, 140.0, 100.0, 165.0]):
        done = c.update(knee, {"front_knee_angle": knee, "front_leg": "L"}, i * 300) or done
    assert "front_leg" not in done.min_during and done.min_during["front_knee_angle"] == 100


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  passed  {t.__name__}")
    print(f"All {len(tests)} rep counter tests passed.")
