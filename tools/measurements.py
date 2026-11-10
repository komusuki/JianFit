"""Replay tool, step 2: turn pose CSVs into the measurements the app judges with.

Follows the order of operations of the Shared Formula Document for every frame:
  1. points are already pixels with confidence (extract_pose.py converted them)
  2. confidence check on the exercise's required joints (chosen side); stop if it fails
  3. body length L, then every raw measurement of the exercise
  4. smoothing: moving average of the last SMOOTH_N judgeable values
  5. rep counting and form checks come in replay step 4

A recorded video has no countdown, so the first BASELINE_MS (1000 ms) with a person in
the picture stands in for it: side, facing and the standing baseline are chosen there,
and judging starts after it. Start every recording with the person standing still.

Usage (from the tools folder, with .venv active):
    python measurements.py "<videos\\csv folder>"          # every video folder inside it
    python measurements.py "<one pose CSV>"
    python measurements.py "<folder>" --exercise forward-lunge   # if the name can't tell
    python measurements.py "<folder>" --overwrite

The exercise comes from the file name: the part before the first "_"
(forward-lunge_S01_side_01 -> forward-lunge). Writes <name>_measurements.csv next to
each pose CSV.
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
    "bodyweight-squat": dict(pose="standing", side=[SHOULDER, HIP, KNEE, ANKLE, HEEL], both=[],
                             baseline=True, main="knee_angle", direction="dip",
                             measurements=["knee_angle", "hip_angle", "torso_lean", "heel_lift"]),
    "jump-squat": dict(pose="standing", side=[SHOULDER, HIP, KNEE, ANKLE], both=[ANKLE],
                       baseline=True, main="knee_angle", direction="dip",
                       measurements=["knee_angle", "jump_rise_left", "jump_rise_right"]),
    "knee-pushup": dict(_PUSHUP, side=[EAR, SHOULDER, ELBOW, WRIST, HIP, KNEE], end=KNEE),
    "standard-pushup": _PUSHUP,
    "decline-pushup": _PUSHUP,
    "forward-lunge": _LUNGE,
    "reverse-lunge": _LUNGE,
    "forearm-plank": dict(pose="floor", side=[SHOULDER, ELBOW, HIP, ANKLE], both=[],
                          baseline=False, main=None, direction="hold", end=ANKLE,
                          measurements=["hip_sag", "elbow_under_shoulder"]),
    "glute-bridge": dict(pose="floor", side=[SHOULDER, HIP, KNEE, ANKLE], both=[],
                         baseline=False, main="hip_angle", direction="hill", end=KNEE,
                         measurements=["hip_angle", "knee_angle", "hip_sag"]),
    "good-morning": dict(pose="standing", side=[SHOULDER, HIP, KNEE, ANKLE], both=[],
                         baseline=False, main="hip_angle", direction="dip",
                         measurements=["hip_angle", "knee_angle", "torso_lean"]),
}


def exercise_from_name(name):
    return name.split("_")[0].lower()


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


def setup(frames, ex):
    """Stand-in for the countdown: choose side, facing and baseline from the first
    BASELINE_MS with a person in the picture."""
    warnings = []
    first = next((t for _, t, p in frames if p is not None), None)
    if first is None:
        return None
    window = [p for _, t, p in frames if p is not None and t < first + f.BASELINE_MS]

    # Side: higher mean confidence of the required joints. Ties: left.
    def mean_conf(s):
        return statistics.fmean(p[j[s]][2] for p in window for j in ex["side"])
    side = LEFT if mean_conf(LEFT) >= mean_conf(RIGHT) else RIGHT

    # Facing: toes vs heel when standing, shoulder vs hip on the floor (median over the window).
    if ex["pose"] == "standing":
        a, b = FOOT_INDEX[side], HEEL[side]
    else:
        a, b = SHOULDER[side], HIP[side]
    diffs = [p[a][0] - p[b][0] for p in window if confident(p, a, b)]
    if diffs:
        facing = f.sign(statistics.median(diffs))
    else:
        facing = 1
        warnings.append("Facing could not be found during setup (joints not visible); assumed +1.")

    # Standing baseline: median y of each ankle and each heel.
    base = {}
    if ex["baseline"]:
        for j in (ANKLE[LEFT], ANKLE[RIGHT], HEEL[LEFT], HEEL[RIGHT]):
            ys = [p[j][1] for p in window if p[j][2] >= f.MIN_CONFIDENCE]
            base[j] = statistics.median(ys) if ys else f.NAN
        if any(math.isnan(v) for v in base.values()):
            warnings.append("An ankle or heel was not visible during setup; heights may be blank.")
    y_floor = (base.get(HEEL[LEFT], f.NAN) + base.get(HEEL[RIGHT], f.NAN)) / 2

    # Day 2 check from the document: standing upright, ankle y must be below shoulder y.
    if ex["pose"] == "standing":
        rows = [p for p in window if confident(p, ANKLE[side], SHOULDER[side])]
        if rows and statistics.median(p[ANKLE[side]][1] - p[SHOULDER[side]][1] for p in rows) < 0:
            warnings.append("Ankles are above the shoulders: the video looks rotated or upside down.")

    return dict(side=side, facing=facing, base=base, y_floor=y_floor,
                setup_end=first + f.BASELINE_MS, warnings=warnings)


def compute(ex, p, s, facing, L, base, y_floor):
    """Raw measurements for one judgeable frame. Returns (measurements, extra columns)."""
    def P(joint):
        return p[joint[s]]                      # the chosen side
    names, m, extra = ex["measurements"], {}, {}
    if "knee_angle" in names:
        m["knee_angle"] = f.joint_angle(P(HIP), P(KNEE), P(ANKLE))
    if "hip_angle" in names:
        m["hip_angle"] = f.joint_angle(P(SHOULDER), P(HIP), P(KNEE))
    if "torso_lean" in names:
        m["torso_lean"] = f.lean(P(SHOULDER), P(HIP))
    if "heel_lift" in names:
        m["heel_lift"] = f.heel_lift(base[HEEL[s]], P(HEEL)[1], L)
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
        # Front leg chosen on every judgeable frame (document v0.2). Crediting each rep to
        # the leg in front at its Bottom stage happens with the rep counter (replay step 4).
        front = LEFT if f.left_is_front(p[ANKLE[LEFT]], p[ANKLE[RIGHT]], facing, L) else RIGHT
        back = RIGHT if front == LEFT else LEFT
        m["front_knee_angle"] = f.joint_angle(p[HIP[front]], p[KNEE[front]], p[ANKLE[front]])
        m["back_knee_height"] = f.back_knee_height(y_floor, p[KNEE[back]][1], L)
        m["front_knee_over_ankle"] = f.align(p[KNEE[front]], p[ANKLE[front]], facing, L)
        extra["front_leg"] = "L" if front == LEFT else "R"
    return m, extra


def process(pose_csv, out_csv, ex_name):
    ex = EXERCISES[ex_name]
    frames = read_pose_csv(pose_csv)
    st = setup(frames, ex)
    if st is None:
        print("    No person found in any frame, skipped.")
        return None
    side, facing = st["side"], st["facing"]
    required = [j[side] for j in ex["side"]] + [j[k] for j in ex["both"] for k in (LEFT, RIGHT)]
    smoothers = {n: f.Smoother(f.SMOOTH_N_JUMP if n.startswith("jump_rise") else f.SMOOTH_N)
                 for n in ex["measurements"]}
    extras = {"front_knee_angle": "front_leg", "head_drop": "head_dropping"}
    extra_cols = [extras[n] for n in ex["measurements"] if n in extras]
    cols = ["frame", "t_ms", "exercise", "status", "side", "facing", "L"]
    for n in ex["measurements"]:
        cols += [n, f"{n}_raw"]
    cols += extra_cols

    counts = {"ok": 0, "low_confidence": 0, "no_person": 0, "too_far": 0}
    smoothed_values = {n: [] for n in ex["measurements"]}
    last_ok_t = None
    bad_since = None
    long_gaps = []
    rows = []
    for frame, t, p in frames:
        row = {"frame": frame, "t_ms": t, "exercise": ex_name,
               "side": "L" if side == LEFT else "R", "facing": facing}
        if t < st["setup_end"]:
            row["status"] = "setup"
            rows.append(row)
            continue
        if p is None:
            status = "no_person"
        elif not confident(p, *required):
            status = "low_confidence"
        else:
            L = f.body_length(p[SHOULDER[side]], p[HIP[side]])
            status = "too_far" if L < f.MIN_BODY_LENGTH_PX else "ok"
        row["status"] = status
        counts[status] += 1

        if status != "ok":
            bad_since = t if bad_since is None else bad_since
            rows.append(row)
            continue
        if bad_since is not None and t - bad_since >= f.LOW_CONF_PAUSE_MS:
            long_gaps.append((bad_since, t))
        bad_since = None
        if last_ok_t is not None and t - last_ok_t > f.SMOOTH_RESET_MS:
            for s in smoothers.values():
                s.reset()
        last_ok_t = t

        row["L"] = L
        raw, extra = compute(ex, p, side, facing, L, st["base"], st["y_floor"])
        for n, v in raw.items():
            row[f"{n}_raw"] = v
            if not math.isnan(v):
                row[n] = smoothers[n].push(v)
                smoothed_values[n].append(row[n])
        row.update(extra)
        rows.append(row)

    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 6) if isinstance(v, float) and not math.isnan(v) else
                            ("" if isinstance(v, float) else v)) for k, v in r.items()})
    return dict(st=st, counts=counts, smoothed=smoothed_values, long_gaps=long_gaps,
                judged=len(frames) - sum(1 for r in rows if r["status"] == "setup"))


def print_report(ex_name, res):
    ex, st, c = EXERCISES[ex_name], res["st"], res["counts"]
    face = "+1 (toward the right of the image)" if st["facing"] > 0 else "-1 (toward the left)"
    print(f"    Exercise:    {ex_name}")
    print(f"    Setup:       first {f.BASELINE_MS} ms, side {'L' if st['side'] == LEFT else 'R'}, facing {face}")
    pct = 100 * c["ok"] / res["judged"] if res["judged"] else 0
    print(f"    Judgeable:   {c['ok']} of {res['judged']} frames after setup ({pct:.0f}%)  |  "
          f"low confidence {c['low_confidence']}, no person {c['no_person']}, too far {c['too_far']}")
    for n in ex["measurements"]:
        vals = res["smoothed"][n]
        rng = f"{min(vals):.2f} to {max(vals):.2f}" if vals else "no values"
        note = ""
        if n == ex["main"]:
            note = "   <- main, dips each rep" if ex["direction"] == "dip" else "   <- main, rises each rep"
        print(f"    {n:<22} {rng}{note}")
    for a, b in res["long_gaps"]:
        print(f"    Warning: no judgeable frame from {a / 1000:.2f} to {b / 1000:.2f} s. The app would "
              f"pause and redo setup here; this tool does not, so check the values after it.")
    for wmsg in st["warnings"]:
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
