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


# Jump squat (Day 9). The setup baseline is off by +0.25 body lengths on purpose: the counter
# uses the rise since the rep started, so the offset must not matter. The same frames are in
# test/engine/rep_counter_test.dart.
OFFSET = 0.25
JUMP = [  # (knee angle, rise of the left ankle since setup); the right ankle is 0.02 lower
    (175, 0), (140, 0), (110, 0), (100, 0), (120, 0), (160, 0), (175, 0.05),   # squat, take off
    (178, 0.30), (178, 0.45), (176, 0.22),                                      # in the air
    (170, 0.02), (140, 0), (125, 0), (135, 0), (150, 0), (165, 0), (175, 0),    # land, stand up
]


def jump_feed(c, frames, step_ms=100):
    reps = []
    for i, (knee, rise) in enumerate(frames):
        values = {"knee_angle": knee, "jump_rise_left": OFFSET + rise,
                  "jump_rise_right": OFFSET + rise - 0.02 if rise else OFFSET}
        r = c.update(knee, values, i * step_ms)
        if r:
            reps.append(r)
    return reps


def test_jump_rep_completes_after_the_landing_window():
    c = RepCounter("dip", 150, 160, jump_limit=0.15)
    reps = jump_feed(c, JUMP)
    assert c.count == 1 and len(reps) == 1
    r = reps[0]
    assert r.deepest == 100                                       # the squat, not the landing bend
    assert abs(r.at_deepest["jump_height"] - 0.43) < 1e-9         # both ankles: the lower one
    assert r.at_deepest["landing_knee_min"] == 125                # smallest in 500 ms after landing
    assert r.end_ms == 1500                                       # landed at 1000 + 500 ms


def test_squat_without_a_jump_completes_after_the_wait():
    c = RepCounter("dip", 150, 160, jump_limit=0.15)
    frames = [(175, 0), (140, 0), (100, 0), (120, 0), (165, 0), (170, 0), (172, 0), (172, 0),
              (172, 0)]
    reps = jump_feed(c, frames)
    assert len(reps) == 1 and reps[0].end_ms == 800               # back up at 400 + 400 ms
    assert reps[0].at_deepest["jump_height"] == 0
    assert "landing_knee_min" not in reps[0].at_deepest


def test_one_ankle_rising_is_not_a_jump():
    c = RepCounter("dip", 150, 160, jump_limit=0.15)
    reps = []
    for i, (knee, left) in enumerate([(175, 0), (140, 0), (100, 0), (165, 0), (175, 0.5),
                                      (175, 0.5), (175, 0.5), (175, 0.5), (175, 0)]):
        values = {"knee_angle": knee, "jump_rise_left": left, "jump_rise_right": 0}
        r = c.update(knee, values, i * 100)
        if r:
            reps.append(r)
    assert len(reps) == 1 and reps[0].at_deepest["jump_height"] == 0


def raw_feed(c, frames):
    """frames: (knee, left ankle rise, right ankle rise), 100 ms apart."""
    reps = []
    for i, (knee, left, right) in enumerate(frames):
        r = c.update(knee, {"knee_angle": knee, "jump_rise_left": left,
                            "jump_rise_right": right}, i * 100)
        if r:
            reps.append(r)
    return reps


def test_jump_is_measured_from_the_lowest_ankle_before_takeoff():
    # The rep starts while the ankles still read 0.08 high (mid-motion). Measured from the
    # rep start the jump would be 0.12 (no jump); from the floor it is 0.20.
    c = RepCounter("dip", 150, 160, jump_limit=0.15)
    reps = raw_feed(c, [
        (175, 0.08, 0.08), (140, 0.08, 0.08), (110, 0, 0), (100, 0, 0), (160, 0, 0),
        (175, 0.20, 0.20), (176, 0.05, 0.05),
        (130, 0, 0), (140, 0, 0), (160, 0, 0), (170, 0, 0), (175, 0, 0),
    ])
    assert len(reps) == 1
    assert abs(reps[0].at_deepest["jump_height"] - 0.20) < 1e-9
    assert reps[0].end_ms == 1100                                 # landed at 600 + 500 ms


def test_one_ankle_down_counts_as_landing():
    # The far ankle keeps reading 0.16 to 0.20 after landing. Waiting for both ankles would
    # never land, and the next jump would merge into this rep.
    c = RepCounter("dip", 150, 160, jump_limit=0.15)
    reps = raw_feed(c, [
        (175, 0, 0), (140, 0, 0), (100, 0, 0), (160, 0, 0), (175, 0.30, 0.30),
        (176, 0.40, 0.40), (170, 0.05, 0.20),
        (130, 0, 0.18), (140, 0, 0.17), (160, 0, 0.16), (170, 0, 0.16), (175, 0, 0.16),
    ])
    assert len(reps) == 1 and reps[0].end_ms == 1100              # landed at 600 + 500 ms
    assert reps[0].at_deepest["landing_knee_min"] == 130


