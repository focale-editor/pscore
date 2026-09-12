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
- shared format and write exceptions with byte offsets.

## Platform support

The package is pure Dart and runs on native platforms, WebAssembly, and
JavaScript.

Only the JavaScript target needs a compromise: it has no 64-bit integers, and its
`ByteData` 64-bit accessors are unavailable. There, `PsCore` composes each 64-bit
field from two 32-bit halves, which is exact up to `psMaxExactInteger`, or two to
the power of 53 minus one. That covers every 64-bit field real Photoshop data
contains, since a larger `8B64` block length or `comp` descriptor value would
describe petabytes. Beyond it, reading raises a `PsFormatException` and writing a
`PsWriteException`, rather than silently dropping the low bits.

Native and WebAssembly targets both use the platform's own 64-bit accessors and
produce byte-identical output over the full signed 64-bit range.

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
