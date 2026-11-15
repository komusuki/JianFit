"""Replay tool, step 4: count reps and judge form like the app, then score against labels.

For every video of one exercise, it reads <name>_measurements.csv (from measurements.py),
feeds the judged frames to the rep counter (rep_counter.py, the mirror of the Dart
counter), runs the form checks on each finished rep, and compares the result with your
labels from the labeling sheet.

Exercise settings (rep limits and form checks) come from the app's own file,
assets/exercises/<id>.json, when it exists, so the replay judges exactly like the phone.
Exercises without one yet use tools/tuning/<id>.json: same form check format, with
start_threshold and complete_threshold at the top level instead of under "tracking".
Form checks are judged by form_judge.py (the mirror of lib/engine/form_judge.dart), at the
strictness level you choose (default standard).

Usage (from the tools folder, with .venv active):
    python replay_check.py "<videos\\csv folder>" --exercise forward-lunge --labels "<JianFit_Labels.xlsx>"
    python replay_check.py "<folder>" --exercise forward-lunge --labels "<xlsx>" --subjects S01,S02
    python replay_check.py "<folder>" --exercise forward-lunge        # no labels: list detected reps
    python replay_check.py "<folder>" --exercise forward-lunge --labels "<xlsx>" --strictness strict

Labels: download the Google Sheet as .xlsx (File > Download > Microsoft Excel). The Videos
tab links video_id to file_name. The Reps tab takes two kinds of rows, and a video can mix them:
  one rep:     start_sec to end_sec covers one rep (RANGE_MIN_SEC or shorter); matched to the
               detected rep it overlaps most.
  whole clip:  start_sec to end_sec covers many reps (longer than RANGE_MIN_SEC) and rep_number
               is HOW MANY reps are in it. Every detected rep whose middle falls in the range
               gets that row's label, and the count is compared with rep_number. Detected reps
               outside every range are listed but not counted. Side accuracy is skipped.
Reps whose notes contain "exclude" are left out of form agreement (they still count as reps).

Scores (written to the console and to replay_results_<exercise>.csv in the csv folder):
  count accuracy  = 1 - sum over videos of |detected - labeled| / total labeled   (target 95%)
  form agreement  = matched reps where the checks agree with the label            (target 85%)
                    label "correct": no check fired; label "<mistake>": that check fired
  side accuracy   = lunges only: front leg at the deepest frame vs the labeled side
"""
import argparse
import csv
import json
import math
import sys
from pathlib import Path

from measurements import EXERCISES, exercise_id
from form_judge import STRICTNESS, check_value, judge_rep, read_form_checks
from rep_counter import RepCounter

TUNING_DIR = Path(__file__).parent / "tuning"
ASSETS_DIR = Path(__file__).parent.parent / "assets" / "exercises"
TARGET_COUNT, TARGET_FORM = 95, 85
RANGE_MIN_SEC = 8   # a label row longer than this is a whole-clip row (no single rep lasts this long)
SIDE_NAMES = {"L": "Left", "R": "Right"}


def load_settings(ex_slug, ex):
    """(file used, start threshold, complete threshold, form checks). The app's exercise file
    wins over the tuning file, so the replay always judges with what the phone uses."""
    ex_id = exercise_id(ex_slug)
    asset, tuning = ASSETS_DIR / f"{ex_id}.json", TUNING_DIR / f"{ex_id}.json"
    if asset.exists():
        path, data = asset, json.loads(asset.read_text(encoding="utf-8"))
        tracking = data.get("tracking", {})
        start, complete = tracking.get("start_threshold"), tracking.get("complete_threshold")
        if tracking.get("main_measurement") not in (None, ex["main"]):
            print(f"Warning: {asset.name} uses main measurement {tracking['main_measurement']}, "
                  f"the replay tool uses {ex['main']}.")
    elif tuning.exists():
        path, data = tuning, json.loads(tuning.read_text(encoding="utf-8"))
        start, complete = data.get("start_threshold"), data.get("complete_threshold")
    else:
        sys.exit(f"No exercise file {asset} and no tuning file {tuning}. "
                 f"Copy tuning/forward_lunge.json and edit it for {ex_slug}.")
    checks, problems = read_form_checks(data.get("form_checks"), ex["measurements"])
    if not isinstance(start, (int, float)) or not isinstance(complete, (int, float)):
        problems.append("start_threshold and complete_threshold must be numbers")
    if problems:
        sys.exit(f"{path.name} has {len(problems)} problem(s):\n" + "\n".join(f"  - {p}" for p in problems))
    return path, start, complete, checks


