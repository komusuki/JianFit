"""Replay tool, step 2: turn pose CSVs into the measurements the app judges with.

Follows the order of operations of the Shared Formula Document for every frame:
  1. points are already pixels with confidence (extract_pose.py converted them)
  2. confidence check on the exercise's required joints (chosen side); stop if it fails
  3. body length L, then every raw measurement of the exercise
  4. smoothing: moving average of the last SMOOTH_N judgeable values
  5. rep counting and form checks come in replay step 4

This file mirrors lib/engine/measurement_layer.dart (formula document v0.4). Setup uses
the first BASELINE_MS (1000 ms) of frames that have a person in view (every required
joint at MIN_CONFIDENCE or more on at least one side; lunges: both legs too). A frame
that fails restarts the window. Side, facing, the standing baseline and the setup thigh and shin
lengths are chosen there, and judging starts after it. Frames with impossible values
(a joint angle under PLAUSIBLE_MIN_ANGLE_DEG, or a thigh or shin far from its setup
length) are unjudgeable. LOW_CONF_PAUSE_MS without a judgeable frame pauses (status
"paused"), and setup is done again. Start every recording with the person standing still.

Usage (from the tools folder, with .venv active):
    python measurements.py "<videos\\csv folder>"          # every video folder inside it
    python measurements.py "<one pose CSV>"
    python measurements.py "<folder>" --exercise forward-lunge   # if the name can't tell
    python measurements.py "<folder>" --overwrite

The exercise comes from the file name: the part before the first "_"
(forward-lunge_S01_side_01 -> forward-lunge). Video names use hyphens; the app's ids use
underscores, and exercise_id() converts (forward-lunge -> forward_lunge, knee-push-up ->
knee_push_up). Writes <name>_measurements.csv next to each pose CSV.
"""
import argparse
import csv
import math
import statistics
import sys
from pathlib import Path

import formulas as f
from formulas import (ANKLE, EAR, ELBOW, FOOT_INDEX, HEEL, HIP, KNEE, LEFT, RIGHT,
                      SHOULDER, WRIST)

# Exercises, from the document's Measurement catalog (provisional).
# When assets/exercises/*.json exists (Day 5), read the required joints from each
# file's "tracking" section instead of this table.
#   pose:     "standing" or "floor" (decides how facing is found)
#   side:     joints required on the chosen side
#   both:     joints required on both sides
#   baseline: True if it measures heights against the standing baseline
#   main:     main measurement (None for holds); direction: "dip", "hill" or "hold"
#   end:      end point of the body line, for hip_sag
_PUSHUP = dict(pose="floor", side=[EAR, SHOULDER, ELBOW, WRIST, HIP, ANKLE], both=[],
               baseline=False, main="elbow_angle", direction="dip", end=ANKLE,
               measurements=["elbow_angle", "hip_sag", "head_drop"])
_LUNGE = dict(pose="standing", side=[SHOULDER, HIP], both=[HIP, KNEE, ANKLE],
              baseline=True, main="front_knee_angle", direction="dip",
              measurements=["front_knee_angle", "back_knee_height", "front_knee_over_ankle",
                            "torso_lean"])
EXERCISES = {
    "bodyweight-squat": dict(pose="standing", side=[SHOULDER, HIP, KNEE, ANKLE], both=[],
                             baseline=True, main="knee_angle", direction="dip",
                             measurements=["knee_angle", "hip_angle", "torso_lean", "heel_lift"]),
    "jump-squat": dict(pose="standing", side=[SHOULDER, HIP, KNEE, ANKLE], both=[ANKLE],
                       baseline=True, main="knee_angle", direction="dip",
                       measurements=["knee_angle", "jump_rise_left", "jump_rise_right"]),
    "knee-push-up": dict(_PUSHUP, side=[EAR, SHOULDER, ELBOW, WRIST, HIP, KNEE], end=KNEE),
    "standard-push-up": _PUSHUP,
    "decline-push-up": _PUSHUP,
    "forward-lunge": _LUNGE,
    "reverse-lunge": _LUNGE,
    "forearm-plank": dict(pose="floor", side=[SHOULDER, ELBOW, HIP, ANKLE], both=[],
                          baseline=False, main=None, direction="hold", end=ANKLE,
                          measurements=["hip_sag", "elbow_under_shoulder", "torso_lean"]),
    "glute-bridge": dict(pose="floor", side=[SHOULDER, HIP, KNEE, ANKLE], both=[],
                         baseline=False, main="hip_angle", direction="hill", end=KNEE,
                         measurements=["hip_angle", "knee_angle", "hip_sag"]),
    "good-morning": dict(pose="standing", side=[SHOULDER, HIP, KNEE, ANKLE], both=[],
                         baseline=False, main="hip_angle", direction="dip",
                         measurements=["hip_angle", "knee_angle", "torso_lean"]),
}


