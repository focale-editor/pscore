import 'dart:typed_data';

import 'package:pscore/src/exceptions.dart';

/// Bounds-checked big-endian input used by Photoshop format parsers.
final class PsBinaryReader {
  /// Bytes exposed by this reader.
  final Uint8List bytes;

  /// Absolute offset represented by local offset zero.
  final int baseOffset;

  /// Big-endian view used for numeric reads.
  final ByteData _data;

  /// Current position relative to [bytes].
  int _offset = 0;

  /// Creates a reader over [bytes].
  PsBinaryReader({
    required this.bytes,
    this.baseOffset = 0,
  }) : _data = ByteData.sublistView(bytes);

  /// Current local offset.
  int get offset => _offset;

  /// Bytes that have not been consumed.
  int get remaining => bytes.length - _offset;

  /// Whether the complete bounded input has been consumed.
  bool get isAtEnd => _offset == bytes.length;

  /// Reads an unsigned byte.
  int readUint8() {
    _require(1);
    return _data.getUint8(_offset++);
  }

  /// Reads a signed 16-bit integer.
  int readInt16() {
    _require(2);
    final int value = _data.getInt16(_offset);
    _offset += 2;
    return value;
  }

  /// Reads an unsigned 16-bit integer.
  int readUint16() {
    _require(2);
    final int value = _data.getUint16(_offset);
    _offset += 2;
    return value;
  }

  /// Reads a signed 32-bit integer.
  int readInt32() {
    _require(4);
    final int value = _data.getInt32(_offset);
    _offset += 4;
    return value;
  }

  /// Reads an unsigned 32-bit integer.
  int readUint32() {
    _require(4);
    final int value = _data.getUint32(_offset);
    _offset += 4;
    return value;
  }

  /// Reads an unsigned 64-bit integer.
  int readUint64() {
    _require(8);
    final int value = _data.getUint64(_offset);
    _offset += 8;
    return value;
  }

  /// Reads a signed 64-bit integer.
  int readInt64() {
    _require(8);
    final int value = _data.getInt64(_offset);
    _offset += 8;
    return value;
  }

  /// Reads a big-endian single-precision floating-point value.
  double readFloat32() {
    _require(4);
    final double value = _data.getFloat32(_offset);
    _offset += 4;
    return value;
  }

  /// Reads a big-endian double-precision floating-point value.
  double readFloat64() {
    _require(8);
    final double value = _data.getFloat64(_offset);
    _offset += 8;
    return value;
  }

  /// Reads a fixed-length Latin-1 string.
  String readString(int length) {
    final Uint8List value = readBytes(length);
    return String.fromCharCodes(value);
  }

  /// Reads and copies [length] bytes.
  Uint8List readBytes(int length) {
    _require(length);
    final Uint8List value = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(value);
  }

  /// Reads a zero-copy view of the next [length] bytes.
  Uint8List readView(int length) {
    _require(length);
    final Uint8List value = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  /// Creates a bounded reader for the next [length] bytes.
  PsBinaryReader readReader(int length) {
    final int absoluteOffset = baseOffset + _offset;
    return PsBinaryReader(bytes: readView(length), baseOffset: absoluteOffset);
  }

  /// Advances over [length] bytes.
  void skip(int length) {
    _require(length);
    _offset += length;
  }

  /// Reads a length after checking it is representable and in bounds.
  int readLength({required bool wide, String label = 'section'}) {
    final int value = wide ? readUint64() : readUint32();
    if (value < 0) {
      // A 64-bit field above the signed maximum reads back negative, which would
      // otherwise surface later as a confusing end-of-input error.
      throw PsFormatException(message: '$label length does not fit a signed 64-bit integer', source: bytes, offset: baseOffset + _offset);
    }
    if (value > remaining) {
      throw PsFormatException(message: '$label length $value exceeds the $remaining remaining bytes', source: bytes, offset: baseOffset + _offset);
    }
    return value;
  }

  /// Ensures that [length] bytes remain before a read or skip.
  void _require(int length) {
    if (length < 0 || length > remaining) {
      throw PsFormatException(message: 'Unexpected end of file: need $length bytes, have $remaining', source: bytes, offset: baseOffset + _offset);
    }
  }
}

/// Growable big-endian output used by the PSD writer.
///
/// Scalars are written straight into one reusable buffer, so encoding a large
/// structure costs no allocation per field.
final class PsBinaryWriter {
  /// Smallest buffer allocated for the first write.
  static const int _minimumCapacity = 256;

  /// Backing buffer, which is larger than [length] while it has spare capacity.
  Uint8List _bytes;

