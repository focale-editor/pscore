import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';

/// A Photoshop action descriptor containing ordered, typed items.
final class PsDescriptor {
  /// Human-readable class name, which is often empty.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Ordered descriptor items.
  final List<PsDescriptorItem> items;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates an action descriptor.
  const PsDescriptor({
    required this.name,
    required this.classId,
    this.items = const <PsDescriptorItem>[],
    this._compactClassId = true,
  });

  /// Returns the last item matching [key], when present.
  PsDescriptorValue? value(String key) {
    for (final PsDescriptorItem item in items.reversed) {
      if (item.key == key) {
        return item.value;
      }
    }
    return null;
  }

  /// Returns a copy where [key] contains [value].
  PsDescriptor withValue(String key, PsDescriptorValue value) {
    final List<PsDescriptorItem> updated = <PsDescriptorItem>[];
    bool replaced = false;
    for (final PsDescriptorItem item in items) {
      if (item.key == key) {
        if (!replaced) {
          updated.add(PsDescriptorItem(key: key, value: value, compactKey: item._compactKey));
        }
        replaced = true;
      } else {
        updated.add(item);
      }
    }
    if (!replaced) {
      updated.add(PsDescriptorItem(key: key, value: value));
    }
    return PsDescriptor(name: name, classId: classId, items: updated, compactClassId: _compactClassId);
  }
}

/// One keyed value inside a Photoshop action descriptor.
final class PsDescriptorItem {
  /// Photoshop key identifier.
  final String key;

  /// Typed value associated with [key].
  final PsDescriptorValue value;

  /// Whether [key] used the compact zero-length representation.
  final bool _compactKey;

  /// Creates a keyed descriptor item.
  const PsDescriptorItem({
    required this.key,
    required this.value,
    this._compactKey = true,
  });
}

/// Base type for Photoshop action-descriptor values.
sealed class PsDescriptorValue {
  /// Creates a typed descriptor value.
  const PsDescriptorValue();

  /// Four-character OSType stored before this value.
  String get type;
}

/// A one-byte descriptor Boolean.
final class PsBooleanValue extends PsDescriptorValue {
  /// Boolean payload.
  final bool value;

  /// Creates a Boolean descriptor value.
  const PsBooleanValue({
    required this.value,
  });

  @override
  String get type => 'bool';
}

/// A signed 32-bit descriptor integer.
final class PsIntegerValue extends PsDescriptorValue {
  /// Integer payload.
  final int value;

  /// Creates an integer descriptor value.
  const PsIntegerValue({
    required this.value,
  });

  @override
  String get type => 'long';
}

/// A signed 64-bit descriptor integer.
final class PsLargeIntegerValue extends PsDescriptorValue {
  /// Integer payload.
  final int value;

  /// Creates a large-integer descriptor value.
  const PsLargeIntegerValue({
    required this.value,
  });

  @override
  String get type => 'comp';
}

/// A double-precision descriptor number.
final class PsDoubleValue extends PsDescriptorValue {
  /// Numeric payload.
  final double value;

  /// Creates a double descriptor value.
  const PsDoubleValue({
    required this.value,
  });

  @override
  String get type => 'doub';
}

/// A double-precision number carrying a Photoshop unit code.
final class PsUnitFloatValue extends PsDescriptorValue {
  /// Four-character unit such as `#Pxl` or `#Pnt`.
  final String unit;

  /// Numeric payload expressed in [unit].
  final double value;

  /// Creates a unit-float descriptor value.
  const PsUnitFloatValue({
    required this.unit,
    required this.value,
  });

  @override
  String get type => 'UntF';
}

/// A list of double-precision values sharing a Photoshop unit code.
final class PsUnitFloatsValue extends PsDescriptorValue {
  /// Four-character unit such as `#Pxl` or `#Pnt`.
  final String unit;

  /// Numeric payloads expressed in [unit].
  final List<double> values;

  /// Creates a unit-floats descriptor value.
  const PsUnitFloatsValue({
    required this.unit,
    required this.values,
  });

  @override
  String get type => 'UnFl';
}

/// A UTF-16 Photoshop descriptor string.
final class PsStringValue extends PsDescriptorValue {
  /// String payload.
  final String value;

