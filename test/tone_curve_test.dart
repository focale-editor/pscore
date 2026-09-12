import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises shared Photoshop tone-curve semantics and binary records.
void main() {
  group('PsToneCurve', () {
    test('evaluates linear and natural-cubic interpolation', () {
      final PsToneCurve identity = PsToneCurve.identity();
      final PsToneCurve hill = PsToneCurve(
        points: const <PsToneCurvePoint>[
          PsToneCurvePoint(input: 0, output: 0),
          PsToneCurvePoint(input: 128, output: 255),
          PsToneCurvePoint(input: 255, output: 0),
        ],
      );

      check(identity.evaluateNormalized(0.25)).isCloseTo(0.25, 0.000001);
      check(hill.evaluate(64, interpolation: PsToneCurveInterpolation.linear)).isCloseTo(127.5, 0.000001);
      check(hill.evaluate(64)).isGreaterThan(127.5);
      check(identity.toUint8LookupTable(size: 3)).deepEquals(<int>[0, 128, 255]);
    });

    test('rejects unordered points during evaluation', () {
      final PsToneCurve curve = PsToneCurve(
        points: const <PsToneCurvePoint>[
          PsToneCurvePoint(input: 100, output: 0),
          PsToneCurvePoint(input: 50, output: 255),
        ],
      );

      check(() => curve.evaluate(75)).throws<StateError>();
    });
  });

  group('PsToneCurveCodec', () {
    test('round-trips count-prefixed output/input pairs', () {
      final PsToneCurve source = PsToneCurve(
        points: const <PsToneCurvePoint>[
          PsToneCurvePoint(input: 0, output: 10),
          PsToneCurvePoint(input: 128, output: 192),
          PsToneCurvePoint(input: 255, output: 250),
        ],
      );

      final Uint8List encoded = PsToneCurveCodec.encode(source);
      final PsToneCurve decoded = PsToneCurveCodec.read(
        PsBinaryReader(bytes: encoded),
      );

      check(decoded.points).deepEquals(source.points);
      check(encoded).deepEquals(<int>[0, 3, 0, 10, 0, 0, 0, 192, 0, 128, 0, 250, 0, 255]);
    });

    test('enforces configured point limits', () {
      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeUint16(2)
        ..writeUint16(0)
        ..writeUint16(0)
        ..writeUint16(255)
        ..writeUint16(255);

      check(
        () => PsToneCurveCodec.read(
          PsBinaryReader(bytes: writer.takeBytes()),
          maxPoints: 1,
        ),
      ).throws<PsFormatException>();
    });
  });
}
