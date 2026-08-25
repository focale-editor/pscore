import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';

/// Boolean operation applied when Photoshop combines a subpath.
enum PsPathOperation {
  /// Excludes areas shared with the accumulated shape.
  exclude(code: 0),

  /// Adds the subpath to the accumulated shape.
  combine(code: 1),

  /// Removes the subpath from the accumulated shape.
  subtract(code: 2),

  /// Keeps only areas shared with the accumulated shape.
  intersect(code: 3);

  /// Signed integer stored in a subpath-length record.
  final int code;

  /// Creates an operation from its binary [code].
  const PsPathOperation({required this.code});

  /// Resolves [code], or returns `null` for an extension or no-operation marker.
  static PsPathOperation? fromCode(int code) => switch (code) {
    0 => exclude,
    1 => combine,
    2 => subtract,
    3 => intersect,
    _ => null,
  };
}

/// Fill rule inferred from Photoshop's subpath flags.
enum PsPathFillRule {
  /// Alternates between filled and unfilled areas at every crossed edge.
  evenOdd,

  /// Uses the signed winding count of crossed edges.
  nonZero;

  /// Resolves the convention used by known Photoshop vector-mask records.
  static PsPathFillRule fromFlags(int flags) => flags == 2 ? nonZero : evenOdd;
}

/// A two-dimensional point in Photoshop path coordinates.
final class PsPathPoint {
  /// Horizontal coordinate, normally relative to a reference width.
  final double x;

  /// Vertical coordinate, normally relative to a reference height.
  final double y;

  /// Creates a point from its horizontal and vertical components.
  const PsPathPoint({
    required this.x,
    required this.y,
  });

  /// Creates a normalized point from pixel coordinates and positive dimensions.
  factory PsPathPoint.fromPixels({
    required double x,
    required double y,
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Path reference dimensions must be positive');
    }
    return PsPathPoint(x: x / width, y: y / height);
  }

  /// Converts the horizontal component using [width].
  double pixelX(num width) => x * width;

  /// Converts the vertical component using [height].
  double pixelY(num height) => y * height;

  /// Applies an axis-aligned scale and translation to this point.
  PsPathPoint transform({
    double scaleX = 1,
    double scaleY = 1,
    double translateX = 0,
    double translateY = 0,
  }) => PsPathPoint(
    x: x * scaleX + translateX,
    y: y * scaleY + translateY,
  );
}

/// One cubic Bézier knot with incoming and outgoing control handles.
final class PsBezierKnot {
  /// Control handle for the segment entering [anchor].
  final PsPathPoint incoming;

  /// On-curve anchor point.
  final PsPathPoint anchor;

  /// Control handle for the segment leaving [anchor].
  final PsPathPoint outgoing;

  /// Whether Photoshop keeps both handles collinear while editing.
  final bool linked;

  /// Creates a cubic Bézier knot.
  const PsBezierKnot({
    required this.incoming,
    required this.anchor,
    required this.outgoing,
    this.linked = true,
  });

  /// Creates a corner whose handles coincide with [anchor].
  const PsBezierKnot.corner({required PsPathPoint anchor})
    : this(
        incoming: anchor,
        anchor: anchor,
        outgoing: anchor,
        linked: false,
      );

  /// Applies an axis-aligned scale and translation to all three points.
  PsBezierKnot transform({
    double scaleX = 1,
    double scaleY = 1,
    double translateX = 0,
    double translateY = 0,
  }) => PsBezierKnot(
    incoming: incoming.transform(
      scaleX: scaleX,
      scaleY: scaleY,
      translateX: translateX,
      translateY: translateY,
    ),
    anchor: anchor.transform(
      scaleX: scaleX,
      scaleY: scaleY,
      translateX: translateX,
      translateY: translateY,
    ),
    outgoing: outgoing.transform(
      scaleX: scaleX,
      scaleY: scaleY,
      translateX: translateX,
      translateY: translateY,
    ),
    linked: linked,
  );
}

/// One open or closed contour inside a Photoshop path.
final class PsSubpath {
  /// Whether the final knot connects back to the first knot.
  final bool closed;

  /// Signed Boolean-operation marker stored by Photoshop.
  ///
  /// The value `-1` denotes an unspecified operation in some custom-shape files.
  final int operation;

  /// Undocumented 16-bit flags following [operation].
  final int flags;

  /// Ordered Bézier knots.
  final List<PsBezierKnot> knots;

  /// Creates a semantic contour.
  const PsSubpath({
    required this.closed,
    required this.knots,
    this.operation = 1,
    this.flags = 0,
  });

  /// Recognized Boolean operation, or `null` when none is specified.
  PsPathOperation? get operationType => PsPathOperation.fromCode(operation);

  /// Fill rule inferred from [flags].
  PsPathFillRule get fillRule => PsPathFillRule.fromFlags(flags);

