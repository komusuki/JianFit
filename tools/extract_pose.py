"""Replay tool, step 1: turn exercise videos into CSV files of body points.

For every frame of a video, MediaPipe finds the 33 body points and this script
writes one CSV row: frame, time_sec, then x, y, z and visibility for each point.
x and y are in PIXELS (like ML Kit on the phone), so angles are not stretched.
Frames where no body is found are kept as blank rows so the timeline stays intact.

Usage (from the tools folder, with .venv active):
    python extract_pose.py "<video file or folder of videos>"
    python extract_pose.py "<folder>" --out "<csv folder>"   # choose where CSVs go
    python extract_pose.py "<folder>" --overwrite            # redo existing CSVs

Each video gets its own folder inside the CSV folder, for example:
    videos\\csv\\bodyweight-squat_S01_front_01\\bodyweight-squat_S01_front_01.csv
    videos\\csv\\bodyweight-squat_S01_front_01\\bodyweight-squat_S01_front_01_check.png
    videos\\csv\\bodyweight-squat_S01_front_01\\bodyweight-squat_S01_front_01_summary.txt
The _check.png is one frame with the detected skeleton drawn on it, so you can
confirm the points sit on the person. The _summary.txt gives the video's length,
how often a body was found, which seconds are missing, and how well each main
joint was tracked. The same summary is printed while the script runs.
"""
import argparse
import csv
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision

MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
             "pose_landmarker_full/float16/latest/pose_landmarker_full.task")
MODEL_PATH = Path(__file__).parent / "models" / "pose_landmarker_full.task"
VIDEO_EXTS = {".mp4", ".mov", ".avi", ".mkv", ".m4v"}

# The 33 body points in MediaPipe's order (ML Kit uses the same order).
LANDMARKS = [
    "nose", "left_eye_inner", "left_eye", "left_eye_outer",
    "right_eye_inner", "right_eye", "right_eye_outer", "left_ear", "right_ear",
    "mouth_left", "mouth_right", "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow", "left_wrist", "right_wrist",
    "left_pinky", "right_pinky", "left_index", "right_index",
    "left_thumb", "right_thumb", "left_hip", "right_hip",
    "left_knee", "right_knee", "left_ankle", "right_ankle",
    "left_heel", "right_heel", "left_foot_index", "right_foot_index",
]


def ensure_model():
    """Download the pose model once (about 9 MB) into tools/models/."""
    if MODEL_PATH.exists():
        return
    MODEL_PATH.parent.mkdir(exist_ok=True)
    print("Downloading the pose model (one time only)...")
    urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)


def csv_header():
    cols = ["frame", "time_sec"]
    for name in LANDMARKS:
        cols += [f"{name}_x", f"{name}_y", f"{name}_z", f"{name}_vis"]
    return cols


def save_check_image(frame, points_px, path):
    """Draw the skeleton on one frame. Left side = green, right side = orange."""
    img = frame.copy()
    for c in vision.PoseLandmarksConnections.POSE_LANDMARKS:
        cv2.line(img, points_px[c.start], points_px[c.end], (255, 255, 255), 2)
    for name, (x, y) in zip(LANDMARKS, points_px):
        color = (0, 200, 0) if name.startswith("left") else (0, 140, 255)
        cv2.circle(img, (x, y), 5, color, -1)
    cv2.imwrite(str(path), img)


# Joints the exercises are judged with: shoulders, elbows, wrists, hips, knees,
# ankles, heels and feet (indices into LANDMARKS).
MAIN_JOINTS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
MIN_VIS = 0.5     # below this the app does not judge a joint (PDF Part 4)
LOW_USABLE = 80   # a joint usable in fewer than this % of frames is marked LOW


def missing_ranges(found, fps):
    """Group the frames with no body into (start_sec, end_sec, frame_count) runs."""
    ranges, start = [], None
    for i, ok in enumerate(found + [True]):
        if not ok and start is None:
            start = i
        elif ok and start is not None:
            ranges.append((start / fps, (i - 1) / fps, i - start))
            start = None
    return ranges


def fmt_range(r):
    return f"{r[0]:.2f}-{r[1]:.2f} s ({r[2]} frames)"


