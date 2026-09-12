import 'dart:typed_data';

import 'package:pscore/src/descriptor.dart';

/// Selects whether descriptor accessors accept compatible scalar encodings.
enum PsDescriptorAccessMode {
  /// Accepts only the descriptor types documented for each accessor.
  strict,

  /// Accepts common Photoshop substitutions such as integers for Booleans.
  compatible,
}

/// A descriptor number paired with its optional Photoshop unit identifier.
final class PsDescriptorNumber {
  /// Numeric payload.
  final double value;

  /// Four-character unit code, or `null` for an unqualified number.
  final String? unit;

  /// Creates an immutable numeric projection.
  const PsDescriptorNumber({
    required this.value,
    required this.unit,
  });
}

/// A Photoshop enumeration represented by its type and selected identifiers.
final class PsDescriptorEnumeration {
  /// Enumeration type identifier, or an empty string for a coerced text value.
  final String typeId;

  /// Selected enumeration identifier.
  final String value;

  /// Creates an immutable enumeration projection.
  const PsDescriptorEnumeration({
    required this.typeId,
    required this.value,
  });
}

/// Provides typed projections for an individual nullable descriptor value.
extension PsDescriptorValueAccess on PsDescriptorValue? {
  /// Returns this value as text with optional terminal-null removal.
  String? asString({bool trimTerminalNulls = true}) {
    final PsDescriptorValue? candidate = this;
    if (candidate is! PsStringValue) {
      return null;
    }
    return trimTerminalNulls ? _trimTerminalNulls(candidate.value) : candidate.value;
  }

  /// Returns this value as a Boolean.
  bool? asBoolean({PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict}) => switch (this) {
    PsBooleanValue(:final bool value) => value,
    PsIntegerValue(:final int value) when mode == PsDescriptorAccessMode.compatible => value != 0,
    PsLargeIntegerValue(:final int value) when mode == PsDescriptorAccessMode.compatible => value != 0,
    _ => null,
  };

  /// Returns this value as an integer.
  int? asInteger({PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict}) => switch (this) {
    PsIntegerValue(:final int value) => value,
    PsLargeIntegerValue(:final int value) => value,
    PsDoubleValue(:final double value) when mode == PsDescriptorAccessMode.compatible => value.round(),
    PsUnitFloatValue(:final double value) when mode == PsDescriptorAccessMode.compatible => value.round(),
    _ => null,
  };

  /// Returns this value as a number with its optional unit.
  PsDescriptorNumber? asNumber() => switch (this) {
    PsIntegerValue(:final int value) => PsDescriptorNumber(value: value.toDouble(), unit: null),
    PsLargeIntegerValue(:final int value) => PsDescriptorNumber(value: value.toDouble(), unit: null),
    PsDoubleValue(:final double value) => PsDescriptorNumber(value: value, unit: null),
    PsUnitFloatValue(:final String unit, :final double value) => PsDescriptorNumber(value: value, unit: unit),
    _ => null,
  };

  /// Returns this value as an enumeration.
  PsDescriptorEnumeration? asEnumeration({PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict}) => switch (this) {
    PsEnumeratedValue(:final String typeId, :final String value) => PsDescriptorEnumeration(typeId: typeId, value: value),
    PsStringValue(:final String value) when mode == PsDescriptorAccessMode.compatible => PsDescriptorEnumeration(typeId: '', value: _trimTerminalNulls(value)),
    _ => null,
  };

  /// Returns this value as a nested descriptor.
  PsDescriptor? asObject() => switch (this) {
    PsObjectValue(:final PsDescriptor value) => value,
    _ => null,
  };

  /// Returns nested descriptors from either one object or a list of objects.
  List<PsDescriptor> asObjects() => switch (this) {
    PsListValue(:final List<PsDescriptorValue> values) => List<PsDescriptor>.unmodifiable(<PsDescriptor>[
      for (final PsDescriptorValue value in values)
        if (value case PsObjectValue(:final PsDescriptor value)) value,
    ]),
    PsObjectValue(:final PsDescriptor value) => <PsDescriptor>[value],
    _ => const <PsDescriptor>[],
  };

  /// Returns this value as an object-array value.
  PsObjectArrayValue? asObjectArray() => switch (this) {
    final PsObjectArrayValue value => value,
    _ => null,
  };

  /// Returns this value as an ordered descriptor list.
  List<PsDescriptorValue>? asList() => switch (this) {
    PsListValue(:final List<PsDescriptorValue> values) => values,
    _ => null,
  };

  /// Returns this value as raw, alias, or path bytes.
  Uint8List? asBytes() => switch (this) {
    PsRawValue(:final Uint8List value) => value,
    PsAliasValue(:final Uint8List value) => value,
    PsPathValue(:final Uint8List value) => value,
    _ => null,
  };
}

/// Provides null-safe typed projections over Photoshop Action Descriptors.
extension PsDescriptorAccess on PsDescriptor {
  /// Returns the first value found under [keys], searching in argument order.
  PsDescriptorValue? firstValue(Iterable<String> keys) {
    for (final String key in keys) {
      final PsDescriptorValue? candidate = value(key);
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  /// Returns a text value with optional terminal-null removal.
  String? stringValue(
    String key, {
    bool trimTerminalNulls = true,
  }) => value(key).asString(trimTerminalNulls: trimTerminalNulls);

  /// Returns a Boolean stored under [key].
  bool? booleanValue(
    String key, {
    PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict,
  }) => value(key).asBoolean(mode: mode);

  /// Returns an integer stored under [key].
  int? integerValue(
    String key, {
    PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict,
  }) => value(key).asInteger(mode: mode);

  /// Returns a numeric value and its optional unit from [key].
  PsDescriptorNumber? numberValue(String key) => value(key).asNumber();

  /// Returns only the numeric payload stored under [key].
  double? scalarValue(String key) => numberValue(key)?.value;

  /// Returns an enumeration stored under [key].
  PsDescriptorEnumeration? enumerationValue(
    String key, {
    PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict,
  }) => value(key).asEnumeration(mode: mode);

  /// Returns only the selected enumeration identifier stored under [key].
  String? enumerationIdentifier(
    String key, {
    PsDescriptorAccessMode mode = PsDescriptorAccessMode.strict,
  }) => enumerationValue(key, mode: mode)?.value;

  /// Returns the nested descriptor stored under [key].
  PsDescriptor? objectValue(String key) => value(key).asObject();

  /// Returns object descriptors from either a list or a single object.
  List<PsDescriptor> objectValues(String key) => value(key).asObjects();

  /// Returns the object-array value stored under [key].
  PsObjectArrayValue? objectArrayValue(String key) => value(key).asObjectArray();

  /// Returns the ordered descriptor list stored under [key].
  List<PsDescriptorValue>? listValue(String key) => value(key).asList();

  /// Returns raw, alias, or path bytes stored under [key].
  Uint8List? bytesValue(String key) => value(key).asBytes();
}

/// Removes only terminal UTF-16 null code units from [value].
String _trimTerminalNulls(String value) {
  int end = value.length;
  while (end > 0 && value.codeUnitAt(end - 1) == 0) {
    end--;
  }
  return value.substring(0, end);
}