  /// Applies an axis-aligned scale and translation to every knot.
  PsSubpath transform({
    double scaleX = 1,
    double scaleY = 1,
    double translateX = 0,
    double translateY = 0,
  }) => PsSubpath(
    closed: closed,
    operation: operation,
    flags: flags,
    knots: <PsBezierKnot>[
      for (final PsBezierKnot knot in knots)
        knot.transform(
          scaleX: scaleX,
          scaleY: scaleY,
          translateX: translateX,
          translateY: translateY,
        ),
    ],
  );
}

/// Base type for one fixed-size Photoshop path record.
sealed class PsPathRecord {
  /// Creates a path-record base value.
  const PsPathRecord();

  /// Two-byte record selector.
  int get selector;
}

/// A record declaring the knot count and operation of a subpath.
final class PsSubpathLengthRecord extends PsPathRecord {
  /// Whether the declared subpath is closed.
  final bool closed;

  /// Number of knot records expected immediately after this record.
  final int knotCount;

  /// Signed Boolean-operation marker, including the `-1` unspecified value.
  final int operation;

  /// Remaining 20 payload bytes retained verbatim.
  ///
  /// The first two bytes are flags interpreted by [flags].
  final Uint8List trailingData;

  /// Creates a subpath-length record.
  PsSubpathLengthRecord({
    required this.closed,
    required this.knotCount,
    this.operation = 1,
    Uint8List? trailingData,
  }) : trailingData = Uint8List.fromList(trailingData ?? Uint8List(20)).asUnmodifiableView();

  /// Undocumented 16-bit flags stored after [operation].
  int get flags => trailingData.length < 2 ? 0 : ByteData.sublistView(trailingData).getUint16(0);

  /// Fill rule inferred from [flags].
  PsPathFillRule get fillRule => PsPathFillRule.fromFlags(flags);

  @override
  int get selector => closed ? 0 : 3;
}

/// A record containing one cubic Bézier knot.
final class PsBezierKnotRecord extends PsPathRecord {
  /// Whether the containing subpath is closed.
  final bool closed;

  /// Knot geometry and handle-linkage state.
  final PsBezierKnot knot;

  /// Creates a Bézier-knot record.
  const PsBezierKnotRecord({
    required this.closed,
    required this.knot,
  });

  @override
  int get selector => closed ? (knot.linked ? 1 : 2) : (knot.linked ? 4 : 5);
}

/// A path fill-rule record, whose defined payload is normally all zeroes.
final class PsPathFillRuleRecord extends PsPathRecord {
  /// First raw 16-bit value retained for compatibility with existing writers.
  final int rule;

  /// Remaining 22 bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates a fill-rule record.
  PsPathFillRuleRecord({
    this.rule = 0,
    Uint8List? trailingData,
  }) : trailingData = Uint8List.fromList(trailingData ?? Uint8List(22)).asUnmodifiableView();

  @override
  int get selector => 6;
}

/// A clipboard-bounds and resolution path record.
final class PsPathClipboardRecord extends PsPathRecord {
  /// Top clipboard edge in normalized coordinates.
  final double top;

  /// Left clipboard edge in normalized coordinates.
  final double left;

  /// Bottom clipboard edge in normalized coordinates.
  final double bottom;

  /// Right clipboard edge in normalized coordinates.
  final double right;

  /// Clipboard resolution.
  final double resolution;

  /// Remaining four bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates a clipboard path record.
  PsPathClipboardRecord({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
    required this.resolution,
    Uint8List? trailingData,
  }) : trailingData = Uint8List.fromList(trailingData ?? Uint8List(4)).asUnmodifiableView();

  @override
  int get selector => 7;
}

/// The initial fill state used before applying subpath operations.
final class PsPathInitialFillRecord extends PsPathRecord {
  /// Exact unsigned 16-bit initial-fill value.
  final int rawValue;

  /// Remaining 22 bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates an initial-fill record.
  PsPathInitialFillRecord({
    bool startsWithAllPixels = false,
    int? rawValue,
    Uint8List? trailingData,
  }) : rawValue = rawValue ?? (startsWithAllPixels ? 1 : 0),
       trailingData = Uint8List.fromList(trailingData ?? Uint8List(22)).asUnmodifiableView();

  /// Whether a nonzero source value requests an initially filled canvas.
  bool get startsWithAllPixels => rawValue != 0;

  @override
  int get selector => 8;
}

/// An unrecognized 26-byte Photoshop path record.
final class PsUnknownPathRecord extends PsPathRecord {
  /// Unknown selector value.
  @override
  final int selector;

  /// Exact 24-byte record payload.
  final Uint8List data;

