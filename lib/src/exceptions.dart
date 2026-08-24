/// Reports malformed, truncated, or unsupported Photoshop-format input.
final class PsFormatException implements FormatException {
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

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return 'PsFormatException$location: $message';
  }
}

/// Reports data that cannot be represented by a requested Photoshop format.
final class PsWriteException implements Exception {
  /// Explains why encoding failed.
  final String message;

  /// Creates an error with a user-facing [message].
  const PsWriteException({
    required this.message,
  });

  @override
  String toString() => 'PsWriteException: $message';
}
