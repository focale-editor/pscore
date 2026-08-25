import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises shared Photoshop vector-path models and binary records.
void main() {
  test('round-trips signed operations, flags, raw values, and unknown records', () {
    final Uint8List lengthTrailing = Uint8List(20);
    ByteData.sublistView(lengthTrailing).setUint16(0, 2);
    final PsVectorPath source = PsVectorPath(
      records: <PsPathRecord>[
        PsPathFillRuleRecord(),
        PsPathInitialFillRecord(rawValue: 2),
        PsSubpathLengthRecord(
          closed: false,
          knotCount: 1,
          operation: -1,
          trailingData: lengthTrailing,
        ),
        const PsBezierKnotRecord(
          closed: false,
          knot: PsBezierKnot(
            incoming: PsPathPoint(x: -0.25, y: 0.5),
            anchor: PsPathPoint(x: 0.5, y: 0.75),
            outgoing: PsPathPoint(x: 1.25, y: 0.5),
            linked: false,
          ),
        ),
        PsUnknownPathRecord(
          selector: 42,
          data: Uint8List.fromList(List<int>.generate(24, (index) => index)),
        ),
      ],
    );

    final Uint8List encoded = PsVectorPathCodec.encode(source);
    final PsVectorPath decoded = PsVectorPathCodec.decode(encoded);
    final PsSubpath subpath = decoded.subpaths.single;

    check(PsVectorPathCodec.encode(decoded)).deepEquals(encoded);
    check(subpath.operation).equals(-1);
    check(subpath.operationType).isNull();
    check(subpath.flags).equals(2);
    check(subpath.fillRule).equals(PsPathFillRule.nonZero);
    check(subpath.knots.single.outgoing.x).equals(1.25);
    check((decoded.records[1] as PsPathInitialFillRecord).rawValue).equals(2);
    check(decoded.startsWithAllPixels).isTrue();
    check((decoded.records.last as PsUnknownPathRecord).selector).equals(42);
  });

  test('creates and transforms semantic subpaths', () {
    final PsVectorPath path = PsVectorPath.fromSubpaths(
      subpaths: const <PsSubpath>[
        PsSubpath(
          closed: true,
          operation: 2,
          flags: 1,
          knots: <PsBezierKnot>[
            PsBezierKnot.corner(anchor: PsPathPoint(x: 0.25, y: 0.5)),
          ],
        ),
      ],
    );

    final PsSubpath transformed = path.subpaths.single.transform(
      scaleX: 200,
      scaleY: 100,
      translateX: 10,
      translateY: 20,
    );

    check(transformed.operationType).equals(PsPathOperation.subtract);
    check(transformed.flags).equals(1);
    check(transformed.knots.single.anchor.x).equals(60);
    check(transformed.knots.single.anchor.y).equals(70);
    check(PsVectorPathCodec.decode(PsVectorPathCodec.encode(path)).subpaths.single.flags).equals(1);
  });

  test('rejects partial and excessive record streams', () {
    final Uint8List oneRecord = PsVectorPathCodec.encode(
      PsVectorPath(records: <PsPathRecord>[PsPathFillRuleRecord()]),
    );

    check(() => PsVectorPathCodec.decode(Uint8List(25))).throws<PsFormatException>();
    check(() => PsVectorPathCodec.decode(oneRecord, maxRecords: 0)).throws<PsFormatException>();
    check(PsVectorPathCodec.tryDecode(Uint8List(1))).isNull();
  });
}
