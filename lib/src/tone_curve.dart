import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';

/// Selects how values between tone-curve control points are calculated.
enum PsToneCurveInterpolation {
  /// Joins adjacent control points with straight segments.
  linear,

  /// Uses a natural cubic spline with zero endpoint curvature.
  naturalCubic,
}

/// One input-to-output control point in a Photoshop tone curve.
final class PsToneCurvePoint {
  /// Horizontal input coordinate as stored by Photoshop.
  final int input;

  /// Vertical output coordinate as stored by Photoshop.
  final int output;

  /// Creates one immutable control point.
  const PsToneCurvePoint({
    required this.input,
    required this.output,
  });

  /// Whether both coordinates use the conventional 0 through 255 range.
  bool get isInOfficialRange => input >= 0 && input <= 255 && output >= 0 && output <= 255;

  /// Input coordinate normalized to the conventional 0 through 1 range.
  double get normalizedInput => input / 255;

  /// Output coordinate normalized to the conventional 0 through 1 range.
  double get normalizedOutput => output / 255;

  @override
  bool operator ==(Object other) => other is PsToneCurvePoint && other.input == input && other.output == output;

  @override
  int get hashCode => Object.hash(input, output);

  @override
  String toString() => 'PsToneCurvePoint(input: $input, output: $output)';
}

/// An immutable Photoshop tone curve with evaluation helpers.
final class PsToneCurve {
  /// Ordered control points.
  final List<PsToneCurvePoint> points;

  /// Validated evaluator shared by every evaluation of this curve.
  ///
  /// Building it validates the point order and solves the spline once, so
  /// sampling a curve per pixel does not repeat that work.
  late final _PsToneCurveEvaluator _evaluator = _PsToneCurveEvaluator(points: points);

  /// Creates a tone curve from [points].
  PsToneCurve({
    required List<PsToneCurvePoint> points,
  }) : points = List<PsToneCurvePoint>.unmodifiable(points);

  /// Creates the conventional two-point identity curve.
  factory PsToneCurve.identity() => PsToneCurve(
    points: const <PsToneCurvePoint>[
      PsToneCurvePoint(input: 0, output: 0),
      PsToneCurvePoint(input: 255, output: 255),
    ],
  );

  /// Whether every control point maps its input to the same output.
  bool get isIdentity => points.isNotEmpty && points.every((point) => point.input == point.output);

  /// Whether input coordinates are strictly increasing in source order.
  bool get hasStrictlyIncreasingInputs {
    for (int index = 1; index < points.length; index++) {
      if (points[index].input <= points[index - 1].input) {
        return false;
      }
    }
    return true;
  }

  /// Evaluates a raw 0 through 255 [input] coordinate.
  double evaluate(
    double input, {
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
    bool clampOutput = true,
  }) {
    final double value = _evaluator.evaluate(input, interpolation);
    return clampOutput ? value.clamp(0, 255).toDouble() : value;
  }

  /// Evaluates an [input] normalized to the 0 through 1 range.
  double evaluateNormalized(
    double input, {
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
    bool clampOutput = true,
  }) =>
      evaluate(
        input * 255,
        interpolation: interpolation,
        clampOutput: clampOutput,
      ) /
      255;

  /// Builds an evenly sampled raw-coordinate lookup table.
  Float64List toLookupTable({
    int size = 256,
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
    bool clampOutput = true,
  }) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }
    final Float64List result = Float64List(size);
    for (int index = 0; index < size; index++) {
      final double input = size == 1 ? 0 : index * 255 / (size - 1);
      final double value = _evaluator.evaluate(input, interpolation);
      result[index] = clampOutput ? value.clamp(0, 255).toDouble() : value;
    }
    return result;
  }

  /// Builds an evenly sampled 8-bit lookup table.
  Uint8List toUint8LookupTable({
    int size = 256,
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
  }) {
    final Float64List values = toLookupTable(size: size, interpolation: interpolation);
    final Uint8List result = Uint8List(values.length);
    for (int index = 0; index < values.length; index++) {
      result[index] = values[index].round();
    }
    return result;
  }
}

/// Encodes and decodes count-prefixed Photoshop tone-curve point records.
abstract final class PsToneCurveCodec {
  /// Reads one curve record at the current [reader] position.
  static PsToneCurve read(
    PsBinaryReader reader, {
    int maxPoints = 0xffff,
  }) {
    final int count = reader.readUint16();
    return PsToneCurve(
      points: readPoints(reader, count: count, maxPoints: maxPoints),
    );
  }

  /// Reads [count] output/input point pairs from [reader].
  static List<PsToneCurvePoint> readPoints(
    PsBinaryReader reader, {
    required int count,
    int maxPoints = 0xffff,
  }) {
    if (count < 0 || count > maxPoints) {
      throw PsFormatException(
        message: 'Tone curve point count $count exceeds the configured $maxPoints limit',
        source: reader.bytes,
        offset: reader.baseOffset + reader.offset,
      );
    }
    return List<PsToneCurvePoint>.unmodifiable(<PsToneCurvePoint>[
      for (int index = 0; index < count; index++)
        PsToneCurvePoint(
          output: reader.readUint16(),
          input: reader.readUint16(),
        ),
    ]);
  }

  /// Encodes one curve record into a new byte buffer.
  static Uint8List encode(PsToneCurve curve) {
    final PsBinaryWriter writer = PsBinaryWriter();
    write(writer, curve);
    return writer.takeBytes();
  }

