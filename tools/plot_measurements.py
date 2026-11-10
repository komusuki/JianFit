"""Replay tool, step 3: plot each video's measurements over time.

The main measurement is on top: each rep shows as a dip (or a hill for the glute bridge),
so rep thresholds are easy to read off the grid. The exercise's other measurements are
below it, for choosing form-check limits. The thick line is the smoothed value the app
uses; the thin line is the raw value. Grey bands mark the setup window and frames that
could not be judged.

Usage (from the tools folder, with .venv active, after measurements.py):
    python plot_measurements.py "<videos\\csv folder>"
    python plot_measurements.py "<one _measurements.csv>"
    python plot_measurements.py "<folder>" --overwrite

Saves <name>_plot.png next to each measurements CSV.
"""
import argparse
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402

from measurements import EXERCISES  # noqa: E402

DEGREE_MEASUREMENTS = ("_angle", "torso_lean", "hip_sag", "head_drop")


def unit(name):
    return "degrees" if name.endswith(DEGREE_MEASUREMENTS) else "body lengths"


def bad_spans(t, status):
    """Time spans where the frame was not judged, as (start, end, kind)."""
    spans, start, kind = [], None, None
    for ti, s in zip(t, status):
        k = None if s == "ok" else ("setup" if s == "setup" else "not judged")
        if k != kind:
            if kind is not None:
                spans.append((start, ti, kind))
            start, kind = ti, k
    if kind is not None:
        spans.append((start, t.iloc[-1], kind))
    return spans


def plot(csv_path, png_path):
    df = pd.read_csv(csv_path)
    name = csv_path.name.removesuffix("_measurements.csv")
    ex_name = df["exercise"].iloc[0]
    ex = EXERCISES[ex_name]
    t = df["t_ms"] / 1000
    rows = list(ex["measurements"])
    if "front_leg" in df:
        rows.append("front_leg")

    fig, axes = plt.subplots(len(rows), 1, figsize=(12, 2.5 * len(rows)), sharex=True, squeeze=False)
    axes = axes[:, 0]
    spans = bad_spans(t, df["status"])
    for ax, n in zip(axes, rows):
        for a, b, kind in spans:
            ax.axvspan(a, b, color="0.85" if kind == "setup" else "0.92", zorder=0)
        if n == "front_leg":
            leg = df["front_leg"].map({"L": 1, "R": 0})
            ax.step(t, leg, where="post", color="tab:purple")
            ax.set_yticks([0, 1], ["right", "left"])
            ax.set_ylim(-0.3, 1.3)
            ax.set_title("front leg", loc="left", fontsize=10)
            continue
        ax.plot(t, df[f"{n}_raw"], color="tab:blue", alpha=0.3, linewidth=0.8, label="raw")
        ax.plot(t, df[n], color="tab:blue", linewidth=1.8, label="smoothed")
        title = n
        if n == ex["main"]:
            title += "  (main measurement, " + ("dips" if ex["direction"] == "dip" else "rises") + " each rep)"
        ax.set_title(title, loc="left", fontsize=10, fontweight="bold" if n == ex["main"] else "normal")
        ax.set_ylabel(unit(n))
        ax.grid(True, alpha=0.35)
        ax.minorticks_on()
        ax.grid(True, which="minor", alpha=0.12)
    axes[0].legend(loc="upper right", fontsize=8)
    axes[-1].set_xlabel("time (s)")

    judged = (df["status"] != "setup").sum()
    pct = 100 * (df["status"] == "ok").sum() / judged if judged else 0
    fig.suptitle(f"{name}   |   {ex_name}   |   side {df['side'].iloc[0]}, facing {df['facing'].iloc[0]:+d}"
                 f"   |   judged {pct:.0f}% of frames after setup   (grey = setup or not judged)",
                 fontsize=11)
    fig.tight_layout()
    fig.savefig(png_path, dpi=110)
    plt.close(fig)


def find_measurement_csvs(src):
    if src.is_file():
        return [src]
    own = src / f"{src.name}_measurements.csv"
    if own.exists():
        return [own]
    return sorted(d / f"{d.name}_measurements.csv" for d in src.iterdir()
                  if (d / f"{d.name}_measurements.csv").exists())


def main():
    parser = argparse.ArgumentParser(description="Plot JianFit measurements over time.")
    parser.add_argument("input", help="the videos\\csv folder, one video's folder, or one _measurements.csv")
    parser.add_argument("--overwrite", action="store_true", help="redo plots that already exist")
    args = parser.parse_args()

    src = Path(args.input)
    if not src.exists():
        sys.exit(f"Not found: {src}")
    csvs = find_measurement_csvs(src)
    if not csvs:
        sys.exit(f"No _measurements.csv files found in {src}. Run measurements.py first.")

    done = skipped = 0
    for n, csv_path in enumerate(csvs, start=1):
        png_path = csv_path.with_name(csv_path.name.replace("_measurements.csv", "_plot.png"))
        if png_path.exists() and not args.overwrite:
            print(f"[{n}/{len(csvs)}] {png_path.name}: already exists, skipped (use --overwrite).")
            skipped += 1
            continue
        plot(csv_path, png_path)
        print(f"[{n}/{len(csvs)}] saved {png_path.name}")
        done += 1
    print(f"Done: {done} plotted, {skipped} skipped.")


if __name__ == "__main__":
    main()
