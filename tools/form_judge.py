"""Python mirror of lib/engine/form_judge.dart (roadmap Part 7). Owner: Member A.

When a rep completes, run every form check from the exercise file.
  range: one standard target. cleanliness: the user's strictness level.
  safety: one fixed limit.
All checks pass: correct rep. Any fails: attempted only.
A value exactly at the limit passes. A check with no value is skipped, not failed.
Keep this file line-for-line equivalent to the Dart code.
"""
from dataclasses import dataclass

STRICTNESS = ("beginner", "standard", "strict")     # lib/models/strictness.dart


@dataclass(frozen=True)
class FormCheck:
    """One form check (lib/models/exercise_definition.dart FormCheck)."""
    name: str
    category: str        # "range", "cleanliness" or "safety"
    measurement: str
    timing: str          # "bottom" (deepest frame) or "throughout" (worst value during the rep)
    kind: str            # "max": value must be <= limit; "min": value must be >= limit
    limits: tuple        # ((strictness, limit), ...) for beginner, standard, strict
    cue: str = ""
    priority: int = 0

    def limit_for(self, strictness):
        return dict(self.limits)[strictness]


@dataclass(frozen=True)
class CheckResult:
    check: FormCheck
    value: object        # float, or None if the measurement had no judgeable value
    limit: float

    @property
    def passed(self):
        """None when skipped (no value)."""
        if self.value is None:
            return None
        return self.value <= self.limit if self.check.kind == "max" else self.value >= self.limit


@dataclass(frozen=True)
class RepVerdict:
    results: tuple

    @property
    def failed(self):
        return [r.check for r in self.results if r.passed is False]

    @property
    def skipped(self):
        """Checks that could not be judged this rep. They don't fail the rep."""
        return [r.check for r in self.results if r.passed is None]

    @property
    def correct(self):
        return not self.failed

    @property
    def top_failed(self):
        """Safety first, then the lowest priority number, then the order in the file."""
        best = None
        for c in self.failed:
            if best is None or _beats(c, best):
                best = c
        return best


def _beats(a, b):
    a_safety, b_safety = a.category == "safety", b.category == "safety"
    if a_safety != b_safety:
        return a_safety
    return a.priority < b.priority


def check_value(check, rep):
    """The deepest frame for "bottom"; the worst value during the rep for "throughout"."""
    if check.timing == "bottom":
        return rep.at_deepest.get(check.measurement)
    during = rep.max_during if check.kind == "max" else rep.min_during
    return during.get(check.measurement)


def judge_rep(rep, checks, strictness):
    """Judges one completed rep against checks at the given strictness level."""
    return RepVerdict(tuple(CheckResult(c, check_value(c, rep), c.limit_for(strictness))
                            for c in checks))


def read_form_checks(raw_checks, measurements):
    """form_checks from an exercise file (lib/models/exercise_definition.dart _Reader.formCheck).
    Returns (checks, problems); problems lists every mistake so a file can be fixed in one go."""
    problems, checks, names = [], [], set()
    if not isinstance(raw_checks, list):
        return [], ["form_checks is missing or is not a list"]
    for i, raw in enumerate(raw_checks):
        path = f"form_checks[{i}]"
        if not isinstance(raw, dict):
            problems.append(f"{path} must be an object")
            continue
        before = len(problems)
        for key in ("name", "measurement", "cue"):
            if not isinstance(raw.get(key), str) or not raw[key].strip():
                problems.append(f"{path}.{key} is missing or is not text")
        category = raw.get("category")
        if category not in ("range", "cleanliness", "safety"):
            problems.append(f"{path}.category must be one of range, cleanliness, safety, not '{category}'")
        if isinstance(raw.get("measurement"), str) and raw["measurement"] not in measurements:
            problems.append(f"{path}.measurement '{raw['measurement']}' must be one of tracking.measurements")
        timing = raw.get("when", "bottom")
        if timing not in ("bottom", "throughout"):
            problems.append(f"{path}.when must be one of bottom, throughout, not '{timing}'")
        priority = raw.get("priority")
        if not isinstance(priority, int) or isinstance(priority, bool) or priority < 1:
            problems.append(f"{path}.priority must be a whole number of 1 or more")
        limits = None
        if ("max" in raw) == ("min" in raw):
            problems.append(f"{path} needs exactly one of max or min")
            kind = None
        else:
            kind = "max" if "max" in raw else "min"
            limit = raw[kind]
            if category == "cleanliness":
                if not isinstance(limit, dict):
                    problems.append(f"{path}.{kind} must be an object with beginner, standard, strict "
                                    f"for a cleanliness check")
                else:
                    for s in STRICTNESS:
                        if not isinstance(limit.get(s), (int, float)) or isinstance(limit.get(s), bool):
                            problems.append(f"{path}.{kind}.{s} is missing or is not a number")
                    for k in limit:
                        if k not in STRICTNESS:
                            problems.append(f"{path}.{kind}: unknown strictness level '{k}'")
                    limits = tuple((s, float(limit[s])) for s in STRICTNESS if s in limit)
            elif category is not None:
                if isinstance(limit, (int, float)) and not isinstance(limit, bool):
                    limits = tuple((s, float(limit)) for s in STRICTNESS)
                else:
                    problems.append(f"{path}.{kind} must be one number for a {category} check")
        if len(problems) != before:
            continue
        if raw["name"] in names:
            problems.append(f"{path}: the name '{raw['name']}' is used twice")
            continue
        names.add(raw["name"])
        checks.append(FormCheck(raw["name"], category, raw["measurement"], timing, kind, limits,
                                raw["cue"], priority))
    return checks, problems