  /// Creates a string descriptor value.
  const PsStringValue({
    required this.value,
  });

  @override
  String get type => 'TEXT';
}

/// A pair of Photoshop type and enumeration identifiers.
final class PsEnumeratedValue extends PsDescriptorValue {
  /// Enumeration type identifier.
  final String typeId;

  /// Selected enumeration identifier.
  final String value;

  /// Whether [typeId] used the compact zero-length representation.
  final bool _compactTypeId;

  /// Whether [value] used the compact zero-length representation.
  final bool _compactValue;

  /// Creates an enumerated descriptor value.
  const PsEnumeratedValue({
    required this.typeId,
    required this.value,
    this._compactTypeId = true,
    this._compactValue = true,
  });

  @override
  String get type => 'enum';
}

/// A nested action descriptor.
final class PsObjectValue extends PsDescriptorValue {
  /// Nested descriptor payload.
  final PsDescriptor value;

  /// Whether this uses the global-object OSType.
  final bool global;

  /// Creates a nested descriptor value.
  const PsObjectValue({
    required this.value,
    this.global = false,
  });

  @override
  String get type => global ? 'GlbO' : 'Objc';
}

/// A descriptor-shaped object array with an explicit element count.
final class PsObjectArrayValue extends PsDescriptorValue {
  /// Number of logical array elements described by [value].
  final int itemsCount;

  /// Descriptor containing the array's column-oriented values.
  final PsDescriptor value;

  /// Creates an object-array descriptor value.
  const PsObjectArrayValue({
    required this.itemsCount,
    required this.value,
  });

  @override
  String get type => 'ObAr';
}

/// An ordered list of independently typed descriptor values.
final class PsListValue extends PsDescriptorValue {
  /// Ordered list payload.
  final List<PsDescriptorValue> values;

  /// Creates a descriptor list.
  const PsListValue({
    required this.values,
  });

  @override
  String get type => 'VlLs';
}

/// An ordered Photoshop object reference.
final class PsReferenceValue extends PsDescriptorValue {
  /// Ordered reference forms, from the broadest to the most specific.
  final List<PsDescriptorValue> values;

  /// Creates an object-reference descriptor value.
  const PsReferenceValue({
    required this.values,
  });

  @override
  String get type => 'obj ';
}

/// A property form inside a Photoshop object reference.
final class PsPropertyValue extends PsDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Referenced property identifier.
  final String keyId;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Whether [keyId] used the compact zero-length representation.
  final bool _compactKeyId;

  /// Creates a property-reference form.
  const PsPropertyValue({
    required this.name,
    required this.classId,
    required this.keyId,
    this._compactClassId = true,
    this._compactKeyId = true,
  });

  @override
  String get type => 'prop';
}

/// A class form inside a Photoshop object reference.
final class PsReferenceClassValue extends PsDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates a class-reference form.
  const PsReferenceClassValue({
    required this.name,
    required this.classId,
    this._compactClassId = true,
  });

  @override
  String get type => 'Clss';
}

/// An enumerated form inside a Photoshop object reference.
final class PsEnumeratedReferenceValue extends PsDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Enumeration type identifier.
  final String typeId;

  /// Selected enumeration identifier.
  final String value;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Whether [typeId] used the compact zero-length representation.
  final bool _compactTypeId;

  /// Whether [value] used the compact zero-length representation.
  final bool _compactValue;

  /// Creates an enumerated-reference form.
  PsEnumeratedReferenceValue({
    required this.name,
    required this.classId,
    required this.typeId,
    required this.value,
    this._compactClassId = true,
    this._compactTypeId = true,
    this._compactValue = true,
  });

  @override
  String get type => 'Enmr';
}

/// An offset form inside a Photoshop object reference.
final class PsOffsetValue extends PsDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Relative offset.
  final int value;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates an offset-reference form.
  const PsOffsetValue({
    required this.name,
    required this.classId,
    required this.value,
    this._compactClassId = true,
  });

  @override
  String get type => 'rele';
}

/// An integer identifier form inside a Photoshop object reference.
final class PsIdentifierValue extends PsDescriptorValue {
  /// Identifier payload.
  final int value;