def find_measurement_csvs(folder, ex_slug):
    """Each video's folder holds <name>_measurements.csv; keep the ones for this exercise."""
    out = []
    for d in sorted(p for p in folder.iterdir() if p.is_dir()):
        m = d / f"{d.name}_measurements.csv"
        if m.exists() and d.name.lower().split("_")[0] == ex_slug:
            out.append(m)
    return out


def to_float(text):
    try:
        v = float(text)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(v) else v


def detect_reps(csv_path, ex, start, complete):
    """Feed judged frames to the rep counter; reset it when the measurement layer paused."""
    counter = RepCounter(ex["direction"], start, complete)
    names = ex["measurements"]
    reps = []
    with open(csv_path, newline="") as fh:
        for row in csv.DictReader(fh):
            if row["status"] == "paused":
                counter.reset(keep_count=True)          # drop any rep in progress
                continue
            if row["status"] != "ok":
                continue                                # unjudgeable: counter keeps its stage
            main = to_float(row[ex["main"]])
            if main is None:
                continue
            values = {n: to_float(row[n]) for n in names if to_float(row[n]) is not None}
            if "front_leg" in row:
                values["front_leg"] = row["front_leg"]
            rep = counter.update(main, values, float(row["t_ms"]))
            if rep:
                reps.append(rep)
    return reps


def run_checks(rep, checks, strictness):
    """The form judge's verdict as (fired, not_judged) check names."""
    verdict = judge_rep(rep, checks, strictness)
    return [c.name for c in verdict.failed], [c.name for c in verdict.skipped]


def load_labels(xlsx):
    """Returns {video stem (lowercase): [label rows]} from the Videos and Reps tabs."""
    try:
        import pandas as pd
        sheets = pd.read_excel(xlsx, sheet_name=["Videos", "Reps"], dtype=str)
    except ImportError as e:
        sys.exit(f"{e}. Run: pip install openpyxl")
    videos = sheets["Videos"].fillna("")
    reps = sheets["Reps"].fillna("")
    stem_of = {r["video_id"].strip(): Path(r["file_name"].strip()).stem.lower()
               for _, r in videos.iterrows() if r["video_id"].strip() and r["file_name"].strip()}
    labels = {}
    for _, r in reps.iterrows():
        vid = r["video_id"].strip()
        start, end = to_float(r["start_sec"]), to_float(r["end_sec"])
        if vid not in stem_of or start is None or end is None:
            continue
        labels.setdefault(stem_of[vid], []).append(dict(
            rep_number=r["rep_number"], side=r["side"].strip(), start_ms=start * 1000,
            end_ms=end * 1000, label=r["label"].strip(), notes=r["notes"].strip()))
    return labels


def match(detected, labeled):
    """One-to-one matching by largest time overlap. Returns {label index: detected index}."""
    pairs = []
    for i, d in enumerate(detected):
        for j, lab in enumerate(labeled):
            overlap = min(d.end_ms, lab["end_ms"]) - max(d.start_ms, lab["start_ms"])
            if overlap > 0:
                pairs.append((overlap, i, j))
    used_d, matches = set(), {}
    for _, i, j in sorted(pairs, reverse=True):
        if i not in used_d and j not in matches:
            matches[j] = i
            used_d.add(i)
    return matches


def is_range(lab):
    return lab["end_ms"] - lab["start_ms"] > RANGE_MIN_SEC * 1000


def range_count(lab):
    """A whole-clip row's rep_number is the number of reps in it."""
    n = to_float(lab["rep_number"])
    return int(n) if n is not None else None


def in_range(rep, lab):
    mid = (rep.start_ms + rep.end_ms) / 2
    return lab["start_ms"] <= mid <= lab["end_ms"]


def pct(a, b):
    return 100 * a / b if b else float("nan")


