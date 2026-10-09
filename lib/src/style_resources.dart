import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pscore/src/descriptor.dart';
import 'package:pscore/src/descriptor_access.dart';

/// Identifies the color representation used by a Photoshop color descriptor.
enum PsColorSpace {
  /// Red, green, and blue components in the Photoshop 0–255 range.
  rgb,

  /// Cyan, magenta, yellow, and black components in percent.
  cmyk,

  /// A single grayscale component in percent.
  grayscale,

  /// Hue, saturation, and brightness components.
  hsb,

  /// CIE L*a*b* components.
  lab,

  /// A named color from a Photoshop color book.
  book,

  /// A descriptor class not recognized by this release.
  unknown,
}

/// Identifies a Photoshop gradient-generation strategy.
enum PsGradientForm {
  /// Explicit color and transparency stops.
  customStops,

  /// Deterministic color-noise parameters.
  colorNoise,

  /// A form identifier not recognized by this release.
  unknown,
}

/// An exact color descriptor with convenient named components.
final class PsColor {
  /// Known interpretation of the Photoshop descriptor class.
  final PsColorSpace colorSpace;

  /// Photoshop descriptor class exactly as stored.
  final String classId;

  /// Numeric components keyed by their Photoshop identifiers.
  final Map<String, PsDescriptorNumber> components;

  /// Color-book name, when [colorSpace] is [PsColorSpace.book].
  final String? bookName;

  /// Named color within a color book, when available.
  final String? colorName;

  /// Numeric Photoshop color-book identifier, when available.
  final int? bookId;

  /// Opaque color-book lookup key, when available.
  final Uint8List? bookKey;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable color view.
  PsColor({
    required this.colorSpace,
    required this.classId,
    required Map<String, PsDescriptorNumber> components,
    required this.bookName,
    required this.colorName,
    required this.bookId,
    required Uint8List? bookKey,
    required this.descriptor,
  }) : components = Map<String, PsDescriptorNumber>.unmodifiable(components),
       bookKey = bookKey == null ? null : Uint8List.fromList(bookKey).asUnmodifiableView();