# Phone check, Nov 17: quick back-to-back jumps merged, and standing up slowly after a landing
# was counted as an extra rep. Frames are 100 ms apart: (knee, left ankle rise, right ankle rise).
B2B = [
    (175, 0, 0), (140, 0, 0), (100, 0, 0), (160, 0, 0), (175, 0.3, 0.3), (176, 0.4, 0.4),
    (170, 0.05, 0.05), (120, 0, 0), (100, 0, 0), (165, 0, 0),        # land at 600, dip, push
    (175, 0.3, 0.3), (176, 0.4, 0.4), (170, 0.05, 0.05),             # takeoff at 1000, land 1200
    (120, 0, 0), (100, 0, 0), (165, 0, 0),
    (175, 0.3, 0.3), (176, 0.4, 0.4), (170, 0.05, 0.05),             # takeoff at 1600, land 1800
    (130, 0, 0), (140, 0, 0), (160, 0, 0), (170, 0, 0), (175, 0, 0),
]


def test_back_to_back_jumps_are_separate_reps():
    c = RepCounter("dip", 150, 160, jump_limit=0.10)
    reps = raw_feed(c, B2B)
    assert c.count == 3
    assert [r.end_ms for r in reps] == [1000, 1600, 2300]   # takeoffs end reps 1 and 2
    assert [r.start_ms for r in reps] == [100, 1000, 1600]
    assert [r.deepest for r in reps] == [100, 100, 100]     # each rep's own squat
    assert reps[2].at_deepest["landing_knee_min"] == 130


def test_standing_up_slowly_after_landing_is_not_a_rep():
    c = RepCounter("dip", 150, 160, jump_limit=0.10)
    reps = raw_feed(c, [
        (175, 0, 0), (140, 0, 0), (100, 0, 0), (160, 0, 0), (175, 0.3, 0.3), (176, 0.4, 0.4),
        (170, 0.05, 0.05), (130, 0, 0), (120, 0, 0), (125, 0, 0), (135, 0, 0),
        (142, 0, 0),                                     # landing window ends, knee still bent
        (148, 0, 0), (155, 0, 0), (165, 0, 0), (172, 0, 0), (172, 0, 0), (172, 0, 0),
        (172, 0, 0), (172, 0, 0), (172, 0, 0),
    ])
    assert c.count == 1 and reps[0].end_ms == 1100


def test_takeoff_after_the_landing_window_starts_a_rep_in_the_air():
    c = RepCounter("dip", 150, 160, jump_limit=0.10)
    reps = raw_feed(c, [
        (175, 0, 0), (140, 0, 0), (100, 0, 0), (160, 0, 0), (175, 0.3, 0.3), (176, 0.4, 0.4),
        (170, 0.05, 0.05), (150, 0, 0), (120, 0, 0), (100, 0, 0), (95, 0, 0),
        (110, 0, 0),                                     # rep 1 completes at 1100, still bent
        (150, 0, 0), (165, 0, 0), (175, 0.3, 0.3),       # no stand-up pause, takeoff at 1400
        (176, 0.4, 0.4), (170, 0.05, 0.05),              # land at 1600
        (140, 0, 0), (150, 0, 0), (160, 0, 0), (170, 0, 0), (175, 0, 0),
    ])
    assert c.count == 2
    assert reps[1].start_ms == 1100 and reps[1].end_ms == 2100
    assert reps[1].deepest == 95                         # the dip before the takeoff
    assert abs(reps[1].at_deepest["jump_height"] - 0.4) < 1e-9


def test_ankle_drift_in_a_deep_landing_is_not_a_takeoff():
    # Phone check 2, Nov 17: in a deep landing the ankle points drift up past the limit; that
    # was taken as a second takeoff, so every rep ended early with a high landing angle.
    c = RepCounter("dip", 150, 160, jump_limit=0.10)
    reps = raw_feed(c, [
        (175, 0, 0), (140, 0, 0), (100, 0, 0), (160, 0, 0), (175, 0.3, 0.3), (176, 0.4, 0.4),
        (170, 0.05, 0.05),                                   # land at 600
        (130, 0.08, 0.08), (110, 0.12, 0.12), (100, 0.13, 0.13), (120, 0.08, 0.08),
        (150, 0.02, 0.02),                                   # landing window ends at 1100
        (165, 0, 0), (175, 0, 0), (175, 0, 0), (175, 0, 0), (175, 0, 0),
    ])
    assert c.count == 1 and reps[0].end_ms == 1100
    assert reps[0].at_deepest["landing_knee_min"] == 100
    assert abs(reps[0].at_deepest["jump_height"] - 0.4) < 1e-9


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  passed  {t.__name__}")
    print(f"All {len(tests)} rep counter tests passed.")
