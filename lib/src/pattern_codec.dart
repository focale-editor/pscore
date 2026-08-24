import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';
import 'package:pscore/src/pack_bits.dart';
import 'package:pscore/src/pattern.dart';

/// Distinguishes standalone PAT records from length-bounded embedded records.
enum PsPatternRecordKind {
  /// A record in an `8BPT` PAT library without an outer length or padding.
  standalone,

  /// A length-prefixed record in a PSD, ABR, or other Photoshop container.
  embedded,
}

/// Receives a recoverable pattern compatibility issue and its absolute byte offset.
typedef PsPatternIssueHandler = void Function(String message, int offset);

/// Verifies that retaining [bytes] decoded bytes remains within a caller's aggregate budget.
typedef PsPatternDecodedBytesGuard = void Function(int bytes, int offset);

/// Resource and preservation limits for one Photoshop pattern record.
final class PsPatternDecodeOptions {
  /// Maximum accepted width or height for a decoded channel.
  final int maxDimension;

  /// Maximum number of ordinary virtual-memory slots before the two special slots.
  final int maxChannelCount;

  /// Maximum accepted byte length for one virtual-memory payload.
  final int maxVirtualMemoryBytes;

  /// Maximum UTF-16 code-unit count accepted for one pattern name.
  final int maxNameCodeUnits;

  /// Maximum aggregate decoded channel bytes retained by one decode operation.
  final int maxDecodedBytes;

  /// Whether recognized channel payloads are decompressed.
  final bool decodeChannelData;

  /// Whether channel slots retain their original encoded payload bytes.
  final bool preserveChannelData;

  /// Whether each pattern retains a complete copy of its source record.
  final bool preserveRecordData;

  /// Creates bounded options suitable for untrusted Photoshop pattern data.
  const PsPatternDecodeOptions({
    this.maxDimension = 100000,
    this.maxChannelCount = 1024,
    this.maxVirtualMemoryBytes = 512 * 1024 * 1024,
    this.maxNameCodeUnits = 1024 * 1024,
    this.maxDecodedBytes = 512 * 1024 * 1024,
    this.decodeChannelData = true,
    this.preserveChannelData = true,
    this.preserveRecordData = true,
  });

  /// Returns options with selected limits or preservation behavior replaced.
  PsPatternDecodeOptions copyWith({
    int? maxDimension,
    int? maxChannelCount,
    int? maxVirtualMemoryBytes,
    int? maxNameCodeUnits,
    int? maxDecodedBytes,
    bool? decodeChannelData,
    bool? preserveChannelData,
    bool? preserveRecordData,
  }) => PsPatternDecodeOptions(
    maxDimension: maxDimension ?? this.maxDimension,
    maxChannelCount: maxChannelCount ?? this.maxChannelCount,
    maxVirtualMemoryBytes: maxVirtualMemoryBytes ?? this.maxVirtualMemoryBytes,
    maxNameCodeUnits: maxNameCodeUnits ?? this.maxNameCodeUnits,
    maxDecodedBytes: maxDecodedBytes ?? this.maxDecodedBytes,
    decodeChannelData: decodeChannelData ?? this.decodeChannelData,
    preserveChannelData: preserveChannelData ?? this.preserveChannelData,
    preserveRecordData: preserveRecordData ?? this.preserveRecordData,
  );
}

/// One decoded pattern together with its retained uncompressed-byte cost.
final class PsPatternDecodeResult {
  /// Decoded and preserved pattern record.
  final PsPattern pattern;

  /// Number of uncompressed channel bytes retained by [pattern].
  final int decodedBytes;

  /// Creates a record decode result.
  const PsPatternDecodeResult({
    required this.pattern,
    required this.decodedBytes,
  });
}

/// Every pattern decoded from a length-prefixed block and its retained byte cost.
final class PsPatternBlockDecodeResult {
  /// Successfully decoded records in source order.
  final List<PsPattern> patterns;

  /// Aggregate number of retained uncompressed channel bytes.
  final int decodedBytes;

