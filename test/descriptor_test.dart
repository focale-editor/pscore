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
  });
}
