import 'dart:typed_data';

/// Largest integer this platform represents exactly.
///
/// JavaScript integers are doubles, so anything above two to the power of 53
/// minus one silently loses its low bits. The `ByteData` 64-bit accessors are
/// unavailable there, and these helpers replace them.
const int psMaxExactInteger = 0x1fffffffffffff;

/// Smallest integer this platform represents exactly.
const int psMinExactInteger = -0x20000000000000;

/// Number of distinct values in one 32-bit half.
const int _halfScale = 4294967296;

/// Largest high half whose composed value stays exactly representable.
const int _maximumHigh = 0x1fffff;

/// Smallest signed high half whose composed value stays exactly representable.
const int _minimumHigh = -0x200000;

/// Reads a big-endian unsigned 64-bit integer at [byteOffset].
///
/// Returns `null` when the stored value exceeds [psMaxExactInteger], because a
/// composed result would silently drop its low bits.
int? psGetUint64(ByteData data, int byteOffset) {
  final int high = data.getUint32(byteOffset);
  if (high > _maximumHigh) {
    return null;
  }
  return high * _halfScale + data.getUint32(byteOffset + 4);
}

/// Reads a big-endian signed 64-bit integer at [byteOffset].
///
/// Returns `null` when the stored value falls outside the exactly representable
/// range. Adding the unsigned low half to the signed high half reconstructs the
/// two's-complement value for negative numbers as well.
int? psGetInt64(ByteData data, int byteOffset) {
  final int high = data.getInt32(byteOffset);
  if (high > _maximumHigh || high < _minimumHigh) {
    return null;
  }
  return high * _halfScale + data.getUint32(byteOffset + 4);
}

/// Writes [value] as a big-endian unsigned 64-bit integer at [byteOffset].
///
/// Returns whether [value] was representable as an exact unsigned integer. A
/// negative [value] stores its low 64 bits, matching the native accessor so that
/// the platforms never disagree about a value JavaScript can represent.
bool psSetUint64(ByteData data, int byteOffset, int value) {
  if (value < 0) {
    return psSetInt64(data, byteOffset, value);
  }
  if (value > psMaxExactInteger) {
    return false;
  }
  data
    ..setUint32(byteOffset, value ~/ _halfScale)
    ..setUint32(byteOffset + 4, value % _halfScale);
  return true;
}

/// Writes [value] as a big-endian signed 64-bit integer at [byteOffset].
///
/// Returns whether [value] was representable as an exact signed integer.
bool psSetInt64(ByteData data, int byteOffset, int value) {
  if (value < psMinExactInteger || value > psMaxExactInteger) {
    return false;
  }
  // Flooring rather than truncating keeps the low half unsigned, which is what
  // the two's-complement byte layout stores for a negative value.
  final int high = (value / _halfScale).floor();
  data
    ..setInt32(byteOffset, high)
    ..setUint32(byteOffset + 4, value - high * _halfScale);
  return true;
}