  /// Creates an `RGBC` color from components in the 0–255 range.
  factory PsColor.rgb({
    required double red,
    required double green,
    required double blue,
  }) => PsColor.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'RGBC',
      items: [
        PsDescriptorItem(
          key: 'Rd  ',
          value: PsDoubleValue(value: red),
        ),
        PsDescriptorItem(
          key: 'Grn ',
          value: PsDoubleValue(value: green),
        ),
        PsDescriptorItem(
          key: 'Bl  ',
          value: PsDoubleValue(value: blue),
        ),
      ],
    ),
  );

  /// Creates a `CMYC` color from ink coverages in percent.
  factory PsColor.cmyk({
    required double cyan,
    required double magenta,
    required double yellow,
    required double black,
  }) => PsColor._create('CMYC', {'Cyn ': cyan, 'Mgnt': magenta, 'Ylw ': yellow, 'Blck': black});

  /// Creates a `Grsc` color from an ink coverage in percent, where 0 is white.
  factory PsColor.grayscale({required double gray}) => PsColor._create('Grsc', {'Gry ': gray});

  /// Creates an `HSBC` color from a hue in degrees and percentages.
  factory PsColor.hsb({
    required double hue,
    required double saturation,
    required double brightness,
  }) => PsColor._create('HSBC', {'H   ': hue, 'Strt': saturation, 'Brgh': brightness}, units: const {'H   ': '#Ang'});

  /// Creates an `LbCl` color from CIE L*a*b* components.
  factory PsColor.lab({
    required double lightness,
    required double a,
    required double b,
  }) => PsColor._create('LbCl', {'Lmnc': lightness, 'A   ': a, 'B   ': b});

  /// Creates a typed view over a Photoshop color [descriptor].
  factory PsColor.fromDescriptor(PsDescriptor descriptor) {
    final List<String> componentKeys = switch (descriptor.classId) {
      'RGBC' || 'RGBColor' => const ['Rd  ', 'Grn ', 'Bl  ', 'red', 'green', 'blue'],
      'CMYC' || 'CMYKColor' => const ['Cyn ', 'Mgnt', 'Ylw ', 'Blck', 'cyan', 'magenta', 'yellowColor', 'black'],
      'Grsc' || 'grayscale' => const ['Gry ', 'gray'],
      'HSBC' || 'HSBColor' => const ['H   ', 'Strt', 'Brgh', 'hue', 'saturation', 'brightness'],
      'LbCl' || 'labColor' => const ['Lmnc', 'A   ', 'B   ', 'luminance', 'a', 'b'],
      _ => const <String>[],
    };
    final Map<String, PsDescriptorNumber> components = {};
    for (final String key in componentKeys) {
      final PsDescriptorNumber? number = descriptor.numberValue(key);
      if (number != null) {
        components[key] = number;
      }
    }
    return PsColor(
      colorSpace: _colorSpaceFor(descriptor.classId),
      classId: descriptor.classId,
      components: components,
      bookName: descriptor.stringValue('Bk  '),
      colorName: descriptor.stringValue('Nm  '),
      bookId: descriptor.integerValue('bookID'),
      bookKey: switch (descriptor.value('bookKey')) {
        PsRawValue(:final Uint8List value) => value,
        _ => null,
      },
      descriptor: descriptor,
    );
  }

  /// Returns the numeric component stored under [key].
  PsDescriptorNumber? component(String key) => components[key];

  /// Red component in the 0–255 range, when this is an RGB color.
  double? get red => (components['Rd  '] ?? components['red'])?.value;

  /// Green component in the 0–255 range, when this is an RGB color.
  double? get green => (components['Grn '] ?? components['green'])?.value;

  /// Blue component in the 0–255 range, when this is an RGB color.
  double? get blue => (components['Bl  '] ?? components['blue'])?.value;

  /// Approximates this color in sRGB, with components in the 0–255 range.
  ///
  /// The conversion uses textbook formulas without any ICC profile: CMYK is
  /// treated as naive subtractive ink and Lab as D50 adapted to D65 with the
  /// Bradford transform. Returns `null` for book colors, unknown classes, and
  /// descriptors missing a component.
  ({double red, double green, double blue})? toRgb() {
    double? read(String short, String long) => (components[short] ?? components[long])?.value;
    switch (colorSpace) {
      case PsColorSpace.rgb:
        final double? red = this.red;
        final double? green = this.green;
        final double? blue = this.blue;
        return red == null || green == null || blue == null ? null : (red: red, green: green, blue: blue);
      case PsColorSpace.grayscale:
        final double? gray = read('Gry ', 'gray');
        if (gray == null) {
          return null;
        }
        final double level = (100 - gray) * 2.55;
        return (red: level, green: level, blue: level);
      case PsColorSpace.cmyk:
        final double? cyan = read('Cyn ', 'cyan');
        final double? magenta = read('Mgnt', 'magenta');
        final double? yellow = read('Ylw ', 'yellowColor');
        final double? black = read('Blck', 'black');
        if (cyan == null || magenta == null || yellow == null || black == null) {
          return null;
        }
        final double retained = 255 * (1 - (black / 100).clamp(0, 1));
        return (
          red: (1 - (cyan / 100).clamp(0, 1)) * retained,
          green: (1 - (magenta / 100).clamp(0, 1)) * retained,
          blue: (1 - (yellow / 100).clamp(0, 1)) * retained,
        );
      case PsColorSpace.hsb:
        final double? hue = read('H   ', 'hue');
        final double? saturation = read('Strt', 'saturation');
        final double? brightness = read('Brgh', 'brightness');
        return hue == null || saturation == null || brightness == null ? null : _hsbToRgb(hue, saturation / 100, brightness / 100);
      case PsColorSpace.lab:
        final double? lightness = read('Lmnc', 'luminance');
        final double? a = read('A   ', 'a');
        final double? b = read('B   ', 'b');
        return lightness == null || a == null || b == null ? null : _labToRgb(lightness, a, b);
      case PsColorSpace.book || PsColorSpace.unknown:
        return null;
    }
  }

  /// Creates a color descriptor of [classId] holding [values] in order.
  factory PsColor._create(String classId, Map<String, double> values, {Map<String, String> units = const {}}) => PsColor.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: classId,
      items: [
        for (final MapEntry<String, double> entry in values.entries)
          PsDescriptorItem(
            key: entry.key,
            value: switch (units[entry.key]) {
              final String unit => PsUnitFloatValue(unit: unit, value: entry.value),
              null => PsDoubleValue(value: entry.value),
            },
          ),
      ],
    ),
  );

  /// Converts a hue in degrees and unit saturation and brightness to sRGB.
  static ({double red, double green, double blue}) _hsbToRgb(double hue, double saturation, double brightness) {
    final double sector = (hue % 360 + 360) % 360 / 60;
    final double s = saturation.clamp(0, 1);
    final double v = brightness.clamp(0, 1) * 255;
    final double fraction = sector - sector.floor();
    final double p = v * (1 - s);
    final double q = v * (1 - fraction * s);
    final double t = v * (1 - (1 - fraction) * s);
    return switch (sector.floor() % 6) {
      0 => (red: v, green: t, blue: p),
      1 => (red: q, green: v, blue: p),
      2 => (red: p, green: v, blue: t),
      3 => (red: p, green: q, blue: v),
      4 => (red: t, green: p, blue: v),
      _ => (red: v, green: p, blue: q),
    };
  }

  /// Converts D50 CIE L*a*b* to sRGB through the Bradford-adapted D65 white.
  static ({double red, double green, double blue}) _labToRgb(double lightness, double a, double b) {
    final double fy = (lightness + 16) / 116;
    final double x50 = 0.96422 * _inverseLabCurve(fy + a / 500);
    final double y50 = _inverseLabCurve(fy);
    final double z50 = 0.82521 * _inverseLabCurve(fy - b / 200);
    final double x = 0.9555766 * x50 - 0.0230393 * y50 + 0.0631636 * z50;
    final double y = -0.0282895 * x50 + 1.0099416 * y50 + 0.0210077 * z50;
    final double z = 0.0122982 * x50 - 0.020483 * y50 + 1.3299098 * z50;
    return (
      red: _encodeSrgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
      green: _encodeSrgb(-0.969266 * x + 1.8760108 * y + 0.041556 * z),
      blue: _encodeSrgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z),
    );
  }

  /// Applies the inverse CIE Lab transfer function.
  static double _inverseLabCurve(double value) => value > 6 / 29 ? value * value * value : (108 / 841) * (value - 4 / 29);

  /// Encodes a linear-light component as an sRGB value in the 0–255 range.
  static double _encodeSrgb(double value) => 255 * (value <= 0.0031308 ? value * 12.92 : 1.055 * math.pow(value, 1 / 2.4).toDouble() - 0.055).clamp(0, 1);

  /// Maps a Photoshop color descriptor [classId] to a known color space.
  static PsColorSpace _colorSpaceFor(String classId) => switch (classId) {
    'RGBC' || 'RGBColor' => PsColorSpace.rgb,
    'CMYC' || 'CMYKColor' => PsColorSpace.cmyk,
    'Grsc' || 'grayscale' => PsColorSpace.grayscale,
    'HSBC' || 'HSBColor' => PsColorSpace.hsb,
    'LbCl' || 'labColor' => PsColorSpace.lab,
    'BkCl' || 'bookColor' => PsColorSpace.book,
    _ => PsColorSpace.unknown,
  };
}