  /// Creates an identifier-reference form.
  const PsIdentifierValue({
    required this.value,
  });

  @override
  String get type => 'Idnt';
}

/// An integer index form inside a Photoshop object reference.
final class PsIndexValue extends PsDescriptorValue {
  /// Index payload.
  final int value;

  /// Creates an index-reference form.
  const PsIndexValue({
    required this.value,
  });

  @override
  String get type => 'indx';
}

/// A Unicode name form inside a Photoshop object reference.
final class PsNameValue extends PsDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Referenced object name.
  final String value;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates a name-reference form.
  const PsNameValue({
    required this.name,
    required this.classId,
    required this.value,
    this._compactClassId = true,
  });

  @override
  String get type => 'name';
}

/// Opaque length-prefixed descriptor data.
final class PsRawValue extends PsDescriptorValue {
  /// Opaque bytes.
  final Uint8List value;

  /// Creates a raw-data descriptor value.
  PsRawValue({
    required this.value,
  });

  @override
  String get type => 'tdta';
}

/// Opaque length-prefixed platform alias data.
final class PsAliasValue extends PsDescriptorValue {
  /// Opaque alias bytes.
  final Uint8List value;

  /// Creates an alias descriptor value.
  PsAliasValue({
    required this.value,
  });

  @override
  String get type => 'alis';
}

/// Opaque length-prefixed Photoshop descriptor path data.
final class PsPathValue extends PsDescriptorValue {
  /// Opaque path bytes.
  final Uint8List value;

  /// Creates a descriptor path value.
  PsPathValue({
    required this.value,
  });

  @override
  String get type => 'Pth ';
}

/// A Photoshop class name and identifier.
final class PsClassValue extends PsDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Whether this uses the global-class OSType.
  final bool global;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates a class descriptor value.
  const PsClassValue({
    required this.name,
    required this.classId,
    this.global = false,
    this._compactClassId = true,
  });

  @override
  String get type => global ? 'GlbC' : 'type';
}

/// Resource limits applied while decoding an Action Descriptor.
final class PsDescriptorDecodeOptions {
  /// Maximum nested object depth.
  final int maxDepth;

  /// Maximum aggregate number of descriptor items and list values.
  final int maxValues;

  /// Creates bounded options suitable for untrusted Photoshop data.
  const PsDescriptorDecodeOptions({
    this.maxDepth = 64,
    this.maxValues = 1000000,
  });
}

/// Encodes and decodes Photoshop action descriptors.
abstract final class PsDescriptorCodec {
  /// Decodes one descriptor and requires all [bytes] to belong to it.
  static PsDescriptor decode(
    Uint8List bytes, {
    PsDescriptorDecodeOptions options = const PsDescriptorDecodeOptions(),
  }) {
    final ({PsDescriptor descriptor, int bytesRead}) decoded = decodePrefix(bytes, options: options);
    if (decoded.bytesRead != bytes.length) {
      throw PsFormatException(message: 'Unexpected bytes after action descriptor', source: bytes, offset: decoded.bytesRead);
    }
    return decoded.descriptor;
  }

  /// Decodes one descriptor from the beginning of [bytes].
  static ({PsDescriptor descriptor, int bytesRead}) decodePrefix(
    Uint8List bytes, {
    PsDescriptorDecodeOptions options = const PsDescriptorDecodeOptions(),
  }) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final PsDescriptor descriptor = decodeReader(reader, options: options);
    return (descriptor: descriptor, bytesRead: reader.offset);
  }

  /// Decodes one descriptor at the current position and advances [reader].
  static PsDescriptor decodeReader(
    PsBinaryReader reader, {
    PsDescriptorDecodeOptions options = const PsDescriptorDecodeOptions(),
  }) => _readDescriptor(reader, _PsDescriptorDecodeContext(options: options), 0);

  /// Encodes [descriptor] without an outer version or length field.
  static Uint8List encode(PsDescriptor descriptor) {
    final PsBinaryWriter writer = PsBinaryWriter();
    _writeDescriptor(writer, descriptor);
    return writer.takeBytes();
  }
}

/// Tracks descriptor recursion and aggregate collection sizes.
final class _PsDescriptorDecodeContext {
  /// Caller-selected resource limits.
  final PsDescriptorDecodeOptions options;

