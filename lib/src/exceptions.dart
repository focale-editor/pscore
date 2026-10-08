/// Reports malformed, truncated, or unsupported Photoshop-format input.
///
/// Format packages extend this class with their own exception type, so one
/// `on PsFormatException` clause catches decoding errors from any of them.
base class PsFormatException implements FormatException {
  /// Human-readable explanation of the malformed data.
  @override
  final String message;

  /// Input object associated with the failure, when available.
  @override
  final Object? source;

  /// Absolute byte offset associated with the failure, when available.
  @override
  final int? offset;

  /// Creates an error at an optional byte [offset].
  const PsFormatException({
    required this.message,
    this.source,
    this.offset,
  });

  /// Type name shown by [toString].
  String get typeName => 'PsFormatException';

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return '$typeName$location: $message';
  }
}

/// Reports data that cannot be represented by a requested Photoshop format.
///
/// Format packages extend this class with their own exception type, so one
/// `on PsWriteException` clause catches encoding errors from any of them.
base class PsWriteException implements Exception {
  /// Explains why encoding failed.
  final String message;

  /// Creates an error with a user-facing [message].
  const PsWriteException({
    required this.message,
  });

  /// Type name shown by [toString].
  String get typeName => 'PsWriteException';

  @override
  String toString() => '$typeName: $message';
}

/// Describes a recoverable compatibility issue found while decoding.
///
/// Format packages extend this class with the source context they track, such
/// as the index of the preset being decoded.
abstract base class PsWarning {
  /// Human-readable explanation of the compatibility issue.
  final String message;

  /// Absolute byte offset associated with the issue, when known.
  final int? offset;

  /// Creates a warning at an optional absolute byte [offset].
  const PsWarning({
    required this.message,
    this.offset,
  });

  /// Type name shown by [toString].
  String get typeName;

  /// Source context shown by [toString] after the byte offset, such as
  /// `' in pattern 2'`, or an empty string.
  String get context => '';

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return '$typeName$location$context: $message';
  }
}
