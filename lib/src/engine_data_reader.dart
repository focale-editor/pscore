part of 'engine_data.dart';

/// Bounded reader for the binary-string PostScript subset used by Adobe text.
final class PsEngineReader {
  /// Input bytes, owned by default or explicitly borrowed with [PsEngineReader.view].
  final Uint8List _bytes;

  /// Maximum accepted sizes and nesting.
  final PsEngineLimits limits;

  /// Whether duplicate keys retain the final value for legacy tolerant readers.
  final bool allowDuplicateKeys;

  /// Current input position.
  int _offset;

  /// Current dictionary/array nesting.
  int _depth = 0;

  /// Number of decoded values.
  int _nodes = 0;

  /// Creates a reader at an explicit byte offset.
  factory PsEngineReader({required List<int> bytes, int offset = 0, PsEngineLimits limits = const PsEngineLimits(), bool allowDuplicateKeys = false}) {
    limits.validate();
    if (bytes.length > limits.maxBytes || bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const PsFormatException(message: 'Invalid or excessive EngineData input.');
    }
    if (offset < 0 || offset > bytes.length) {
      throw ArgumentError.value(offset, 'offset');
    }
    return PsEngineReader._(bytes: Uint8List.fromList(bytes), offset: offset, limits: limits, allowDuplicateKeys: allowDuplicateKeys);
  }

  /// Borrows a typed byte buffer for short-lived scans without copying it.
  ///
  /// The caller must not mutate [bytes] while reading. Returned values own their
  /// data; use the default constructor when input ownership is uncertain.
  factory PsEngineReader.view({required Uint8List bytes, int offset = 0, PsEngineLimits limits = const PsEngineLimits(), bool allowDuplicateKeys = false}) {
    limits.validate();
    if (bytes.length > limits.maxBytes) {
      throw const PsFormatException(message: 'Excessive EngineData input.');
    }
    if (offset < 0 || offset > bytes.length) {
      throw ArgumentError.value(offset, 'offset');
    }
    return PsEngineReader._(bytes: bytes.asUnmodifiableView(), offset: offset, limits: limits, allowDuplicateKeys: allowDuplicateKeys);
  }

  /// Retains validated input and the initial cursor.
  PsEngineReader._({required this._bytes, required this._offset, required this.limits, required this.allowDuplicateKeys});

  /// Current absolute offset, including trivia consumed after a root.
  int get offset => _offset;

  /// Reads one root and optionally requires complete input consumption.
  PsEngineValue readRoot({bool allowBareDictionary = false, bool requireEnd = true}) {
    skipTrivia();
    final PsEngineValue value = allowBareDictionary && !_startsWith('<<') ? _readDictionary(bare: true) : readValue();
    skipTrivia();
    if (requireEnd && _offset != _bytes.length) {
      throw PsFormatException(message: 'Unexpected trailing EngineData.', offset: _offset);
    }
    return value;
  }

  /// Reads one bounded value, retaining its exact original source range.
  PsEngineValue readValue() {
    skipTrivia();
    if (_offset >= _bytes.length) {
      throw PsFormatException(message: 'Missing EngineData value.', offset: _offset);
    }
    if (_startsWith('<<')) {
      return _readDictionary(bare: false);
    }
    if (_bytes[_offset] == 91) {
      return _readArray();
    }
    if (_bytes[_offset] == 40) {
      return readLiteralString();
    }
    _count();
    final int start = _offset;
    if (_bytes[_offset] == 47) {
      final String name = _readName();
      return PsEngineName(start: start, end: _offset, value: name);
    }
    final String token = _readToken();
    if (token == 'true' || token == 'false') {
      return PsEngineBoolean(start: start, end: _offset, value: token == 'true');
    }
    if (token == 'null') {
      return PsEngineNull(start: start, end: _offset);
    }
    final num? number = num.tryParse(token);
    if (number != null && number.isFinite && (number is! int || number.abs() <= _engineMaxInteger)) {
      return PsEngineNumber(start: start, end: _offset, value: number, lexeme: token);
    }
    return PsEngineToken(start: start, end: _offset, value: token);
  }