def main():
    parser = argparse.ArgumentParser(description="Replay step 4: rep counting and form checks vs labels.")
    parser.add_argument("folder", help="the videos\\csv folder (one subfolder per video)")
    parser.add_argument("--exercise", required=True, choices=sorted(EXERCISES))
    parser.add_argument("--labels", help="the labeling sheet downloaded as .xlsx")
    parser.add_argument("--subjects", help="only these subjects, for example S01,S02")
    parser.add_argument("--strictness", choices=STRICTNESS, default="standard",
                        help="limits for cleanliness checks (default standard)")
    args = parser.parse_args()

    folder = Path(args.folder)
    ex = EXERCISES[args.exercise]
    if ex["main"] is None:
        sys.exit(f"{args.exercise} is a hold; replay_check.py handles rep exercises only.")
    settings_path, start, complete, checks = load_settings(args.exercise, ex)
    csvs = find_measurement_csvs(folder, args.exercise)
    if args.subjects:
        wanted = {s.strip().upper() for s in args.subjects.split(",")}
        csvs = [c for c in csvs if c.parent.name.split("_")[1].upper() in wanted]
    if not csvs:
        sys.exit(f"No {args.exercise} measurement files in {folder}. Run measurements.py first.")
    labels = load_labels(args.labels) if args.labels else {}

    direction = "below" if ex["direction"] == "dip" else "above"
    print(f"Replay check: {args.exercise}   (settings: {settings_path.parent.name}/{settings_path.name}, "
          f"strictness {args.strictness})")
    print(f"  Rep: starts {direction} {start}, completes back past {complete} ({ex['main']})")
    for c in checks:
        fails = f"> {c.limit_for(args.strictness):g}" if c.kind == "max" else f"< {c.limit_for(args.strictness):g}"
        where = "at the deepest frame" if c.timing == "bottom" else "at any point in the rep"
        print(f"  Check {c.name}: fails if {c.measurement} {fails} {where} ({c.category})")
    print()

    results, totals, per_subject = [], {}, {}
    check_stats = {c.name: dict(caught=0, missed=0, false_on_correct=0, false_on_other=0) for c in checks}
    for n, csv_path in enumerate(csvs, start=1):
        stem = csv_path.parent.name
        subject = stem.split("_")[1].upper() if "_" in stem else "?"
        reps = detect_reps(csv_path, ex, start, complete)
        verdicts = [run_checks(r, checks, args.strictness) for r in reps]
        labeled = labels.get(stem.lower(), [])
        print(f"[{n}/{len(csvs)}] {stem}")

        if not labeled:
            print(f"    No labels found: detected {len(reps)} reps")
            for i, (r, (fired, _)) in enumerate(zip(reps, verdicts), start=1):
                leg = SIDE_NAMES.get(r.at_deepest.get("front_leg"), "")
                print(f"      rep {i}: {r.start_ms / 1000:.2f} to {r.end_ms / 1000:.2f} s, deepest "
                      f"{r.deepest:.1f}{', ' + leg + ' leg' if leg else ''}, "
                      f"checks: {', '.join(fired) or 'none'}")
                results.append(dict(video=stem, subject=subject, detected_rep=i,
                                    detected_start_sec=round(r.start_ms / 1000, 2),
                                    detected_end_sec=round(r.end_ms / 1000, 2), detected_side=leg,
                                    deepest=round(r.deepest, 2), fired=";".join(fired)))
            print()
            continue

        ranges = [lab for lab in labeled if is_range(lab)]
        singles = [lab for lab in labeled if not is_range(lab)]
        bad = [lab for lab in ranges if range_count(lab) is None]
        if bad:
            sys.exit(f"{stem}: a whole-clip label row ({bad[0]['start_ms'] / 1000:g} to "
                     f"{bad[0]['end_ms'] / 1000:g} s) needs the number of reps in rep_number.")
        # Detected reps inside a whole-clip range belong to it; the rest are matched to single rows.
        owner = {}
        for i, r in enumerate(reps):
            for k, lab in enumerate(ranges):
                if in_range(r, lab):
                    owner[i] = k
                    break
        free = [i for i in range(len(reps)) if i not in owner]
        sub = match([reps[i] for i in free], singles)
        matches = {j: free[i] for j, i in sub.items()}
        pairs = [(lab, matches.get(j)) for j, lab in enumerate(singles)]
        for k, lab in enumerate(ranges):
            in_k = [i for i in sorted(owner) if owner[i] == k]
            pairs += [(lab, i) for i in in_k]
            n_lab, n_det = range_count(lab), len(in_k)
            print(f"    {lab['start_ms'] / 1000:g} to {lab['end_ms'] / 1000:g} s, {lab['label'] or 'no label'}: "
                  f"labeled {n_lab} reps, detected {n_det}")
        outside = [i for i in free if i not in matches.values()]
        labeled_count = len(singles) + sum(range_count(lab) for lab in ranges)
        # Reps outside every range only count as extras when the video also has single-rep rows.
        counted_extra = len(outside) if singles else 0
        detected_count = len(matches) + len(owner) + counted_extra
        s = dict(labeled=labeled_count, detected=detected_count, matched=len(matches) + len(owner),
                 form_judged=0, form_agree=0, side_judged=0, side_agree=0)
        for lab, i in pairs:
            whole = is_range(lab)
            row = dict(video=stem, subject=subject, label_rep=lab["rep_number"], label_side=lab["side"],
                       label_start_sec=lab["start_ms"] / 1000, label_end_sec=lab["end_ms"] / 1000,
                       label=lab["label"], notes=lab["notes"])
            if i is None:
                row["result"] = "missed (no rep detected)"
                results.append(row)
                continue
            r, (fired, not_judged) = reps[i], verdicts[i]
            leg = SIDE_NAMES.get(r.at_deepest.get("front_leg"), "")
            row.update(detected_rep=i + 1, detected_start_sec=round(r.start_ms / 1000, 2),
                       detected_end_sec=round(r.end_ms / 1000, 2), detected_side=leg,
                       deepest=round(r.deepest, 2), fired=";".join(fired), not_judged=";".join(not_judged))
            for c in checks:
                v = check_value(c, r)
                row[c.name] = "" if v is None else round(v, 3)
            label = lab["label"]
            excluded = "exclude" in lab["notes"].lower() or not label
            if not excluded and label != "correct" and label not in check_stats:
                row["result"] = f"label '{label}' has no check in {settings_path.name}"
            elif not excluded:
                agree = (not fired) if label == "correct" else (label in fired)
                s["form_judged"] += 1
                s["form_agree"] += agree
                row["result"] = "agree" if agree else "disagree"
                for name, st in check_stats.items():
                    if name in fired and label == name:
                        st["caught"] += 1
                    elif label == name:
                        st["missed"] += 1
                    elif name in fired:
                        st["false_on_correct" if label == "correct" else "false_on_other"] += 1
            else:
                row["result"] = "excluded from form agreement"
            if leg and lab["side"] in ("Left", "Right") and not whole:
                s["side_judged"] += 1
                s["side_agree"] += leg == lab["side"]
            results.append(row)
        for i in outside:
            r, (fired, _) = reps[i], verdicts[i]
            results.append(dict(video=stem, subject=subject, detected_rep=i + 1,
                                detected_start_sec=round(r.start_ms / 1000, 2),
                                detected_end_sec=round(r.end_ms / 1000, 2),
                                deepest=round(r.deepest, 2), fired=";".join(fired),
                                result="extra (no label)" if singles else "outside labeled time (not counted)"))

        s["count_error"] = abs(s["detected"] - s["labeled"])
        for bucket in (totals, per_subject.setdefault(subject, {})):
            for k, v in s.items():
                bucket[k] = bucket.get(k, 0) + v
        side_txt = f" | side {s['side_agree']}/{s['side_judged']}" if s["side_judged"] else ""
        out_txt = f", {len(outside)} outside labeled time" if outside and not singles else ""
        print(f"    labeled {s['labeled']}, detected {s['detected']}{out_txt} | "
              f"form agree {s['form_agree']}/{s['form_judged']}{side_txt}\n")

    out_csv = folder / f"replay_results_{args.exercise}.csv"
    cols = []
    for r in results:
        cols += [k for k in r if k not in cols]
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(results)

    if totals:
        def summary(t):
            count_acc = max(0.0, 100 - pct(t["count_error"], t["labeled"]))
            form = pct(t["form_agree"], t["form_judged"])
            side = f" | side {pct(t['side_agree'], t['side_judged']):.0f}%" if t["side_judged"] else ""
            return (f"count accuracy {count_acc:.1f}% (target {TARGET_COUNT}%) | form agreement "
                    f"{form:.1f}% (target {TARGET_FORM}%), {t['form_agree']}/{t['form_judged']} reps{side}")
        print(f"Overall:  {summary(totals)}")
        for subj in sorted(per_subject):
            print(f"  {subj}:    {summary(per_subject[subj])}")
        print("\nPer check (caught on its own mistake / missed / false alarms on correct reps / on other mistakes):")
        for name, st in check_stats.items():
            own = st["caught"] + st["missed"]
            print(f"  {name:<22} caught {st['caught']}/{own}, missed {st['missed']}, "
                  f"false on correct {st['false_on_correct']}, on other mistakes {st['false_on_other']}")
        print("  (false alarms on other mistakes are often real: a shallow lunge also leaves the back knee high)")
    print(f"\nDetails per rep: {out_csv}")


if __name__ == "__main__":
    main()
