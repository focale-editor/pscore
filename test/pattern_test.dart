import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises the pattern record model, binary decoder, and RGBA renderer.
void main() {
  group('PsPatternRecordDecoder', () {
    test('decodes an embedded RGB pattern with PackBits and sheet alpha', () {
      final Uint8List record = _record(
        mode: PsPatternColorMode.rgb,
        channels: <_TestChannel>[
          const _TestChannel(depth: 8, bytes: <int>[255, 0], packBits: true),
          const _TestChannel(depth: 8, bytes: <int>[0, 255], packBits: true),
          const _TestChannel(depth: 8, bytes: <int>[0, 0], packBits: true),
        ],
        alpha: const _TestChannel(depth: 8, bytes: <int>[255, 64], packBits: true),
      );
      final PsBinaryWriter block = PsBinaryWriter()
        ..writeUint32(record.length)
        ..writeBytes(record)
        ..writeZeros((4 - record.length % 4) % 4);

      final PsPatternBlockDecodeResult decoded = PsPatternBlockDecoder.decodeAll(
        reader: PsBinaryReader(bytes: block.takeBytes()),
        maxPatterns: 1,
      );
      final PsPattern pattern = decoded.patterns.single;
      final PsPatternImage image = pattern.renderRgba8();

      expect(pattern.name, 'Shared pattern');
      expect(pattern.channels, hasLength(4));
      expect(decoded.decodedBytes, 8);
      expect(image.rgba, orderedEquals(<int>[255, 0, 0, 255, 0, 255, 0, 64]));
    });

    test('interprets an indexed PAT transparent-index footer', () {
      final Uint8List palette = Uint8List(256 * 3)..setRange(0, 6, <int>[255, 0, 0, 0, 0, 255]);
      final Uint8List record = _record(
        mode: PsPatternColorMode.indexed,
        channels: <_TestChannel>[
          const _TestChannel(depth: 8, bytes: <int>[0, 1]),
        ],
        palette: palette,
        colorsUsed: 2,
        transparentIndex: 1,
      );

      final PsPatternDecodeResult decoded = PsPatternRecordDecoder.decode(
        reader: PsBinaryReader(bytes: record),
        kind: PsPatternRecordKind.standalone,
      );
      final PsPatternImage image = decoded.pattern.renderRgba8();

      expect(decoded.pattern.indexedMetadata?.colorsUsed, 2);
      expect(decoded.pattern.indexedMetadata?.transparentIndex, 1);
      expect(image.rgba, orderedEquals(<int>[255, 0, 0, 255, 0, 0, 255, 0]));
    });

    test('retains full-precision one, sixteen, and float samples', () {
      final PsPatternChannel bitmap = _channel(depth: 1, bytes: <int>[0x80], width: 2);
      final PsPatternChannel deep = _channel(depth: 16, bytes: <int>[0x40, 0x00], width: 1);
      final ByteData floatData = ByteData(4)..setFloat32(0, 0.25);
      final PsPatternChannel floating = _channel(depth: 32, bytes: floatData.buffer.asUint8List(), width: 1);

      expect(bitmap.sampleAt(x: 0, y: 0), 1);
      expect(bitmap.sampleAt(x: 1, y: 0), 0);
      expect(deep.sampleAt(x: 0, y: 0), 16384);
      expect(deep.byteSampleAt(x: 0, y: 0), 128);
      expect(floating.normalizedSampleAt(x: 0, y: 0), closeTo(0.25, 0.000001));
    });

    test('uses caller CMYK conversion and renders Lab neutrals', () {
      final PsPattern cmyk = _decodedPattern(
        mode: PsPatternColorMode.cmyk,
        values: <int>[255, 128, 0, 255],
      );
      final PsPattern lab = _decodedPattern(
        mode: PsPatternColorMode.lab,
        values: <int>[128, 128, 128],
      );
      double? convertedCyan;

      final PsPatternImage cmykImage = cmyk.renderRgba8(
        cmykConverter: ({required cyan, required magenta, required yellow, required black}) {
          convertedCyan = cyan;
          return const PsRgbColor(red: 1, green: 2, blue: 3);
        },
      );
      final PsPatternImage labImage = lab.renderRgba8();

      expect(convertedCyan, 0);
      expect(cmykImage.rgba, orderedEquals(<int>[1, 2, 3, 255]));
      expect((labImage.rgba[0] - labImage.rgba[1]).abs(), lessThanOrEqualTo(2));
      expect((labImage.rgba[1] - labImage.rgba[2]).abs(), lessThanOrEqualTo(2));
    });

    test('preserves unsupported compression without losing the record', () {
      final Uint8List record = _record(
        mode: PsPatternColorMode.grayscale,
        channels: <_TestChannel>[
          const _TestChannel(depth: 8, bytes: <int>[10, 20], compressionCode: 7),
        ],
      );
      final List<String> issues = <String>[];

      final PsPatternDecodeResult decoded = PsPatternRecordDecoder.decode(
        reader: PsBinaryReader(bytes: record),
        kind: PsPatternRecordKind.standalone,
        onIssue: (message, offset) => issues.add('$offset:$message'),
      );

      expect(decoded.pattern.channelForSlot(0)?.compression, PsPatternCompression.unknown);
      expect(decoded.pattern.channelForSlot(0)?.decodedData, isNull);
      expect(decoded.pattern.channelForSlot(0)?.encodedData, orderedEquals(<int>[10, 20]));
      expect(decoded.pattern.canRenderRgba8, isFalse);
      expect(decoded.pattern.renderRgba8, throwsStateError);
      expect(issues, isNotEmpty);
    });

    test('can decode pixels without retaining encoded channel copies', () {
      final Uint8List record = _record(
        mode: PsPatternColorMode.grayscale,
        channels: <_TestChannel>[
          const _TestChannel(depth: 8, bytes: <int>[10, 20]),
        ],
      );

      final PsPatternDecodeResult decoded = PsPatternRecordDecoder.decode(
        reader: PsBinaryReader(bytes: record),
        kind: PsPatternRecordKind.standalone,
        options: const PsPatternDecodeOptions(
          preserveChannelData: false,
          preserveRecordData: false,
        ),
      );

      expect(decoded.pattern.slots.first.data, isEmpty);
      expect(decoded.pattern.channels.first.encodedData, isEmpty);
      expect(decoded.pattern.channels.first.decodedData, orderedEquals(<int>[10, 20]));
      expect(decoded.pattern.recordData, isNull);
    });

    test('renders one-bit bitmap samples as black and white pixels', () {
      final Uint8List record = _record(
        mode: PsPatternColorMode.bitmap,
        channels: const <_TestChannel>[
          _TestChannel(depth: 1, bytes: <int>[0x80]),
        ],
      );

      final PsPatternDecodeResult decoded = PsPatternRecordDecoder.decode(
        reader: PsBinaryReader(bytes: record),
        kind: PsPatternRecordKind.standalone,
      );

      expect(decoded.pattern.renderRgba8().rgba, orderedEquals(<int>[0, 0, 0, 255, 255, 255, 255, 255]));
    });

    test('bounds pattern names before allocating their UTF-16 code units', () {
      final Uint8List record = _record(
        mode: PsPatternColorMode.grayscale,
        channels: const <_TestChannel>[
          _TestChannel(depth: 8, bytes: <int>[10, 20]),
        ],
      );

      expect(
        () => PsPatternRecordDecoder.decode(
          reader: PsBinaryReader(bytes: record),
          kind: PsPatternRecordKind.standalone,
          options: const PsPatternDecodeOptions(maxNameCodeUnits: 2),
        ),
        throwsA(isA<PsFormatException>()),
      );
    });
  });
}

