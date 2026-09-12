import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises shared Photoshop tagged-block framing.
void main() {
  test('reads ordinary and wide tagged-block headers', () {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString('8BIM')
      ..writeString('test')
      ..writeUint32(3)
      ..writeBytes(<int>[1, 2, 3])
      ..writeUint8(0)
      ..writeString('8B64')
      ..writeString('wide')
      ..writeUint64(1)
      ..writeUint8(4)
      ..writeZeros(3);
    final PsBinaryReader reader = PsBinaryReader(bytes: writer.takeBytes());

    final PsTaggedBlockHeader first = PsTaggedBlockCodec.readHeader(reader);
    check(first.key).equals('test');
    check(first.declaredLength).equals(3);
    reader.skip(first.declaredLength);
    check(PsTaggedBlockCodec.paddingLength(reader, payloadLength: first.declaredLength)).equals(1);
    reader.skip(1);

    final PsTaggedBlockHeader second = PsTaggedBlockCodec.readHeader(reader);
    check(second.usesWideLength).equals(true);
    check(second.payloadOffset).equals(second.offset + 16);
  });

  test('writes canonical or preserved length and padding', () {
    final PsTaggedBlock block = PsTaggedBlock(
      signature: '8BIM',
      key: 'test',
      declaredLength: 9,
      data: Uint8List.fromList(<int>[1, 2, 3]),
      paddingData: Uint8List.fromList(<int>[7, 8]),
    );

    final Uint8List canonical = PsTaggedBlockCodec.encode(block);
    final PsBinaryReader canonicalReader = PsBinaryReader(bytes: canonical)..skip(8);
    check(canonicalReader.readUint32()).equals(3);
    check(canonical.length).equals(16);

    final Uint8List preserved = PsTaggedBlockCodec.encode(
      block,
      preserveDeclaredLength: true,
      preservePadding: true,
    );
    final PsBinaryReader preservedReader = PsBinaryReader(bytes: preserved)..skip(8);
    check(preservedReader.readUint32()).equals(9);
    check(preserved.sublist(preserved.length - 2)).deepEquals(<int>[7, 8]);
  });
}
