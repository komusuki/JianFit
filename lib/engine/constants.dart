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
