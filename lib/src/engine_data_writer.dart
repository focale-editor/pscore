part of 'engine_data.dart';

/// Serializes Adobe text-engine values without evaluating PostScript.
abstract final class PsEngineCodec {
  /// Encodes one immutable value with explicit byte, node and depth bounds.
  static Uint8List encode({required PsEngineValue value, bool bareDictionary = false, PsEngineLimits limits = const PsEngineLimits()}) {
    limits.validate();
    if (bareDictionary && value is! PsEngineDictionary) {
      throw ArgumentError('Only an EngineData dictionary can omit its delimiters.');
    }
    final _PsEngineWriter writer = _PsEngineWriter(limits: limits);
    writer.write(value, bare: bareDictionary);
    return writer.bytes.takeBytes();
  }
}

/// Bounded writer retaining binary string bytes and unknown atom spellings.
final class _PsEngineWriter {
  /// Output policy.
  final PsEngineLimits limits;

  /// Encoded output under construction.
  final BytesBuilder bytes = BytesBuilder(copy: false);

  /// Number of values emitted so far.
  int _nodes = 0;

  /// Creates a writer for one atomic encoding operation.
  _PsEngineWriter({required this.limits});

  /// Appends bytes only after checking the total output budget.
  void _add(List<int> value) {
    if (bytes.length + value.length > limits.maxBytes) {
      throw const PsWriteException(message: 'EngineData exceeds the output byte limit.');
    }
    bytes.add(value);
  }

  /// Appends syntax representable as Latin-1.
  void _text(String value) => _add(latin1.encode(value));

  /// Writes a valid literal name or bare token without permitting injected syntax.
  void _atom(String value, {bool name = false}) {
    final List<int> encoded = latin1.encode(value);
    if ((!name && encoded.isEmpty) || encoded.any(_engineDelimiter)) {
      throw const PsWriteException(message: 'Invalid EngineData name or token.');
    }
    if (name) {
      _add([47]);
    }
    _add(encoded);
  }

  /// Writes one value, counting nested containers and strings before allocation.
  void write(PsEngineValue value, {bool bare = false, int depth = 0}) {
    if (++_nodes > limits.maxNodes || depth > limits.maxDepth) {
      throw const PsWriteException(message: 'EngineData exceeds the node or depth limit.');
    }
    switch (value) {
      case PsEngineDictionary(:final values):
        if (depth >= limits.maxDepth) {
          throw const PsWriteException(message: 'EngineData exceeds the nesting limit.');
        }
        if (!bare) {
          _text('<< ');
        }
        for (final MapEntry<String, PsEngineValue> entry in values.entries) {
          _atom(entry.key, name: true);
          _text(' ');
          write(entry.value, depth: depth + 1);
          _text(' ');
        }
        if (!bare) {
          _text('>>');
        }
      case PsEngineArray(:final values):
        if (depth >= limits.maxDepth) {
          throw const PsWriteException(message: 'EngineData exceeds the nesting limit.');
        }
        _text('[ ');
        for (final PsEngineValue entry in values) {
          write(entry, depth: depth + 1);
          _text(' ');
        }
        _text(']');
      case PsEngineString():
        final Uint8List source = value.bytes;
        if (source.length > limits.maxStringBytes) {
          throw const PsWriteException(message: 'EngineData string exceeds the byte limit.');
        }
        final int escapedLength = source.length + source.where((byte) => byte == 40 || byte == 41 || byte == 92).length + 2;
        if (bytes.length + escapedLength > limits.maxBytes) {
          throw const PsWriteException(message: 'EngineData exceeds the output byte limit.');
        }
        final Uint8List encoded = Uint8List(escapedLength)..[0] = 40;
        int offset = 1;
        for (final int byte in source) {
          if (byte == 40 || byte == 41 || byte == 92) {
            encoded[offset++] = 92;
          }
          encoded[offset++] = byte;
        }
        encoded[offset] = 41;
        _add(encoded);
      case PsEngineName(:final value):
        _atom(value, name: true);
      case PsEngineNumber(:final value, :final lexeme):
        if (lexeme != null && num.tryParse(lexeme) != value) {
          throw const PsWriteException(message: 'EngineData number spelling disagrees with its value.');
        }
        _atom(lexeme ?? value.toString());
      case PsEngineBoolean(:final value):
        _text(value ? 'true' : 'false');
      case PsEngineNull():
        _text('null');
      case PsEngineToken(:final value):
        _atom(value);
    }
  }
}