def exercise_from_name(name):
    return name.split("_")[0].lower()


def exercise_id(slug):
    """Video-name slug to the app's exercise id (Member B's ids): forward-lunge -> forward_lunge.
    Use it to find assets/exercises/<id>.json and tools/tuning/<id>.json."""
    return slug.replace("-", "_")


def read_pose_csv(path):
    """Returns a list of (frame, t_ms, points); points is None when no person was found."""
    frames = []
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        if "t_ms" not in reader.fieldnames:
            sys.exit(f"{path.name} is in the old CSV format. Re-run extract_pose.py with --overwrite.")
        for row in reader:
            if row["lm0_x"] == "":
                pts = None
            else:
                pts = [(float(row[f"lm{i}_x"]), float(row[f"lm{i}_y"]), float(row[f"lm{i}_c"] or 0))
                       for i in range(33)]
            frames.append((int(row["frame"]), float(row["t_ms"]), pts))
    return frames


def confident(p, *joints):
    return all(p[j][2] >= f.MIN_CONFIDENCE for j in joints)


def is_setup_frame(p, ex):
    """A setup frame has an ear at MIN_CONFIDENCE or more (v0.5: a chair has no head), every
    required joint at MIN_CONFIDENCE or more on at least one side, plus the joints required
    on both sides (both legs for lunges). Document v0.3 and v0.5."""
    if p is None:
        return False
    head_ok = any(confident(p, EAR[s]) for s in (LEFT, RIGHT))
    both_ok = confident(p, *[j[k] for j in ex["both"] for k in (LEFT, RIGHT)])
    side_ok = any(confident(p, *[j[s] for j in ex["side"]]) for s in (LEFT, RIGHT))
    return head_ok and both_ok and side_ok


def moved(first, p, ex):
    """v0.5: a required joint, shoulder or hip of a side that passes in both frames is more
    than STILL_MAX_MOVE body lengths from where it was in the first setup frame
    (measurement_layer.dart _moved)."""
    joints = list(dict.fromkeys(ex["side"] + [SHOULDER, HIP]))
    for s in (LEFT, RIGHT):
        idx = [j[s] for j in joints]
        if not (confident(first, *idx) and confident(p, *idx)):
            continue
        L = f.body_length(first[SHOULDER[s]], first[HIP[s]])
        if any(f.segment_length(first[i], p[i]) > f.STILL_MAX_MOVE * L for i in idx):
            return True
    return False


SETUP_BENT_DEG = 150   # tool-only warning: main angle this low during setup means "not standing"


def leg_segments(ex, side):
    """Thigh (hip-knee) and shin (knee-ankle) of every leg whose joints are required."""
    segs = []
    for s in (LEFT, RIGHT):
        req = {j[s] for j in ex["both"]} | ({j[s] for j in ex["side"]} if s == side else set())
        if HIP[s] in req and KNEE[s] in req:
            segs.append((HIP[s], KNEE[s]))
        if KNEE[s] in req and ANKLE[s] in req:
            segs.append((KNEE[s], ANKLE[s]))
    return segs


def finish_setup(window, ex):
    """Side, facing and baseline from the setup frames (measurement_layer.dart _finishSetup)."""
    # Side (v0.4): the side whose required joints pass the confidence check in more setup
    # frames; if equal, the higher mean confidence; if still equal, left.
    def pass_rate(side):
        return statistics.fmean(confident(p, *[j[side] for j in ex["side"]]) for p in window)

    def mean_confidence(side):
        return statistics.fmean(statistics.fmean(p[j[side]][2] for j in ex["side"]) for p in window)
    key = {sd: (pass_rate(sd), mean_confidence(sd)) for sd in (LEFT, RIGHT)}
    side = RIGHT if key[RIGHT] > key[LEFT] else LEFT

    # Facing: standing = toes vs heel, floor = shoulder vs hip (median over the window).
    a, b = (FOOT_INDEX[side], HEEL[side]) if ex["pose"] == "standing" else (SHOULDER[side], HIP[side])
    diffs = [p[a][0] - p[b][0] for p in window]
    facing = 1 if not diffs or statistics.median(diffs) >= 0 else -1

    # Baseline: median y of each ankle and heel; floor = mean heel baseline.
    base = {j: statistics.median(p[j][1] for p in window)
            for j in (ANKLE[LEFT], ANKLE[RIGHT], HEEL[LEFT], HEEL[RIGHT])}
    y_floor = (base[HEEL[LEFT]] + base[HEEL[RIGHT]]) / 2
    # Setup lengths of the thighs and shins, for the plausibility check (v0.4).
    lengths = {(a, b): statistics.median(f.segment_length(p[a], p[b]) for p in window)
               for a, b in leg_segments(ex, side)}

    warnings = []
    # Day 2 check from the document: standing upright, ankle y must be below shoulder y.
    if ex["pose"] == "standing" and statistics.median(
            p[ANKLE[side]][1] - p[SHOULDER[side]][1] for p in window) < 0:
        warnings.append("Ankles are above the shoulders: the video looks rotated or upside down.")
    return side, facing, base, y_floor, lengths, warnings


