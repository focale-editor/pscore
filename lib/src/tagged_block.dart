import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';

/// Determines whether one Photoshop tagged block uses a 64-bit length.
typedef PsTaggedBlockWideLengthResolver = bool Function(String signature, String key);

/// One Photoshop tagged block with loss-preserving source metadata.
final class PsTaggedBlock {
  /// Four-byte Photoshop signature, normally `8BIM` or `8B64`.
  final String signature;

  /// Four-byte block key.
  final String key;

  /// Absolute offset of the block signature, or `-1` for authored data.
  final int offset;

  /// Payload length exactly as declared in the block header.
  final int declaredLength;

  /// Unpadded payload, or an empty list when preservation was disabled.
  final Uint8List data;

  /// Number of payload bytes physically available in the decoded input.
  final int dataByteCount;

  /// Optional alignment bytes following the payload.
  final Uint8List paddingData;

  /// Creates an immutable tagged block.
  PsTaggedBlock({
    required this.signature,
    required this.key,
    this.offset = -1,
    int? declaredLength,
    required Uint8List data,
    int? dataByteCount,
    Uint8List? paddingData,
  }) : declaredLength = declaredLength ?? data.length,
       dataByteCount = dataByteCount ?? data.length,
       data = Uint8List.fromList(data).asUnmodifiableView(),
       paddingData = Uint8List.fromList(paddingData ?? Uint8List(0)).asUnmodifiableView();

  /// Whether every byte declared by the header was available.
  bool get isComplete => dataByteCount == declaredLength;
}

/// A decoded tagged-block header whose payload has not yet been consumed.
final class PsTaggedBlockHeader {
  /// Four-byte Photoshop signature.
  final String signature;

  /// Four-byte block key.
  final String key;

  /// Absolute offset of the signature.
  final int offset;

  /// Declared payload length.
  final int declaredLength;

  /// Whether the length occupied eight bytes.
  final bool usesWideLength;

  /// Creates immutable header metadata.
  const PsTaggedBlockHeader({
    required this.signature,
    required this.key,
    required this.offset,
    required this.declaredLength,
    required this.usesWideLength,
  });

  /// Absolute offset at which the payload begins.
  int get payloadOffset => offset + (usesWideLength ? 16 : 12);
}

/// Reads, writes, and recognizes Photoshop tagged-block framing.
abstract final class PsTaggedBlockCodec {
  /// Signatures conventionally used by Photoshop tagged blocks.
  static const Set<String> standardSignatures = <String>{'8BIM', '8B64'};

  /// Tests whether a supported signature starts at [relativeOffset].
  static bool hasSignature(
    PsBinaryReader reader, {
    int relativeOffset = 0,
    Set<String> signatures = standardSignatures,
  }) {
    if (relativeOffset < 0 || reader.remaining < relativeOffset + 4) {
      return false;
    }
    final int offset = reader.offset + relativeOffset;
    final String signature = String.fromCharCodes(
      Uint8List.sublistView(reader.bytes, offset, offset + 4),
    );
    return signatures.contains(signature);
  }

  /// Returns whether the current standard signature selects a 64-bit length.
  static bool usesWideLengthSignature(PsBinaryReader reader) => hasSignature(
    reader,
    signatures: const <String>{'8B64'},
  );