  /// Creates an opaque path record.
  PsUnknownPathRecord({
    required this.selector,
    required Uint8List data,
  }) : data = Uint8List.fromList(data).asUnmodifiableView();
}

/// An ordered Photoshop path retaining every fixed-size source record.
final class PsVectorPath {
  /// Path records in file order.
  final List<PsPathRecord> records;

  /// Creates a path from exact Photoshop records.
  PsVectorPath({required List<PsPathRecord> records}) : records = List<PsPathRecord>.unmodifiable(records);

  /// Creates a path from application-friendly [subpaths].
  factory PsVectorPath.fromSubpaths({
    required List<PsSubpath> subpaths,
    int fillRule = 0,
    bool startsWithAllPixels = false,
  }) => PsVectorPath(
    records: <PsPathRecord>[
      PsPathFillRuleRecord(rule: fillRule),
      PsPathInitialFillRecord(startsWithAllPixels: startsWithAllPixels),
      ..._recordsFromSubpaths(subpaths),
    ],
  );

  /// Reconstructs semantic contours from adjacent length and knot records.
  List<PsSubpath> get subpaths {
    final List<PsSubpath> result = <PsSubpath>[];
    for (int index = 0; index < records.length; index++) {
      final PsPathRecord record = records[index];
      if (record is! PsSubpathLengthRecord) {
        continue;
      }
      final List<PsBezierKnot> knots = <PsBezierKnot>[];
      for (int knotIndex = 0; knotIndex < record.knotCount && index + 1 < records.length; knotIndex++) {
        final PsPathRecord knotRecord = records[++index];
        if (knotRecord is! PsBezierKnotRecord) {
          index--;
          break;
        }
        knots.add(knotRecord.knot);
      }
      result.add(
        PsSubpath(
          closed: record.closed,
          operation: record.operation,
          flags: record.flags,
          knots: List<PsBezierKnot>.unmodifiable(knots),
        ),
      );
    }
    return List<PsSubpath>.unmodifiable(result);
  }

  /// Initial fill state, or `false` when no record is present.
  bool get startsWithAllPixels {
    for (final PsPathRecord record in records.reversed) {
      if (record is PsPathInitialFillRecord) {
        return record.startsWithAllPixels;
      }
    }
    return false;
  }

  /// Returns a copy with new geometry while preserving ancillary records.
  PsVectorPath withSubpaths(List<PsSubpath> subpaths) => PsVectorPath(
    records: <PsPathRecord>[
      for (final PsPathRecord record in records)
        if (record is! PsSubpathLengthRecord && record is! PsBezierKnotRecord) record,
      ..._recordsFromSubpaths(subpaths),
    ],
  );
}

/// Encodes and decodes streams of 26-byte Photoshop path records.
abstract final class PsVectorPathCodec {
  /// Fixed byte length of one record, including its selector.
  static const int recordByteLength = 26;

  /// Decodes [bytes], returning `null` for malformed or excessive data.
  static PsVectorPath? tryDecode(
    Uint8List bytes, {
    int maxRecords = 1000000,
  }) {
    try {
      return decode(bytes, maxRecords: maxRecords);
    } on FormatException {
      return null;
    }
  }