/// Describes one synthetic channel used by [_record].
final class _TestChannel {
  /// Source precision.
  final int depth;

  /// Uncompressed row-major source bytes.
  final List<int> bytes;

  /// Whether to encode rows with PackBits.
  final bool packBits;

  /// Explicit compression marker used for forward-compatibility tests.
  final int? compressionCode;

  /// Creates a synthetic channel description.
  const _TestChannel({
    required this.depth,
    required this.bytes,
    this.packBits = false,
    this.compressionCode,
  });
}

/// Builds one standalone-compatible version 1 pattern record.
Uint8List _record({
  required PsPatternColorMode mode,
  required List<_TestChannel> channels,
  _TestChannel? alpha,
  Uint8List? palette,
  int colorsUsed = 0,
  int transparentIndex = 0xffff,
}) {
  const int width = 2;
  const int height = 1;
  const int declaredChannelCount = 3;
  final PsBinaryWriter virtualMemory = PsBinaryWriter()
    ..writeInt32(0)
    ..writeInt32(0)
    ..writeInt32(height)
    ..writeInt32(width)
    ..writeUint32(declaredChannelCount);
  for (int index = 0; index < declaredChannelCount + 2; index++) {
    final _TestChannel? channel = index < channels.length ? channels[index] : (index == declaredChannelCount + 1 ? alpha : null);
    if (channel == null) {
      virtualMemory.writeUint32(0);
    } else {
      _writeChannel(virtualMemory, channel, width: width, height: height);
    }
  }
  final Uint8List virtualMemoryBytes = virtualMemory.takeBytes();
  final PsBinaryWriter record = PsBinaryWriter()
    ..writeUint32(1)
    ..writeUint32(mode.code)
    ..writeUint16(height)
    ..writeUint16(width);
  _writeUnicodeString(record, 'Shared pattern');
  record
    ..writeUint8(10)
    ..writeString('pattern-id');
  if (mode == PsPatternColorMode.indexed) {
    record
      ..writeBytes(palette ?? Uint8List(256 * 3))
      ..writeUint16(colorsUsed)
      ..writeUint16(transparentIndex);
  }
  record
    ..writeUint32(3)
    ..writeUint32(virtualMemoryBytes.length)
    ..writeBytes(virtualMemoryBytes);
  return record.takeBytes();
}

