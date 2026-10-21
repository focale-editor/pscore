<p align="center">
  <img src="screenshots/overview.png" alt="PsCore package illustration" width="180">
</p>

# PsCore

PsCore contains the pure Dart binary primitives shared by Focale's Photoshop format packages. It prevents AbrKit, AcvKit, AslKit, CshKit, PatKit and PsdKit from maintaining subtly different implementations of the same codecs.

The package currently provides:

- bounds-checked big-endian binary readers and writers;
- a complete Photoshop Action Descriptor model, reader, and writer;
- every standard descriptor OSType and object-reference form;
- bounded descriptor depth and value counts for untrusted input;
- PackBits row encoding and decoding;
- a shared Photoshop pattern-record model, bounded decoder, and encoder;
- raw and PackBits pattern planes at 1, 8, 16, and 32 bits;
- profile-independent RGBA previews for standard Photoshop color modes;
- tone curves, vector paths, and preset hierarchies;
- layer-style colors, gradients, contours, effects, and blending options, with
  typed views over existing descriptors and builders for new ones;
- format, write, and warning base types that every format package extends, so
  one `on PsFormatException` clause catches errors from any of them.

## Platform support

The package is pure Dart and runs on native platforms, WebAssembly, and
JavaScript.

`comp` Action Descriptor values retain every signed 64-bit integer on all
three targets. Read `PsLargeIntegerValue.exactValue` as a `BigInt`, or construct
one with `PsLargeIntegerValue.fromBigInt(value: value)`. The existing const
integer constructor remains available. `intValue` is nullable when the target
cannot represent a value exactly; the compatibility `value` getter throws
`StateError` in that case instead of rounding it. Integer descriptor projections
also return `null` for an unrepresentable value.

`PsBinaryReader.readBigInt64` and `PsBinaryWriter.writeBigInt64` provide the same
exact signed range for other binary structures. Ordinary `readInt64`/`writeInt64`
and 64-bit length fields continue to use `int`; JavaScript rejects values beyond
`psMaxExactInteger` for those APIs. Native and WebAssembly integer APIs retain
the platform's signed 64-bit range.

## Usage

```dart
import 'dart:typed_data';

import 'package:pscore/pscore.dart';

final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
final int version = reader.readUint16();

final PsDescriptor descriptor = PsDescriptorCodec.decode(descriptorBytes);
final PsDescriptorValue? name = descriptor.value('Nm  ');

final Uint8List encoded = PsDescriptorCodec.encode(descriptor);
```

Container packages can reuse the pattern-record decoder while controlling source preservation and decoded-memory limits:

```dart
final PsPatternDecodeResult decoded = PsPatternRecordDecoder.decode(
  reader: reader,
  kind: PsPatternRecordKind.standalone,
  options: const PsPatternDecodeOptions(
    preserveChannelData: false,
    preserveRecordData: false,
  ),
);
final PsPatternImage preview = decoded.pattern.renderRgba8();
final Uint8List patternBytes = PsPatternRecordEncoder.encode(
  pattern: decoded.pattern,
  kind: PsPatternRecordKind.standalone,
);
```

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
