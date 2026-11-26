"""Python mirror of lib/engine/hold_timer.dart (roadmap Part 5, Day 9). Owner: Member A.

Keep this file line-for-line equivalent to the Dart code.
Stages: not in position, holding (timer runs), broken (timer pauses, cue).
  In position: torso_lean at least HOLD_MIN_LEAN_DEG (body near horizontal), when the
    exercise measures torso_lean. Standing up is not a broken hold.
  Holding: every form check passes on the frame; time between judged frames is added,
    except across gaps longer than SMOOTH_RESET_MS.
  Broken: a check has failed for HOLD_BREAK_MS. update() returns the verdict once per
    break. The timer stops as soon as a check fails, so the grace period only delays the
    cue, never adds time.
  Getting into position: before the first passing frame, a hold cannot break until the
    user has been in position for HOLD_SETTLE_MS (v0.5.2).
  After a break: the next break needs good form held for HOLD_RECOVER_MS first, so values
    flickering around a limit give one cue, not one every second (v0.5.3). The timer still
    counts every passing frame.
"""
from form_judge import judge_rep
from formulas import (HOLD_BREAK_MS, HOLD_MIN_LEAN_DEG, HOLD_RECOVER_MS, HOLD_SETTLE_MS, NAN,
                      SMOOTH_RESET_MS)
from rep_counter import RepResult

NOT_IN_POSITION, HOLDING, BROKEN = "notInPosition", "holding", "broken"


def judge_values(values, checks, strictness):
    """One frame's verdict (form_judge.dart judgeValues): every check reads the frame's own
    value, whatever its "when", because a frame has no bottom or range."""
    frame = RepResult(deepest=NAN, at_deepest=values, duration_ms=0, end_ms=0,
                      min_during=values, max_during=values)
    return judge_rep(frame, checks, strictness)


class HoldTimer:
    def __init__(self, checks, strictness):
        self.checks = checks
        self.strictness = strictness
        self.state = NOT_IN_POSITION
        self.seconds = 0.0                  # seconds held so far in this set
        self._last_pass_ms = None           # the previous frame, if every check passed on it
        self._failing_since_ms = None
        self._in_position_since_ms = None   # first frame of this stretch in position
        self._passing_since_ms = None       # first frame of the current run of passing frames
        self._armed = True                  # False after a break until form holds HOLD_RECOVER_MS

    def update(self, values, t_ms):
        """Feed one judged frame's smoothed values. Returns the verdict when the hold breaks
        (once per break), otherwise None."""
        last_pass = self._last_pass_ms
        self._last_pass_ms = None
        lean = values.get("torso_lean")
        if lean is not None and lean < HOLD_MIN_LEAN_DEG:
            self.state = NOT_IN_POSITION
            self._failing_since_ms = None
            self._in_position_since_ms = None
            self._passing_since_ms = None
            self._armed = True
            return None
        if self._in_position_since_ms is None:
            self._in_position_since_ms = t_ms
        verdict = judge_values(values, self.checks, self.strictness)
        if verdict.correct:
            # Only time between two passing frames counts.
            if last_pass is not None and t_ms - last_pass <= SMOOTH_RESET_MS:
                self.seconds += (t_ms - last_pass) / 1000
            self._last_pass_ms = t_ms
            self.state = HOLDING
            self._failing_since_ms = None
            if self._passing_since_ms is None:
                self._passing_since_ms = t_ms
            if not self._armed and t_ms - self._passing_since_ms >= HOLD_RECOVER_MS:
                self._armed = True
            return None
        self._passing_since_ms = None
        # Still getting into position: no break yet.
        if self.state == NOT_IN_POSITION and t_ms - self._in_position_since_ms < HOLD_SETTLE_MS:
            return None
        # Not long enough back in good form since the last break: no new break.
        if not self._armed:
            return None
        if self._failing_since_ms is None:
            self._failing_since_ms = t_ms
        if self.state != BROKEN and t_ms - self._failing_since_ms >= HOLD_BREAK_MS:
            self.state = BROKEN
            self._armed = False
            return verdict
        return None

    def reset(self):
        """New set: time and stage start over."""
        self.state = NOT_IN_POSITION
        self.seconds = 0.0
        self._last_pass_ms = None
        self._failing_since_ms = None
        self._in_position_since_ms = None
        self._passing_since_ms = None
        self._armed = True
