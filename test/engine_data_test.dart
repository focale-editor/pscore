import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Parses the shared text-engine grammar with byte-exact source retention.
void main() {
  test('owns document input and parsed strings while permitting explicit borrowed scans', () {
    final Uint8List bytes = Uint8List.fromList(latin1.encode('(one) (two)'));
    final PsEngineReader owned = PsEngineReader(bytes: bytes);
    final PsEngineReader borrowed = PsEngineReader.view(bytes: bytes, offset: 6);
    final PsEngineString first = owned.readLiteralString();
    final PsEngineString second = borrowed.readLiteralString();
    bytes.fillRange(0, bytes.length, 0);
    check(first.text()).equals('one');
    check(second.text()).equals('two');
    owned.skipTrivia();
    check(owned.readLiteralString().text()).equals('two');
    check(borrowed.offset).equals(11);
  });

  test('reads bare and wrapped ATE dictionaries, arrays, names and future tokens', () {
    const String content = '/0 << /Text (hello) /Kinds [true false null /CoolTypeFont future] >> /Count +001.50';
    for (final String source in [content, '<< $content >>']) {
      final PsEngineDocument document = PsEngineDocument.decode(bytes: latin1.encode(source));
      final PsEngineDictionary root = document.root as PsEngineDictionary;
      final PsEngineDictionary child = root['0']! as PsEngineDictionary;
      check((child['Text']! as PsEngineString).text()).equals('hello');
      final List<PsEngineValue> values = (child['Kinds']! as PsEngineArray).values;
      check((values[0] as PsEngineBoolean).value).isTrue();
      check(values[2]).isA<PsEngineNull>();
      check((values[3] as PsEngineName).value).equals('CoolTypeFont');
      check((values[4] as PsEngineToken).value).equals('future');
      check((root['Count']! as PsEngineNumber).value).equals(1.5);
      check(document.bytes).deepEquals(latin1.encode(source));
    }
  });

  test('preserves raw binary CR/LF, escapes, UTF-16 and supplementary characters', () {
    final PsEngineString raw = PsEngineReader(bytes: [40, 13, 10, 0, 40, 65, 41, 92, 49, 48, 49, 41]).readLiteralString();
    check(raw.bytes).deepEquals([13, 10, 0, 40, 65, 41, 65]);
    for (final Endian endian in [Endian.big, Endian.little]) {
      final PsEngineString text = PsEngineString.fromText(text: 'Été\r\n🖋 (\\)', endian: endian);
      final PsEngineString decoded = PsEngineDocument.decode(bytes: PsEngineCodec.encode(value: text)).root as PsEngineString;
      check(decoded.bytes).deepEquals(text.bytes);
      check(decoded.text()).equals('Été\r\n🖋 (\\)');
    }
    check(() => PsEngineString(bytes: [254, 255, 0]).text()).throws<PsFormatException>();
    check(() => raw.bytes[0] = 0).throws<UnsupportedError>();
  });

  test('atomically edits source-backed values without normalizing neighboring data', () {
    const String source = '% header\n/0 << /Text (before) % retain\n /Size +001.50 /Unknown future >> % tail\n';
    final PsEngineDocument original = PsEngineDocument.decode(bytes: latin1.encode(source));
    final PsEngineDictionary model = (original.root as PsEngineDictionary)['0']! as PsEngineDictionary;
    final PsEngineDocument edited = original.replaceValues(
      replacements: {
        model['Text']!: PsEngineString(bytes: latin1.encode('after')),
        model['Size']!: PsEngineNumber(value: 12),
      },
    );
    check(latin1.decode(edited.bytes)).equals(source.replaceFirst('(before)', '(after)').replaceFirst('+001.50', '12'));
    check(latin1.decode(original.bytes)).equals(source);
    check(() => edited.replaceValues(replacements: {model['Text']!: const PsEngineNull()})).throws<ArgumentError>();
    check(() => original.replaceValues(replacements: {model: const PsEngineNull(), model['Text']!: const PsEngineNull()})).throws<ArgumentError>();
  });

  test('enforces byte, string, node, depth, duplicate and complete-input limits', () {
    check(() => PsEngineDocument.decode(bytes: latin1.encode('<< /a 1 /a 2 >>'))).throws<PsFormatException>();
    final PsEngineDictionary tolerant = PsEngineReader(bytes: latin1.encode('<< /a 1 /a 2 >>'), allowDuplicateKeys: true).readRoot() as PsEngineDictionary;
    check((tolerant['a']! as PsEngineNumber).value).equals(2);
    for (final String source in ['<< /a 1', '(abc', '[1', '1 2', '<< /a >>', '{']) {
      check(() => PsEngineDocument.decode(bytes: latin1.encode(source))).throws<PsFormatException>();
    }
    check(() => PsEngineDocument.decode(bytes: latin1.encode('(abc)'), limits: const PsEngineLimits(maxBytes: 3))).throws<PsFormatException>();
    check(() => PsEngineDocument.decode(bytes: latin1.encode('(abc)'), limits: const PsEngineLimits(maxStringBytes: 2))).throws<PsFormatException>();
    check(() => PsEngineDocument.decode(bytes: latin1.encode('[1 2]'), limits: const PsEngineLimits(maxNodes: 2))).throws<PsFormatException>();
    check(() => PsEngineDocument.decode(bytes: latin1.encode('[[1]]'), limits: const PsEngineLimits(maxDepth: 1))).throws<PsFormatException>();
    check(
      () => PsEngineCodec.encode(
        value: PsEngineString(bytes: [1, 2]),
        limits: const PsEngineLimits(maxBytes: 2),
      ),
    ).throws<PsWriteException>();
  });

  test('retains integers outside portable precision as uninterpreted atoms', () {
    final PsEngineValue value = PsEngineDocument.decode(bytes: latin1.encode('9007199254740993')).root;
    check(value).isA<PsEngineToken>();
    check(latin1.decode(PsEngineCodec.encode(value: value))).equals('9007199254740993');
    check(() => PsEngineNumber(value: double.infinity)).throws<ArgumentError>();
    check(() => PsEngineCodec.encode(value: const PsEngineName(value: 'name /inject'))).throws<PsWriteException>();
    check(() => PsEngineCodec.encode(value: PsEngineNumber(value: 1, lexeme: '2'))).throws<PsWriteException>();
  });
}