/// One color stop in a custom Photoshop gradient.
final class PsGradientColorStop {
  /// Stop position in Photoshop's 0–4096 gradient coordinate range.
  final int? location;

  /// Transition midpoint in percent.
  final int? midpoint;

  /// Photoshop stop-kind enumeration, such as `UsrS` or `FrgC`.
  final PsDescriptorEnumeration? kind;

  /// Explicit stop color, when the stop is not dynamically sourced.
  final PsColor? color;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable gradient color stop.
  const PsGradientColorStop({
    required this.location,
    required this.midpoint,
    required this.kind,
    required this.color,
    required this.descriptor,
  });

  /// Creates a user-defined `Clrt` stop with an explicit [color].
  factory PsGradientColorStop.create({
    required PsColor color,
    required int location,
    int midpoint = 50,
  }) => PsGradientColorStop.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'Clrt',
      items: [
        PsDescriptorItem(
          key: 'Clr ',
          value: PsObjectValue(value: color.descriptor),
        ),
        const PsDescriptorItem(
          key: 'Type',
          value: PsEnumeratedValue(typeId: 'Clry', value: 'UsrS'),
        ),
        PsDescriptorItem(
          key: 'Lctn',
          value: PsIntegerValue(value: location),
        ),
        PsDescriptorItem(
          key: 'Mdpn',
          value: PsIntegerValue(value: midpoint),
        ),
      ],
    ),
  );

  /// Creates a typed view over a Photoshop color-stop [descriptor].
  factory PsGradientColorStop.fromDescriptor(PsDescriptor descriptor) {
    final PsDescriptor? color = descriptor.objectValue('Clr ');
    return PsGradientColorStop(
      location: descriptor.integerValue('Lctn', mode: .compatible),
      midpoint: descriptor.integerValue('Mdpn', mode: .compatible),
      kind: descriptor.enumerationValue('Type'),
      color: color == null ? null : PsColor.fromDescriptor(color),
      descriptor: descriptor,
    );
  }
}

