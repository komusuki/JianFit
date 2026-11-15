"""Python mirror of lib/engine/rep_counter.dart (roadmap Part 5). Owner: Member A.

One main measurement drives a state machine with two thresholds and a gap between them,
so jitter is not a rep. Keep this file line-for-line equivalent to the Dart code.

Roadmap stages -> this code:
  Ready      -> READY
  Going Down -> GOING_DOWN
  Bottom     -> the moment the value turns back by REP_TURNAROUND_DEG
  Coming Up  -> COMING_UP
  Complete   -> the moment update() returns a RepResult
A rep that completes in under MIN_REP_MS is dropped without counting (v0.4.2): real reps take
longer, and these short ones come from the measurement jumping, for example when a lunge's
front leg switches during the step.
"""
from dataclasses import dataclass, field

from formulas import MIN_REP_MS, REP_TURNAROUND_DEG

READY, GOING_DOWN, COMING_UP = "ready", "goingDown", "comingUp"


@dataclass
class RepResult:
    deepest: float        # deepest main value (minimum for dip, maximum for hill)
    at_deepest: dict      # all smoothed measurements at the deepest frame (for the form judge)
    duration_ms: float    # from leaving Ready to Complete
    end_ms: float
    # Lowest and highest smoothed value of each measurement during the rep, from leaving
    # Ready to Complete (for form checks with "when": throughout).
    min_during: dict = field(default_factory=dict)
    max_during: dict = field(default_factory=dict)
    start_ms: float = field(init=False)   # Python only, for matching labels: end - duration

    def __post_init__(self):
        self.start_ms = self.end_ms - self.duration_ms


class RepCounter:
    def __init__(self, direction, start_threshold, complete_threshold,
                 turnaround=REP_TURNAROUND_DEG, min_rep_ms=MIN_REP_MS):
        assert (complete_threshold > start_threshold if direction == "dip"
                else complete_threshold < start_threshold)
        self.direction = direction
        self.start_threshold = start_threshold
        self.complete_threshold = complete_threshold
        self.turnaround = turnaround
        self.min_rep_ms = min_rep_ms
        self.stage = READY
        self.count = 0
        self._extreme = None
        self._at_extreme = {}
        self._min = {}
        self._max = {}
        self._start_ms = 0

    def _dip(self):
        return self.direction == "dip"

    def _started(self, v):
        return v < self.start_threshold if self._dip() else v > self.start_threshold

    def _returned(self, v):
        return v > self.complete_threshold if self._dip() else v < self.complete_threshold

    def _deeper(self, v):
        return v < self._extreme if self._dip() else v > self._extreme

    def _track(self, values):
        for k, v in values.items():
            if not isinstance(v, (int, float)):
                continue                        # Python only: skip text columns such as front_leg
            lo, hi = self._min.get(k), self._max.get(k)
            self._min[k] = v if lo is None else min(lo, v)
            self._max[k] = v if hi is None else max(hi, v)

    def update(self, main, values, t_ms):
        """Feed one judged frame. Returns a RepResult when a rep completes."""
        if self.stage == READY:
            if self._started(main):
                self.stage = GOING_DOWN
                self._start_ms = t_ms
                self._extreme = main
                self._at_extreme = dict(values)
                self._min.clear()
                self._max.clear()
                self._track(values)
            return None

        self._track(values)

        if self._returned(main):
            if t_ms - self._start_ms < self.min_rep_ms:
                self.reset(keep_count=True)     # too short to be a rep: drop it
                return None
            self.count += 1
            result = RepResult(deepest=self._extreme, at_deepest=self._at_extreme,
                               duration_ms=t_ms - self._start_ms, end_ms=t_ms,
                               min_during=dict(self._min), max_during=dict(self._max))
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
        self._min.clear()
        self._max.clear()
        if not keep_count:
            self.count = 0