  /// Decodes a complete stream of fixed-size path records.
  static PsVectorPath decode(
    Uint8List bytes, {
    int maxRecords = 1000000,
  }) {
    if (maxRecords < 0) {
      throw ArgumentError.value(maxRecords, 'maxRecords', 'must not be negative');
    }
    if (bytes.length % recordByteLength != 0) {
      throw PsFormatException(
        message: 'Photoshop path data must contain complete $recordByteLength-byte records',
        source: bytes,
        offset: bytes.length - bytes.length % recordByteLength,
      );
    }
    final int recordCount = bytes.length ~/ recordByteLength;
    if (recordCount > maxRecords) {
      throw PsFormatException(
        message: 'Photoshop path record count $recordCount exceeds the configured $maxRecords limit',
        source: bytes,
        offset: 0,
      );
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final List<PsPathRecord> records = <PsPathRecord>[];
    while (!reader.isAtEnd) {
      final int selector = reader.readUint16();
      final PsBinaryReader payload = reader.readReader(24);
      records.add(_readPathRecord(selector, payload));
    }
    return PsVectorPath(records: records);
  }

  /// Encodes [path] as fixed-size Photoshop path records.
  static Uint8List encode(PsVectorPath path) {
    final PsBinaryWriter writer = PsBinaryWriter();
    for (final PsPathRecord record in path.records) {
      writer.writeUint16(record.selector);
      _writePathRecord(writer, record);
    }
    return writer.takeBytes();
  }
}

/// Converts semantic [subpaths] into exact length and knot records.
List<PsPathRecord> _recordsFromSubpaths(List<PsSubpath> subpaths) {
  final List<PsPathRecord> records = <PsPathRecord>[];
  for (final PsSubpath subpath in subpaths) {
    final Uint8List trailingData = Uint8List(20);
    ByteData.sublistView(trailingData).setUint16(0, subpath.flags);
    records.add(
      PsSubpathLengthRecord(
        closed: subpath.closed,
        knotCount: subpath.knots.length,
        operation: subpath.operation,
        trailingData: trailingData,
      ),
    );
    for (final PsBezierKnot knot in subpath.knots) {
      records.add(PsBezierKnotRecord(closed: subpath.closed, knot: knot));
    }
  }
  return records;
}

/// Decodes one path record with [selector].
PsPathRecord _readPathRecord(int selector, PsBinaryReader reader) => switch (selector) {
  0 || 3 => PsSubpathLengthRecord(
    closed: selector == 0,
    knotCount: reader.readUint16(),
    operation: reader.readInt16(),
    trailingData: reader.readBytes(20),
  ),
  1 || 2 || 4 || 5 => PsBezierKnotRecord(
    closed: selector == 1 || selector == 2,
    knot: PsBezierKnot(
      incoming: _readPathPoint(reader),
      anchor: _readPathPoint(reader),
      outgoing: _readPathPoint(reader),
      linked: selector == 1 || selector == 4,
    ),
  ),
  6 => PsPathFillRuleRecord(
    rule: reader.readUint16(),
    trailingData: reader.readBytes(22),
  ),
  7 => PsPathClipboardRecord(
    top: _readPathFixed(reader),
    left: _readPathFixed(reader),
    bottom: _readPathFixed(reader),
    right: _readPathFixed(reader),
    resolution: _readPathFixed(reader),
    trailingData: reader.readBytes(4),
  ),
  8 => PsPathInitialFillRecord(
    rawValue: reader.readUint16(),
    trailingData: reader.readBytes(22),
  ),
  _ => PsUnknownPathRecord(selector: selector, data: reader.readBytes(24)),
};

/// Encodes one fixed-size path [record].
void _writePathRecord(PsBinaryWriter writer, PsPathRecord record) {
  switch (record) {
    case PsSubpathLengthRecord():
      _requireLength(record.trailingData, 20, 'subpath-length trailing data');
      writer
        ..writeUint16(record.knotCount)
        ..writeInt16(record.operation)
        ..writeBytes(record.trailingData);
    case PsBezierKnotRecord():
      _writePathPoint(writer, record.knot.incoming);
      _writePathPoint(writer, record.knot.anchor);
      _writePathPoint(writer, record.knot.outgoing);
    case PsPathFillRuleRecord():
      _requireLength(record.trailingData, 22, 'fill-rule trailing data');
      writer
        ..writeUint16(record.rule)
        ..writeBytes(record.trailingData);
    case PsPathClipboardRecord():
      _requireLength(record.trailingData, 4, 'clipboard trailing data');
      _writePathFixed(writer, record.top);
      _writePathFixed(writer, record.left);
      _writePathFixed(writer, record.bottom);
      _writePathFixed(writer, record.right);
      _writePathFixed(writer, record.resolution);
      writer.writeBytes(record.trailingData);
    case PsPathInitialFillRecord():
      _requireLength(record.trailingData, 22, 'initial-fill trailing data');
      writer
        ..writeUint16(record.rawValue)
        ..writeBytes(record.trailingData);
    case PsUnknownPathRecord():
      _requireLength(record.data, 24, 'unknown path record');
      writer.writeBytes(record.data);
  }
}

/// Reads one point stored in vertical-then-horizontal order.
PsPathPoint _readPathPoint(PsBinaryReader reader) {
  final double y = _readPathFixed(reader);
  final double x = _readPathFixed(reader);
  return PsPathPoint(x: x, y: y);
}

/// Writes one point in vertical-then-horizontal order.
void _writePathPoint(PsBinaryWriter writer, PsPathPoint point) {
  _writePathFixed(writer, point.y);
  _writePathFixed(writer, point.x);
}

/// Reads a signed 8.24 fixed-point path coordinate.
double _readPathFixed(PsBinaryReader reader) => reader.readInt32() / 16777216;

/// Writes [value] as a signed 8.24 fixed-point coordinate.
void _writePathFixed(PsBinaryWriter writer, double value) {
  final double scaled = value * 16777216;
  if (!scaled.isFinite || scaled < -2147483648 || scaled > 2147483647) {
    throw PsWriteException(message: 'Path coordinate $value does not fit signed 8.24 fixed point');
  }
  writer.writeInt32(scaled.round());
}

/// Requires [bytes] to have the fixed [length] expected by a record.
void _requireLength(Uint8List bytes, int length, String label) {
  if (bytes.length != length) {
    throw PsWriteException(message: '$label must contain exactly $length bytes');
  }
}
