import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises shared binary reading and writing primitives.
void main() {
  group('PsBinaryReader and PsBinaryWriter', () {
    test('round-trip big-endian numeric and string primitives', () {
      final Uint8List bytes =
          (PsBinaryWriter()
                ..writeUint8(255)
                ..writeInt16(-123)
                ..writeUint32(0xfedcba98)
                ..writeInt64(-0x123456789)
                ..writeFloat32(1.5)
                ..writeFloat64(-2.25)
                ..writeString('8BIM'))
              .takeBytes();

      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);

      check(reader.readUint8()).equals(255);
      check(reader.readInt16()).equals(-123);
      check(reader.readUint32()).equals(0xfedcba98);
      check(reader.readInt64()).equals(-0x123456789);
      check(reader.readFloat32()).equals(1.5);
      check(reader.readFloat64()).equals(-2.25);
      check(reader.readString(4)).equals('8BIM');
      check(reader.isAtEnd).isTrue();
    });

    test('preserves absolute offsets for bounded child readers', () {
      final PsBinaryReader reader = PsBinaryReader(bytes: Uint8List.fromList(<int>[0, 1, 2, 3]), baseOffset: 100)..skip(1);

      final PsBinaryReader child = reader.readReader(2);

      check(child.baseOffset).equals(101);
      check(child.readBytes(2)).deepEquals(<int>[1, 2]);
      check(reader.offset).equals(3);
    });

    test('rejects reads beyond a bounded buffer', () {
      final PsBinaryReader reader = PsBinaryReader(bytes: Uint8List(1));

      check(reader.readUint16).throws<PsFormatException>();
    });
  });
}
