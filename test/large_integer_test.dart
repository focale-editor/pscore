import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises values whose low bits would otherwise disappear on JavaScript.
void main() {
  for (final String decimal in ['-9223372036854775808', '-9007199254740993', '9007199254740993', '9223372036854775807']) {
    test('preserves signed 64-bit descriptor $decimal', () {
      final BigInt value = BigInt.parse(decimal);
      final PsDescriptor descriptor = PsDescriptor(
        name: '',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'wide',
            value: PsLargeIntegerValue.fromBigInt(value: value),
          ),
          const PsDescriptorItem(key: 'next', value: PsBooleanValue(value: true)),
        ],
      );
      final Uint8List encoded = PsDescriptorCodec.encode(descriptor);
      final PsDescriptor decoded = PsDescriptorCodec.decode(encoded);
      final PsLargeIntegerValue integer = decoded.value('wide')! as PsLargeIntegerValue;
      expect(integer.exactValue, value);
      expect(decoded.booleanValue('next'), isTrue);
      expect(PsDescriptorCodec.encode(decoded), encoded);
      if (integer.intValue case final int exact) {
        expect(BigInt.from(exact), value);
      } else {
        expect(() => integer.value, throwsStateError);
        expect(decoded.integerValue('wide'), isNull);
      }
    });
  }
  test('Typed gradient views retain unrepresentable descriptor values without rounding', () {
    final PsLargeIntegerValue wide = PsLargeIntegerValue.fromBigInt(value: BigInt.parse('9007199254740993'));
    final PsDescriptor descriptor = const PsDescriptor(name: '', classId: 'Grdn').withValue('Mnm ', PsListValue(values: [wide]));
    final PsGradient gradient = PsGradient.fromDescriptor(descriptor);
    expect(gradient.minimumValues, wide.intValue == null ? isEmpty : [wide.intValue]);
    expect((gradient.descriptor.listValue('Mnm ')!.single as PsLargeIntegerValue).exactValue, wide.exactValue);
  });

  test('rejects overflowing signed values before writing', () {
    final PsBinaryWriter writer = PsBinaryWriter();
    expect(() => writer.writeBigInt64(BigInt.one << 63), throwsA(isA<PsWriteException>()));
    expect(writer.length, 0);
    expect(() => PsLargeIntegerValue.fromBigInt(value: -(BigInt.one << 63) - BigInt.one), throwsRangeError);
  });
  test('keeps the const integer constructor and integer projections', () {
    const PsLargeIntegerValue value = PsLargeIntegerValue(value: 42);
    expect(value.value, 42);
    expect(value.exactValue, BigInt.from(42));
    expect(value.asInteger(), 42);
  });
}
