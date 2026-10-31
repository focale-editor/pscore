import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/src/exceptions.dart';

part 'engine_data_reader.dart';
part 'engine_data_writer.dart';

/// Resource bounds for Adobe EngineData and ATE text-engine structures.
final class PsEngineLimits {
  /// Maximum input or encoded output size.
  final int maxBytes;

  /// Maximum number of parsed or written values.
  final int maxNodes;

  /// Maximum dictionary and array nesting.
  final int maxDepth;

  /// Maximum decoded string length in bytes.
  final int maxStringBytes;

  /// Creates shared limits for PSD text and Illustrator ATE payloads.
  const PsEngineLimits({this.maxBytes = 128 * 1024 * 1024, this.maxNodes = 1000000, this.maxDepth = 64, this.maxStringBytes = 64 * 1024 * 1024});

  /// Rejects invalid resource policies before reading or writing.
  void validate() {
    if (maxBytes <= 0 || maxNodes <= 0 || maxDepth <= 0 || maxStringBytes <= 0) {
      throw ArgumentError('EngineData limits must be positive.');
    }
  }
}

/// One immutable text-engine value with optional original byte coordinates.
sealed class PsEngineValue {
  /// Inclusive source offset when read from a document.
  final int? start;

  /// Exclusive source offset when read from a document.
  final int? end;

  /// Creates a value; newly authored values need no source positions.
  const PsEngineValue({this.start, this.end});
}

/// An ordered text-engine dictionary with literal-name keys.
final class PsEngineDictionary extends PsEngineValue {
  /// Immutable values in original insertion order.
  final Map<String, PsEngineValue> values;

  /// Creates an owned dictionary snapshot.
  PsEngineDictionary({super.start, super.end, required Map<String, PsEngineValue> values}) : values = Map.unmodifiable(values);

  /// Looks up a key without coercing numeric names or missing fields.
  PsEngineValue? operator [](String key) => values[key];
}

/// An immutable text-engine array.
final class PsEngineArray extends PsEngineValue {
  /// Values in original order.
  final List<PsEngineValue> values;

  /// Creates an owned array snapshot.
  PsEngineArray({super.start, super.end, required List<PsEngineValue> values}) : values = List.unmodifiable(values);
}

/// A binary literal string whose raw CR/LF bytes are preserved.
final class PsEngineString extends PsEngineValue {
  /// Owned unescaped binary data.
  final Uint8List _bytes;

  /// Creates an engine string without guessing its encoding.
  PsEngineString({super.start, super.end, required List<int> bytes}) : _bytes = Uint8List.fromList(bytes) {
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('EngineData strings contain bytes only.');
    }
  }

  /// Encodes UTF-16 with an explicit byte-order marker.
  factory PsEngineString.fromText({required String text, Endian endian = Endian.big}) {
    final Uint8List bytes = Uint8List(2 + text.length * 2);
    final ByteData data = ByteData.sublistView(bytes)..setUint16(0, 0xfeff, endian);
    for (int index = 0; index < text.length; index++) {
      data.setUint16(2 + index * 2, text.codeUnitAt(index), endian);
    }
    return PsEngineString(bytes: bytes);
  }

  /// Immutable decoded bytes, including any byte-order marker.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Decodes BOM-marked UTF-16, using [fallback] for strings without a BOM.
  ///
  /// Odd UTF-16 lengths are rejected instead of truncating a final byte.
  String text({Encoding fallback = latin1}) {
    if (_bytes.length < 2 || !(_bytes[0] == 0xfe && _bytes[1] == 0xff || _bytes[0] == 0xff && _bytes[1] == 0xfe)) {
      return fallback.decode(_bytes);
    }
    if (_bytes.length.isOdd) {
      throw const PsFormatException(message: 'Odd UTF-16 EngineData string length.');
    }
    final Endian endian = _bytes[0] == 0xfe ? Endian.big : Endian.little;
    final ByteData data = ByteData.sublistView(_bytes);
    return String.fromCharCodes([for (int index = 2; index < _bytes.length; index += 2) data.getUint16(index, endian)]);
  }
}

/// A slash-prefixed name used as a value rather than a dictionary key.
final class PsEngineName extends PsEngineValue {
  /// Name bytes represented one-to-one as Latin-1 characters.
  final String value;

  /// Creates a literal name.
  const PsEngineName({super.start, super.end, required this.value});
}

/// A finite number with its original spelling retained when parsed.
final class PsEngineNumber extends PsEngineValue {
  /// Number exactly representable under the shared VM/JavaScript policy.
  final num value;

  /// Original numeric token, or null for a newly created value.
  final String? lexeme;

  /// Creates a portable numeric value.
  PsEngineNumber({super.start, super.end, required this.value, this.lexeme}) {
    if (!value.isFinite || value is int && value.abs() > _engineMaxInteger) {
      throw ArgumentError('EngineData numbers must be finite and portable.');
    }
  }
}

