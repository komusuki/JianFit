"""Rule tests for measurements.py (formula document v0.4), on small synthetic videos.

Covers: the "setup while bent" warning, side choice by pass rate, the
plausibility check, the front-leg margin, the automatic pause, and (v0.5) the head
and stillness checks in setup.
Run from the tools folder:  python test_measurement_rules.py   (or: pytest)
"""
import csv
import math
import tempfile
from pathlib import Path

import measurements as m

FPS, FLOOR = 15, 1600
SH, HP, KN, AN, HE, FT, EAR = (11, 12), (23, 24), (25, 26), (27, 28), (29, 30), (31, 32), (7, 8)


def squat(theta=175.0, x=500.0, conf=(0.6, 0.95)):
    """Side-view squat facing +x with knee angle theta; conf = (left, right)."""
    pts = [[540.0, 500.0, 0.9] for _ in range(33)]
    a = math.radians((180 - theta) / 2)
    for side, dx in ((0, -10), (1, 0)):
        ax, ay = x + dx, FLOOR
        kx, ky = ax + 400 * math.sin(a), ay - 400 * math.cos(a)
        hx, hy = kx - 400 * math.sin(a), ky - 400 * math.cos(a)
        sx, sy = hx + 500 * math.sin(a), hy - 500 * math.cos(a)
        for j, (px, py) in {AN: (ax, ay), KN: (kx, ky), HP: (hx, hy), SH: (sx, sy), HE: (ax - 50, ay + 40),
                            FT: (ax + 150, ay + 50), EAR: (sx + 20, sy - 120)}.items():
            pts[j[side]] = [px, py, conf[side]]
    return pts


def ik_knee(h, a, facing, l1=400, l2=400):
    dx, dy = a[0] - h[0], a[1] - h[1]
    d = min(math.hypot(dx, dy), l1 + l2 - 1e-6)
    aa = (l1 ** 2 - l2 ** 2 + d ** 2) / (2 * d)
    hh = math.sqrt(max(0.0, l1 ** 2 - aa ** 2))
    px, py = h[0] + aa * dx / d, h[1] + aa * dy / d
    k1, k2 = (px - hh * dy / d, py + hh * dx / d), (px + hh * dy / d, py - hh * dx / d)
    return max((k1, k2), key=lambda k: facing * k[0])


def lunge(s, front, step_jitter=0.0, facing=-1):
    """Side-view lunge facing -x; s = depth 0..1; front = 0 (left) or 1 (right)."""
    pts = [[540.0, 500.0, 0.9] for _ in range(33)]
    hip = (600, FLOOR - 790 + 380 * s)
    for side in (0, 1):
        sign = 1 if side == front else -1
        ank = (600 + facing * sign * (330 * s + step_jitter), FLOOR)
        knee = ik_knee(hip, ank, facing)
        conf = 0.95 if side == 0 else 0.8
        pts[AN[side]], pts[KN[side]], pts[HP[side]] = [*ank, conf], [*knee, conf], [*hip, conf]
        pts[SH[side]] = [hip[0], hip[1] - 500, conf]
        pts[HE[side]] = [ank[0] - facing * 50, FLOOR + 40, conf]
        pts[FT[side]] = [ank[0] + facing * 150, FLOOR + 50, conf]
    return pts


def run(frames, exercise):
    """Write frames as a pose CSV, run measurements.process, return (result, rows)."""
    d = Path(tempfile.mkdtemp())
    pose, out = d / "clip.csv", d / "clip_measurements.csv"
    with open(pose, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["frame", "t_ms", "width", "height"] + [f"lm{i}_{k}" for i in range(33) for k in "xyc"])
        for i, p in enumerate(frames):
            w.writerow([i, round(i * 1000 / FPS), 1080, 1920] + ([""] * 99 if p is None else
                                                                  [v for pt in p for v in pt]))
    res = m.process(pose, out, exercise)
    rows = list(csv.DictReader(open(out))) if out.exists() else []
    return res, rows


def first_judged_t(rows):
    return next(float(r["t_ms"]) for r in rows if r["status"] == "ok")


def test_setup_while_bent_warns():
    # Holds the bottom of a squat (knee 100 degrees) still from the start, then stands.
    frames = [squat(100.0) for _ in range(int(1.5 * FPS))] + [squat(175.0) for _ in range(FPS)]
    res, _ = run(frames, "bodyweight-squat")
    assert any("happened while bent" in w for w in res["warnings"]), res["warnings"]
    res2, _ = run([squat(175.0) for _ in range(int(2.5 * FPS))], "bodyweight-squat")
    assert not any("bent" in w for w in res2["warnings"])


