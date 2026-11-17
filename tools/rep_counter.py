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

Jump squat (Day 9, when jump_limit is set): a jump is both ankles rising more than jump_limit
above their lowest point before takeoff (so the setup baseline cancels out). Landing is when they
are no longer both above it. The rep completes LANDING_WINDOW_MS after landing, and
landing_knee_min is the smallest knee angle in that window; the deepest value stays the one from
before the jump. Without a jump, the rep completes JUMP_WAIT_MS after the knee is back up. Each
rep also reports jump_height.
Back-to-back jumps: a takeoff inside the landing window completes the rep right there, and the
next rep starts in the air (its deepest value is the dip after the landing). After a rep that
completed while the knee was still bent, a new rep only starts once the knee has been back up,
or at the next takeoff, so standing up slowly after a landing is not a rep.
A takeoff (and jump_height) only counts while the knee is extended past start_threshold: feet
can't leave the floor in a deep bend, and the ankle points drift up at the bottom of a squat.
"""
from dataclasses import dataclass, field

from formulas import JUMP_WAIT_MS, LANDING_WINDOW_MS, MIN_REP_MS, REP_TURNAROUND_DEG

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
                 turnaround=REP_TURNAROUND_DEG, min_rep_ms=MIN_REP_MS, jump_limit=None):
        assert (complete_threshold > start_threshold if direction == "dip"
                else complete_threshold < start_threshold)
        self.direction = direction
        self.start_threshold = start_threshold
        self.complete_threshold = complete_threshold
        self.turnaround = turnaround
        self.min_rep_ms = min_rep_ms
        self.jump_limit = jump_limit
        self.stage = READY
        self.count = 0
        self._extreme = None
        self._at_extreme = {}
        self._min = {}
        self._max = {}
        self._start_ms = 0
        self._clear_jump()
        self._clear_ready(None)

    def _clear_ready(self, t_ms, armed=True, extreme=None, at_extreme=None, low_l=None, low_r=None):
        """Jump mode, between reps: what a takeoff with no rep in progress starts from."""
        self._armed = armed                       # False: the knee must come back up first
        self._ready_ms = t_ms                     # start time for a rep that begins in the air
        self._ready_extreme = extreme             # deepest main value since then
        self._ready_at = dict(at_extreme or {})
        self._ready_l, self._ready_r = low_l, low_r   # lowest ankle values since then

    def _clear_jump(self):
        self._rise_start_l = self._rise_start_r = None   # jump_rise values when the rep started
        self._jump_height = 0.0
        self._airborne = self._jumped = False
        self._landed_ms = self._landing_min = self._back_up_ms = None
        self._landing_at = {}                     # values at the landing_knee_min frame
        self._low_l = self._low_r = None          # lowest ankle values since landing

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
            if self.jump_limit is not None:
                return self._ready_jump(main, values, t_ms)
            if self._started(main):
                self._start(main, values, t_ms)
            return None

        self._track(values)
        if self.jump_limit is not None:
            return self._update_jump(main, values, t_ms)
        if self._returned(main):
            return self._complete(t_ms)
        self._follow_depth(main, values)
        return None

    def _start(self, main, values, t_ms):
        self.stage = GOING_DOWN
        self._start_ms = t_ms
        self._extreme = main
        self._at_extreme = dict(values)
        self._min.clear()
        self._max.clear()
        self._track(values)
        self._rise_start_l = values.get("jump_rise_left")
        self._rise_start_r = values.get("jump_rise_right")

    def _start_in_air(self, start_ms, extreme, at_extreme, l0, r0, lower, values):
        """A takeoff with no rep in progress: the rep starts at start_ms (when the previous rep
        completed); its deepest value is the dip before this takeoff."""
        self.stage = COMING_UP
        self._start_ms = start_ms
        self._extreme = extreme
        self._at_extreme = dict(at_extreme)
        self._min.clear()
        self._max.clear()
        self._track(at_extreme)
        self._track(values)
        self._rise_start_l, self._rise_start_r = l0, r0
        self._jump_height = lower
        self._airborne = self._jumped = True

    def _ready_jump(self, main, values, t_ms):
        l, r = values.get("jump_rise_left"), values.get("jump_rise_right")
        if self._ready_ms is None:
            self._ready_ms = t_ms
        if self._ready_extreme is None or self._deeper_than(main, self._ready_extreme):
            self._ready_extreme, self._ready_at = main, dict(values)
        if self._returned(main):
            self._armed = True
        l0, r0 = self._ready_l, self._ready_r
        if (None not in (l, r, l0, r0) and not self._started(main)
                and min(l - l0, r - r0) > self.jump_limit):
            self._start_in_air(self._ready_ms, self._ready_extreme, self._ready_at, l0, r0,
                               min(l - l0, r - r0), values)
            return None
        if l is not None:
            self._ready_l = l if l0 is None else min(l0, l)
        if r is not None:
            self._ready_r = r if r0 is None else min(r0, r)
        if self._armed and self._started(main):
            self._start(main, values, t_ms)
        return None

    def _deeper_than(self, v, ref):
        return v < ref if self._dip() else v > ref

    def _follow_depth(self, main, values):
        if self._deeper(main):
            self._extreme = main
            self._at_extreme = dict(values)
            self.stage = GOING_DOWN
        elif self.stage == GOING_DOWN and abs(main - self._extreme) >= self.turnaround:
            self.stage = COMING_UP          # bottom passed

    def _update_jump(self, main, values, t_ms):
        limit = self.jump_limit
        l, r = values.get("jump_rise_left"), values.get("jump_rise_right")
        if not self._jumped:
            # Feet on the floor until the jump: each ankle's reference is its lowest value so far
            # in this rep, so a rep that starts mid-motion or a drifting far ankle doesn't shrink
            # the jump.
            if l is not None:
                self._rise_start_l = l if self._rise_start_l is None else min(self._rise_start_l, l)
            if r is not None:
                self._rise_start_r = r if self._rise_start_r is None else min(self._rise_start_r, r)
        l0, r0 = self._rise_start_l, self._rise_start_r
        if None not in (l, r, l0, r0):
            lower = min(l - l0, r - r0)              # both ankles must rise
            extended = not self._started(main)     # a deep bend is never a takeoff
            if extended:
                self._jump_height = max(self._jump_height, lower)
            if not self._airborne and extended and lower > limit:
                if self._landed_ms is not None:
                    return self._retakeoff(l, r, lower, values, t_ms)
                self._airborne = self._jumped = True
            elif self._airborne and lower <= limit:
                self._airborne = False                 # landed: not both ankles up any more
                self._landed_ms, self._landing_min = t_ms, main
                self._landing_at = dict(values)
        if self._jumped:
            if self._landed_ms is None:
                return None                            # still in the air
            if l is not None:
                self._low_l = l if self._low_l is None else min(self._low_l, l)
            if r is not None:
                self._low_r = r if self._low_r is None else min(self._low_r, r)
            if t_ms - self._landed_ms < LANDING_WINDOW_MS:
                if self._deeper_than(main, self._landing_min):
                    self._landing_min, self._landing_at = main, dict(values)
                return None
            low_min, low_at = self._landing_min, self._landing_at
            low_l, low_r = self._low_l, self._low_r
            result = self._complete(t_ms)
            # Still bent after the landing window: no new rep until the knee is back up or the
            # next takeoff.
            self._clear_ready(t_ms, armed=self._returned(main), extreme=low_min,
                              at_extreme=low_at, low_l=low_l, low_r=low_r)
            return result
        if self._returned(main):
            if self._back_up_ms is None:
                self._back_up_ms = t_ms
            if t_ms - self._back_up_ms >= JUMP_WAIT_MS:
                return self._complete(t_ms)
            return None
        self._back_up_ms = None
        self._follow_depth(main, values)
        return None

    def _retakeoff(self, l, r, lower, values, t_ms):
        """Takeoff inside the landing window (back-to-back jumps): this rep completes now, and
        the next one starts now, in the air, with the dip after the landing as its deepest value."""
        dip, dip_at = self._landing_min, self._landing_at
        l0 = self._low_l if self._low_l is not None else self._rise_start_l
        r0 = self._low_r if self._low_r is not None else self._rise_start_r
        result = self._complete(t_ms)
        lower = min(l - l0, r - r0)
        self._start_in_air(t_ms, dip, dip_at, l0, r0, lower, values)
        return result

    def _complete(self, t_ms):
        if t_ms - self._start_ms < self.min_rep_ms:
            self.reset(keep_count=True)         # too short to be a rep: drop it
            return None
        rep_values = {}
        if self.jump_limit is not None:
            if self._rise_start_l is not None and self._rise_start_r is not None:
                rep_values["jump_height"] = self._jump_height
            if self._landing_min is not None:
                rep_values["landing_knee_min"] = self._landing_min
        self.count += 1
        result = RepResult(deepest=self._extreme, at_deepest={**self._at_extreme, **rep_values},
                           duration_ms=t_ms - self._start_ms, end_ms=t_ms,
                           min_during={**self._min, **rep_values},
                           max_during={**self._max, **rep_values})
        self.reset(keep_count=True)
        return result

    def reset(self, keep_count=False):
        """Drop any rep in progress (after a pause or a new set)."""
        self.stage = READY
        self._extreme = None
        self._at_extreme = {}
        self._min.clear()
        self._max.clear()
        self._clear_jump()
        self._clear_ready(None)
        if not keep_count:
            self.count = 0