  /// Big-endian view used for numeric writes.
  ByteData _data;

  /// Number of bytes written so far.
  int _length = 0;

  /// Creates a writer whose buffer starts at [initialCapacity] bytes.
  ///
  /// Sizing the buffer up front avoids the copies that repeated growth costs
  /// when the encoded length is already known.
  PsBinaryWriter({
    int initialCapacity = _minimumCapacity,
  }) : this._(Uint8List(initialCapacity < 0 ? _minimumCapacity : initialCapacity));

  /// Creates a writer over an already allocated [_bytes] buffer.
  PsBinaryWriter._(this._bytes) : _data = ByteData.sublistView(_bytes);

  /// Number of bytes written.
  int get length => _length;

  /// Writes an unsigned byte.
  void writeUint8(int value) {
    _reserve(1);
    _bytes[_length++] = value;
  }

  /// Writes a signed 16-bit integer.
  void writeInt16(int value) {
    _reserve(2);
    _data.setInt16(_length, value);
    _length += 2;
  }

  /// Writes an unsigned 16-bit integer.
  void writeUint16(int value) {
    _reserve(2);
    _data.setUint16(_length, value);
    _length += 2;
  }

  /// Writes a signed 32-bit integer.
  void writeInt32(int value) {
    _reserve(4);
    _data.setInt32(_length, value);
    _length += 4;
  }

  /// Writes an unsigned 32-bit integer.
  void writeUint32(int value) {
    _reserve(4);
    _data.setUint32(_length, value);
    _length += 4;
  }

  /// Writes an unsigned 64-bit integer.
  void writeUint64(int value) {
    _reserve(8);
    _data.setUint64(_length, value);
    _length += 8;
  }

  /// Writes a signed 64-bit integer.
  void writeInt64(int value) {
    _reserve(8);
    _data.setInt64(_length, value);
    _length += 8;
  }

  /// Writes a big-endian single-precision floating-point value.
  void writeFloat32(double value) {
    _reserve(4);
    _data.setFloat32(_length, value);
    _length += 4;
  }

  /// Writes a big-endian double-precision floating-point value.
  void writeFloat64(double value) {
    _reserve(8);
    _data.setFloat64(_length, value);
    _length += 8;
  }

  /// Writes a fixed-size character string.
  ///
  /// Only the low byte of each code unit is written, so callers must validate
  /// that [value] is Latin-1 before writing a field Photoshop reads back.
  void writeString(String value) => writeBytes(value.codeUnits);

  /// Appends arbitrary bytes.
  void writeBytes(List<int> value) {
    _reserve(value.length);
    _bytes.setRange(_length, _length + value.length, value);
    _length += value.length;
  }

  /// Writes every code unit of [value] as a big-endian 16-bit integer.
  ///
  /// Writing UTF-16 text in one call avoids a per-code-unit method call, which
  /// dominates encoding long descriptor strings.
  void writeUint16List(List<int> value) {
    _reserve(value.length * 2);
    int offset = _length;
    for (final int unit in value) {
      _data.setUint16(offset, unit);
      offset += 2;
    }
    _length = offset;
  }

  /// Writes zero padding.
  void writeZeros(int count) {
    _reserve(count);
    _bytes.fillRange(_length, _length + count, 0);
    _length += count;
  }

  /// Writes either a 32-bit or 64-bit section length.
  void writeLength(int value, {required bool wide}) {
    if (wide) {
      writeUint64(value);
    } else {
      writeUint32(value);
    }
  }

  /// Returns all written bytes and resets this writer.
  Uint8List takeBytes() {
    final Uint8List result = _length == _bytes.length
        ? _bytes
        : _length * 2 < _bytes.length
        ? Uint8List.fromList(Uint8List.sublistView(_bytes, 0, _length))
        : Uint8List.sublistView(_bytes, 0, _length);
    _bytes = Uint8List(0);
    _data = ByteData.sublistView(_bytes);
    _length = 0;
    return result;
  }

  /// Ensures the buffer can hold [count] more bytes, growing it geometrically.
  void _reserve(int count) {
    if (count < 0) {
      throw PsWriteException(message: 'Cannot write a negative byte count of $count');
    }
    final int required = _length + count;
    if (required <= _bytes.length) {
      return;
    }
    int capacity = _bytes.length < _minimumCapacity ? _minimumCapacity : _bytes.length;
    while (capacity < required) {
      capacity *= 2;
    }
    final Uint8List grown = Uint8List(capacity);
    grown.setRange(0, _length, _bytes);
    _bytes = grown;
    _data = ByteData.sublistView(grown);
  }
}