  /// Creates an immutable block decode result.
  PsPatternBlockDecodeResult({
    required List<PsPattern> patterns,
    required this.decodedBytes,
  }) : patterns = List<PsPattern>.unmodifiable(patterns);
}

/// Decodes the shared versioned pattern-record structure used by Photoshop formats.
abstract final class PsPatternRecordDecoder {
  /// Number of bytes in an indexed RGB palette.
  static const int _paletteBytes = 256 * 3;

  /// Number of bytes preceding one channel's encoded payload.
  static const int _channelHeaderBytes = 23;

  /// Decodes one record from the current position of [reader].
  ///
  /// A standalone record consumes through its bounded virtual-memory array only;
  /// an embedded record consumes all remaining bytes as record extensions.
  static PsPatternDecodeResult decode({
    required PsBinaryReader reader,
    required PsPatternRecordKind kind,
    PsPatternDecodeOptions options = const PsPatternDecodeOptions(),
    PsPatternIssueHandler? onIssue,
    PsPatternDecodedBytesGuard? onDecodedBytesRequired,
  }) {
    final int recordStart = reader.offset;
    final int absoluteStart = reader.baseOffset + recordStart;
    final int version = reader.readUint32();
    final int colorModeCode = reader.readUint32();
    final PsPatternColorMode colorMode = PsPatternColorMode.fromCode(colorModeCode);
    final int vertical = reader.readInt16();
    final int horizontal = reader.readInt16();
    final String name = _readUnicodeString(
      reader,
      maxCodeUnits: options.maxNameCodeUnits,
    );
    final Uint8List idData = reader.readBytes(reader.readUint8());
    final String id = _trimTerminalNulls(String.fromCharCodes(idData));

    if (version != 1) {
      _issue(onIssue, 'Pattern record version $version is not currently defined', absoluteStart);
    }
    if (colorMode == PsPatternColorMode.unknown) {
      _issue(onIssue, 'Pattern color mode $colorModeCode is unknown and will use a grayscale preview', absoluteStart + 4);
    }
    if (vertical < 0 || horizontal < 0 || vertical > options.maxDimension || horizontal > options.maxDimension) {
      _issue(onIssue, 'Pattern point $horizontal x $vertical is negative or exceeds the configured ${options.maxDimension} dimension limit', absoluteStart + 8);
    }

    Uint8List? palette;
    PsPatternIndexedMetadata? indexedMetadata;
    if (colorMode == PsPatternColorMode.indexed) {
      palette = reader.readBytes(_paletteBytes);
      indexedMetadata = _readIndexedMetadata(
        reader: reader,
        kind: kind,
        onIssue: onIssue,
      );
    } else if (colorMode == PsPatternColorMode.unknown && !_looksLikeVirtualMemoryArray(reader, relativeOffset: 0) && _looksLikeVirtualMemoryArray(reader, relativeOffset: _paletteBytes + 4)) {
      _issue(onIssue, 'Unknown color mode contains an indexed-style palette that was preserved', reader.baseOffset + reader.offset);
      palette = reader.readBytes(_paletteBytes);
      indexedMetadata = _readIndexedMetadata(
        reader: reader,
        kind: kind,
        onIssue: onIssue,
      );
    }

    final int virtualMemoryOffset = reader.baseOffset + reader.offset;
    final int virtualMemoryVersion = reader.readUint32();
    final int virtualMemoryLength = reader.readUint32();
    if (virtualMemoryLength > options.maxVirtualMemoryBytes) {
      throw PsFormatException(
        message: 'Pattern virtual-memory length $virtualMemoryLength exceeds the configured ${options.maxVirtualMemoryBytes} byte limit',
        source: reader.bytes,
        offset: virtualMemoryOffset + 4,
      );
    }
    if (virtualMemoryLength > reader.remaining) {
      throw PsFormatException(
        message: 'Pattern virtual-memory length $virtualMemoryLength exceeds the ${reader.remaining} remaining bytes',
        source: reader.bytes,
        offset: virtualMemoryOffset + 4,
      );
    }
    final PsBinaryReader virtualMemory = reader.readReader(virtualMemoryLength);
    PsRectangle bounds = PsRectangle(top: 0, left: 0, bottom: vertical, right: horizontal);
    int declaredChannelCount = 0;
    final List<PsPatternChannelSlot> slots = <PsPatternChannelSlot>[];
    int decodedBytes = 0;
    Uint8List virtualMemoryTrailingData;

    if (virtualMemoryVersion != 3) {
      _issue(onIssue, 'Pattern virtual-memory version $virtualMemoryVersion is not currently defined', virtualMemoryOffset);
    }
    if (virtualMemory.remaining < 20) {
      _issue(onIssue, 'Pattern virtual-memory payload is shorter than its fixed header', virtualMemory.baseOffset);
      virtualMemoryTrailingData = virtualMemory.readBytes(virtualMemory.remaining);
    } else {
      bounds = _readRectangle(virtualMemory);
      declaredChannelCount = virtualMemory.readUint32();
      if (!bounds.isValid || bounds.width > options.maxDimension || bounds.height > options.maxDimension) {
        _issue(onIssue, 'Pattern virtual-memory bounds ${bounds.width} x ${bounds.height} are invalid or excessive', virtualMemory.baseOffset);
      }
      if (declaredChannelCount > options.maxChannelCount) {
        _issue(onIssue, 'Pattern channel count $declaredChannelCount exceeds the configured ${options.maxChannelCount} limit', virtualMemory.baseOffset + 16);
        virtualMemoryTrailingData = virtualMemory.readBytes(virtualMemory.remaining);
      } else {
        final int slotCount = declaredChannelCount + 2;
        for (int index = 0; index < slotCount; index++) {
          if (virtualMemory.remaining < 4) {
            _issue(onIssue, 'Pattern virtual-memory slot list is truncated at slot $index', virtualMemory.baseOffset + virtualMemory.offset);
            break;
          }
          final ({PsPatternChannelSlot slot, int decodedBytes, bool stop}) result = _decodeSlot(
            reader: virtualMemory,
            index: index,
            options: options,
            decodedBytes: decodedBytes,
            onIssue: onIssue,
            onDecodedBytesRequired: onDecodedBytesRequired,
          );
          slots.add(result.slot);
          decodedBytes += result.decodedBytes;
          if (result.stop) {
            break;
          }
        }
        virtualMemoryTrailingData = virtualMemory.readBytes(virtualMemory.remaining);
        if (virtualMemoryTrailingData.isNotEmpty) {
          _issue(
            onIssue,
            '${virtualMemoryTrailingData.length} unrecognized bytes remain after the pattern channel slots',
            virtualMemory.baseOffset + virtualMemory.offset - virtualMemoryTrailingData.length,
          );
        }
      }
    }

    final Uint8List recordTrailingData = kind == PsPatternRecordKind.embedded ? reader.readBytes(reader.remaining) : Uint8List(0);
    if (recordTrailingData.isNotEmpty) {
      _issue(onIssue, '${recordTrailingData.length} extension bytes remain after the embedded pattern record', reader.baseOffset + reader.offset - recordTrailingData.length);
    }
    final int recordEnd = reader.offset;
    final Uint8List? recordData = options.preserveRecordData ? Uint8List.sublistView(reader.bytes, recordStart, recordEnd) : null;
    final PsPattern pattern = PsPattern(
      version: version,
      colorMode: colorMode,
      colorModeCode: colorModeCode,
      vertical: vertical,
      horizontal: horizontal,
      name: name,
      id: id,
      idData: idData,
      palette: palette,
      indexedMetadata: indexedMetadata,
      virtualMemoryVersion: virtualMemoryVersion,
      bounds: bounds,
      declaredChannelCount: declaredChannelCount,
      slots: slots,
      virtualMemoryTrailingData: virtualMemoryTrailingData,
      recordTrailingData: recordTrailingData,
      recordData: recordData,
    );
    return PsPatternDecodeResult(pattern: pattern, decodedBytes: decodedBytes);
  }