/// One opacity stop in a custom Photoshop gradient.
final class PsGradientTransparencyStop {
  /// Stop position in Photoshop's 0–4096 gradient coordinate range.
  final int? location;

  /// Transition midpoint in percent.
  final int? midpoint;

  /// Stop opacity, normally expressed with the `#Prc` unit.
  final PsDescriptorNumber? opacity;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable gradient transparency stop.
  const PsGradientTransparencyStop({
    required this.location,
    required this.midpoint,
    required this.opacity,
    required this.descriptor,
  });

  /// Creates a `TrnS` stop whose [opacity] is a percentage.
  factory PsGradientTransparencyStop.create({
    required double opacity,
    required int location,
    int midpoint = 50,
  }) => PsGradientTransparencyStop.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'TrnS',
      items: [
        PsDescriptorItem(
          key: 'Opct',
          value: PsUnitFloatValue(unit: '#Prc', value: opacity),
        ),
        PsDescriptorItem(
          key: 'Lctn',
          value: PsIntegerValue(value: location),
        ),
        PsDescriptorItem(
          key: 'Mdpn',
          value: PsIntegerValue(value: midpoint),
        ),
      ],
    ),
  );

  /// Creates a typed view over a Photoshop transparency-stop [descriptor].
  factory PsGradientTransparencyStop.fromDescriptor(PsDescriptor descriptor) => PsGradientTransparencyStop(
    location: descriptor.integerValue('Lctn', mode: .compatible),
    midpoint: descriptor.integerValue('Mdpn', mode: .compatible),
    opacity: descriptor.numberValue('Opct'),
    descriptor: descriptor,
  );
}

/// A Photoshop gradient descriptor preserving both stop and noise forms.
final class PsGradient {
  /// Preset name stored by Photoshop, when present.
  final String? name;

  /// Known interpretation of [formIdentifier].
  final PsGradientForm form;

  /// Exact gradient-form enumeration identifier.
  final String? formIdentifier;

  /// Interpolation smoothness in Photoshop's 0–4096 range.
  final double? smoothness;

  /// Explicit color stops in source order.
  final List<PsGradientColorStop> colorStops;

  /// Explicit transparency stops in source order.
  final List<PsGradientTransparencyStop> transparencyStops;

  /// Noise-gradient random seed, when present.
  final int? randomSeed;

  /// Whether a noise gradient generates transparency.
  final bool? showsTransparency;

  /// Whether a noise gradient restricts generated colors.
  final bool? restrictsColors;

  /// Noise-gradient color-space enumeration, when present.
  final PsDescriptorEnumeration? colorSpace;

  /// Four noise-gradient minimum channel values, when present.
  final List<int> minimumValues;

  /// Four noise-gradient maximum channel values, when present.
  final List<int> maximumValues;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable gradient view.
  PsGradient({
    required this.name,
    required this.form,
    required this.formIdentifier,
    required this.smoothness,
    required List<PsGradientColorStop> colorStops,
    required List<PsGradientTransparencyStop> transparencyStops,
    required this.randomSeed,
    required this.showsTransparency,
    required this.restrictsColors,
    required this.colorSpace,
    required List<int> minimumValues,
    required List<int> maximumValues,
    required this.descriptor,
  }) : colorStops = List<PsGradientColorStop>.unmodifiable(colorStops),
       transparencyStops = List<PsGradientTransparencyStop>.unmodifiable(transparencyStops),
       minimumValues = List<int>.unmodifiable(minimumValues),
       maximumValues = List<int>.unmodifiable(maximumValues);

