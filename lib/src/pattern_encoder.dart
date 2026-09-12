import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';
import 'package:pscore/src/pack_bits.dart';
import 'package:pscore/src/pattern.dart';
import 'package:pscore/src/pattern_codec.dart';

/// Controls how strongly a Photoshop pattern record is validated before encoding.
enum PsPatternEncodeMode {
  /// Produces only canonical version 1 records with version 3 channel arrays.
  strict,

  /// Writes representable preserved values, including compatibility extensions.
  permissive,
}

/// Preservation and validation choices applied while encoding pattern records.
final class PsPatternEncodeOptions {
  /// Validation policy applied before values are written.
  final PsPatternEncodeMode mode;

  /// Whether bytes after the recognized virtual-memory slots are retained.
  final bool includeVirtualMemoryTrailingData;

  /// Whether bytes after an embedded record's virtual-memory array are retained.
  final bool includeRecordTrailingData;

  /// Creates options for canonical pattern output by default.
  const PsPatternEncodeOptions({
    this.mode = PsPatternEncodeMode.strict,
    this.includeVirtualMemoryTrailingData = true,
    this.includeRecordTrailingData = true,
  });
}

/// Encodes the pattern-record structure shared by PAT, ABR, ASL, and PSD data.
abstract final class PsPatternRecordEncoder {
  /// Number of bytes in an indexed RGB palette.
  static const int _paletteBytes = 256 * 3;

  /// Encodes [pattern] without an outer record length or alignment.
  static Uint8List encode({
    required PsPattern pattern,
    required PsPatternRecordKind kind,
    PsPatternEncodeOptions options = const PsPatternEncodeOptions(),
  }) {
    _validateRepresentable(pattern, kind, options);
    if (options.mode == PsPatternEncodeMode.strict) {
      _validateStrict(pattern, kind, options);
    }

    final PsBinaryWriter virtualMemory = PsBinaryWriter()
      ..writeInt32(pattern.bounds.top)
      ..writeInt32(pattern.bounds.left)
      ..writeInt32(pattern.bounds.bottom)
      ..writeInt32(pattern.bounds.right)
      ..writeUint32(pattern.declaredChannelCount);
    for (final PsPatternChannelSlot slot in pattern.slots) {
      _writeSlot(virtualMemory, slot, options);
    }
    if (options.includeVirtualMemoryTrailingData) {
      virtualMemory.writeBytes(pattern.virtualMemoryTrailingData);
    }
    final Uint8List virtualMemoryData = virtualMemory.takeBytes();

    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint32(pattern.version)
      ..writeUint32(pattern.colorModeCode)
      ..writeInt16(pattern.vertical)
      ..writeInt16(pattern.horizontal);
    _writeUnicodeString(
      writer,
      pattern.name,
      terminate: kind == PsPatternRecordKind.standalone,
    );
    final List<int> idData = options.mode == PsPatternEncodeMode.permissive && pattern.idData.isNotEmpty ? pattern.idData : pattern.id.codeUnits;
    writer
      ..writeUint8(idData.length)
      ..writeBytes(idData);
    if (pattern.palette case final Uint8List palette) {
      writer.writeBytes(palette);
      _writeIndexedMetadata(writer, pattern.indexedMetadata, kind, options);
    }
    writer
      ..writeUint32(pattern.virtualMemoryVersion)
      ..writeUint32(virtualMemoryData.length)
      ..writeBytes(virtualMemoryData);
    if (kind == PsPatternRecordKind.embedded && options.includeRecordTrailingData) {
      writer.writeBytes(pattern.recordTrailingData);
    }
    return writer.takeBytes();
  }

  /// Writes the indexed palette footer appropriate for [kind].
  static void _writeIndexedMetadata(
    PsBinaryWriter writer,
    PsPatternIndexedMetadata? metadata,
    PsPatternRecordKind kind,
    PsPatternEncodeOptions options,
  ) {
    if (metadata == null) {
      writer.writeZeros(4);
      return;
    }
    if (kind == PsPatternRecordKind.standalone && metadata.colorsUsed != null && metadata.transparentIndex != null) {
      writer
        ..writeUint16(metadata.colorsUsed!)
        ..writeUint16(metadata.transparentIndex!);
      return;
    }
    if (metadata.rawData.length == 4) {
      writer.writeBytes(metadata.rawData);
      return;
    }
    if (options.mode == PsPatternEncodeMode.permissive) {
      writer.writeBytes(metadata.rawData);
      return;
    }
    writer.writeZeros(4);
  }

