import 'dart:math' as math;
import 'dart:typed_data';

/// Identifies the Photoshop color model used by a pattern record.
enum PsPatternColorMode {
  /// One-bit black-and-white samples.
  bitmap(code: 0, colorChannelCount: 1),

  /// A single grayscale channel.
  grayscale(code: 1, colorChannelCount: 1),

  /// Palette indices into an interleaved RGB table.
  indexed(code: 2, colorChannelCount: 1),

  /// Separate red, green, and blue channels.
  rgb(code: 3, colorChannelCount: 3),

  /// Separate inverted cyan, magenta, yellow, and black channels.
  cmyk(code: 4, colorChannelCount: 4),

  /// Independent channels whose first plane can be previewed as grayscale.
  multichannel(code: 7, colorChannelCount: 1),

  /// A duotone intensity plane without its external ink definition.
  duotone(code: 8, colorChannelCount: 1),

  /// CIE L*a*b* channels.
  lab(code: 9, colorChannelCount: 3),

  /// A color-model code unknown to this release.
  unknown(code: -1, colorChannelCount: 1);

  /// Numeric color-model marker stored by Photoshop.
  final int code;

  /// Number of leading virtual-memory slots used for a standard preview.
  final int colorChannelCount;

  /// Creates a color model with its binary [code] and preview channel count.
  const PsPatternColorMode({
    required this.code,
    required this.colorChannelCount,
  });

  /// Resolves the known value represented by [code].
  static PsPatternColorMode fromCode(int code) => switch (code) {
    0 => bitmap,
    1 => grayscale,
    2 => indexed,
    3 => rgb,
    4 => cmyk,
    7 => multichannel,
    8 => duotone,
    9 => lab,
    _ => unknown,
  };
}

/// Identifies the storage method used by a pattern channel.
enum PsPatternCompression {
  /// Samples are stored directly in row-major order.
  raw(code: 0),

  /// Every row is encoded independently with PackBits.
  packBits(code: 1),

  /// A compression marker unknown to this release.
  unknown(code: -1);

  /// Numeric compression marker stored by Photoshop.
  final int code;

  /// Creates a compression value with its binary [code].
  const PsPatternCompression({required this.code});

  /// Resolves the known value represented by [code].
  static PsPatternCompression fromCode(int code) => switch (code) {
    0 => raw,
    1 => packBits,
    _ => unknown,
  };
}

/// A rectangle using Photoshop's inclusive top/left and exclusive bottom/right convention.
final class PsRectangle {
  /// Vertical coordinate of the first row.
  final int top;

  /// Horizontal coordinate of the first column.
  final int left;

  /// Exclusive vertical coordinate following the last row.
  final int bottom;

  /// Exclusive horizontal coordinate following the last column.
  final int right;

