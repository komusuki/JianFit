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
    videos\\csv\\bodyweight_squat_S01_front\\bodyweight_squat_S01_front.csv
    videos\\csv\\bodyweight_squat_S01_front\\bodyweight_squat_S01_front_check.png
The _check.png is one frame with the detected skeleton drawn on it, so you can
confirm the points sit on the person.
"""
import argparse
import csv
import sys
import urllib.request
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


def process_video(video_path, csv_path):
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print(f"  Could not open {video_path.name}, skipped.")
        return
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
    frame_idx = detected = 0
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
                detected += 1
                points = result.pose_landmarks[0]
                for p in points:
                    vis = "" if p.visibility is None else round(p.visibility, 3)
                    row += [round(p.x * w, 2), round(p.y * h, 2), round(p.z * w, 2), vis]
                if not check_saved and frame_idx >= total // 2:
                    points_px = [(int(p.x * w), int(p.y * h)) for p in points]
                    save_check_image(frame, points_px,
                                     csv_path.with_name(csv_path.stem + "_check.png"))
                    check_saved = True
            else:
                row += [""] * (len(LANDMARKS) * 4)
            writer.writerow(row)
            frame_idx += 1

    cap.release()
    part_path.replace(csv_path)
    pct = 100 * detected / frame_idx if frame_idx else 0
    print(f"  {video_path.name}: {frame_idx} frames, body found in {pct:.0f}% -> {csv_path.name}")
    if pct < 80:
        print("    Warning: body missing in many frames. Check the video framing and the _check.png.")


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

    print(f"Processing {len(videos)} video(s) into {out_dir}")
    for video in videos:
        csv_path = out_dir / video.stem / f"{video.stem}.csv"
        if csv_path.exists() and not args.overwrite:
            print(f"  {video.name}: CSV already exists, skipped (use --overwrite to redo).")
            continue
        process_video(video, csv_path)
    print("Done.")


if __name__ == "__main__":
    main()