  /// Reads one tagged-block header and leaves [reader] at its payload.
  static PsTaggedBlockHeader readHeader(
    PsBinaryReader reader, {
    Set<String> signatures = standardSignatures,
    PsTaggedBlockWideLengthResolver wideLengthResolver = _wideBySignature,
    int maxPayloadBytes = 0x7fffffffffffffff,
  }) {
    final int offset = reader.baseOffset + reader.offset;
    final String signature = reader.readString(4);
    if (!signatures.contains(signature)) {
      throw PsFormatException(
        message: 'Unsupported tagged-block signature "$signature"',
        source: reader.bytes,
        offset: offset,
      );
    }
    final String key = reader.readString(4);
    final bool wide = wideLengthResolver(signature, key);
    final int declaredLength = wide ? reader.readUint64() : reader.readUint32();
    if (declaredLength < 0) {
      // A 64-bit length above the signed maximum reads back negative.
      throw PsFormatException(
        message: 'Tagged block $key length does not fit a signed 64-bit integer',
        source: reader.bytes,
        offset: offset + 8,
      );
    }
    if (declaredLength > maxPayloadBytes) {
      throw PsFormatException(
        message: 'Tagged block $key length $declaredLength exceeds the configured $maxPayloadBytes byte limit',
        source: reader.bytes,
        offset: offset + 8,
      );
    }
    return PsTaggedBlockHeader(
      signature: signature,
      key: key,
      offset: offset,
      declaredLength: declaredLength,
      usesWideLength: wide,
    );
  }

  /// Returns optional zero padding before the next recognizable block.
  static int paddingLength(
    PsBinaryReader reader, {
    required int payloadLength,
    int alignment = 4,
    Set<String> signatures = standardSignatures,
  }) {
    if (alignment <= 1 || hasSignature(reader, signatures: signatures)) {
      return 0;
    }
    final int expectedLength = (alignment - payloadLength % alignment) % alignment;
    if (expectedLength == 0 || reader.remaining < expectedLength || !_allZero(reader, expectedLength)) {
      return 0;
    }
    return reader.remaining == expectedLength || hasSignature(reader, relativeOffset: expectedLength, signatures: signatures) ? expectedLength : 0;
  }

  /// Encodes one tagged block into a new byte buffer.
  static Uint8List encode(
    PsTaggedBlock block, {
    PsTaggedBlockWideLengthResolver wideLengthResolver = _wideBySignature,
    int alignment = 4,
    bool preserveDeclaredLength = false,
    bool preservePadding = false,
  }) {
    final PsBinaryWriter writer = PsBinaryWriter();
    write(
      writer,
      block,
      wideLengthResolver: wideLengthResolver,
      alignment: alignment,
      preserveDeclaredLength: preserveDeclaredLength,
      preservePadding: preservePadding,
    );
    return writer.takeBytes();
  }

  /// Writes one tagged block at the current [writer] position.
  static void write(
    PsBinaryWriter writer,
    PsTaggedBlock block, {
    PsTaggedBlockWideLengthResolver wideLengthResolver = _wideBySignature,
    int alignment = 4,
    bool preserveDeclaredLength = false,
    bool preservePadding = false,
  }) {
    _requireFourCharacters(block.signature, 'Tagged-block signature');
    _requireFourCharacters(block.key, 'Tagged-block key');
    final bool wide = wideLengthResolver(block.signature, block.key);
    final int length = preserveDeclaredLength ? block.declaredLength : block.data.length;
    final int maximum = wide ? 0x7fffffffffffffff : 0xffffffff;
    if (length < 0 || length > maximum) {
      throw PsWriteException(
        message: 'Tagged block ${block.key} length $length does not fit its ${wide ? 64 : 32}-bit field',
      );
    }
    writer
      ..writeString(block.signature)
      ..writeString(block.key)
      ..writeLength(length, wide: wide)
      ..writeBytes(block.data);
    if (preservePadding) {
      writer.writeBytes(block.paddingData);
    } else if (alignment > 1) {
      writer.writeZeros((alignment - block.data.length % alignment) % alignment);
    }
  }

  /// Tests whether the first [length] remaining bytes are all zero.
  static bool _allZero(PsBinaryReader reader, int length) {
    for (int index = 0; index < length; index++) {
      if (reader.bytes[reader.offset + index] != 0) {
        return false;
      }
    }
    return true;
  }

  /// Requires a fixed-size one-byte character string.
  static void _requireFourCharacters(String value, String label) {
    if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
      throw PsWriteException(
        message: '$label must contain exactly four Latin-1 characters',
      );
    }
  }
}

/// Selects wide lengths for the standard `8B64` signature.
bool _wideBySignature(String signature, String key) => signature == '8B64';