def judgeable(p, ex, side, lengths):
    """(status, L): status is ok, no_person, low_confidence, too_far or implausible
    (measurement_layer.dart _judgeableBodyLength, plus the v0.4 plausibility check)."""
    if p is None:
        return "no_person", None
    required = [j[side] for j in ex["side"]] + [j[k] for j in ex["both"] for k in (LEFT, RIGHT)]
    if not confident(p, *required):
        return "low_confidence", None
    L = f.body_length(p[SHOULDER[side]], p[HIP[side]])
    if L < f.MIN_BODY_LENGTH_PX:
        return "too_far", None
    for (a, b), setup_len in lengths.items():
        if not f.plausible_length(f.segment_length(p[a], p[b]), setup_len):
            return "implausible", None
    return "ok", L


def compute(ex, p, s, facing, L, base, y_floor, prev_front=None):
    """Raw measurements for one frame. Returns (measurements, extra columns, front leg)."""
    def P(joint):
        return p[joint[s]]                      # the chosen side
    names, m, extra, front = ex["measurements"], {}, {}, None
    if "knee_angle" in names:
        m["knee_angle"] = f.joint_angle(P(HIP), P(KNEE), P(ANKLE))
    if "hip_angle" in names:
        m["hip_angle"] = f.joint_angle(P(SHOULDER), P(HIP), P(KNEE))
    if "torso_lean" in names:
        m["torso_lean"] = f.lean(P(SHOULDER), P(HIP))
    if "heel_lift" in names:
        # Heel is not a required joint, so skip this measurement when unsure.
        heel = P(HEEL)
        m["heel_lift"] = (f.NAN if heel[2] < f.MIN_CONFIDENCE or HEEL[s] not in base
                          else f.heel_lift(base[HEEL[s]], heel[1], L))
    if "jump_rise_left" in names:
        m["jump_rise_left"] = f.jump_rise(base[ANKLE[LEFT]], p[ANKLE[LEFT]][1], L)
        m["jump_rise_right"] = f.jump_rise(base[ANKLE[RIGHT]], p[ANKLE[RIGHT]][1], L)
    if "elbow_angle" in names:
        m["elbow_angle"] = f.joint_angle(P(SHOULDER), P(ELBOW), P(WRIST))
    if "hip_sag" in names:
        m["hip_sag"] = f.hip_sag(P(SHOULDER), P(HIP), P(ex["end"]))
    if "head_drop" in names:
        m["head_drop"], dropping = f.head_drop(P(EAR), P(SHOULDER), P(HIP))
        extra["head_dropping"] = "" if dropping is None else int(dropping)
    if "elbow_under_shoulder" in names:
        m["elbow_under_shoulder"] = abs(f.align(P(ELBOW), P(SHOULDER), facing, L))
    if "front_knee_angle" in names:
        # Front leg on every judgeable frame, with the v0.4 margin. Crediting each rep to the
        # leg in front at its Bottom stage happens with the rep counter (replay step 4).
        front = f.front_leg(p[ANKLE[LEFT]], p[ANKLE[RIGHT]], facing, L, prev_front)
        back = RIGHT if front == LEFT else LEFT
        m["front_knee_angle"] = f.joint_angle(p[HIP[front]], p[KNEE[front]], p[ANKLE[front]])
        m["back_knee_height"] = f.back_knee_height(y_floor, p[KNEE[back]][1], L)
        m["front_knee_over_ankle"] = f.align(p[KNEE[front]], p[ANKLE[front]], facing, L)
        extra["front_leg"] = "L" if front == LEFT else "R"
    return m, extra, front


