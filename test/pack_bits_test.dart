import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises PackBits encoding and decoding.
void main() {
  group('PsPackBitsCodec', () {
    test('round-trips literal and repeated runs', () {
      final Uint8List source = Uint8List.fromList(<int>[
        1,
        2,
        3,
        ...List<int>.filled(128, 9),
        4,
        5,
        ...List<int>.filled(3, 7),
      ]);

      final Uint8List encoded = PsPackBitsCodec.encodeRow(source);
      final Uint8List decoded = PsPackBitsCodec.decodeRow(encoded, decodedLength: source.length);

      expect(decoded, orderedEquals(source));
    });

    test('bounds the output buffer for incompressible rows', () {
      // Rows where no byte repeats produce the worst case: one control byte
      // per 128 literal bytes. An undersized bound would fail here instead of
      // in a caller that preallocates from it.
      for (final int rowBytes in <int>[0, 1, 2, 127, 128, 129, 255, 256, 257, 4096]) {
        final Uint8List row = Uint8List.fromList(<int>[
          for (int index = 0; index < rowBytes; index++) (index * 7 + index ~/ 128) & 0xff,
        ]);

        final Uint8List encoded = PsPackBitsCodec.encodeRow(row);

        expect(encoded.length, lessThanOrEqualTo(PsPackBitsCodec.maxEncodedLength(rowBytes)), reason: 'row of $rowBytes bytes');
        expect(PsPackBitsCodec.decodeRow(encoded, decodedLength: rowBytes), orderedEquals(row), reason: 'row of $rowBytes bytes');
      }
    });

    test('encodes into a caller-owned buffer at an offset', () {
      final Uint8List first = Uint8List.fromList(<int>[1, 1, 1, 1, 2, 3]);
      final Uint8List second = Uint8List.fromList(<int>[4, 5, 5, 5, 5, 6]);
      final Uint8List buffer = Uint8List(PsPackBitsCodec.maxEncodedLength(first.length) + PsPackBitsCodec.maxEncodedLength(second.length));

      final int afterFirst = PsPackBitsCodec.encodeRowInto(first, buffer, 0);
      final int afterSecond = PsPackBitsCodec.encodeRowInto(second, buffer, afterFirst);

      expect(Uint8List.sublistView(buffer, 0, afterFirst), orderedEquals(PsPackBitsCodec.encodeRow(first)));
      expect(Uint8List.sublistView(buffer, afterFirst, afterSecond), orderedEquals(PsPackBitsCodec.encodeRow(second)));
      expect(PsPackBitsCodec.decodeRow(Uint8List.sublistView(buffer, afterFirst, afterSecond), decodedLength: second.length), orderedEquals(second));
    });

    test('accepts the PackBits no-op marker', () {
      final Uint8List decoded = PsPackBitsCodec.decodeRow(
        Uint8List.fromList(<int>[128, 0, 42]),
        decodedLength: 1,
      );

      expect(decoded, orderedEquals(<int>[42]));
    });

    test('rejects a row with the wrong decoded size', () {
      expect(
        () => PsPackBitsCodec.decodeRow(Uint8List.fromList(<int>[0, 1]), decodedLength: 2),
        throwsA(isA<PsFormatException>()),
      );
    });

    test('round-trips table-prefixed rows with narrow and wide lengths', () {
      final Uint8List source = Uint8List.fromList(<int>[
        1,
        1,
        1,
        2,
        3,
        4,
        5,
        5,
        5,
        6,
        7,
        8,
      ]);

      for (final bool wide in <bool>[false, true]) {
        final Uint8List encoded = PsPackBitsCodec.encodeRows(
          source,
          rowBytes: 4,
          rowCount: 3,
          wideRowLengths: wide,
        );

        expect(
          PsPackBitsCodec.decodeRows(
            encoded,
            rowBytes: 4,
            rowCount: 3,
            wideRowLengths: wide,
          ),
          orderedEquals(source),
        );
      }
    });

    test('reports consumed bytes when rows are followed by another payload', () {
      final Uint8List source = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final Uint8List encoded = PsPackBitsCodec.encodeRows(
        source,
        rowBytes: 2,
        rowCount: 2,
      );
      final Uint8List withTrailing = Uint8List.fromList(<int>[...encoded, 9, 8]);

      final ({Uint8List data, int bytesRead}) decoded = PsPackBitsCodec.decodeRowsPrefix(
        withTrailing,
        rowBytes: 2,
        rowCount: 2,
      );

      expect(decoded.data, orderedEquals(source));
      expect(decoded.bytesRead, encoded.length);
      expect(
        () => PsPackBitsCodec.decodeRows(
          withTrailing,
          rowBytes: 2,
          rowCount: 2,
        ),
        throwsA(isA<PsFormatException>()),
      );
    });

    test('rejects mismatched row input lengths', () {
      expect(
        () => PsPackBitsCodec.encodeRows(
          Uint8List.fromList(<int>[1, 2, 3]),
          rowBytes: 2,
          rowCount: 2,
        ),
        throwsA(isA<PsWriteException>()),
      );
    });

    test('reports invalid row geometry in the relevant codec domain', () {
      expect(
        () => PsPackBitsCodec.decodeRows(
          Uint8List(0),
          rowBytes: -1,
          rowCount: 0,
        ),
        throwsA(isA<PsFormatException>()),
      );
      expect(
        () => PsPackBitsCodec.encodeRows(
          Uint8List(0),
          rowBytes: -1,
          rowCount: 0,
        ),
        throwsA(isA<PsWriteException>()),
      );
    });
  });
}
