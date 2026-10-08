import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// A format-specific error mirroring how format packages extend the base.
final class _KitFormatException extends PsFormatException {
  /// Creates an error at an optional byte [offset].
  const _KitFormatException({required super.message, super.offset});

  @override
  String get typeName => 'KitFormatException';
}

/// A format-specific warning carrying one extra context field.
final class _KitWarning extends PsWarning {
  /// Zero-based preset position associated with the issue.
  final int? presetIndex;

  /// Creates a warning with optional source context.
  const _KitWarning({required super.message, super.offset, this.presetIndex});

  @override
  String get typeName => 'KitWarning';

  @override
  String get context {
    final int? index = presetIndex;
    return index == null ? '' : ' in preset ${index + 1}';
  }
}

/// Exercises the shared exception and warning hierarchy.
void main() {
  test('format-specific errors are caught as shared errors', () {
    Object? caught;
    try {
      throw const _KitFormatException(message: 'Broken header', offset: 4);
    } on PsFormatException catch (error) {
      caught = error;
    }

    check(caught).isA<FormatException>();
    check(caught.toString()).equals('KitFormatException at byte 4: Broken header');
  });

  test('shared errors keep their own type name', () {
    check(const PsFormatException(message: 'Bad').toString()).equals('PsFormatException: Bad');
    check(const PsWriteException(message: 'Too large').toString()).equals('PsWriteException: Too large');
  });

  test('warnings combine offset and format-specific context', () {
    check(const _KitWarning(message: 'Skipped', offset: 12, presetIndex: 2).toString()).equals('KitWarning at byte 12 in preset 3: Skipped');
    check(const _KitWarning(message: 'Skipped').toString()).equals('KitWarning: Skipped');
  });
}