/// Writes one complete virtual-memory channel slot.
void _writeChannel(
  PsBinaryWriter writer,
  _TestChannel channel, {
  required int width,
  required int height,
}) {
  final PsBinaryWriter payload = PsBinaryWriter()
    ..writeUint32(channel.depth)
    ..writeInt32(0)
    ..writeInt32(0)
    ..writeInt32(height)
    ..writeInt32(width)
    ..writeUint16(channel.depth)
    ..writeUint8(channel.compressionCode ?? (channel.packBits ? 1 : 0));
  if (channel.packBits) {
    final int rowBytes = (width * channel.depth + 7) ~/ 8;
    final List<Uint8List> rows = <Uint8List>[
      for (int row = 0; row < height; row++) PsPackBitsCodec.encodeRow(Uint8List.fromList(channel.bytes.sublist(row * rowBytes, (row + 1) * rowBytes))),
    ];
    for (final Uint8List row in rows) {
      payload.writeUint16(row.length);
    }
    rows.forEach(payload.writeBytes);
  } else {
    payload.writeBytes(channel.bytes);
  }
  final Uint8List bytes = payload.takeBytes();
  writer
    ..writeUint32(1)
    ..writeUint32(bytes.length)
    ..writeBytes(bytes);
}

/// Creates a decoded channel directly for precision-model tests.
PsPatternChannel _channel({
  required int depth,
  required List<int> bytes,
  required int width,
}) => PsPatternChannel(
  primaryDepth: depth,
  depth: depth,
  bounds: PsRectangle(top: 0, left: 0, bottom: 1, right: width),
  compression: PsPatternCompression.raw,
  compressionCode: 0,
  encodedData: Uint8List.fromList(bytes),
  decodedData: Uint8List.fromList(bytes),
  trailingData: Uint8List(0),
);

/// Creates a one-pixel pattern whose leading slots contain [values].
PsPattern _decodedPattern({
  required PsPatternColorMode mode,
  required List<int> values,
}) => PsPattern(
  version: 1,
  colorMode: mode,
  colorModeCode: mode.code,
  vertical: 1,
  horizontal: 1,
  name: 'Preview',
  id: 'preview',
  idData: Uint8List.fromList('preview'.codeUnits),
  palette: null,
  indexedMetadata: null,
  virtualMemoryVersion: 3,
  bounds: const PsRectangle(top: 0, left: 0, bottom: 1, right: 1),
  declaredChannelCount: values.length,
  slots: <PsPatternChannelSlot>[
    for (int index = 0; index < values.length; index++)
      PsPatternChannelSlot(
        index: index,
        writtenCode: 1,
        declaredLength: 24,
        data: Uint8List.fromList(<int>[...List<int>.filled(23, 0), values[index]]),
        channel: _channel(depth: 8, bytes: <int>[values[index]], width: 1),
      ),
    PsPatternChannelSlot(index: values.length, writtenCode: 0, declaredLength: null, data: Uint8List(0), channel: null),
    PsPatternChannelSlot(index: values.length + 1, writtenCode: 0, declaredLength: null, data: Uint8List(0), channel: null),
  ],
  virtualMemoryTrailingData: Uint8List(0),
  recordTrailingData: Uint8List(0),
  recordData: null,
);

/// Writes a descriptor-style UTF-16 string with a terminal null unit.
void _writeUnicodeString(PsBinaryWriter writer, String value) {
  final List<int> codeUnits = <int>[...value.codeUnits, 0];
  writer.writeUint32(codeUnits.length);
  codeUnits.forEach(writer.writeUint16);
}