def test_side_choice_prefers_the_side_that_passes():
    # Right side has higher confidence overall, but its knee is hidden (0.3): left must win.
    frames = []
    for _ in range(int(3 * FPS)):
        p = squat()
        p[KN[1]][2] = 0.3
        frames.append(p)
    res, rows = run(frames, "bodyweight-squat")
    assert res["setups"][0][2] == m.LEFT
    assert any(r["status"] == "ok" for r in rows)    # frames can be judged on the chosen side


def test_implausible_frames_are_not_judged():
    frames = [squat() for _ in range(int(3 * FPS))]
    frames[30][KN[1]] = [frames[30][HP[1]][0] + 5, frames[30][HP[1]][1] + 15, 0.95]   # knee at the hip
    frames[31][AN[1]] = [frames[31][AN[1]][0] + 900, frames[31][AN[1]][1], 0.95]      # shin far too long
    _, rows = run(frames, "bodyweight-squat")
    assert rows[30]["status"] == "implausible" and rows[31]["status"] == "implausible"
    assert rows[32]["status"] == "ok"


def test_front_leg_does_not_flicker():
    # Standing with feet together, ankles jitter by +-15 px (about 0.03 body lengths).
    frames = [lunge(0.0, 0) for _ in range(int(1.5 * FPS))]
    frames += [lunge(0.0, i % 2, step_jitter=15) for i in range(int(2 * FPS))]
    _, rows = run(frames, "forward-lunge")
    legs = [r["front_leg"] for r in rows if r["status"] == "ok"]
    assert len(set(legs)) == 1, legs


def test_front_leg_switches_when_clearly_apart():
    frames = [lunge(0.0, 0) for _ in range(int(1.5 * FPS))]
    frames += [lunge(0.8, 0) for _ in range(FPS)] + [lunge(0.8, 1) for _ in range(FPS)]
    _, rows = run(frames, "forward-lunge")
    ok = [(float(r["t_ms"]), r["front_leg"]) for r in rows if r["status"] == "ok"]
    assert {leg for t, leg in ok if 1600 <= t < 2400} == {"L"}      # left leg lunge
    assert {leg for t, leg in ok if 2600 <= t < 3400} == {"R"}      # right leg lunge


def test_pause_redoes_setup():
    frames = [squat() for _ in range(int(2 * FPS))] + [None] * int(2.5 * FPS) + \
             [squat() for _ in range(int(2 * FPS))]
    res, rows = run(frames, "bodyweight-squat")
    assert len(res["pauses"]) == 1 and len(res["setups"]) == 2
    assert any(r["status"] == "paused" for r in rows)


def test_setup_needs_a_head():
    # v0.5: no ear, no person (a chair has no head); one ear is enough.
    frames = []
    for _ in range(int(2 * FPS)):
        p = squat()
        p[EAR[0]][2] = p[EAR[1]][2] = 0.1
        frames.append(p)
    _, rows = run(frames, "bodyweight-squat")
    assert all(r["status"] == "setup" for r in rows)
    for p in frames:
        p[EAR[1]][2] = 0.9
    res, _ = run(frames, "bodyweight-squat")
    assert len(res["setups"]) == 1


def test_setup_waits_until_still():
    # v0.5: walking 80 px per frame (more than 0.1 x 500 px), then standing still.
    frames = [squat(x=500.0 + 80 * i) for i in range(FPS)] + [squat(x=1700.0) for _ in range(int(1.5 * FPS))]
    res, _ = run(frames, "bodyweight-squat")
    start, end = res["setups"][0][:2]
    assert start >= 1000 and end - start >= 1000, res["setups"]


def test_lunge_skips_the_stillness_check():
    # v0.4.1 kept for both-sides exercises: moving frames still finish setup in 1 s.
    frames = [lunge(0.1 * (i % 2), i % 2) for i in range(int(2 * FPS))]
    res, _ = run(frames, "forward-lunge")
    assert res["setups"] and res["setups"][0][0] == 0, res["setups"]


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  passed  {t.__name__}")
    print(f"All {len(tests)} measurement rule tests passed.")
