# PsCore

PsCore contains the pure Dart binary primitives shared by Focale's Photoshop format packages. It prevents AbrKit, PatKit, and PsdKit from maintaining subtly different implementations of the same codecs.

The package currently provides:

- bounds-checked big-endian binary readers and writers;
- a complete Photoshop Action Descriptor model, reader, and writer;
- every standard descriptor OSType and object-reference form;
- bounded descriptor depth and value counts for untrusted input;
- PackBits row encoding and decoding;
- a shared Photoshop pattern-record model and bounded decoder;
- raw and PackBits pattern planes at 1, 8, 16, and 32 bits;
- profile-independent RGBA previews for standard Photoshop color modes;
- shared format and write exceptions with byte offsets.

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
```

PsCore deliberately does not contain PSD-, ABR-, or PAT-container domain models. Those belong in PsdKit, AbrKit, and PatKit respectively; only their genuinely shared binary structures live here.