  /// Writes one sparse virtual-memory channel slot.
  static void _writeSlot(
    PsBinaryWriter writer,
    PsPatternChannelSlot slot,
    PsPatternEncodeOptions options,
  ) {
    writer.writeUint32(slot.writtenCode);
    if (!slot.isWritten) {
      return;
    }
    final Uint8List data = _slotData(slot, options);
    writer
      ..writeUint32(options.mode == PsPatternEncodeMode.permissive ? slot.declaredLength ?? data.length : data.length)
      ..writeBytes(data);
  }

  /// Rebuilds a parsed channel or falls back to its complete opaque payload.
  static Uint8List _slotData(
    PsPatternChannelSlot slot,
    PsPatternEncodeOptions options,
  ) {
    final PsPatternChannel? channel = slot.channel;
    if (channel == null) {
      if (slot.data.isEmpty && slot.declaredLength != 0) {
        throw PsWriteException(message: 'Pattern slot ${slot.index} has no channel or preserved payload');
      }
      return slot.data;
    }
    final Uint8List encodedSamples = _encodedSamples(channel, slot, options);
    return (PsBinaryWriter()
          ..writeUint32(channel.primaryDepth)
          ..writeInt32(channel.bounds.top)
          ..writeInt32(channel.bounds.left)
          ..writeInt32(channel.bounds.bottom)
          ..writeInt32(channel.bounds.right)
          ..writeUint16(channel.depth)
          ..writeUint8(channel.compressionCode)
          ..writeBytes(encodedSamples))
        .takeBytes();
  }

  /// Encodes decoded samples with their selected compression or reuses source bytes.
  static Uint8List _encodedSamples(
    PsPatternChannel channel,
    PsPatternChannelSlot slot,
    PsPatternEncodeOptions options,
  ) {
    final Uint8List? decodedData = channel.decodedData;
    if (decodedData == null) {
      if (channel.encodedData.isNotEmpty || channel.bounds.pixelCount == 0) {
        return channel.encodedData;
      }
      if (slot.data.length >= 23) {
        return Uint8List.sublistView(slot.data, 23);
      }
      throw PsWriteException(message: 'Pattern slot ${slot.index} has no encoded or decoded sample data');
    }
    final int rowBytes = (channel.bounds.width * channel.depth + 7) ~/ 8;
    final int expectedLength = rowBytes * channel.bounds.height;
    if (decodedData.length != expectedLength) {
      throw PsWriteException(
        message: 'Pattern slot ${slot.index} has ${decodedData.length} decoded bytes; expected $expectedLength',
      );
    }
    final PsBinaryWriter writer = PsBinaryWriter();
    switch (channel.compression) {
      case PsPatternCompression.raw:
        writer.writeBytes(decodedData);
      case PsPatternCompression.packBits:
        final List<Uint8List> rows = <Uint8List>[
          for (int row = 0; row < channel.bounds.height; row++)
            PsPackBitsCodec.encodeRow(
              Uint8List.sublistView(decodedData, row * rowBytes, (row + 1) * rowBytes),
            ),
        ];
        for (final Uint8List row in rows) {
          if (row.length > 0xffff) {
            throw PsWriteException(message: 'Pattern slot ${slot.index} has a PackBits row exceeding the 16-bit length capacity');
          }
          writer.writeUint16(row.length);
        }
        rows.forEach(writer.writeBytes);
      case PsPatternCompression.unknown:
        if (options.mode == PsPatternEncodeMode.strict) {
          throw PsWriteException(message: 'Pattern slot ${slot.index} uses unknown compression ${channel.compressionCode}');
        }
        if (channel.encodedData.isEmpty) {
          throw PsWriteException(message: 'Pattern slot ${slot.index} cannot regenerate unknown compression ${channel.compressionCode}');
        }
        return channel.encodedData;
    }
    writer.writeBytes(channel.trailingData);
    return writer.takeBytes();
  }

  /// Writes one length-prefixed UTF-16 string.
  static void _writeUnicodeString(
    PsBinaryWriter writer,
    String value, {
    required bool terminate,
  }) {
    final List<int> codeUnits = <int>[...value.codeUnits, if (terminate) 0];
    writer.writeUint32(codeUnits.length);
    codeUnits.forEach(writer.writeUint16);
  }

