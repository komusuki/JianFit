// Constants from the JianFit Shared Formula Document.
// The comment after each one is its name in the document.
// Dart style uses lowerCamelCase, so the names differ only in case.

const double minConfidence = 0.5; // MIN_CONFIDENCE
const int lowConfPauseMs = 2000; // LOW_CONF_PAUSE_MS
const int baselineMs = 1000; // BASELINE_MS
const int smoothN = 5; // SMOOTH_N
const int smoothNJump = 3; // SMOOTH_N_JUMP
const int smoothResetMs = 500; // SMOOTH_RESET_MS
const double minBodyLengthPx = 20; // MIN_BODY_LENGTH_PX
const double verticalLinePx = 1; // VERTICAL_LINE_PX
const int landingWindowMs = 500; // LANDING_WINDOW_MS

// Rep counter (not a formula, so not in the document yet).
// The main measurement must move this many degrees back from its deepest
// value before the counter treats the bottom as passed.
const double repTurnaroundDeg = 5;

// Added in formula v0.4 and v0.4.2.
const double frontLegMargin = 0.1; // FRONT_LEG_MARGIN
const double plausibleMinAngleDeg = 30; // PLAUSIBLE_MIN_ANGLE_DEG
const double plausibleLengthChange = 0.4; // PLAUSIBLE_LENGTH_CHANGE
// A rep shorter than this (leaving Ready to Complete) is dropped. Engine setting.
const int minRepMs = 500; // MIN_REP_MS

// Added in formula v0.5.
// Setup restarts when a required joint moves more than this many body lengths
// from where it was at the start of the window (only for exercises without
// both-sides joints; see the formula document).
const double stillMaxMove = 0.1; // STILL_MAX_MOVE

// Cue manager (roadmap Part 7). Engine settings, not formulas.
// The same cue is not spoken again within this time (safety cues excepted).
const int cueRepeatMs = 5000;
// The same mistake this many times in a set: show the tip card.
const int tipAfterMistakes = 3;

// Day 9 engine settings (rep counter and hold timer). Not formulas, but listed
// in the formula document so tools/rep_counter.py uses the same values.
// Jump squat: a rep with no jump completes this long after the knee is back up.
const int jumpWaitMs = 400; // JUMP_WAIT_MS
// Holds: a check must fail this long before the hold counts as broken.
const int holdBreakMs = 500; // HOLD_BREAK_MS
// Floor holds (plank): in position only while torso_lean is at least this.
const double holdMinLeanDeg = 60; // HOLD_MIN_LEAN_DEG
// Holds: before the first passing frame, no break until in position this long.
const int holdSettleMs = 1000; // HOLD_SETTLE_MS
