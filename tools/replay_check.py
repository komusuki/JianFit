"""Replay tool, step 4: count reps and judge form like the app, then score against labels.

For every video of one exercise, it reads <name>_measurements.csv (from measurements.py),
feeds the judged frames to the rep counter (rep_counter.py, the mirror of the Dart
counter), runs the form checks on each finished rep, and compares the result with your
labels from the labeling sheet. Tune the numbers in tuning/<exercise>.json and run it again.

Usage (from the tools folder, with .venv active):
    python replay_check.py "<videos\\csv folder>" --exercise forward-lunge --labels "<JianFit_Labels.xlsx>"
    python replay_check.py "<folder>" --exercise forward-lunge --labels "<xlsx>" --subjects S01,S02
    python replay_check.py "<folder>" --exercise forward-lunge        # no labels: list detected reps

Labels: download the Google Sheet as .xlsx (File > Download > Microsoft Excel). The Videos
tab links video_id to file_name; the Reps tab holds one row per rep. Reps whose notes
contain "exclude" are left out of form agreement (they still count as reps).

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

from measurements import EXERCISES
from rep_counter import RepCounter

TUNING_DIR = Path(__file__).parent / "tuning"
TARGET_COUNT, TARGET_FORM = 95, 85
SIDE_NAMES = {"L": "Left", "R": "Right"}


def load_settings(ex_slug):
    path = TUNING_DIR / f"{ex_slug.replace('-', '_')}.json"
    if not path.exists():
        sys.exit(f"No tuning file {path}. Copy tuning/forward_lunge.json and edit it for {ex_slug}.")
    return path, json.loads(path.read_text())


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


def detect_reps(csv_path, ex, settings):
    """Feed judged frames to the rep counter; reset it when the measurement layer paused."""
    counter = RepCounter(ex["direction"], settings["start_threshold"], settings["complete_threshold"])
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


def run_checks(rep, checks, main_name):
    """Each check uses the value at the deepest frame. Returns (fired, not_judged)."""
    fired, not_judged = [], []
    for c in checks:
        v = rep.deepest if c["measurement"] == main_name else rep.at_deepest.get(c["measurement"])
        if v is None:
            not_judged.append(c["name"])
        elif ("max" in c and v > c["max"]) or ("min" in c and v < c["min"]):
            fired.append(c["name"])
    return fired, not_judged


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


def pct(a, b):
    return 100 * a / b if b else float("nan")


def main():
    parser = argparse.ArgumentParser(description="Replay step 4: rep counting and form checks vs labels.")
    parser.add_argument("folder", help="the videos\\csv folder (one subfolder per video)")
    parser.add_argument("--exercise", required=True, choices=sorted(EXERCISES))
    parser.add_argument("--labels", help="the labeling sheet downloaded as .xlsx")
    parser.add_argument("--subjects", help="only these subjects, for example S01,S02")
    args = parser.parse_args()

    folder = Path(args.folder)
    ex = EXERCISES[args.exercise]
    if ex["main"] is None:
        sys.exit(f"{args.exercise} is a hold; replay_check.py handles rep exercises only.")
    settings_path, settings = load_settings(args.exercise)
    checks = settings.get("form_checks", [])
    csvs = find_measurement_csvs(folder, args.exercise)
    if args.subjects:
        wanted = {s.strip().upper() for s in args.subjects.split(",")}
        csvs = [c for c in csvs if c.parent.name.split("_")[1].upper() in wanted]
    if not csvs:
        sys.exit(f"No {args.exercise} measurement files in {folder}. Run measurements.py first.")
    labels = load_labels(args.labels) if args.labels else {}

    direction = "below" if ex["direction"] == "dip" else "above"
    print(f"Replay check: {args.exercise}   (settings: tuning/{settings_path.name})")
    print(f"  Rep: starts {direction} {settings['start_threshold']}, completes back past "
          f"{settings['complete_threshold']} ({ex['main']})")
    for c in checks:
        limit = f"> {c['max']}" if "max" in c else f"< {c['min']}"
        print(f"  Check {c['name']}: {c['measurement']} {limit} at the deepest frame ({c['category']})")
    print()

    results, totals, per_subject = [], {}, {}
    check_stats = {c["name"]: dict(caught=0, missed=0, false_on_correct=0, false_on_other=0) for c in checks}
    for n, csv_path in enumerate(csvs, start=1):
        stem = csv_path.parent.name
        subject = stem.split("_")[1].upper() if "_" in stem else "?"
        reps = detect_reps(csv_path, ex, settings)
        verdicts = [run_checks(r, checks, ex["main"]) for r in reps]
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

        matches = match(reps, labeled)
        s = dict(labeled=len(labeled), detected=len(reps), matched=len(matches),
                 form_judged=0, form_agree=0, side_judged=0, side_agree=0)
        for j, lab in enumerate(labeled):
            row = dict(video=stem, subject=subject, label_rep=lab["rep_number"], label_side=lab["side"],
                       label_start_sec=lab["start_ms"] / 1000, label_end_sec=lab["end_ms"] / 1000,
                       label=lab["label"], notes=lab["notes"])
            i = matches.get(j)
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
                v = r.deepest if c["measurement"] == ex["main"] else r.at_deepest.get(c["measurement"])
                row[c["measurement"]] = "" if v is None else round(v, 3)
            label = lab["label"]
            excluded = "exclude" in lab["notes"].lower() or not label
            if not excluded and label != "correct" and label not in check_stats:
                row["result"] = f"label '{label}' has no check in the tuning file"
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
            if leg and lab["side"] in ("Left", "Right"):
                s["side_judged"] += 1
                s["side_agree"] += leg == lab["side"]
            results.append(row)
        for i, (r, (fired, _)) in enumerate(zip(reps, verdicts)):
            if i not in matches.values():
                results.append(dict(video=stem, subject=subject, detected_rep=i + 1,
                                    detected_start_sec=round(r.start_ms / 1000, 2),
                                    detected_end_sec=round(r.end_ms / 1000, 2),
                                    deepest=round(r.deepest, 2), fired=";".join(fired),
                                    result="extra (no label)"))

        s["count_error"] = abs(s["detected"] - s["labeled"])
        for bucket in (totals, per_subject.setdefault(subject, {})):
            for k, v in s.items():
                bucket[k] = bucket.get(k, 0) + v
        side_txt = f" | side {s['side_agree']}/{s['side_judged']}" if s["side_judged"] else ""
        print(f"    labeled {s['labeled']}, detected {s['detected']}, matched {s['matched']} "
              f"(missed {s['labeled'] - s['matched']}, extra {s['detected'] - s['matched']}) | "
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