  /// Reads the palette trailer when present and interprets standalone metadata.
  static PsPatternIndexedMetadata _readIndexedMetadata({
    required PsBinaryReader reader,
    required PsPatternRecordKind kind,
    required PsPatternIssueHandler? onIssue,
  }) {
    final bool trailerPresent = _looksLikeVirtualMemoryArray(reader, relativeOffset: 4);
    if (!trailerPresent && _looksLikeVirtualMemoryArray(reader, relativeOffset: 0)) {
      _issue(onIssue, 'Indexed pattern omits the usual four-byte palette trailer', reader.baseOffset + reader.offset);
      return PsPatternIndexedMetadata(rawData: Uint8List(0));
    }
    final Uint8List rawData = reader.readBytes(4);
    if (kind == PsPatternRecordKind.embedded) {
      return PsPatternIndexedMetadata(rawData: rawData);
    }
    final ByteData values = ByteData.sublistView(rawData);
    return PsPatternIndexedMetadata(
      rawData: rawData,
      colorsUsed: values.getUint16(0),
      transparentIndex: values.getUint16(2),
    );
  }

  /// Decodes or preserves one virtual-memory slot while retaining synchronization.
  static ({PsPatternChannelSlot slot, int decodedBytes, bool stop}) _decodeSlot({
    required PsBinaryReader reader,
    required int index,
    required PsPatternDecodeOptions options,
    required int decodedBytes,
    required PsPatternIssueHandler? onIssue,
    required PsPatternDecodedBytesGuard? onDecodedBytesRequired,
  }) {
    final int slotOffset = reader.baseOffset + reader.offset;
    final int writtenCode = reader.readUint32();
    if (writtenCode == 0) {
      return (
        slot: PsPatternChannelSlot(index: index, writtenCode: writtenCode, declaredLength: null, data: Uint8List(0), channel: null),
        decodedBytes: 0,
        stop: false,
      );
    }
    if (writtenCode != 1) {
      _issue(onIssue, 'Pattern slot $index uses the nonstandard written marker $writtenCode', slotOffset);
    }
    if (reader.remaining < 4) {
      _issue(onIssue, 'Pattern slot $index is missing its channel length', reader.baseOffset + reader.offset);
      return (
        slot: PsPatternChannelSlot(index: index, writtenCode: writtenCode, declaredLength: null, data: Uint8List(0), channel: null),
        decodedBytes: 0,
        stop: true,
      );
    }
    final int declaredLength = reader.readUint32();
    if (declaredLength == 0) {
      return (
        slot: PsPatternChannelSlot(index: index, writtenCode: writtenCode, declaredLength: declaredLength, data: Uint8List(0), channel: null),
        decodedBytes: 0,
        stop: false,
      );
    }
    if (declaredLength > reader.remaining) {
      _issue(onIssue, 'Pattern slot $index length $declaredLength exceeds the ${reader.remaining} remaining virtual-memory bytes', reader.baseOffset + reader.offset - 4);
      final Uint8List data = reader.readView(reader.remaining);
      return (
        slot: PsPatternChannelSlot(
          index: index,
          writtenCode: writtenCode,
          declaredLength: declaredLength,
          data: options.preserveChannelData ? data : Uint8List(0),
          channel: null,
        ),
        decodedBytes: 0,
        stop: true,
      );
    }
    final Uint8List data = reader.readView(declaredLength);
    if (data.length < _channelHeaderBytes) {
      _issue(onIssue, 'Pattern slot $index channel is shorter than its $_channelHeaderBytes-byte header', slotOffset + 8);
      return (
        slot: PsPatternChannelSlot(
          index: index,
          writtenCode: writtenCode,
          declaredLength: declaredLength,
          data: options.preserveChannelData ? data : Uint8List(0),
          channel: null,
        ),
        decodedBytes: 0,
        stop: false,
      );
    }
    final ({PsPatternChannel channel, int decodedBytes}) decoded = _decodeChannel(
      bytes: data,
      baseOffset: slotOffset + 8,
      options: options,
      alreadyDecodedBytes: decodedBytes,
      onIssue: onIssue,
      onDecodedBytesRequired: onDecodedBytesRequired,
    );
    return (
      slot: PsPatternChannelSlot(
        index: index,
        writtenCode: writtenCode,
        declaredLength: declaredLength,
        data: options.preserveChannelData ? data : Uint8List(0),
        channel: decoded.channel,
      ),
      decodedBytes: decoded.decodedBytes,
      stop: false,
    );
  }