  /// Aggregate number of collection values accepted so far.
  int _values = 0;

  /// Creates a decode context using [options].
  _PsDescriptorDecodeContext({
    required this.options,
  });

  /// Rejects an object nested deeper than the configured bound.
  void checkDepth(PsBinaryReader reader, int depth) {
    if (depth > options.maxDepth) {
      throw PsFormatException(message: 'Action Descriptor depth $depth exceeds the configured ${options.maxDepth} limit', source: reader.bytes, offset: reader.baseOffset + reader.offset);
    }
  }

  /// Accounts [count] descriptor values before allocation or iteration.
  void addValues(PsBinaryReader reader, int count) {
    if (count < 0 || count > options.maxValues - _values) {
      throw PsFormatException(
        message: 'Action Descriptor value count exceeds the configured ${options.maxValues} limit',
        source: reader.bytes,
        offset: reader.baseOffset + reader.offset,
      );
    }
    _values += count;
  }
}

/// Reads one action descriptor from [reader].
PsDescriptor _readDescriptor(PsBinaryReader reader, _PsDescriptorDecodeContext context, int depth) {
  context.checkDepth(reader, depth);
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  final int count = reader.readUint32();
  context.addValues(reader, count);
  final List<PsDescriptorItem> items = <PsDescriptorItem>[];
  for (int index = 0; index < count; index++) {
    final ({String value, bool compact}) key = _readId(reader);
    final String type = reader.readString(4);
    items.add(PsDescriptorItem(key: key.value, value: _readValue(reader, type, context, depth), compactKey: key.compact));
  }
  return PsDescriptor(name: name, classId: classId.value, items: items, compactClassId: classId.compact);
}

/// Reads a descriptor value whose OSType is [type].
PsDescriptorValue _readValue(PsBinaryReader reader, String type, _PsDescriptorDecodeContext context, int depth) => switch (type) {
  'bool' => PsBooleanValue(value: reader.readUint8() != 0),
  'long' => PsIntegerValue(value: reader.readInt32()),
  'comp' => PsLargeIntegerValue(value: reader.readInt64()),
  'doub' => PsDoubleValue(value: reader.readFloat64()),
  'UntF' => PsUnitFloatValue(unit: reader.readString(4), value: reader.readFloat64()),
  'UnFl' => _readUnitFloatsValue(reader, context),
  'TEXT' => PsStringValue(value: _readUnicodeString(reader)),
  'enum' => _readEnumeratedValue(reader),
  'Objc' => PsObjectValue(value: _readDescriptor(reader, context, depth + 1)),
  'GlbO' => PsObjectValue(value: _readDescriptor(reader, context, depth + 1), global: true),
  'ObAr' => _readObjectArrayValue(reader, context, depth),
  'VlLs' => _readListValue(reader, context, depth, reference: false),
  'obj ' => _readListValue(reader, context, depth, reference: true),
  'prop' => _readPropertyValue(reader),
  'Clss' => _readReferenceClassValue(reader),
  'Enmr' => _readEnumeratedReferenceValue(reader),
  'rele' => _readOffsetValue(reader),
  'Idnt' => PsIdentifierValue(value: reader.readInt32()),
  'indx' => PsIndexValue(value: reader.readInt32()),
  'name' => _readNameValue(reader),
  'tdta' => PsRawValue(value: reader.readBytes(reader.readLength(wide: false, label: 'descriptor raw data'))),
  'alis' => PsAliasValue(value: reader.readBytes(reader.readLength(wide: false, label: 'descriptor alias'))),
  'Pth ' => PsPathValue(value: reader.readBytes(reader.readLength(wide: false, label: 'descriptor path'))),
  'type' => _readClassValue(reader, global: false),
  'GlbC' => _readClassValue(reader, global: true),
  _ => throw PsFormatException(message: 'Unsupported action-descriptor type "$type"', source: reader.bytes, offset: reader.baseOffset + reader.offset - 4),
};

