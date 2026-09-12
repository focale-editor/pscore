import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/descriptor.dart';
import 'package:pscore/src/exceptions.dart';

/// A Photoshop Action Descriptor preceded by its 32-bit format version.
final class PsVersionedDescriptor {
  /// Descriptor format version, normally 16.
  final int version;

  /// Complete Action Descriptor.
  final PsDescriptor descriptor;

  /// Creates a versioned descriptor.
  const PsVersionedDescriptor({
    this.version = 16,
    required this.descriptor,
  });
}

/// Encodes and decodes 32-bit-versioned Photoshop Action Descriptors.
abstract final class PsVersionedDescriptorCodec {
  /// Decodes one complete versioned descriptor.
  static PsVersionedDescriptor decode(
    Uint8List bytes, {
    int? expectedVersion,
    PsDescriptorDecodeOptions options = const PsDescriptorDecodeOptions(),
  }) {
    final ({PsVersionedDescriptor value, int bytesRead}) decoded = decodePrefix(
      bytes,
      expectedVersion: expectedVersion,
      options: options,
    );
    if (decoded.bytesRead != bytes.length) {
      throw PsFormatException(
        message: 'Unexpected bytes after versioned Action Descriptor',
        source: bytes,
        offset: decoded.bytesRead,
      );
    }
    return decoded.value;
  }

  /// Decodes one versioned descriptor from the start of [bytes].
  static ({PsVersionedDescriptor value, int bytesRead}) decodePrefix(
    Uint8List bytes, {
    int? expectedVersion,
    PsDescriptorDecodeOptions options = const PsDescriptorDecodeOptions(),
  }) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final PsVersionedDescriptor value = read(
      reader,
      expectedVersion: expectedVersion,
      options: options,
    );
    return (value: value, bytesRead: reader.offset);
  }

  /// Reads one versioned descriptor at the current [reader] position.
  static PsVersionedDescriptor read(
    PsBinaryReader reader, {
    int? expectedVersion,
    PsDescriptorDecodeOptions options = const PsDescriptorDecodeOptions(),
  }) {
    final int versionOffset = reader.baseOffset + reader.offset;
    final int version = reader.readUint32();
    if (expectedVersion != null && version != expectedVersion) {
      throw PsFormatException(
        message: 'Action Descriptor version $version does not match expected version $expectedVersion',
        source: reader.bytes,
        offset: versionOffset,
      );
    }
    return PsVersionedDescriptor(
      version: version,
      descriptor: PsDescriptorCodec.decodeReader(reader, options: options),
    );
  }

  /// Encodes [value] without an outer length or alignment field.
  static Uint8List encode(PsVersionedDescriptor value) {
    final PsBinaryWriter writer = PsBinaryWriter();
    write(writer, value);
    return writer.takeBytes();
  }

  /// Writes [value] at the current [writer] position.
  static void write(PsBinaryWriter writer, PsVersionedDescriptor value) {
    if (value.version < 0 || value.version > 0xffffffff) {
      throw PsWriteException(
        message: 'Action Descriptor version ${value.version} does not fit an unsigned 32-bit field',
      );
    }
    writer
      ..writeUint32(value.version)
      ..writeBytes(PsDescriptorCodec.encode(value.descriptor));
  }
}