  /// Decodes the fixed channel header and its recognized bitmap payload.
  static ({PsPatternChannel channel, int decodedBytes}) _decodeChannel({
    required Uint8List bytes,
    required int baseOffset,
    required PsPatternDecodeOptions options,
    required int alreadyDecodedBytes,
    required PsPatternIssueHandler? onIssue,
    required PsPatternDecodedBytesGuard? onDecodedBytesRequired,
  }) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes, baseOffset: baseOffset);
    final int primaryDepth = reader.readUint32();
    final PsRectangle bounds = _readRectangle(reader);
    final int depth = reader.readUint16();
    final int compressionCode = reader.readUint8();
    final PsPatternCompression compression = PsPatternCompression.fromCode(compressionCode);
    final int encodedOffset = reader.baseOffset + reader.offset;
    final Uint8List encodedData = reader.readView(reader.remaining);
    final Uint8List retainedEncodedData = options.preserveChannelData ? encodedData : Uint8List(0);
    if (primaryDepth != depth) {
      _issue(onIssue, 'Pattern channel depth fields disagree: $primaryDepth and $depth', baseOffset);
    }
    if (!bounds.isValid || bounds.width > options.maxDimension || bounds.height > options.maxDimension) {
      _issue(onIssue, 'Pattern channel bounds ${bounds.width} x ${bounds.height} are invalid or excessive', baseOffset + 4);
      return (
        channel: PsPatternChannel(
          primaryDepth: primaryDepth,
          depth: depth,
          bounds: bounds,
          compression: compression,
          compressionCode: compressionCode,
          encodedData: retainedEncodedData,
          decodedData: null,
          trailingData: Uint8List(0),
        ),
        decodedBytes: 0,
      );
    }
    if (depth != 1 && depth != 8 && depth != 16 && depth != 32) {
      _issue(onIssue, 'Pattern channel depth $depth is preserved but not decoded', baseOffset + 20);
      return (
        channel: PsPatternChannel(
          primaryDepth: primaryDepth,
          depth: depth,
          bounds: bounds,
          compression: compression,
          compressionCode: compressionCode,
          encodedData: retainedEncodedData,
          decodedData: null,
          trailingData: Uint8List(0),
        ),
        decodedBytes: 0,
      );
    }
    if (compression == PsPatternCompression.unknown) {
      _issue(onIssue, 'Pattern compression code $compressionCode is preserved but not decoded', encodedOffset - 1);
      return (
        channel: PsPatternChannel(
          primaryDepth: primaryDepth,
          depth: depth,
          bounds: bounds,
          compression: compression,
          compressionCode: compressionCode,
          encodedData: retainedEncodedData,
          decodedData: null,
          trailingData: Uint8List(0),
        ),
        decodedBytes: 0,
      );
    }
    if (!options.decodeChannelData) {
      return (
        channel: PsPatternChannel(
          primaryDepth: primaryDepth,
          depth: depth,
          bounds: bounds,
          compression: compression,
          compressionCode: compressionCode,
          encodedData: retainedEncodedData,
          decodedData: null,
          trailingData: Uint8List(0),
        ),
        decodedBytes: 0,
      );
    }

    final int rowBytes = (bounds.width * depth + 7) ~/ 8;
    final int expectedBytes = rowBytes * bounds.height;
    if (expectedBytes > options.maxDecodedBytes - alreadyDecodedBytes) {
      throw PsFormatException(
        message: 'Decoded pattern bytes exceed the configured ${options.maxDecodedBytes} byte limit',
        source: bytes,
        offset: baseOffset,
      );
    }
    onDecodedBytesRequired?.call(alreadyDecodedBytes + expectedBytes, baseOffset);
    final ({Uint8List? decodedData, Uint8List trailingData}) payload = _decodePayload(
      encodedData: encodedData,
      encodedOffset: encodedOffset,
      rowBytes: rowBytes,
      height: bounds.height,
      expectedBytes: expectedBytes,
      compression: compression,
      onIssue: onIssue,
    );
    final int retainedBytes = payload.decodedData?.length ?? 0;
    return (
      channel: PsPatternChannel(
        primaryDepth: primaryDepth,
        depth: depth,
        bounds: bounds,
        compression: compression,
        compressionCode: compressionCode,
        encodedData: retainedEncodedData,
        decodedData: payload.decodedData,
        trailingData: options.preserveChannelData ? payload.trailingData : Uint8List(0),
      ),
      decodedBytes: retainedBytes,
    );
  }

  /// Decodes raw or PackBits bytes and separates any recognized trailing extension.
  static ({Uint8List? decodedData, Uint8List trailingData}) _decodePayload({
    required Uint8List encodedData,
    required int encodedOffset,
    required int rowBytes,
    required int height,
    required int expectedBytes,
    required PsPatternCompression compression,
    required PsPatternIssueHandler? onIssue,
  }) {
    if (compression == PsPatternCompression.raw) {
      if (encodedData.length < expectedBytes) {
        _issue(onIssue, 'Raw pattern channel has ${encodedData.length} bytes; expected at least $expectedBytes', encodedOffset);
        return (decodedData: null, trailingData: Uint8List(0));
      }
      return (
        decodedData: Uint8List.sublistView(encodedData, 0, expectedBytes),
        trailingData: Uint8List.sublistView(encodedData, expectedBytes),
      );
    }
    final PsBinaryReader compressed = PsBinaryReader(bytes: encodedData, baseOffset: encodedOffset);
    if (compressed.remaining < height * 2) {
      _issue(onIssue, 'Pattern PackBits row-length table is truncated', encodedOffset);
      return (decodedData: null, trailingData: Uint8List(0));
    }
    final List<int> rowLengths = <int>[
      for (int row = 0; row < height; row++) compressed.readUint16(),
    ];
    final Uint8List output = Uint8List(expectedBytes);
    try {
      for (int row = 0; row < height; row++) {
        final int rowLength = rowLengths[row];
        final Uint8List encodedRow = compressed.readBytes(rowLength);
        final Uint8List decodedRow = PsPackBitsCodec.decodeRow(encodedRow, decodedLength: rowBytes);
        output.setRange(row * rowBytes, (row + 1) * rowBytes, decodedRow);
      }
    } on PsFormatException catch (error) {
      _issue(onIssue, 'Pattern PackBits data could not be decoded: ${error.message}', error.offset ?? encodedOffset);
      return (decodedData: null, trailingData: Uint8List(0));
    }
    return (
      decodedData: output,
      trailingData: compressed.readBytes(compressed.remaining),
    );
  }

  /// Reads one signed Photoshop rectangle.
  static PsRectangle _readRectangle(PsBinaryReader reader) => PsRectangle(
    top: reader.readInt32(),
    left: reader.readInt32(),
    bottom: reader.readInt32(),
    right: reader.readInt32(),
  );

  /// Reads a big-endian length-prefixed UTF-16 string.
  static String _readUnicodeString(
    PsBinaryReader reader, {
    required int maxCodeUnits,
  }) {
    final int length = reader.readUint32();
    if (length > maxCodeUnits) {
      throw PsFormatException(
        message: 'Pattern Unicode string length $length exceeds the configured $maxCodeUnits code-unit limit',
        source: reader.bytes,
        offset: reader.baseOffset + reader.offset - 4,
      );
    }
    if (length > reader.remaining ~/ 2) {
      throw PsFormatException(
        message: 'Pattern Unicode string length $length exceeds the available data',
        source: reader.bytes,
        offset: reader.baseOffset + reader.offset - 4,
      );
    }
    final String value = String.fromCharCodes(<int>[
      for (int index = 0; index < length; index++) reader.readUint16(),
    ]);
    return _trimTerminalNulls(value);
  }

  /// Removes only terminal null characters from [value].
  static String _trimTerminalNulls(String value) {
    int end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return value.substring(0, end);
  }

  /// Tests whether a plausible versioned virtual-memory header begins after [relativeOffset].
  static bool _looksLikeVirtualMemoryArray(PsBinaryReader reader, {required int relativeOffset}) {
    if (relativeOffset < 0 || relativeOffset + 8 > reader.remaining) {
      return false;
    }
    final ByteData data = ByteData.sublistView(reader.bytes);
    final int offset = reader.offset + relativeOffset;
    final int version = data.getUint32(offset);
    final int length = data.getUint32(offset + 4);
    return version == 3 && length <= reader.remaining - relativeOffset - 8;
  }

  /// Reports a recoverable compatibility [message] when a handler is installed.
  static void _issue(PsPatternIssueHandler? handler, String message, int offset) => handler?.call(message, offset);
}