  /// Writes one count-prefixed curve record at the current [writer] position.
  static void write(PsBinaryWriter writer, PsToneCurve curve) {
    if (curve.points.length > 0xffff) {
      throw const PsWriteException(message: 'Tone curve point count exceeds the unsigned 16-bit capacity');
    }
    writer.writeUint16(curve.points.length);
    writePoints(writer, curve.points);
  }

  /// Writes output/input point pairs without a count prefix.
  static void writePoints(PsBinaryWriter writer, Iterable<PsToneCurvePoint> points) {
    for (final PsToneCurvePoint point in points) {
      if (point.input < 0 || point.input > 0xffff || point.output < 0 || point.output > 0xffff) {
        throw PsWriteException(
          message: 'Tone curve point (${point.input}, ${point.output}) does not fit unsigned 16-bit coordinates',
        );
      }
      writer
        ..writeUint16(point.output)
        ..writeUint16(point.input);
    }
  }
}

/// Efficiently evaluates one validated sequence of control points.
final class _PsToneCurveEvaluator {
  /// Control points in strictly increasing input order.
  final List<PsToneCurvePoint> _points;

  /// Natural-spline second derivatives, calculated only when needed.
  List<double>? _secondDerivatives;

  /// Creates an evaluator after checking that interpolation is well-defined.
  _PsToneCurveEvaluator({
    required List<PsToneCurvePoint> points,
  }) : _points = points {
    if (points.isEmpty) {
      throw StateError('An empty tone curve cannot be evaluated');
    }
    for (int index = 1; index < points.length; index++) {
      if (points[index].input <= points[index - 1].input) {
        throw StateError('Tone curve inputs must be strictly increasing before evaluation');
      }
    }
  }

  /// Evaluates [input] with the selected [interpolation].
  double evaluate(double input, PsToneCurveInterpolation interpolation) {
    if (_points.length == 1 || input <= _points.first.input) {
      return _points.first.output.toDouble();
    }
    if (input >= _points.last.input) {
      return _points.last.output.toDouble();
    }
    final int upperIndex = _findUpperIndex(input);
    final int lowerIndex = upperIndex - 1;
    return switch (interpolation) {
      PsToneCurveInterpolation.linear => _evaluateLinear(input, lowerIndex, upperIndex),
      PsToneCurveInterpolation.naturalCubic => _evaluateNaturalCubic(input, lowerIndex, upperIndex),
    };
  }

  /// Locates the first point whose input is greater than [input].
  int _findUpperIndex(double input) {
    int lower = 1;
    int upper = _points.length - 1;
    while (lower < upper) {
      final int middle = (lower + upper) ~/ 2;
      if (_points[middle].input > input) {
        upper = middle;
      } else {
        lower = middle + 1;
      }
    }
    return lower;
  }

  /// Linearly interpolates between the two surrounding point indices.
  double _evaluateLinear(double input, int lowerIndex, int upperIndex) {
    final PsToneCurvePoint lower = _points[lowerIndex];
    final PsToneCurvePoint upper = _points[upperIndex];
    final double ratio = (input - lower.input) / (upper.input - lower.input);
    return lower.output + ratio * (upper.output - lower.output);
  }

  /// Evaluates the natural cubic segment between two surrounding points.
  double _evaluateNaturalCubic(double input, int lowerIndex, int upperIndex) {
    final PsToneCurvePoint lower = _points[lowerIndex];
    final PsToneCurvePoint upper = _points[upperIndex];
    final double width = (upper.input - lower.input).toDouble();
    final double lowerWeight = (upper.input - input) / width;
    final double upperWeight = (input - lower.input) / width;
    final List<double> derivatives = _secondDerivatives ??= _calculateSecondDerivatives();
    return lowerWeight * lower.output +
        upperWeight * upper.output +
        ((lowerWeight * lowerWeight * lowerWeight - lowerWeight) * derivatives[lowerIndex] + (upperWeight * upperWeight * upperWeight - upperWeight) * derivatives[upperIndex]) * width * width / 6;
  }

  /// Calculates natural-spline second derivatives for every control point.
  List<double> _calculateSecondDerivatives() {
    final int count = _points.length;
    final List<double> derivatives = List<double>.filled(count, 0);
    if (count <= 2) {
      return derivatives;
    }
    final List<double> temporary = List<double>.filled(count - 1, 0);
    for (int index = 1; index < count - 1; index++) {
      final double previousWidth = (_points[index].input - _points[index - 1].input).toDouble();
      final double nextWidth = (_points[index + 1].input - _points[index].input).toDouble();
      final double totalWidth = previousWidth + nextWidth;
      final double ratio = previousWidth / totalWidth;
      final double denominator = ratio * derivatives[index - 1] + 2;
      derivatives[index] = (ratio - 1) / denominator;
      final double slopeDifference = (_points[index + 1].output - _points[index].output) / nextWidth - (_points[index].output - _points[index - 1].output) / previousWidth;
      temporary[index] = (6 * slopeDifference / totalWidth - ratio * temporary[index - 1]) / denominator;
    }
    for (int index = count - 2; index >= 0; index--) {
      derivatives[index] = derivatives[index] * derivatives[index + 1] + temporary[index];
    }
    return derivatives;
  }
}