  /// Creates a rectangle from its four stored edges.
  const PsRectangle({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  /// Number of columns covered by the rectangle.
  int get width => right - left;

  /// Number of rows covered by the rectangle.
  int get height => bottom - top;

  /// Number of pixels covered by the rectangle.
  int get pixelCount => width * height;

  /// Whether both dimensions are strictly positive.
  bool get isValid => width > 0 && height > 0;
}

/// The four bytes following an indexed pattern's 256-entry palette.
final class PsPatternIndexedMetadata {
  /// Number of meaningful palette colors in a standalone PAT record, when interpreted.
  final int? colorsUsed;

  /// Palette index treated as transparent when no alpha plane exists, when interpreted.
  final int? transparentIndex;

  /// Exact four-byte trailer, including reserved bytes in embedded records.
  final Uint8List rawData;

  /// Creates immutable indexed-palette metadata.
  PsPatternIndexedMetadata({
    required Uint8List rawData,
    this.colorsUsed,
    this.transparentIndex,
  }) : rawData = Uint8List.fromList(rawData).asUnmodifiableView();

  /// Whether [transparentIndex] names one of the 256 palette entries.
  bool get hasTransparentIndex {
    final int? index = transparentIndex;
    return index != null && index >= 0 && index < 256;
  }
}

/// One decoded or preserved virtual-memory channel from a Photoshop pattern.
final class PsPatternChannel {
  /// First depth value stored at the beginning of the channel header.
  final int primaryDepth;

  /// Second depth value used to lay out channel samples.
  final int depth;

  /// Source-space rectangle covered by this channel.
  final PsRectangle bounds;

  /// Known interpretation of [compressionCode].
  final PsPatternCompression compression;

  /// Original numeric compression marker.
  final int compressionCode;

  /// Original bytes following the fixed 23-byte channel header.
  final Uint8List encodedData;

  /// Row-major uncompressed bytes, or `null` when decoding was disabled or unsupported.
  final Uint8List? decodedData;

  /// Bytes remaining after the recognized raw samples or PackBits rows.
  final Uint8List trailingData;

  /// Numeric view over [decodedData] used for multibyte samples.
  late final ByteData? _decodedValues;

  /// Creates an immutable decoded or preserved channel.
  PsPatternChannel({
    required this.primaryDepth,
    required this.depth,
    required this.bounds,
    required this.compression,
    required this.compressionCode,
    required Uint8List encodedData,
    required Uint8List? decodedData,
    required Uint8List trailingData,
  }) : encodedData = Uint8List.fromList(encodedData).asUnmodifiableView(),
       decodedData = decodedData == null ? null : Uint8List.fromList(decodedData).asUnmodifiableView(),
       trailingData = Uint8List.fromList(trailingData).asUnmodifiableView() {
    final Uint8List? values = this.decodedData;
    _decodedValues = values == null ? null : ByteData.sublistView(values);
  }

  /// Number of bytes used by one decoded row.
  int get rowBytes => (bounds.width * depth + 7) ~/ 8;

  /// Returns the exact stored sample at source coordinate [x], [y].
  ///
  /// Integer depths return an `int`; 32-bit channels return a floating-point value.
  /// A missing or unavailable sample returns `null`.
  num? sampleAt({
    required int x,
    required int y,
  }) {
    final Uint8List? bytes = decodedData;
    final ByteData? values = _decodedValues;
    final int localX = x - bounds.left;
    final int localY = y - bounds.top;
    if (bytes == null || localX < 0 || localY < 0 || localX >= bounds.width || localY >= bounds.height) {
      return null;
    }
    return switch (depth) {
      1 => (bytes[localY * rowBytes + localX ~/ 8] >> (7 - localX % 8)) & 1,
      8 => bytes[localY * bounds.width + localX],
      16 when values != null => values.getUint16((localY * bounds.width + localX) * 2),
      32 when values != null => values.getFloat32((localY * bounds.width + localX) * 4),
      _ => null,
    };
  }

  /// Returns a sample normalized to the range 0–1, or [fallback] when unavailable.
  ///
  /// Photoshop's integer 16-bit channels use the application-specific 0–32768 range.
  double normalizedSampleAt({
    required int x,
    required int y,
    double fallback = 0,
  }) {
    final num? sample = sampleAt(x: x, y: y);
    if (sample == null) {
      return fallback;
    }
    return _normalizedSample(sample, fallback);
  }

  /// Converts one exact [sample] to the normalized range used by renderers.
  double _normalizedSample(num sample, double fallback) {
    final double normalized = switch (depth) {
      1 => sample.toDouble(),
      8 => sample.toDouble() / 255,
      16 => sample.toDouble() / 32768,
      32 => sample.toDouble(),
      _ => fallback,
    };
    if (!normalized.isFinite) {
      return fallback;
    }
    return normalized.clamp(0, 1).toDouble();
  }

  /// Returns a sample normalized to an unsigned byte, or [fallback] when unavailable.
  int byteSampleAt({
    required int x,
    required int y,
    int fallback = 0,
  }) {
    final num? sample = sampleAt(x: x, y: y);
    if (sample == null) {
      return fallback;
    }
    return (_normalizedSample(sample, fallback.toDouble() / 255) * 255).round().clamp(0, 255);
  }
}

/// One of the declared channel slots in a Photoshop virtual-memory array.
final class PsPatternChannelSlot {
  /// Zero-based position in the complete declared slot list.
  final int index;

  /// Exact value of the four-byte written marker.
  final int writtenCode;

  /// Declared channel payload length, or `null` for an unwritten slot.
  final int? declaredLength;

  /// Exact bounded payload following the optional length field.
  final Uint8List data;

  /// Parsed channel header and samples, or `null` for empty or malformed data.
  final PsPatternChannel? channel;

  /// Creates an immutable virtual-memory slot.
  PsPatternChannelSlot({
    required this.index,
    required this.writtenCode,
    required this.declaredLength,
    required Uint8List data,
    required this.channel,
  }) : data = Uint8List.fromList(data).asUnmodifiableView();

  /// Whether Photoshop marked this slot as written.
  bool get isWritten => writtenCode != 0;
}

/// An eight-bit red, green, and blue color returned by a color converter.
final class PsRgbColor {
  /// Red component in the range 0–255.
  final int red;

  /// Green component in the range 0–255.
  final int green;

  /// Blue component in the range 0–255.
  final int blue;

  /// Creates a color from byte-valued components.
  const PsRgbColor({
    required this.red,
    required this.green,
    required this.blue,
  });
}

/// Converts normalized CMYK ink amounts to an eight-bit RGB color.
typedef PsCmykToRgbConverter = PsRgbColor Function({
  required double cyan,
  required double magenta,
  required double yellow,
  required double black,
});

/// A rendered row-major RGBA image suitable for editor integration.
final class PsPatternImage {
  /// Number of pixel columns.
  final int width;

  /// Number of pixel rows.
  final int height;

  /// Four bytes per pixel in red, green, blue, alpha order.
  final Uint8List rgba;

  /// Creates an immutable rendered image.
  PsPatternImage({
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : rgba = Uint8List.fromList(rgba).asUnmodifiableView();

  /// Returns one component from the pixel at [x], [y].
  int componentAt({
    required int x,
    required int y,
    required int component,
  }) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    RangeError.checkValueInInterval(component, 0, 3, 'component');
    return rgba[(y * width + x) * 4 + component];
  }
}

/// A complete Photoshop pattern record with its source planes and metadata.
final class PsPattern {
  /// Pattern format version stored in the record.
  final int version;

  /// Known interpretation of [colorModeCode].
  final PsPatternColorMode colorMode;

  /// Original numeric Photoshop color-mode code.
  final int colorModeCode;

  /// Vertical value from the record's point field, normally the tile height.
  final int vertical;

  /// Horizontal value from the record's point field, normally the tile width.
  final int horizontal;

  /// Human-readable preset name without terminal null code units.
  final String name;

  /// Pattern identifier decoded from its Pascal string.
  final String id;

  /// Exact bytes of the identifier, including any terminal null byte.
  final Uint8List idData;

  /// Interleaved 256-entry RGB palette for indexed patterns, when present.
  final Uint8List? palette;

  /// Indexed palette footer, including standalone transparency metadata.
  final PsPatternIndexedMetadata? indexedMetadata;

  /// Virtual-memory-array format version.
  final int virtualMemoryVersion;

  /// Rectangle declared by the complete virtual-memory array.
  final PsRectangle bounds;

  /// Number of ordinary channel slots declared before the two special slots.
  final int declaredChannelCount;

  /// Every ordinary, user-mask, and sheet-transparency slot in source order.
  final List<PsPatternChannelSlot> slots;

  /// Bytes following the recognized slot list inside the virtual-memory payload.
  final Uint8List virtualMemoryTrailingData;

  /// Bytes following the virtual-memory array inside a bounded embedded record.
  final Uint8List recordTrailingData;

  /// Complete source record bytes when preservation was requested.
  final Uint8List? recordData;

  /// Creates an immutable Photoshop pattern record.
  PsPattern({
    required this.version,
    required this.colorMode,
    required this.colorModeCode,
    required this.vertical,
    required this.horizontal,
    required this.name,
    required this.id,
    required Uint8List idData,
    required Uint8List? palette,
    required this.indexedMetadata,
    required this.virtualMemoryVersion,
    required this.bounds,
    required this.declaredChannelCount,
    required List<PsPatternChannelSlot> slots,
    required Uint8List virtualMemoryTrailingData,
    required Uint8List recordTrailingData,
    required Uint8List? recordData,
  }) : idData = Uint8List.fromList(idData).asUnmodifiableView(),
       palette = palette == null ? null : Uint8List.fromList(palette).asUnmodifiableView(),
       slots = List<PsPatternChannelSlot>.unmodifiable(slots),
       virtualMemoryTrailingData = Uint8List.fromList(virtualMemoryTrailingData).asUnmodifiableView(),
       recordTrailingData = Uint8List.fromList(recordTrailingData).asUnmodifiableView(),
       recordData = recordData == null ? null : Uint8List.fromList(recordData).asUnmodifiableView();

  /// Tile width reported by the point field, with the VMA width as a fallback.
  int get width => horizontal > 0 ? horizontal : bounds.width;

  /// Tile height reported by the point field, with the VMA height as a fallback.
  int get height => vertical > 0 ? vertical : bounds.height;

  /// Every successfully parsed channel, in slot order.
  List<PsPatternChannel> get channels => List<PsPatternChannel>.unmodifiable(<PsPatternChannel>[
    for (final PsPatternChannelSlot slot in slots)
      if (slot.channel case final PsPatternChannel channel) channel,
  ]);

  /// The special user-mask channel, when the corresponding slot is present.
  PsPatternChannel? get userMaskChannel => channelForSlot(declaredChannelCount);

  /// The special sheet-transparency channel, when the final slot is present.
  PsPatternChannel? get alphaChannel => channelForSlot(declaredChannelCount + 1);

  /// Whether all planes needed by [renderRgba8] have decoded sample data.
  bool get canRenderRgba8 {
    for (int index = 0; index < colorMode.colorChannelCount; index++) {
      if (channelForSlot(index)?.decodedData == null) {
        return false;
      }
    }
    final PsPatternChannel? alpha = alphaChannel;
    return alpha == null || alpha.decodedData != null;
  }

  /// Returns the parsed channel at [index], or `null` for an absent or malformed slot.
  PsPatternChannel? channelForSlot(int index) {
    if (index < 0 || index >= slots.length) {
      return null;
    }
    return slots[index].channel;
  }

  /// Renders the source planes into an immutable RGBA8 tile.
  ///
  /// CMYK uses [cmykConverter] when supplied and a deterministic profile-free ink
  /// multiplication otherwise. Duotone and multichannel records use their first
  /// plane as grayscale because their external ink definitions are not in PAT data.
  PsPatternImage renderRgba8({
    PsCmykToRgbConverter? cmykConverter,
    int maxPixelCount = 64 * 1024 * 1024,
  }) {
    if (!canRenderRgba8) {
      throw StateError('Pattern "$name" does not have every decoded plane required for RGBA rendering');
    }
    final int outputWidth = width;
    final int outputHeight = height;
    final int pixelCount = outputWidth * outputHeight;
    if (outputWidth <= 0 || outputHeight <= 0 || pixelCount > maxPixelCount) {
      throw StateError('Pattern dimensions $outputWidth x $outputHeight cannot be rendered within the $maxPixelCount pixel limit');
    }
    final Uint8List output = Uint8List(pixelCount * 4);
    final int originX = bounds.isValid ? bounds.left : 0;
    final int originY = bounds.isValid ? bounds.top : 0;
    final PsPatternChannel? alpha = alphaChannel;
    for (int y = 0; y < outputHeight; y++) {
      for (int x = 0; x < outputWidth; x++) {
        final int sourceX = originX + x;
        final int sourceY = originY + y;
        final PsRgbColor color = _rgbAt(
          x: sourceX,
          y: sourceY,
          cmykConverter: cmykConverter,
        );
        int alphaValue = _byteSample(alpha, x: sourceX, y: sourceY, fallback: 255);
        if (alpha == null && colorMode == PsPatternColorMode.indexed && indexedMetadata?.hasTransparentIndex == true) {
          final int index = _byteSample(channelForSlot(0), x: sourceX, y: sourceY, fallback: 0);
          if (index == indexedMetadata?.transparentIndex) {
            alphaValue = 0;
          }
        }
        final int offset = (y * outputWidth + x) * 4;
        output[offset] = color.red;
        output[offset + 1] = color.green;
        output[offset + 2] = color.blue;
        output[offset + 3] = alphaValue;
      }
    }
    return PsPatternImage(width: outputWidth, height: outputHeight, rgba: output);
  }

  /// Resolves one source coordinate into a profile-independent RGB preview.
  PsRgbColor _rgbAt({
    required int x,
    required int y,
    required PsCmykToRgbConverter? cmykConverter,
  }) => switch (colorMode) {
    PsPatternColorMode.bitmap => _grayColor(255 - _byteSample(channelForSlot(0), x: x, y: y, fallback: 0)),
    PsPatternColorMode.grayscale || PsPatternColorMode.multichannel || PsPatternColorMode.duotone || PsPatternColorMode.unknown => _grayColor(_byteSample(channelForSlot(0), x: x, y: y, fallback: 0)),
    PsPatternColorMode.indexed => _indexedColor(x: x, y: y),
    PsPatternColorMode.rgb => PsRgbColor(
      red: _byteSample(channelForSlot(0), x: x, y: y, fallback: 0),
      green: _byteSample(channelForSlot(1), x: x, y: y, fallback: 0),
      blue: _byteSample(channelForSlot(2), x: x, y: y, fallback: 0),
    ),
    PsPatternColorMode.cmyk => _cmykColor(x: x, y: y, converter: cmykConverter),
    PsPatternColorMode.lab => _labColor(x: x, y: y),
  };

  /// Resolves a palette index while retaining a grayscale fallback for missing tables.
  PsRgbColor _indexedColor({
    required int x,
    required int y,
  }) {
    final int index = _byteSample(channelForSlot(0), x: x, y: y, fallback: 0);
    final Uint8List? table = palette;
    if (table == null || table.length < 256 * 3) {
      return _grayColor(index);
    }
    final int offset = index * 3;
    return PsRgbColor(red: table[offset], green: table[offset + 1], blue: table[offset + 2]);
  }

  /// Converts Photoshop's inverted CMYK samples with an optional caller profile.
  PsRgbColor _cmykColor({
    required int x,
    required int y,
    required PsCmykToRgbConverter? converter,
  }) {
    final double cyanInverted = _normalizedSample(channelForSlot(0), x: x, y: y, fallback: 1);
    final double magentaInverted = _normalizedSample(channelForSlot(1), x: x, y: y, fallback: 1);
    final double yellowInverted = _normalizedSample(channelForSlot(2), x: x, y: y, fallback: 1);
    final double blackInverted = _normalizedSample(channelForSlot(3), x: x, y: y, fallback: 1);
    if (converter != null) {
      return converter(
        cyan: 1 - cyanInverted,
        magenta: 1 - magentaInverted,
        yellow: 1 - yellowInverted,
        black: 1 - blackInverted,
      );
    }
    return PsRgbColor(
      red: (cyanInverted * blackInverted * 255).round().clamp(0, 255),
      green: (magentaInverted * blackInverted * 255).round().clamp(0, 255),
      blue: (yellowInverted * blackInverted * 255).round().clamp(0, 255),
    );
  }

  /// Converts normalized Photoshop Lab channels through D50 XYZ and sRGB.
  PsRgbColor _labColor({
    required int x,
    required int y,
  }) {
    final double lightness = _normalizedSample(channelForSlot(0), x: x, y: y, fallback: 0) * 100;
    final double a = _normalizedSample(channelForSlot(1), x: x, y: y, fallback: 128 / 255) * 255 - 128;
    final double b = _normalizedSample(channelForSlot(2), x: x, y: y, fallback: 128 / 255) * 255 - 128;
    final double fy = (lightness + 16) / 116;
    final double fx = fy + a / 500;
    final double fz = fy - b / 200;
    final double xD50 = 0.96422 * _labPivot(fx);
    final double yD50 = _labPivot(fy);
    final double zD50 = 0.82521 * _labPivot(fz);
    final double xD65 = 0.9555766 * xD50 - 0.0230393 * yD50 + 0.0631636 * zD50;
    final double yD65 = -0.0282895 * xD50 + 1.0099416 * yD50 + 0.0210077 * zD50;
    final double zD65 = 0.0122982 * xD50 - 0.0204830 * yD50 + 1.3299098 * zD50;
    final double redLinear = 3.2404542 * xD65 - 1.5371385 * yD65 - 0.4985314 * zD65;
    final double greenLinear = -0.969266 * xD65 + 1.8760108 * yD65 + 0.041556 * zD65;
    final double blueLinear = 0.0556434 * xD65 - 0.2040259 * yD65 + 1.0572252 * zD65;
    return PsRgbColor(
      red: _linearToByte(redLinear),
      green: _linearToByte(greenLinear),
      blue: _linearToByte(blueLinear),
    );
  }

  /// Applies the inverse CIE Lab transfer function.
  static double _labPivot(double value) {
    final double cube = value * value * value;
    return cube > 216 / 24389 ? cube : (116 * value - 16) / 903.2962962962963;
  }

  /// Converts one linear sRGB component to a byte.
  static int _linearToByte(double value) {
    final double encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * math.pow(value, 1 / 2.4).toDouble() - 0.055;
    return (encoded * 255).round().clamp(0, 255);
  }

  /// Creates an RGB color whose three components share [gray].
  static PsRgbColor _grayColor(int gray) => PsRgbColor(red: gray, green: gray, blue: gray);

  /// Reads a normalized sample without exposing nullable channel handling to render code.
  static double _normalizedSample(
    PsPatternChannel? channel, {
    required int x,
    required int y,
    required double fallback,
  }) => channel?.normalizedSampleAt(x: x, y: y, fallback: fallback) ?? fallback;

  /// Reads a byte sample without exposing nullable channel handling to render code.
  static int _byteSample(
    PsPatternChannel? channel, {
    required int x,
    required int y,
    required int fallback,
  }) => channel?.byteSampleAt(x: x, y: y, fallback: fallback) ?? fallback;
}
