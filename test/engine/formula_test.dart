// Checks the Dart formulas against test/fixtures/formula_cases.json,
// the same cases Member C's pytest uses.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:jianfit/engine/geometry.dart';
import 'package:jianfit/engine/smoothing.dart';

Pt _p(dynamic v) => Pt((v[0] as num).toDouble(), (v[1] as num).toDouble());
double _d(dynamic v) => (v as num).toDouble();

void main() {
  final cases = jsonDecode(
    File('test/fixtures/formula_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  const tol = 0.01;

  test('joint_angle', () {
    for (final c in cases['joint_angle'] as List) {
      final r = jointAngle(_p(c['a']), _p(c['b']), _p(c['c']));
      if (c['expected'] == 'nan') {
        expect(r.isNaN, isTrue);
      } else {
        expect(r, closeTo(_d(c['expected']), tol));
      }
    }
  });

  test('lean', () {
    for (final c in cases['lean'] as List) {
      expect(
        lean(_p(c['shoulder']), _p(c['hip'])),
        closeTo(_d(c['expected']), tol),
      );
    }
  });

  test('hip_sag', () {
    for (final c in cases['hip_sag'] as List) {
      expect(
        hipSag(_p(c['shoulder']), _p(c['hip']), _p(c['end'])),
        closeTo(_d(c['expected']), tol),
      );
    }
  });

  test('head_drop', () {
    for (final c in cases['head_drop'] as List) {
      final ear = _p(c['ear']),
          shoulder = _p(c['shoulder']),
          hip = _p(c['hip']);
      expect(headDrop(ear, shoulder, hip), closeTo(_d(c['expected']), tol));
      expect(headDropping(ear, shoulder, hip), c['dropping']);
    }
  });

  test('align', () {
    for (final c in cases['align'] as List) {
      final len = bodyLength(_p(c['shoulder']), _p(c['hip']));
      expect(
        align(_p(c['p']), _p(c['q']), len, c['facing'] as int),
        closeTo(_d(c['expected']), tol),
      );
    }
  });

  test('heel_lift', () {
    for (final c in cases['heel_lift'] as List) {
      expect(
        heightAbove(_d(c['base_heel_y']), _d(c['heel_y']), _d(c['L'])),
        closeTo(_d(c['expected']), tol),
      );
    }
  });

  test('smoothing', () {
    for (final c in cases['smoothing'] as List) {
      final m = MovingAverage(c['n'] as int);
      final out = [for (final v in c['inputs'] as List) m.add(_d(v))];
      final expected = c['expected'] as List;
      for (var i = 0; i < out.length; i++) {
        expect(out[i], closeTo(_d(expected[i]), tol));
      }
    }
  });
}