/// Reads one unit-float array after accounting its element count.
PsUnitFloatsValue _readUnitFloatsValue(PsBinaryReader reader, _PsDescriptorDecodeContext context) {
  final String unit = reader.readString(4);
  final int count = reader.readUint32();
  context.addValues(reader, count);
  return PsUnitFloatsValue(
    unit: unit,
    values: <double>[for (int index = 0; index < count; index++) reader.readFloat64()],
  );
}

/// Reads a list or object-reference list after accounting its element count.
PsDescriptorValue _readListValue(PsBinaryReader reader, _PsDescriptorDecodeContext context, int depth, {required bool reference}) {
  final int count = reader.readUint32();
  context.addValues(reader, count);
  final List<PsDescriptorValue> values = <PsDescriptorValue>[
    for (int index = 0; index < count; index++) _readValue(reader, reader.readString(4), context, depth),
  ];
  return reference ? PsReferenceValue(values: values) : PsListValue(values: values);
}

/// Reads an object array and its column-oriented descriptor payload.
PsObjectArrayValue _readObjectArrayValue(PsBinaryReader reader, _PsDescriptorDecodeContext context, int depth) {
  final int itemsCount = reader.readUint32();
  context.addValues(reader, itemsCount);
  return PsObjectArrayValue(itemsCount: itemsCount, value: _readDescriptor(reader, context, depth + 1));
}

/// Writes [descriptor] without an outer version or length field.
void _writeDescriptor(PsBinaryWriter writer, PsDescriptor descriptor) {
  _writeUnicodeString(writer, descriptor.name);
  _writeId(writer, descriptor.classId, compact: descriptor._compactClassId);
  writer.writeUint32(descriptor.items.length);
  for (final PsDescriptorItem item in descriptor.items) {
    _writeId(writer, item.key, compact: item._compactKey);
    writer.writeString(item.value.type);
    _writeValue(writer, item.value);
  }
}

/// Writes one typed descriptor [value].
void _writeValue(PsBinaryWriter writer, PsDescriptorValue value) {
  switch (value) {
    case PsBooleanValue():
      writer.writeUint8(value.value ? 1 : 0);
    case PsIntegerValue():
      writer.writeInt32(value.value);
    case PsLargeIntegerValue():
      writer.writeInt64(value.value);
    case PsDoubleValue():
      writer.writeFloat64(value.value);
    case PsUnitFloatValue():
      _writeFourCharacters(writer, value.unit, 'descriptor unit');
      writer.writeFloat64(value.value);
    case PsUnitFloatsValue():
      _writeFourCharacters(writer, value.unit, 'descriptor unit');
      writer.writeUint32(value.values.length);
      value.values.forEach(writer.writeFloat64);
    case PsStringValue():
      _writeUnicodeString(writer, value.value);
    case PsEnumeratedValue():
      _writeId(writer, value.typeId, compact: value._compactTypeId);
      _writeId(writer, value.value, compact: value._compactValue);
    case PsObjectValue():
      _writeDescriptor(writer, value.value);
    case PsObjectArrayValue():
      writer.writeUint32(value.itemsCount);
      _writeDescriptor(writer, value.value);
    case PsListValue():
      writer.writeUint32(value.values.length);
      for (final PsDescriptorValue item in value.values) {
        writer.writeString(item.type);
        _writeValue(writer, item);
      }
    case PsReferenceValue():
      writer.writeUint32(value.values.length);
      for (final PsDescriptorValue item in value.values) {
        writer.writeString(item.type);
        _writeValue(writer, item);
      }
    case PsPropertyValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
      _writeId(writer, value.keyId, compact: value._compactKeyId);
    case PsReferenceClassValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
    case PsEnumeratedReferenceValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
      _writeId(writer, value.typeId, compact: value._compactTypeId);
      _writeId(writer, value.value, compact: value._compactValue);
    case PsOffsetValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
      writer.writeUint32(value.value);
    case PsIdentifierValue():
      writer.writeInt32(value.value);
    case PsIndexValue():
      writer.writeInt32(value.value);
    case PsNameValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
      _writeUnicodeString(writer, value.value);
    case PsRawValue():
      writer
        ..writeUint32(value.value.length)
        ..writeBytes(value.value);
    case PsAliasValue():
      writer
        ..writeUint32(value.value.length)
        ..writeBytes(value.value);
    case PsPathValue():
      writer
        ..writeUint32(value.value.length)
        ..writeBytes(value.value);
    case PsClassValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
  }
}

