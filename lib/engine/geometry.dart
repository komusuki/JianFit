// Formulas from the JianFit Shared Formula Document.
// Every function here must stay equivalent to the Python replay tool.

import 'dart:math';

import 'constants.dart';

/// A landmark in pixels of the upright image, with its confidence (0 to 1).
class Pt {
  const Pt(this.x, this.y, [this.c = 1.0]);
  final double x;
  final double y;
  final double c;
}

/// Joint angle at b, from 0 to 180 degrees. NaN when two points overlap.
double jointAngle(Pt a, Pt b, Pt c) {
  final bax = a.x - b.x, bay = a.y - b.y;
  final bcx = c.x - b.x, bcy = c.y - b.y;
  final n = sqrt(bax * bax + bay * bay) * sqrt(bcx * bcx + bcy * bcy);
  if (n < 1e-6) return double.nan;
  final cos = ((bax * bcx + bay * bcy) / n).clamp(-1.0, 1.0);
  return acos(cos) * 180 / pi;
}

/// Angle between the hip-to-shoulder line and straight up. 0 = upright.
double lean(Pt shoulder, Pt hip) {
  final vx = shoulder.x - hip.x, vy = shoulder.y - hip.y;
  final n = sqrt(vx * vx + vy * vy);
  if (n < 1e-6) return double.nan;
  return acos((-vy / n).clamp(-1.0, 1.0)) * 180 / pi;
}

/// True when p is below the line through l1 and l2 (y grows downward).
/// Null when the line is nearly vertical.
bool? below(Pt p, Pt l1, Pt l2) {
  final dx = l2.x - l1.x;
  if (dx.abs() < verticalLinePx) return null;
  final yLine = l1.y + (l2.y - l1.y) * (p.x - l1.x) / dx;
  return p.y > yLine;
}

/// Signed hip sag: positive = hips below the shoulder-end line.
double hipSag(Pt shoulder, Pt hip, Pt end) {
  final isBelow = below(hip, shoulder, end);
  final angle = jointAngle(shoulder, hip, end);
  if (isBelow == null || angle.isNaN) return double.nan;
  final d = 180 - angle;
  return isBelow ? d : -d;
}

/// Head line deviation in degrees. Use [headDropping] for the direction.
double headDrop(Pt ear, Pt shoulder, Pt hip) =>
    180 - jointAngle(ear, shoulder, hip);

/// True when the ear is below the hip-to-shoulder line extended.
bool? headDropping(Pt ear, Pt shoulder, Pt hip) => below(ear, hip, shoulder);

/// Body length L: torso length in pixels.
double bodyLength(Pt shoulder, Pt hip) =>
    sqrt(pow(shoulder.x - hip.x, 2) + pow(shoulder.y - hip.y, 2));

/// How far p is in front of q, in body lengths.
double align(Pt p, Pt q, double bodyLen, int facing) =>
    facing * (p.x - q.x) / bodyLen;

/// Height above a baseline y, in body lengths (heel_lift, jump_rise,
/// back_knee_height).
double heightAbove(double baseY, double y, double bodyLen) =>
    (baseY - y) / bodyLen;

/// Median of a non-empty list.
double median(List<double> values) {
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}