def setup_bent_angle(window, ex, side, facing, base, y_floor):
    """Tool-only warning (not in the app): median main angle during setup, if it shows the
    person was bent (dip exercises only). None when the setup looks upright."""
    if ex["direction"] != "dip":
        return None
    values = []
    for p in window:
        L = f.body_length(p[SHOULDER[side]], p[HIP[side]])
        if L >= f.MIN_BODY_LENGTH_PX:
            v = compute(ex, p, side, facing, L, base, y_floor)[0].get(ex["main"], f.NAN)
            if not math.isnan(v):
                values.append(v)
    if values and statistics.median(values) < SETUP_BENT_DEG:
        return statistics.median(values)
    return None


def implausible_angle(raw):
    """v0.4: any joint angle below PLAUSIBLE_MIN_ANGLE_DEG makes the whole frame unjudgeable."""
    return any(n.endswith("_angle") and not math.isnan(v) and v < f.PLAUSIBLE_MIN_ANGLE_DEG
               for n, v in raw.items())


def process(pose_csv, out_csv, ex_name):
    """Run every frame through setup, the confidence check, measurements and smoothing,
    in the same order as MeasurementLayer.process in the Dart engine."""
    ex = EXERCISES[ex_name]
    names = ex["measurements"]
    frames = read_pose_csv(pose_csv)
    smoothers = {n: f.Smoother(f.SMOOTH_N_JUMP if n.startswith("jump_rise") else f.SMOOTH_N)
                 for n in names}
    extras = {"front_knee_angle": "front_leg", "head_drop": "head_dropping"}
    cols = ["frame", "t_ms", "exercise", "status", "side", "facing", "L"]
    for n in names:
        cols += [n, f"{n}_raw"]
    cols += [extras[n] for n in names if n in extras]

    side = None                       # None until setup finishes (MeasurementLayer.side)
    facing, base, y_floor, lengths, prev_front = 1, {}, f.NAN, {}, None
    setup_frames, setup_start, last_judged = [], None, None
    setups, pauses, warnings = [], [], []
    counts = {"ok": 0, "low_confidence": 0, "no_person": 0, "too_far": 0, "implausible": 0}
    smoothed_values = {n: [] for n in names}
    rows = []

    for frame, t, p in frames:
        row = {"frame": frame, "t_ms": t, "exercise": ex_name}
        if side is None:                                   # setup window
            row["status"] = "setup"
            if not is_setup_frame(p, ex):
                setup_frames, setup_start = [], None
            else:
                # v0.5: without both-sides joints the person must also stand still.
                if not ex["both"] and setup_frames and moved(setup_frames[0], p, ex):
                    setup_frames, setup_start = [], None
                setup_start = t if setup_start is None else setup_start
                setup_frames.append(p)
                if t - setup_start >= f.BASELINE_MS:
                    side, facing, base, y_floor, lengths, w = finish_setup(setup_frames, ex)
                    warnings += [m for m in w if m not in warnings]
                    bent = setup_bent_angle(setup_frames, ex, side, facing, base, y_floor)
                    if bent is not None:
                        warnings.append(f"Setup at {setup_start / 1000:.2f}-{t / 1000:.2f} s happened while "
                                        f"bent ({ex['main']} about {bent:.0f} degrees), so heights may be "
                                        f"off. Reshoot with 2 s of standing still.")
                    setups.append((setup_start, t, side, facing))
                    last_judged, setup_frames, prev_front = t, [], None
            rows.append(row)
            continue

        row["side"], row["facing"] = ("L" if side == LEFT else "R"), facing
        status, L = judgeable(p, ex, side, lengths)
        raw = extra = front = None
        if status == "ok":
            raw, extra, front = compute(ex, p, side, facing, L, base, y_floor, prev_front)
            if implausible_angle(raw):
                status = "implausible"
        if status != "ok":
            if t - last_judged >= f.LOW_CONF_PAUSE_MS:     # automatic pause: setup again
                status = "paused"
                pauses.append(t)
                side, facing, base, y_floor, lengths, prev_front = None, 1, {}, f.NAN, {}, None
                setup_frames, setup_start, last_judged = [], None, None
                for sm in smoothers.values():
                    sm.reset()
            else:
                counts[status] += 1
            row["status"] = status
            rows.append(row)
            continue

        if t - last_judged > f.SMOOTH_RESET_MS:
            for sm in smoothers.values():
                sm.reset()
        row["status"], row["L"] = "ok", L
        counts["ok"] += 1
        prev_front = front
        for n, v in raw.items():
            row[f"{n}_raw"] = v
            if not math.isnan(v):                           # unjudgeable for this one only
                row[n] = smoothers[n].push(v)
                smoothed_values[n].append(row[n])
        row.update(extra)
        last_judged = t
        rows.append(row)

    if not setups:
        print(f"    Setup never completed: no {f.BASELINE_MS} ms in a row with")
        print("    an ear and the required joints visible (confidence 0.5+), standing still unless both")
        print("    legs are required. Skipped. Check the _summary.txt and the video.")
        return None
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 6) if isinstance(v, float) and not math.isnan(v) else
                            ("" if isinstance(v, float) else v)) for k, v in r.items()})
    judged = sum(1 for r in rows if r["status"] not in ("setup", "paused"))
    return dict(setups=setups, pauses=pauses, warnings=warnings, counts=counts,
                smoothed=smoothed_values, judged=judged)


