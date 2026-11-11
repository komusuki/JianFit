// Landmark index map from the Shared Formula Document.
// ML Kit and MediaPipe use the same 33 landmarks in the same order.

enum Side { left, right }

enum Joint { ear, shoulder, elbow, wrist, hip, knee, ankle, heel, footIndex }

const Map<Joint, int> _leftIndex = {
  Joint.ear: 7,
  Joint.shoulder: 11,
  Joint.elbow: 13,
  Joint.wrist: 15,
  Joint.hip: 23,
  Joint.knee: 25,
  Joint.ankle: 27,
  Joint.heel: 29,
  Joint.footIndex: 31,
};

/// Landmark index (0 to 32) of a joint on one side. Right = left + 1.
int landmarkIndex(Joint joint, Side side) =>
    _leftIndex[joint]! + (side == Side.right ? 1 : 0);