/// Reads a length-prefixed big-endian UTF-16 string.
String _readUnicodeString(PsBinaryReader reader) {
  final int length = reader.readUint32();
  if (length > reader.remaining ~/ 2) {
    throw const PsFormatException(message: 'Truncated descriptor Unicode string');
  }
  return String.fromCharCodes(<int>[for (int index = 0; index < length; index++) reader.readUint16()]);
}

/// Writes [value] as a length-prefixed big-endian UTF-16 string.
void _writeUnicodeString(PsBinaryWriter writer, String value) {
  writer.writeUint32(value.codeUnits.length);
  value.codeUnits.forEach(writer.writeUint16);
}

/// Reads a variable-length Photoshop identifier.
({String value, bool compact}) _readId(PsBinaryReader reader) {
  final int length = reader.readUint32();
  return (value: reader.readString(length == 0 ? 4 : length), compact: length == 0);
}

/// Writes a four-byte or length-prefixed Photoshop identifier.
void _writeId(PsBinaryWriter writer, String value, {required bool compact}) {
  if (compact && value.length == 4 && value.codeUnits.every((unit) => unit <= 0xff)) {
    writer
      ..writeUint32(0)
      ..writeString(value);
    return;
  }
  if (value.codeUnits.any((unit) => unit > 0xff)) {
    throw const PsWriteException(message: 'Descriptor identifiers must contain one-byte characters');
  }
  writer
    ..writeUint32(value.length)
    ..writeString(value);
}

/// Reads both identifiers in an enumerated descriptor value.
PsEnumeratedValue _readEnumeratedValue(PsBinaryReader reader) {
  final ({String value, bool compact}) typeId = _readId(reader);
  final ({String value, bool compact}) value = _readId(reader);
  return PsEnumeratedValue(
    typeId: typeId.value,
    value: value.value,
    compactTypeId: typeId.compact,
    compactValue: value.compact,
  );
}

/// Reads a class descriptor value and its identifier representation.
PsClassValue _readClassValue(PsBinaryReader reader, {required bool global}) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  return PsClassValue(name: name, classId: classId.value, global: global, compactClassId: classId.compact);
}

/// Reads a property reference and preserves both identifier encodings.
PsPropertyValue _readPropertyValue(PsBinaryReader reader) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  final ({String value, bool compact}) keyId = _readId(reader);
  return PsPropertyValue(
    name: name,
    classId: classId.value,
    keyId: keyId.value,
    compactClassId: classId.compact,
    compactKeyId: keyId.compact,
  );
}

/// Reads a class reference and preserves its identifier encoding.
PsReferenceClassValue _readReferenceClassValue(PsBinaryReader reader) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  return PsReferenceClassValue(name: name, classId: classId.value, compactClassId: classId.compact);
}

/// Reads an enumerated reference and preserves its identifier encodings.
PsEnumeratedReferenceValue _readEnumeratedReferenceValue(PsBinaryReader reader) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  final ({String value, bool compact}) typeId = _readId(reader);
  final ({String value, bool compact}) value = _readId(reader);
  return PsEnumeratedReferenceValue(
    name: name,
    classId: classId.value,
    typeId: typeId.value,
    value: value.value,
    compactClassId: classId.compact,
    compactTypeId: typeId.compact,
    compactValue: value.compact,
  );
}

/// Reads an offset reference and preserves its class identifier encoding.
PsOffsetValue _readOffsetValue(PsBinaryReader reader) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  return PsOffsetValue(name: name, classId: classId.value, value: reader.readUint32(), compactClassId: classId.compact);
}

/// Reads a name reference and preserves its class identifier encoding.
PsNameValue _readNameValue(PsBinaryReader reader) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  return PsNameValue(name: name, classId: classId.value, value: _readUnicodeString(reader), compactClassId: classId.compact);
}

/// Writes a required four-character descriptor code.
void _writeFourCharacters(PsBinaryWriter writer, String value, String label) {
  if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsWriteException(message: '$label must contain four one-byte characters');
  }
  writer.writeString(value);
}
