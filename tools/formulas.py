"""JianFit shared formulas: the Python mirror of the Shared Formula Document (v0.2).

Owner of the formulas: Member A. This file only copies them. Every function must stay
line-for-line equivalent to the Dart engine (lib/engine). To change a formula, one pull
request updates the document, the Dart code and this file together.

A point is (x, y, c): pixels in the upright image (origin top-left, y grows downward)
and the landmark's confidence. Angles are in degrees, distances in body lengths,
time in milliseconds. Never round before comparing.
"""
import math

NAN = float("nan")

# ---- Constants (one place, names from the formula document) ----
MIN_CONFIDENCE = 0.5      # Confidence check (proposed)
LOW_CONF_PAUSE_MS = 2000  # Automatic pause after this long with no judgeable frame
BASELINE_MS = 1000        # Standing baseline window (proposed)
SMOOTH_N = 5              # Moving average length (proposed)
# Named in v0.2 of the document.
SMOOTH_N_JUMP = 3         # jump_rise only
SMOOTH_RESET_MS = 500     # clear the smoothing buffers after this long with no judgeable frame
MIN_BODY_LENGTH_PX = 20   # L below this: person too far away, frame unjudgeable
VERTICAL_LINE_PX = 1      # below(): a line closer to vertical than this gives "unknown"
LANDING_WINDOW_MS = 500   # soft landing window after a jump

# ---- Landmark numbers (left, right) from the Landmark map section ----
EAR = (7, 8)
SHOULDER = (11, 12)
ELBOW = (13, 14)
WRIST = (15, 16)
HIP = (23, 24)
KNEE = (25, 26)
ANKLE = (27, 28)
HEEL = (29, 30)
FOOT_INDEX = (31, 32)
LEFT, RIGHT = 0, 1


# ---- Joint angle (reference code, copied as written) ----
def joint_angle(a, b, c):
    bax, bay = a[0] - b[0], a[1] - b[1]
    bcx, bcy = c[0] - b[0], c[1] - b[1]
    n = math.hypot(bax, bay) * math.hypot(bcx, bcy)
    if n < 1e-6:
        return float("nan")
    cos = max(-1.0, min(1.0, (bax * bcx + bay * bcy) / n))
    return math.degrees(math.acos(cos))


# ---- Body line and head line ----
def below(p, l1, l2):
    """True if point p is below the line through l1 and l2. None if the line is nearly vertical."""
    dx = l2[0] - l1[0]
    if abs(dx) < VERTICAL_LINE_PX:
        return None
    line_y = l1[1] + (l2[1] - l1[1]) * (p[0] - l1[0]) / dx
    return p[1] > line_y


def hip_sag(shoulder, hip, end):
    """Signed: + hips below the shoulder-end line (sag), - hips above it (pike or overarch)."""
    theta = joint_angle(shoulder, hip, end)
    is_below = below(hip, shoulder, end)
    if math.isnan(theta) or is_below is None:
        return NAN
    return (180 - theta) if is_below else -(180 - theta)


def head_drop(ear, shoulder, hip):
    """Returns (head_drop, dropping). dropping is None when the hip-shoulder line is vertical."""
    value = 180 - joint_angle(ear, shoulder, hip)
    return value, below(ear, hip, shoulder)


# ---- Lean ----
def lean(shoulder, hip):
    """Angle between the hip-to-shoulder line and straight up: 0 upright, 90 horizontal."""
    vx, vy = shoulder[0] - hip[0], shoulder[1] - hip[1]
    n = math.hypot(vx, vy)
    if n < 1e-6:
        return NAN
    return math.degrees(math.acos(max(-1.0, min(1.0, -vy / n))))


# ---- Body length, facing and alignment ----
def body_length(shoulder, hip):
    """L = torso length on the chosen side, in pixels (proposed)."""
    return math.hypot(shoulder[0] - hip[0], shoulder[1] - hip[1])


def sign(v):
    """+1 or -1; sign(0) = +1 (formula document v0.2, Facing)."""
    return 1 if v >= 0 else -1


def facing_standing(foot_index, heel):
    return sign(foot_index[0] - heel[0])


def facing_floor(shoulder, hip):
    return sign(shoulder[0] - hip[0])


def align(p, q, facing, L):
    """How far p is in front of q, in body lengths. Positive = p is ahead of q."""
    return facing * (p[0] - q[0]) / L


# ---- Heights against the standing baseline ----
def heel_lift(base_heel_y, heel_y, L):
    return (base_heel_y - heel_y) / L


def jump_rise(base_ankle_y, ankle_y, L):
    return (base_ankle_y - ankle_y) / L


def back_knee_height(y_floor, back_knee_y, L):
    return (y_floor - back_knee_y) / L


def left_is_front(left_ankle, right_ankle, facing, L):
    """Lunges: the left leg is the front leg when its ankle is further ahead."""
    return align(left_ankle, right_ankle, facing, L) > 0


# ---- Smoothing ----
class Smoother:
    """Plain moving average of the last n judgeable values; averages what it has while warming up."""

    def __init__(self, n=SMOOTH_N):
        self.n = n
        self.buf = []

    def push(self, value):
        self.buf.append(value)
        if len(self.buf) > self.n:
            self.buf.pop(0)
        return sum(self.buf) / len(self.buf)

    def reset(self):
        self.buf.clear()