  /// Reads a literal binary string without normalizing raw CR or LF bytes.
  PsEngineString readLiteralString() {
    _count();
    final int start = _offset;
    if (_offset >= _bytes.length || _bytes[_offset++] != 40) {
      throw PsFormatException(message: 'Expected EngineData literal string.', offset: start);
    }
    int depth = 1;
    final BytesBuilder value = BytesBuilder(copy: false);

    /// Appends one byte after checking the decoded string budget.
    void append(int byte) {
      if (value.length >= limits.maxStringBytes) {
        throw PsFormatException(message: 'EngineData string exceeds the byte limit.', offset: start);
      }
      value.addByte(byte);
    }

    while (_offset < _bytes.length) {
      final int byte = _bytes[_offset++];
      if (byte == 92) {
        if (_offset == _bytes.length) {
          throw PsFormatException(message: 'Truncated EngineData escape.', offset: _offset);
        }
        final int escaped = _bytes[_offset++];
        if (escaped == 10) {
          continue;
        }
        if (escaped == 13) {
          if (_offset < _bytes.length && _bytes[_offset] == 10) {
            _offset++;
          }
          continue;
        }
        if (escaped >= 48 && escaped <= 55) {
          int octal = escaped - 48;
          int digits = 1;
          while (digits < 3 && _offset < _bytes.length && _bytes[_offset] >= 48 && _bytes[_offset] <= 55) {
            octal = octal * 8 + _bytes[_offset++] - 48;
            digits++;
          }
          append(octal & 255);
        } else {
          append(switch (escaped) {
            110 => 10,
            114 => 13,
            116 => 9,
            98 => 8,
            102 => 12,
            _ => escaped,
          });
        }
      } else if (byte == 40) {
        depth++;
        append(byte);
      } else if (byte == 41) {
        if (--depth == 0) {
          return PsEngineString(start: start, end: _offset, bytes: value.takeBytes());
        }
        append(byte);
      } else {
        append(byte);
      }
    }
    throw PsFormatException(message: 'Unterminated EngineData string.', offset: start);
  }

  /// Reads wrapped or bare dictionary entries without discarding duplicate keys silently.
  PsEngineDictionary _readDictionary({required bool bare}) {
    _enter();
    final int start = _offset;
    if (!bare) {
      _offset += 2;
    }
    final Map<String, PsEngineValue> values = {};
    while (true) {
      skipTrivia();
      if (bare && _offset == _bytes.length || !bare && _startsWith('>>')) {
        if (!bare) {
          _offset += 2;
        }
        _depth--;
        return PsEngineDictionary(start: start, end: _offset, values: values);
      }
      if (_offset >= _bytes.length || _bytes[_offset] != 47) {
        throw PsFormatException(message: 'Expected EngineData dictionary key.', offset: _offset);
      }
      final String name = _readName();
      if (!allowDuplicateKeys && values.containsKey(name)) {
        throw PsFormatException(message: 'Duplicate EngineData dictionary key.', offset: _offset);
      }
      values[name] = readValue();
    }
  }

  /// Reads an immutable ordered array.
  PsEngineArray _readArray() {
    _enter();
    final int start = _offset++;
    final List<PsEngineValue> values = [];
    while (true) {
      skipTrivia();
      if (_offset >= _bytes.length) {
        throw PsFormatException(message: 'Unterminated EngineData array.', offset: start);
      }
      if (_bytes[_offset] == 93) {
        _offset++;
        _depth--;
        return PsEngineArray(start: start, end: _offset, values: values);
      }
      values.add(readValue());
    }
  }

  /// Enforces the aggregate node limit before constructing another value.
  void _count() {
    if (++_nodes > limits.maxNodes) {
      throw PsFormatException(message: 'EngineData exceeds the node limit.', offset: _offset);
    }
  }

  /// Opens one dictionary or array level.
  void _enter() {
    _count();
    if (++_depth > limits.maxDepth) {
      throw PsFormatException(message: 'EngineData exceeds the nesting limit.', offset: _offset);
    }
  }

  /// Reads a slash-prefixed literal name.
  String _readName() {
    _offset++;
    final int start = _offset;
    while (_offset < _bytes.length && !_engineDelimiter(_bytes[_offset])) {
      _offset++;
    }
    return latin1.decode(Uint8List.sublistView(_bytes, start, _offset));
  }

  /// Reads one uninterpreted token without consuming its delimiter.
  String _readToken() {
    final int start = _offset;
    while (_offset < _bytes.length && !_engineDelimiter(_bytes[_offset])) {
      _offset++;
    }
    if (start == _offset) {
      throw PsFormatException(message: 'Invalid EngineData token.', offset: start);
    }
    return latin1.decode(Uint8List.sublistView(_bytes, start, _offset));
  }

  /// Skips whitespace and percent comments outside binary strings.
  void skipTrivia() {
    while (_offset < _bytes.length) {
      if (_engineWhitespace(_bytes[_offset])) {
        _offset++;
      } else if (_bytes[_offset] == 37) {
        while (_offset < _bytes.length && _bytes[_offset] != 10 && _bytes[_offset] != 13) {
          _offset++;
        }
      } else {
        return;
      }
    }
  }

  /// Checks a short ASCII delimiter at the current offset.
  bool _startsWith(String value) {
    if (_offset + value.length > _bytes.length) {
      return false;
    }
    for (int index = 0; index < value.length; index++) {
      if (_bytes[_offset + index] != value.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }
}

/// Recognizes PostScript whitespace outside literal strings.
bool _engineWhitespace(int byte) => const {0, 9, 10, 12, 13, 32}.contains(byte);

/// Recognizes syntax delimiters without treating raw string bytes as text.
bool _engineDelimiter(int byte) => _engineWhitespace(byte) || const {40, 41, 60, 62, 91, 93, 123, 125, 47, 37}.contains(byte);