/// Decodes four-byte-aligned length-prefixed pattern records from Photoshop blocks.
abstract final class PsPatternBlockDecoder {
  /// Decodes every complete record remaining in [reader].
  static PsPatternBlockDecodeResult decodeAll({
    required PsBinaryReader reader,
    required int maxPatterns,
    PsPatternDecodeOptions options = const PsPatternDecodeOptions(),
    PsPatternIssueHandler? onIssue,
    PsPatternDecodedBytesGuard? onDecodedBytesRequired,
  }) {
    final List<PsPattern> patterns = <PsPattern>[];
    int decodedBytes = 0;
    while (!reader.isAtEnd) {
      final int recordOffset = reader.baseOffset + reader.offset;
      if (patterns.length >= maxPatterns) {
        throw PsFormatException(message: 'Pattern count exceeds the configured $maxPatterns limit', source: reader.bytes, offset: recordOffset);
      }
      if (reader.remaining < 4) {
        onIssue?.call('Truncated pattern length field', recordOffset);
        break;
      }
      final int payloadLength = reader.readUint32();
      if (payloadLength == 0 || payloadLength > reader.remaining) {
        onIssue?.call('Pattern length $payloadLength exceeds the block bounds', recordOffset);
        break;
      }
      final PsBinaryReader record = reader.readReader(payloadLength);
      try {
        final PsPatternDecodeResult result = PsPatternRecordDecoder.decode(
          reader: record,
          kind: PsPatternRecordKind.embedded,
          options: options.copyWith(maxDecodedBytes: options.maxDecodedBytes - decodedBytes),
          onIssue: onIssue,
          onDecodedBytesRequired: onDecodedBytesRequired == null ? null : (bytes, offset) => onDecodedBytesRequired(decodedBytes + bytes, offset),
        );
        patterns.add(result.pattern);
        decodedBytes += result.decodedBytes;
      } on PsFormatException catch (error) {
        onIssue?.call('Skipped malformed pattern: ${error.message}', error.offset ?? recordOffset);
      }
      final int padding = (4 - payloadLength % 4) % 4;
      if (padding <= reader.remaining) {
        reader.skip(padding);
      } else if (!reader.isAtEnd) {
        onIssue?.call('Truncated four-byte padding after pattern record', reader.baseOffset + reader.offset);
        reader.skip(reader.remaining);
      }
    }
    return PsPatternBlockDecodeResult(patterns: patterns, decodedBytes: decodedBytes);
  }
}