  /// Checks that all emitted numeric and byte fields are representable.
  static void _validateRepresentable(
    PsPattern pattern,
    PsPatternRecordKind kind,
    PsPatternEncodeOptions options,
  ) {
    _requireUnsigned(pattern.version, 32, 'Pattern version');
    _requireUnsigned(pattern.colorModeCode, 32, 'Pattern color mode');
    _requireSigned(pattern.vertical, 16, 'Pattern vertical point');
    _requireSigned(pattern.horizontal, 16, 'Pattern horizontal point');
    final int nameLength = pattern.name.codeUnits.length + (kind == PsPatternRecordKind.standalone ? 1 : 0);
    _requireUnsigned(nameLength, 32, 'Pattern name length');
    final List<int> idData = options.mode == PsPatternEncodeMode.permissive && pattern.idData.isNotEmpty ? pattern.idData : pattern.id.codeUnits;
    if (idData.length > 0xff || idData.any((value) => value > 0xff)) {
      throw const PsWriteException(message: 'Pattern identifier must fit a 255-byte Latin-1 Pascal string');
    }
    final Uint8List? palette = pattern.palette;
    if (palette != null && palette.length != _paletteBytes) {
      throw const PsWriteException(message: 'A pattern palette must contain exactly 768 interleaved RGB bytes');
    }
    _requireUnsigned(pattern.virtualMemoryVersion, 32, 'Pattern virtual-memory version');
    _requireSigned(pattern.bounds.top, 32, 'Pattern top bound');
    _requireSigned(pattern.bounds.left, 32, 'Pattern left bound');
    _requireSigned(pattern.bounds.bottom, 32, 'Pattern bottom bound');
    _requireSigned(pattern.bounds.right, 32, 'Pattern right bound');
    _requireUnsigned(pattern.declaredChannelCount, 32, 'Pattern declared channel count');
    for (final PsPatternChannelSlot slot in pattern.slots) {
      _requireUnsigned(slot.writtenCode, 32, 'Pattern slot ${slot.index} written marker');
      final int? declaredLength = slot.declaredLength;
      if (declaredLength != null) {
        _requireUnsigned(declaredLength, 32, 'Pattern slot ${slot.index} declared length');
      }
      final PsPatternChannel? channel = slot.channel;
      if (channel != null) {
        _requireUnsigned(channel.primaryDepth, 32, 'Pattern slot ${slot.index} primary depth');
        _requireUnsigned(channel.depth, 16, 'Pattern slot ${slot.index} depth');
        _requireUnsigned(channel.compressionCode, 8, 'Pattern slot ${slot.index} compression');
        _requireSigned(channel.bounds.top, 32, 'Pattern slot ${slot.index} top bound');
        _requireSigned(channel.bounds.left, 32, 'Pattern slot ${slot.index} left bound');
        _requireSigned(channel.bounds.bottom, 32, 'Pattern slot ${slot.index} bottom bound');
        _requireSigned(channel.bounds.right, 32, 'Pattern slot ${slot.index} right bound');
      }
    }
    final PsPatternIndexedMetadata? metadata = pattern.indexedMetadata;
    if (metadata?.colorsUsed case final int colorsUsed) {
      _requireUnsigned(colorsUsed, 16, 'Indexed color count');
    }
    if (metadata?.transparentIndex case final int transparentIndex) {
      _requireUnsigned(transparentIndex, 16, 'Indexed transparent index');
    }
  }

