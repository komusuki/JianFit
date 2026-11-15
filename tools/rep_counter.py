"""Python mirror of lib/engine/rep_counter.dart (roadmap Part 5). Owner: Member A.

One main measurement drives a state machine with two thresholds and a gap between them,
so jitter is not a rep. Keep this file line-for-line equivalent to the Dart code.

Roadmap stages -> this code:
  Ready      -> READY
  Going Down -> GOING_DOWN
  Bottom     -> the moment the value turns back by REP_TURNAROUND_DEG
  Coming Up  -> COMING_UP
  Complete   -> the moment update() returns a RepResult
"""
from dataclasses import dataclass, field

from formulas import REP_TURNAROUND_DEG

READY, GOING_DOWN, COMING_UP = "ready", "goingDown", "comingUp"


@dataclass
class RepResult:
    deepest: float        # deepest main value (minimum for dip, maximum for hill)
    at_deepest: dict      # all smoothed measurements at the deepest frame (for the form judge)
    duration_ms: float    # from leaving Ready to Complete
    end_ms: float
    start_ms: float = field(init=False)   # Python only, for matching labels: end - duration

    def __post_init__(self):
        self.start_ms = self.end_ms - self.duration_ms


class RepCounter:
    def __init__(self, direction, start_threshold, complete_threshold,
                 turnaround=REP_TURNAROUND_DEG):
        assert (complete_threshold > start_threshold if direction == "dip"
                else complete_threshold < start_threshold)
        self.direction = direction
        self.start_threshold = start_threshold
        self.complete_threshold = complete_threshold
        self.turnaround = turnaround
        self.stage = READY
        self.count = 0
        self._extreme = None
        self._at_extreme = {}
        self._start_ms = 0

    def _dip(self):
        return self.direction == "dip"

    def _started(self, v):
        return v < self.start_threshold if self._dip() else v > self.start_threshold

    def _returned(self, v):
        return v > self.complete_threshold if self._dip() else v < self.complete_threshold

    def _deeper(self, v):
        return v < self._extreme if self._dip() else v > self._extreme

    def update(self, main, values, t_ms):
        """Feed one judged frame. Returns a RepResult when a rep completes."""
        if self.stage == READY:
            if self._started(main):
                self.stage = GOING_DOWN
                self._start_ms = t_ms
                self._extreme = main
                self._at_extreme = dict(values)
            return None

        if self._returned(main):
            self.count += 1
            result = RepResult(deepest=self._extreme, at_deepest=self._at_extreme,
                               duration_ms=t_ms - self._start_ms, end_ms=t_ms)
            self.reset(keep_count=True)
            return result

        if self._deeper(main):
            self._extreme = main
            self._at_extreme = dict(values)
            self.stage = GOING_DOWN
        elif self.stage == GOING_DOWN and abs(main - self._extreme) >= self.turnaround:
            self.stage = COMING_UP          # bottom passed
        return None

    def reset(self, keep_count=False):
        """Drop any rep in progress (after a pause or a new set)."""
        self.stage = READY
        self._extreme = None
        self._at_extreme = {}
        if not keep_count:
            self.count = 0