  /// Creates a custom-stops `Grdn` gradient with full smoothness.
  factory PsGradient.custom({
    String name = 'Custom',
    required List<PsGradientColorStop> colorStops,
    List<PsGradientTransparencyStop> transparencyStops = const [],
  }) => PsGradient.fromDescriptor(
    PsDescriptor(
      name: '$name\u0000',
      classId: 'Grdn',
      items: [
        PsDescriptorItem(
          key: 'Nm  ',
          value: PsStringValue(value: '$name\u0000'),
        ),
        const PsDescriptorItem(
          key: 'GrdF',
          value: PsEnumeratedValue(typeId: 'GrdF', value: 'CstS'),
        ),
        const PsDescriptorItem(key: 'Intr', value: PsDoubleValue(value: 4096)),
        PsDescriptorItem(
          key: 'Clrs',
          value: PsListValue(
            values: [for (final PsGradientColorStop stop in colorStops) PsObjectValue(value: stop.descriptor)],
          ),
        ),
        PsDescriptorItem(
          key: 'Trns',
          value: PsListValue(
            values: [for (final PsGradientTransparencyStop stop in transparencyStops) PsObjectValue(value: stop.descriptor)],
          ),
        ),
      ],
    ),
  );

  /// Creates a typed view over a Photoshop gradient [descriptor].
  factory PsGradient.fromDescriptor(PsDescriptor descriptor) {
    final PsDescriptorEnumeration? form = descriptor.enumerationValue('GrdF');
    return PsGradient(
      name: descriptor.stringValue('Nm  '),
      form: switch (form?.value) {
        'CstS' || 'customStops' => PsGradientForm.customStops,
        'ClNs' || 'colorNoise' => PsGradientForm.colorNoise,
        _ => PsGradientForm.unknown,
      },
      formIdentifier: form?.value,
      smoothness: descriptor.scalarValue('Intr') ?? descriptor.scalarValue('Smth'),
      colorStops: [
        for (final PsDescriptor stop in _objects(descriptor.listValue('Clrs'))) PsGradientColorStop.fromDescriptor(stop),
      ],
      transparencyStops: [
        for (final PsDescriptor stop in _objects(descriptor.listValue('Trns'))) PsGradientTransparencyStop.fromDescriptor(stop),
      ],
      randomSeed: descriptor.integerValue('RndS'),
      showsTransparency: descriptor.booleanValue('ShTr'),
      restrictsColors: descriptor.booleanValue('VctC'),
      colorSpace: descriptor.enumerationValue('ClrS'),
      minimumValues: _integers(descriptor.listValue('Mnm ')),
      maximumValues: _integers(descriptor.listValue('Mxm ')),
      descriptor: descriptor,
    );
  }

  /// Extracts every integer value from an optional descriptor list.
  static List<int> _integers(List<PsDescriptorValue>? values) => [
    for (final PsDescriptorValue value in values ?? const <PsDescriptorValue>[])
      if (value case PsIntegerValue(:final int value)) value else if (value case PsLargeIntegerValue(:final int value)) value,
  ];
}

/// One point in a Photoshop shaping or gloss contour.
final class PsContourPoint {
  /// Horizontal contour coordinate.
  final PsDescriptorNumber? horizontal;

  /// Vertical contour coordinate.
  final PsDescriptorNumber? vertical;

  /// Whether Photoshop joins this point continuously to its neighbors.
  final bool? continuous;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable contour-point view.
  const PsContourPoint({
    required this.horizontal,
    required this.vertical,
    required this.continuous,
    required this.descriptor,
  });

  /// Creates a `CrPt` point with coordinates in the 0–255 range.
  factory PsContourPoint.create({
    required double horizontal,
    required double vertical,
    bool? continuous,
  }) => PsContourPoint.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'CrPt',
      items: [
        PsDescriptorItem(
          key: 'Hrzn',
          value: PsDoubleValue(value: horizontal),
        ),
        PsDescriptorItem(
          key: 'Vrtc',
          value: PsDoubleValue(value: vertical),
        ),
        if (continuous != null)
          PsDescriptorItem(
            key: 'Cnty',
            value: PsBooleanValue(value: continuous),
          ),
      ],
    ),
  );

  /// Creates a typed view over one contour-point [descriptor].
  factory PsContourPoint.fromDescriptor(PsDescriptor descriptor) => PsContourPoint(
    horizontal: descriptor.numberValue('Hrzn'),
    vertical: descriptor.numberValue('Vrtc'),
    continuous: descriptor.booleanValue('Cnty'),
    descriptor: descriptor,
  );
}

/// A Photoshop shaping curve used by contours and Satin mappings.
final class PsContour {
  /// Human-readable contour name, when stored.
  final String? name;

