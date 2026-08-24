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
  });
}
