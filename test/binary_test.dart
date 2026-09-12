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

    test('round-trips the whole exactly representable 64-bit range', () {
      // The web has no 64-bit integers, so its range is narrower. Driving the
      // expectations from the advertised bounds keeps this test honest on both.
      final List<int> values = <int>[0, 1, -1, 0xffffffff, -0x100000000, psMaxExactInteger, psMinExactInteger];
      final PsBinaryWriter writer = PsBinaryWriter();
      values.forEach(writer.writeInt64);

      final PsBinaryReader reader = PsBinaryReader(bytes: writer.takeBytes());
      final List<int> decoded = <int>[for (int index = 0; index < values.length; index++) reader.readInt64()];

      check(decoded).deepEquals(values);
      check(reader.isAtEnd).isTrue();
    });

    test('stores a negative 64-bit value in two-s complement order', () {
      const List<int> allOnes = <int>[255, 255, 255, 255, 255, 255, 255, 255];

      check((PsBinaryWriter()..writeInt64(-1)).takeBytes()).deepEquals(allOnes);
      // The unsigned accessor stores the low 64 bits, as `ByteData` does.
      check((PsBinaryWriter()..writeUint64(-1)).takeBytes()).deepEquals(allOnes);
      check(PsBinaryReader(bytes: Uint8List.fromList(allOnes)).readInt64()).equals(-1);
    });

    test('reports a stored 64-bit value the platform cannot hold exactly', () {
      // Two to the power of 54, which is beyond the web's exact integer range
      // but an ordinary value where 64-bit integers are native.
      final Uint8List bytes = Uint8List(8)..[1] = 0x40;
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);

      if (psMaxExactInteger > 0x1fffffffffffff) {
        check(reader.readInt64()).equals(0x40000000000000);
      } else {
        check(reader.readInt64).throws<PsFormatException>();
      }
    });

    test('refuses to write a 64-bit value the platform cannot hold exactly', () {
      if (psMaxExactInteger > 0x1fffffffffffff) {
        // Nothing fits a 64-bit field without fitting a native 64-bit integer.
        return;
      }
      final PsBinaryWriter writer = PsBinaryWriter();

      check(() => writer.writeInt64(psMaxExactInteger + 2)).throws<PsWriteException>();
      check(() => writer.writeUint64(psMaxExactInteger + 2)).throws<PsWriteException>();
    });
  });
}
