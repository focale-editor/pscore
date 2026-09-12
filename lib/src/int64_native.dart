import 'dart:typed_data';

/// Largest integer this platform represents exactly.
const int psMaxExactInteger = 0x7fffffffffffffff;

/// Smallest integer this platform represents exactly.
const int psMinExactInteger = -0x8000000000000000;

/// Reads a big-endian unsigned 64-bit integer at [byteOffset].
///
/// Returns `null` when the stored value is not exactly representable, which
/// cannot happen on a platform with native 64-bit integers. Values above the
/// signed maximum read back negative, exactly as `ByteData` reports them.
int? psGetUint64(ByteData data, int byteOffset) => data.getUint64(byteOffset);

/// Reads a big-endian signed 64-bit integer at [byteOffset].
///
/// Returns `null` when the stored value is not exactly representable, which
/// cannot happen on a platform with native 64-bit integers.
int? psGetInt64(ByteData data, int byteOffset) => data.getInt64(byteOffset);

/// Writes [value] as a big-endian unsigned 64-bit integer at [byteOffset].
///
/// Returns whether [value] was representable, which is always true here.
bool psSetUint64(ByteData data, int byteOffset, int value) {
  data.setUint64(byteOffset, value);
  return true;
}

/// Writes [value] as a big-endian signed 64-bit integer at [byteOffset].
///
/// Returns whether [value] was representable, which is always true here.
bool psSetInt64(ByteData data, int byteOffset, int value) {
  data.setInt64(byteOffset, value);
  return true;
}