  /// Applies the canonical constraints understood by Photoshop writers.
  static void _validateStrict(
    PsPattern pattern,
    PsPatternRecordKind kind,
    PsPatternEncodeOptions options,
  ) {
    if (pattern.version != 1 || pattern.virtualMemoryVersion != 3) {
      throw const PsWriteException(message: 'Strict pattern output requires record version 1 and virtual-memory version 3');
    }
    if (pattern.colorMode == PsPatternColorMode.unknown || pattern.colorMode.code != pattern.colorModeCode) {
      throw PsWriteException(message: 'Strict pattern output does not support color mode ${pattern.colorModeCode}');
    }
    if (pattern.name.isEmpty || pattern.name.codeUnits.contains(0)) {
      throw const PsWriteException(message: 'Strict pattern output requires a nonempty name without embedded nulls');
    }
    if (pattern.id.isEmpty || pattern.id.codeUnits.any((value) => value == 0 || value > 0xff)) {
      throw const PsWriteException(message: 'Strict pattern output requires a nonempty Latin-1 identifier without nulls');
    }
    if (kind == PsPatternRecordKind.standalone && (pattern.vertical <= 0 || pattern.horizontal <= 0)) {
      throw const PsWriteException(message: 'A standalone pattern requires positive horizontal and vertical dimensions');
    }
    if (!pattern.bounds.isValid) {
      throw const PsWriteException(message: 'Strict pattern output requires positive virtual-memory bounds');
    }
    if (pattern.slots.length != pattern.declaredChannelCount + 2) {
      throw PsWriteException(
        message: 'Pattern declares ${pattern.declaredChannelCount} ordinary channels but contains ${pattern.slots.length} total slots',
      );
    }
    if (pattern.declaredChannelCount < pattern.colorMode.colorChannelCount) {
      throw const PsWriteException(message: 'Pattern does not declare enough channel slots for its color mode');
    }
    if (pattern.colorMode == PsPatternColorMode.indexed) {
      if (pattern.palette == null || pattern.indexedMetadata == null) {
        throw const PsWriteException(message: 'An indexed pattern requires a palette and four-byte palette metadata');
      }
    } else if (pattern.palette != null || pattern.indexedMetadata != null) {
      throw const PsWriteException(message: 'Only indexed patterns can contain palette data in strict output');
    }
    for (int index = 0; index < pattern.slots.length; index++) {
      final PsPatternChannelSlot slot = pattern.slots[index];
      if (slot.index != index) {
        throw PsWriteException(message: 'Pattern slot ${slot.index} is out of source order at position $index');
      }
      if (slot.writtenCode != 0 && slot.writtenCode != 1) {
        throw PsWriteException(message: 'Pattern slot $index uses noncanonical written marker ${slot.writtenCode}');
      }
      if (!slot.isWritten) {
        if (slot.declaredLength != null || slot.data.isNotEmpty || slot.channel != null) {
          throw PsWriteException(message: 'Unwritten pattern slot $index contains channel data');
        }
        continue;
      }
      if (slot.channel case final PsPatternChannel channel) {
        if (channel.primaryDepth != channel.depth || channel.depth != 1 && channel.depth != 8 && channel.depth != 16 && channel.depth != 32) {
          throw PsWriteException(message: 'Pattern slot $index uses inconsistent or unsupported depth fields');
        }
        if (!channel.bounds.isValid) {
          throw PsWriteException(message: 'Pattern slot $index requires positive channel bounds');
        }
        if (channel.compression == PsPatternCompression.unknown || channel.compression.code != channel.compressionCode) {
          throw PsWriteException(message: 'Pattern slot $index uses unsupported compression ${channel.compressionCode}');
        }
      } else if (slot.data.isEmpty) {
        throw PsWriteException(message: 'Written pattern slot $index has no payload');
      }
    }
    if (options.includeVirtualMemoryTrailingData && pattern.virtualMemoryTrailingData.isNotEmpty) {
      throw const PsWriteException(message: 'Strict pattern output cannot contain virtual-memory trailing bytes');
    }
    if (kind == PsPatternRecordKind.embedded && options.includeRecordTrailingData && pattern.recordTrailingData.isNotEmpty) {
      throw const PsWriteException(message: 'Strict pattern output cannot contain embedded-record trailing bytes');
    }
  }

  /// Requires [value] to fit an unsigned integer field.
  static void _requireUnsigned(int value, int bits, String label) {
    final int maximum = (1 << bits) - 1;
    if (value < 0 || value > maximum) {
      throw PsWriteException(message: '$label value $value does not fit an unsigned $bits-bit field');
    }
  }

  /// Requires [value] to fit a signed integer field.
  static void _requireSigned(int value, int bits, String label) {
    final int minimum = -(1 << (bits - 1));
    final int maximum = (1 << (bits - 1)) - 1;
    if (value < minimum || value > maximum) {
      throw PsWriteException(message: '$label value $value does not fit a signed $bits-bit field');
    }
  }
}

/// Encodes length-prefixed, four-byte-aligned embedded pattern records.
abstract final class PsPatternBlockEncoder {
  /// Encodes [patterns] in source order into one Photoshop pattern block.
  static Uint8List encodeAll(
    List<PsPattern> patterns, {
    PsPatternEncodeOptions options = const PsPatternEncodeOptions(),
  }) {
    final PsBinaryWriter writer = PsBinaryWriter();
    for (final PsPattern pattern in patterns) {
      final Uint8List data = PsPatternRecordEncoder.encode(
        pattern: pattern,
        kind: PsPatternRecordKind.embedded,
        options: options,
      );
      writer
        ..writeUint32(data.length)
        ..writeBytes(data)
        ..writeZeros((4 - data.length % 4) % 4);
    }
    return writer.takeBytes();
  }
}