/// Largest integer represented exactly by every supported Dart target.
const int _engineMaxInteger = 9007199254740991;

/// A Boolean text-engine value.
final class PsEngineBoolean extends PsEngineValue {
  /// Boolean state.
  final bool value;

  /// Creates a Boolean value.
  const PsEngineBoolean({super.start, super.end, required this.value});
}

/// A null text-engine value.
final class PsEngineNull extends PsEngineValue {
  /// Creates a null value while retaining its source position.
  const PsEngineNull({super.start, super.end});
}

/// An uninterpreted bare token, including numbers outside portable precision.
final class PsEngineToken extends PsEngineValue {
  /// Original token without whitespace or delimiters.
  final String value;

  /// Preserves a future keyword without assigning semantics to it.
  const PsEngineToken({super.start, super.end, required this.value});
}

/// A source-preserving immutable Adobe text-engine document.
final class PsEngineDocument {
  /// Owned original source bytes.
  final Uint8List _bytes;

  /// Complete parsed root, usually a dictionary.
  final PsEngineValue root;

  /// Whether the root dictionary omits its outer `<<` and `>>` delimiters.
  final bool bareDictionary;

  /// Resource policy retained for edited copies.
  final PsEngineLimits limits;

  /// Reads a complete PSD or ATE payload, including optional bare dictionaries.
  factory PsEngineDocument.decode({required List<int> bytes, PsEngineLimits limits = const PsEngineLimits(), bool allowBareDictionary = true}) {
    final PsEngineReader reader = PsEngineReader(bytes: bytes, limits: limits);
    reader.skipTrivia();
    final bool bare = allowBareDictionary && !reader._startsWith('<<') && (reader.offset == bytes.length || reader._bytes[reader.offset] == 47);
    final PsEngineValue root = reader.readRoot(allowBareDictionary: bare);
    return PsEngineDocument._(bytes: reader._bytes, root: root, bareDictionary: bare, limits: limits);
  }

  /// Retains a parsed snapshot and its interpretation policy.
  PsEngineDocument._({required this._bytes, required this.root, required this.bareDictionary, required this.limits});

  /// Original bytes with comments, number spelling and unknown tokens intact.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Walks every node in source order without exposing mutable collections.
  Iterable<PsEngineValue> get values sync* {
    /// Visits the already depth-bounded hierarchy.
    Iterable<PsEngineValue> walk(PsEngineValue value) sync* {
      yield value;
      if (value is PsEngineDictionary) {
        for (final PsEngineValue child in value.values.values) {
          yield* walk(child);
        }
      } else if (value is PsEngineArray) {
        for (final PsEngineValue child in value.values) {
          yield* walk(child);
        }
      }
    }

    yield* walk(root);
  }

  /// Atomically replaces owned, nonoverlapping values and reparses the result.
  ///
  /// This edits syntax only. Format-specific text, style-run, frame and layout
  /// dependencies must be synchronized by the caller in the same transaction.
  PsEngineDocument replaceValues({required Map<PsEngineValue, PsEngineValue> replacements}) {
    final Set<PsEngineValue> owned = values.toSet();
    if (replacements.keys.any((value) => !owned.contains(value))) {
      throw ArgumentError('EngineData edit uses a foreign snapshot value.');
    }
    final List<MapEntry<PsEngineValue, PsEngineValue>> ordered = replacements.entries.toList()..sort((a, b) => a.key.start!.compareTo(b.key.start!));
    final List<Uint8List> encoded = [];
    int position = 0;
    int length = 0;
    for (final MapEntry<PsEngineValue, PsEngineValue> entry in ordered) {
      if (entry.key.start! < position) {
        throw ArgumentError('Overlapping EngineData edits.');
      }
      final Uint8List replacement = PsEngineCodec.encode(value: entry.value, bareDictionary: identical(entry.key, root) && bareDictionary, limits: limits);
      length += entry.key.start! - position + replacement.length;
      if (length > limits.maxBytes) {
        throw const PsFormatException(message: 'Edited EngineData exceeds the byte limit.');
      }
      encoded.add(replacement);
      position = entry.key.end!;
    }
    if (length + _bytes.length - position > limits.maxBytes) {
      throw const PsFormatException(message: 'Edited EngineData exceeds the byte limit.');
    }
    final BytesBuilder output = BytesBuilder(copy: false);
    position = 0;
    for (int index = 0; index < ordered.length; index++) {
      final PsEngineValue value = ordered[index].key;
      output
        ..add(Uint8List.sublistView(_bytes, position, value.start))
        ..add(encoded[index]);
      position = value.end!;
    }
    output.add(Uint8List.sublistView(_bytes, position));
    return PsEngineDocument.decode(bytes: output.takeBytes(), limits: limits, allowBareDictionary: bareDictionary);
  }
}
