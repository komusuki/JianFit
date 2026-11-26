"""Tests for hold_timer.py (mirror of lib/engine/hold_timer.dart). Run: python -m pytest test_hold_timer.py"""
import pytest

from form_judge import read_form_checks
from hold_timer import BROKEN, HOLDING, NOT_IN_POSITION, HoldTimer

CHECKS = [
    {"name": "hips_sagging", "category": "safety", "measurement": "hip_sag", "max": 15,
     "cue": "Lift your hips.", "priority": 1},
    {"name": "elbows_not_under_shoulders", "category": "cleanliness",
     "measurement": "elbow_under_shoulder", "max": {"beginner": 0.4, "standard": 0.3, "strict": 0.2},
     "cue": "Elbows under your shoulders.", "priority": 2},
]
GOOD = dict(hip_sag=0.0, elbow_under_shoulder=0.1, torso_lean=85.0)
SAG = dict(GOOD, hip_sag=25.0)
STANDING = dict(GOOD, torso_lean=10.0)


def make_timer():
    checks, problems = read_form_checks(CHECKS, ["hip_sag", "elbow_under_shoulder", "torso_lean"])
    assert not problems
    return HoldTimer(checks, "standard")


def feed(timer, values, start, end, step=100):
    """Frames every step ms from start to end; returns [(t_ms, verdict)] for each break."""
    out = []
    for t in range(start, end + 1, step):
        v = timer.update(values, t)
        if v:
            out.append((t, v))
    return out


def test_time_counts_between_passing_frames():
    timer = make_timer()
    feed(timer, GOOD, 0, 1000)
    assert timer.seconds == pytest.approx(1.0)
    assert timer.state == HOLDING


def test_standing_up_is_not_a_break():
    timer = make_timer()
    feed(timer, GOOD, 0, 1000)
    assert feed(timer, STANDING, 1100, 3000) == []
    assert timer.state == NOT_IN_POSITION
    assert timer.seconds == pytest.approx(1.0)


def test_failing_check_stops_the_timer_and_breaks_once():
    timer = make_timer()
    feed(timer, GOOD, 0, 1000)
    breaks = feed(timer, SAG, 1100, 3000)
    assert [t for t, _ in breaks] == [1600]           # HOLD_BREAK_MS after the first failing frame
    assert [c.name for c in breaks[0][1].failed] == ["hips_sagging"]
    assert timer.state == BROKEN
    assert timer.seconds == pytest.approx(1.0)        # no time while failing


def test_a_short_failure_is_not_a_break():
    timer = make_timer()
    feed(timer, GOOD, 0, 500)
    assert feed(timer, SAG, 600, 900) == []           # 300 ms of failing
    feed(timer, GOOD, 1000, 1500)
    assert timer.state == HOLDING
    assert timer.seconds == pytest.approx(1.0)        # 0.5 + 0.5: the gap is not counted


def test_a_new_break_after_holding_again():
    timer = make_timer()
    feed(timer, GOOD, 0, 500)
    first = feed(timer, SAG, 600, 1200)
    feed(timer, GOOD, 1300, 2400)                     # good for HOLD_RECOVER_MS: armed again
    second = feed(timer, SAG, 2500, 3100)
    assert [t for t, _ in first + second] == [1100, 3000]
    assert timer.seconds == pytest.approx(1.6)


def test_a_gap_longer_than_smooth_reset_adds_nothing():
    timer = make_timer()
    for t in (0, 100, 700, 800):                      # 600 ms gap: over SMOOTH_RESET_MS
        timer.update(GOOD, t)
    assert timer.seconds == pytest.approx(0.2)


def test_reset_starts_over():
    timer = make_timer()
    feed(timer, GOOD, 0, 1000)
    timer.reset()
    assert timer.seconds == 0
    assert timer.state == NOT_IN_POSITION


def test_no_break_while_getting_into_position():
    timer = make_timer()
    breaks = feed(timer, SAG, 0, 2000)                # sagging from the first frame in position
    assert [t for t, _ in breaks] == [1500]           # HOLD_SETTLE_MS, then HOLD_BREAK_MS
    assert timer.seconds == 0


def test_settle_time_starts_again_after_standing_up():
    timer = make_timer()
    feed(timer, GOOD, 0, 1500)
    feed(timer, STANDING, 1600, 1600)
    breaks = feed(timer, SAG, 1700, 3500)
    assert [t for t, _ in breaks] == [3200]           # 1700 + 1000 + 500


def test_flickering_after_a_break_gives_one_cue():
    timer = make_timer()
    feed(timer, GOOD, 0, 200)
    breaks = []
    for start in range(300, 4000, 1000):              # 600 ms sagging, 400 ms good, repeated
        breaks += feed(timer, SAG, start, start + 500)
        feed(timer, GOOD, start + 600, start + 900)
    assert [t for t, _ in breaks] == [800]            # one break: never back in form for 1 s
    assert timer.seconds > 1.0                        # good frames still count