def process_video(video_path, csv_path):
    """Write the CSV and check image. Returns a stats dict, or None if the video can't be opened."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return None
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    options = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
    )
    # Write to a .part file first, so a crash never leaves a half CSV behind.
    part_path = csv_path.with_suffix(".part")
    check_path = csv_path.with_name(csv_path.stem + "_check.png")
    frame_idx = w = h = 0
    found = []                                  # True/False per frame
    vis_sum = {j: 0.0 for j in MAIN_JOINTS}     # for average confidence per joint
    vis_ok = {j: 0 for j in MAIN_JOINTS}        # frames where the joint is usable
    check_saved = False

    with vision.PoseLandmarker.create_from_options(options) as landmarker, \
            open(part_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(csv_header())
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            h, w = frame.shape[:2]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect_for_video(image, int(frame_idx * 1000 / fps))

            row = [frame_idx, round(frame_idx / fps, 4)]
            if result.pose_landmarks:
                found.append(True)
                points = result.pose_landmarks[0]
                for p in points:
                    vis = "" if p.visibility is None else round(p.visibility, 3)
                    row += [round(p.x * w, 2), round(p.y * h, 2), round(p.z * w, 2), vis]
                for j in MAIN_JOINTS:
                    v = points[j].visibility or 0.0
                    vis_sum[j] += v
                    vis_ok[j] += v >= MIN_VIS
                if not check_saved and frame_idx >= total // 2:
                    points_px = [(int(p.x * w), int(p.y * h)) for p in points]
                    save_check_image(frame, points_px, check_path)
                    check_saved = True
            else:
                found.append(False)
                row += [""] * (len(LANDMARKS) * 4)
            writer.writerow(row)
            frame_idx += 1
            if frame_idx % 30 == 0 and total:
                print(f"\r    Reading frames... {min(100, 100 * frame_idx // total)}%", end="", flush=True)

    cap.release()
    print("\r" + " " * 40 + "\r", end="")
    part_path.replace(csv_path)

    detected = sum(found)
    joints = {}
    for j in MAIN_JOINTS:
        avg = vis_sum[j] / detected if detected else 0.0
        usable = 100 * vis_ok[j] / detected if detected else 0.0
        joints[LANDMARKS[j]] = (avg, usable)
    return {
        "video": video_path.name, "width": w, "height": h, "fps": fps,
        "frames": frame_idx, "detected": detected,
        "missing": missing_ranges(found, fps), "joints": joints,
        "csv": csv_path.name, "check": check_path.name if check_saved else None,
    }


def print_report(s, folder):
    pct = 100 * s["detected"] / s["frames"] if s["frames"] else 0
    seconds = s["frames"] / s["fps"]
    print(f"    Video:       {s['width']}x{s['height']}, {s['fps']:.1f} fps, "
          f"{s['frames']} frames ({seconds:.1f} s)")
    print(f"    Body found:  {s['detected']} of {s['frames']} frames ({pct:.0f}%)")
    gaps = s["missing"]
    shown = ", ".join(fmt_range(r) for r in gaps[:5]) or "none"
    more = f", and {len(gaps) - 5} more (see summary)" if len(gaps) > 5 else ""
    print(f"    Missing:     {shown}{more}")
    low = [name for name, (_, usable) in s["joints"].items() if usable < LOW_USABLE]
    if low:
        print(f"    Low joints:  {', '.join(low)} (often the side away from the camera)")
    print(f"    Saved to:    {folder}")
    if pct < 80:
        print("    Warning: body missing in many frames. Check the framing and the _check.png.")


def write_summary(s, path):
    pct = 100 * s["detected"] / s["frames"] if s["frames"] else 0
    lines = [
        "JianFit pose extraction summary",
        "===============================",
        f"Video:        {s['video']}",
        f"Processed:    {datetime.now():%Y-%m-%d %H:%M}",
        f"Resolution:   {s['width']} x {s['height']} px",
        f"Frame rate:   {s['fps']:.1f} fps",
        f"Length:       {s['frames']} frames ({s['frames'] / s['fps']:.1f} s)",
        f"Body found:   {s['detected']} of {s['frames']} frames ({pct:.0f}%)",
        "",
        "Missing time ranges (no body found; these rows are blank in the CSV)",
    ]
    lines += [f"  {fmt_range(r)}" for r in s["missing"]] or ["  none"]
    lines += [
        "",
        "Main joint tracking (over the frames where a body was found)",
        f"  avg = average confidence from 0 to 1. usable = share of frames at or above {MIN_VIS},",
        f"  the level the app needs to judge a joint. LOW = usable below {LOW_USABLE}%.",
    ]
    for name, (avg, usable) in s["joints"].items():
        flag = "   LOW" if usable < LOW_USABLE else ""
        lines.append(f"  {name:<18} avg {avg:.2f}   usable {usable:3.0f}%{flag}")
    lines += ["", "Files", f"  {s['csv']:<45} all 33 body points, one row per frame"]
    if s["check"]:
        lines.append(f"  {s['check']:<45} one frame with the skeleton drawn on it")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Turn exercise videos into CSVs of body points.")
    parser.add_argument("input", help="a video file or a folder of videos")
    parser.add_argument("--out", help="folder for the CSVs (default: a 'csv' folder next to the videos)")
    parser.add_argument("--overwrite", action="store_true", help="redo videos that already have a CSV")
    args = parser.parse_args()

    src = Path(args.input)
    if not src.exists():
        sys.exit(f"Not found: {src}")
    if src.is_file():
        videos = [src]
    else:
        videos = sorted(p for p in src.iterdir() if p.suffix.lower() in VIDEO_EXTS)
    if not videos:
        sys.exit(f"No videos found in {src}")

    out_dir = Path(args.out) if args.out else (src.parent if src.is_file() else src) / "csv"
    out_dir.mkdir(parents=True, exist_ok=True)
    ensure_model()

    print(f"Processing {len(videos)} video(s) into {out_dir}\n")
    done = skipped = failed = 0
    for n, video in enumerate(videos, start=1):
        folder = out_dir / video.stem
        csv_path = folder / f"{video.stem}.csv"
        print(f"[{n}/{len(videos)}] {video.name}")
        if csv_path.exists() and not args.overwrite:
            print("    Skipped: CSV already exists (use --overwrite to redo).\n")
            skipped += 1
            continue
        stats = process_video(video, csv_path)
        if stats is None:
            print("    Could not open this video, skipped.\n")
            failed += 1
            continue
        write_summary(stats, folder / f"{video.stem}_summary.txt")
        print_report(stats, folder)
        print()
        done += 1
    print(f"Done: {done} processed, {skipped} skipped, {failed} could not be opened.")


if __name__ == "__main__":
    main()
