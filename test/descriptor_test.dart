import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises Action Descriptor encoding, decoding, and limits.
void main() {
  group('PsDescriptorCodec', () {
    test('round-trips nested and binary Action Descriptor values', () {
      final PsDescriptor source = PsDescriptor(
        name: 'Brush',
        classId: 'Brsh',
        items: <PsDescriptorItem>[
          const PsDescriptorItem(key: 'bool', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'long', value: PsIntegerValue(value: -42)),
          const PsDescriptorItem(key: 'comp', value: PsLargeIntegerValue(value: 0x123456789)),
          const PsDescriptorItem(key: 'doub', value: PsDoubleValue(value: 1.25)),
          const PsDescriptorItem(
            key: 'unit',
            value: PsUnitFloatValue(unit: '#Prc', value: 25),
          ),
          const PsDescriptorItem(
            key: 'many',
            value: PsUnitFloatsValue(unit: '#Pxl', values: <double>[1, 2, 3]),
          ),
          const PsDescriptorItem(
            key: 'text',
            value: PsStringValue(value: 'Été 😀\u0000'),
          ),
          const PsDescriptorItem(
            key: 'enum',
            value: PsEnumeratedValue(typeId: 'BlnM', value: 'Nrml'),
          ),
          PsDescriptorItem(
            key: 'obj ',
            value: PsObjectValue(
              value: PsDescriptor(
                name: '',
                classId: 'nested',
                items: <PsDescriptorItem>[
                  PsDescriptorItem(
                    key: 'raw ',
                    value: PsRawValue(value: Uint8List.fromList(<int>[0, 1, 255])),
                  ),
                ],
              ),
            ),
          ),
          const PsDescriptorItem(
            key: 'list',
            value: PsListValue(values: <PsDescriptorValue>[PsBooleanValue(value: false), PsDoubleValue(value: 2.5)]),
          ),
          const PsDescriptorItem(
            key: 'refs',
            value: PsReferenceValue(
              values: <PsDescriptorValue>[
                PsIdentifierValue(value: 7),
                PsNameValue(name: '', classId: 'Lyr ', value: 'Layer'),
              ],
            ),
          ),
        ],
      );

      final Uint8List encoded = PsDescriptorCodec.encode(source);
      final PsDescriptor decoded = PsDescriptorCodec.decode(encoded);

      check(decoded.name).equals(source.name);
      check(decoded.classId).equals(source.classId);
      check(decoded.items).length.equals(source.items.length);
      check(PsDescriptorCodec.encode(decoded)).deepEquals(encoded);
    });

    test('enforces nested descriptor depth limits', () {
      PsDescriptor descriptor = const PsDescriptor(name: '', classId: 'leaf');
      for (int depth = 0; depth < 4; depth++) {
        descriptor = PsDescriptor(
          name: '',
          classId: 'node',
          items: <PsDescriptorItem>[
            PsDescriptorItem(
              key: 'next',
              value: PsObjectValue(value: descriptor),
            ),
          ],
        );
      }
      final Uint8List encoded = PsDescriptorCodec.encode(descriptor);

      check(
        () => PsDescriptorCodec.decode(encoded, options: const PsDescriptorDecodeOptions(maxDepth: 2)),
      ).throws<PsFormatException>();
    });

    test('preserves class-prefixed ATN integer references and following values', () {
      // Independently framed ATN descriptor: a reference list containing an
      // identifier and an index, followed by a Boolean outside that list.
      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeUint32(0)
        ..writeUint32(0)
        ..writeString('move')
        ..writeUint32(2)
        ..writeUint32(0)
        ..writeString('null')
        ..writeString('obj ')
        ..writeUint32(2);
      for (final String form in ['Idnt', 'indx']) {
        writer
          ..writeString(form)
          ..writeUint32(1)
          ..writeUint16(0)
          ..writeUint32(4)
          ..writeString('Lyr ')
          ..writeUint32(form == 'Idnt' ? 0xf0000001 : 0);
      }
      writer
        ..writeUint32(0)
        ..writeString('Adjs')
        ..writeString('bool')
        ..writeUint8(1);
      final Uint8List bytes = writer.takeBytes();

      final PsDescriptor descriptor = PsDescriptorCodec.decode(
        bytes,
        options: const PsDescriptorDecodeOptions(integerReferencesHaveClass: true),
      );

      final PsReferenceValue reference = descriptor.value('null')! as PsReferenceValue;
      final PsIdentifierValue identifier = reference.values.first as PsIdentifierValue;
      final PsIndexValue index = reference.values.last as PsIndexValue;
      check(identifier.name).equals('\u0000');
      check(identifier.classId).equals('Lyr ');
      check(identifier.value).equals(0xf0000001);
      check(index.name).equals('\u0000');
      check(index.classId).equals('Lyr ');
      check(index.value).equals(0);
      check(descriptor.booleanValue('Adjs')).equals(true);
      check(PsDescriptorCodec.encode(descriptor, requireIntegerReferenceClasses: true)).deepEquals(bytes);
    });

    test('rejects an ATN reference without its object class inside nested data', () {
      const PsDescriptor descriptor = PsDescriptor(
        name: '',
        classId: 'move',
        items: [
          PsDescriptorItem(
            key: 'null',
            value: PsListValue(
              values: [
                PsObjectValue(
                  value: PsDescriptor(
                    name: '',
                    classId: 'null',
                    items: [
                      PsDescriptorItem(
                        key: 'refs',
                        value: PsReferenceValue(values: [PsIndexValue(value: 3)]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

      check(() => PsDescriptorCodec.encode(descriptor, requireIntegerReferenceClasses: true)).throws<PsWriteException>();
      final Uint8List compact = PsDescriptorCodec.encode(descriptor);
      check(PsDescriptorCodec.encode(PsDescriptorCodec.decode(compact))).deepEquals(compact);
    });

    test('enforces aggregate descriptor value limits before allocation', () {
      const PsDescriptor descriptor = PsDescriptor(
        name: '',
        classId: 'root',
        items: <PsDescriptorItem>[
          PsDescriptorItem(
            key: 'list',
            value: PsListValue(values: <PsDescriptorValue>[PsIntegerValue(value: 1), PsIntegerValue(value: 2), PsIntegerValue(value: 3)]),
          ),
        ],
      );
      final Uint8List encoded = PsDescriptorCodec.encode(descriptor);

      check(
        () => PsDescriptorCodec.decode(encoded, options: const PsDescriptorDecodeOptions(maxValues: 2)),
      ).throws<PsFormatException>();
    });

    test('bounds nested list depth instead of overflowing the stack', () {
      // Nesting only lists reaches the recursion limit with a few bytes per
      // level, so the depth bound has to cover them as well as objects.
      const int nesting = 200000;
      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeUint32(0)
        ..writeUint32(0)
        ..writeString('root')
        ..writeUint32(1)
        ..writeUint32(0)
        ..writeString('deep');
      for (int level = 0; level < nesting; level++) {
        writer
          ..writeString('VlLs')
          ..writeUint32(1);
      }
      writer
        ..writeString('long')
        ..writeInt32(1);
      final Uint8List encoded = writer.takeBytes();

      check(() => PsDescriptorCodec.decode(encoded)).throws<PsFormatException>();
    });

    test('refuses to write an identifier the format cannot represent', () {
      // A zero-length identifier field selects the compact four-character form,
      // so an empty identifier would make readers consume the following bytes.
      const PsDescriptor descriptor = PsDescriptor(
        name: 'Name',
        classId: '',
        items: <PsDescriptorItem>[
          PsDescriptorItem(key: 'keyA', value: PsIntegerValue(value: 42)),
        ],
      );

      check(() => PsDescriptorCodec.encode(descriptor)).throws<PsWriteException>();
    });
  });

  group('PsDescriptorAccess', () {
    test('projects scalar and nested values without losing units', () {
      const PsDescriptor nested = PsDescriptor(name: '', classId: 'nested');
      const PsDescriptor descriptor = PsDescriptor(
        name: '',
        classId: 'root',
        items: <PsDescriptorItem>[
          PsDescriptorItem(
            key: 'text',
            value: PsStringValue(value: 'Name\u0000\u0000'),
          ),
          PsDescriptorItem(key: 'flag', value: PsIntegerValue(value: 1)),
          PsDescriptorItem(
            key: 'size',
            value: PsUnitFloatValue(unit: '#Pxl', value: 12.5),
          ),
          PsDescriptorItem(
            key: 'mode',
            value: PsEnumeratedValue(typeId: 'BlnM', value: 'Mltp'),
          ),
          PsDescriptorItem(
            key: 'obj ',
            value: PsObjectValue(value: nested),
          ),
          PsDescriptorItem(
            key: 'list',
            value: PsListValue(values: <PsDescriptorValue>[PsObjectValue(value: nested)]),
          ),
        ],
      );

      check(descriptor.stringValue('text')).equals('Name');
      check(descriptor.booleanValue('flag')).isNull();
      check(descriptor.booleanValue('flag', mode: PsDescriptorAccessMode.compatible)).equals(true);
      check(descriptor.numberValue('size')?.value).equals(12.5);
      check(descriptor.numberValue('size')?.unit).equals('#Pxl');
      check(descriptor.enumerationIdentifier('mode')).equals('Mltp');
      check(descriptor.objectValue('obj ')?.classId).equals('nested');
      check(descriptor.objectValues('list')).length.equals(1);
    });
  });

  group('PsVersionedDescriptorCodec', () {
    test('round-trips a version and reports prefix length', () {
      const PsVersionedDescriptor source = PsVersionedDescriptor(
        descriptor: PsDescriptor(name: '', classId: 'root'),
      );
      final Uint8List encoded = PsVersionedDescriptorCodec.encode(source);
      final Uint8List withTrailing = Uint8List.fromList(<int>[...encoded, 1, 2]);

      final ({PsVersionedDescriptor value, int bytesRead}) decoded = PsVersionedDescriptorCodec.decodePrefix(
        withTrailing,
        expectedVersion: 16,
      );

      check(decoded.value.version).equals(16);
      check(decoded.value.descriptor.classId).equals('root');
      check(decoded.bytesRead).equals(encoded.length);
      check(
        () => PsVersionedDescriptorCodec.decode(encoded, expectedVersion: 17),
      ).throws<PsFormatException>();
    });
  });

  group('PsDescriptor', () {
    test('withoutValue removes every item stored under a key', () {
      const PsDescriptor descriptor = PsDescriptor(
        name: '',
        classId: 'null',
        items: [
          PsDescriptorItem(key: 'Clr ', value: PsBooleanValue(value: true)),
          PsDescriptorItem(key: 'Opct', value: PsDoubleValue(value: 50)),
        ],
      );

      final PsDescriptor removed = descriptor.withoutValue('Clr ');

      check(removed.items.map((item) => item.key)).deepEquals(['Opct']);
      check(removed.classId).equals('null');
      check(identical(descriptor.withoutValue('Grad'), descriptor)).isTrue();
    });
  });
}