def print_report(ex_name, res):
    ex, c = EXERCISES[ex_name], res["counts"]
    print(f"    Exercise:    {ex_name}")
    for i, (a, b, side, facing) in enumerate(res["setups"]):
        face = "+1 (toward the right of the image)" if facing > 0 else "-1 (toward the left)"
        label = "Setup:      " if i == 0 else "Setup again:"
        print(f"    {label} {a / 1000:.2f}-{b / 1000:.2f} s, side {'L' if side == LEFT else 'R'}, facing {face}")
    pct = 100 * c["ok"] / res["judged"] if res["judged"] else 0
    print(f"    Judgeable:   {c['ok']} of {res['judged']} frames after setup ({pct:.0f}%)  |  "
          f"low confidence {c['low_confidence']}, no person {c['no_person']}, too far {c['too_far']}, "
          f"implausible {c['implausible']}")
    for n in ex["measurements"]:
        vals = res["smoothed"][n]
        rng = f"{min(vals):.2f} to {max(vals):.2f}" if vals else "no values"
        note = ""
        if n == ex["main"]:
            note = "   <- main, dips each rep" if ex["direction"] == "dip" else "   <- main, rises each rep"
        print(f"    {n:<22} {rng}{note}")
    for t in res["pauses"]:
        print(f"    Paused at {t / 1000:.2f} s: no judgeable frame for {f.LOW_CONF_PAUSE_MS} ms, "
              f"so setup was done again (as the app would).")
    for wmsg in res["warnings"]:
        print(f"    Warning: {wmsg}")
    if pct < 70:
        print("    Warning: under 70% of frames could be judged. Check the joint table in the _summary.txt.")


def find_pose_csvs(src):
    if src.is_file():
        return [src]
    own = src / f"{src.name}.csv"
    if own.exists():
        return [own]
    return sorted(d / f"{d.name}.csv" for d in src.iterdir() if (d / f"{d.name}.csv").exists())


def main():
    parser = argparse.ArgumentParser(description="Compute JianFit measurements from pose CSVs.")
    parser.add_argument("input", help="the videos\\csv folder, one video's folder, or one pose CSV")
    parser.add_argument("--exercise", choices=sorted(EXERCISES), help="use this exercise for every file")
    parser.add_argument("--overwrite", action="store_true", help="redo files that already have measurements")
    args = parser.parse_args()

    src = Path(args.input)
    if not src.exists():
        sys.exit(f"Not found: {src}")
    pose_csvs = find_pose_csvs(src)
    if not pose_csvs:
        sys.exit(f"No pose CSVs found in {src}. Run extract_pose.py first.")

    print(f"Computing measurements for {len(pose_csvs)} video(s)\n")
    done = skipped = 0
    for n, pose_csv in enumerate(pose_csvs, start=1):
        name = pose_csv.stem
        out_csv = pose_csv.with_name(f"{name}_measurements.csv")
        print(f"[{n}/{len(pose_csvs)}] {name}")
        ex_name = args.exercise or exercise_from_name(name)
        if ex_name not in EXERCISES:
            print(f"    Unknown exercise '{ex_name}'. Name the file like forward-lunge_S01_side_01, "
                  f"or use --exercise. Known: {', '.join(sorted(EXERCISES))}\n")
            skipped += 1
            continue
        if out_csv.exists() and not args.overwrite:
            print("    Skipped: measurements already exist (use --overwrite to redo).\n")
            skipped += 1
            continue
        res = process(pose_csv, out_csv, ex_name)
        if res is None:
            skipped += 1
            print()
            continue
        print_report(ex_name, res)
        print(f"    Saved:       {out_csv.name}\n")
        done += 1
    print(f"Done: {done} processed, {skipped} skipped.")


if __name__ == "__main__":
    main()