  /// Curve points in source order.
  final List<PsContourPoint> points;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable contour view.
  PsContour({
    required this.name,
    required List<PsContourPoint> points,
    required this.descriptor,
  }) : points = List<PsContourPoint>.unmodifiable(points);

  /// Creates a named `ShpC` contour from [points].
  factory PsContour.create({
    required String name,
    required List<PsContourPoint> points,
  }) => PsContour.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'ShpC',
      items: [
        PsDescriptorItem(
          key: 'Nm  ',
          value: PsStringValue(value: '$name\u0000'),
        ),
        PsDescriptorItem(
          key: 'Crv ',
          value: PsListValue(values: [for (final PsContourPoint point in points) PsObjectValue(value: point.descriptor)]),
        ),
      ],
    ),
  );

  /// Creates Photoshop's default two-point `Linear` contour.
  factory PsContour.linear() => PsContour.create(
    name: 'Linear',
    points: [
      PsContourPoint.create(horizontal: 0, vertical: 0),
      PsContourPoint.create(horizontal: 255, vertical: 255),
    ],
  );

  /// Creates a typed view over a Photoshop contour [descriptor].
  factory PsContour.fromDescriptor(PsDescriptor descriptor) => PsContour(
    name: descriptor.stringValue('Nm  '),
    points: [for (final PsDescriptor point in _objects(descriptor.listValue('Crv '))) PsContourPoint.fromDescriptor(point)],
    descriptor: descriptor,
  );
}

/// A name and stable identifier referring to an embedded Photoshop pattern.
final class PsPatternReference {
  /// User-visible pattern name, when stored.
  final String? name;

  /// Pattern identifier used to resolve embedded pixel data.
  final String? id;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable pattern reference.
  const PsPatternReference({
    required this.name,
    required this.id,
    required this.descriptor,
  });

  /// Creates a `Ptrn` reference to the pattern identified by [id].
  factory PsPatternReference.create({
    required String name,
    required String id,
  }) => PsPatternReference.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'Ptrn',
      items: [
        PsDescriptorItem(
          key: 'Nm  ',
          value: PsStringValue(value: '$name\u0000'),
        ),
        PsDescriptorItem(
          key: 'Idnt',
          value: PsStringValue(value: '$id\u0000'),
        ),
      ],
    ),
  );

  /// Creates a typed view over a Photoshop pattern [descriptor].
  factory PsPatternReference.fromDescriptor(PsDescriptor descriptor) => PsPatternReference(
    name: descriptor.stringValue('Nm  '),
    id: descriptor.stringValue('Idnt') ?? descriptor.stringValue('identifier'),
    descriptor: descriptor,
  );
}

/// A two-dimensional descriptor point used by layer-style offsets and phases.
final class PsPoint {
  /// Horizontal coordinate with its optional Photoshop unit.
  final PsDescriptorNumber? horizontal;

  /// Vertical coordinate with its optional Photoshop unit.
  final PsDescriptorNumber? vertical;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable point view.
  const PsPoint({
    required this.horizontal,
    required this.vertical,
    required this.descriptor,
  });

  /// Creates a `Pnt ` point, storing unit floats when [unit] is given.
  factory PsPoint.create({
    required double horizontal,
    required double vertical,
    String? unit,
  }) => PsPoint.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'Pnt ',
      items: [
        PsDescriptorItem(key: 'Hrzn', value: _number(horizontal, unit)),
        PsDescriptorItem(key: 'Vrtc', value: _number(vertical, unit)),
      ],
    ),
  );

  /// Creates a typed view over a Photoshop point [descriptor].
  factory PsPoint.fromDescriptor(PsDescriptor descriptor) => PsPoint(
    horizontal: descriptor.numberValue('Hrzn'),
    vertical: descriptor.numberValue('Vrtc'),
    descriptor: descriptor,
  );

  /// Encodes [value] as a plain double or as a unit float.
  static PsDescriptorValue _number(double value, String? unit) => unit == null ? PsDoubleValue(value: value) : PsUnitFloatValue(unit: unit, value: value);
}

/// Returns the object descriptors found in an optional descriptor list.
List<PsDescriptor> _objects(List<PsDescriptorValue>? values) => [
  for (final PsDescriptorValue value in values ?? const <PsDescriptorValue>[])
    if (value case PsObjectValue(:final PsDescriptor value)) value,
];
