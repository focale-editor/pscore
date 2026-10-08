import 'package:pscore/src/descriptor.dart';
import 'package:pscore/src/descriptor_access.dart';
import 'package:pscore/src/style_resources.dart';

/// Identifies a recognized Photoshop layer-effect family.
enum PsLayerEffectKind {
  /// A shadow cast outside the layer silhouette.
  dropShadow(rootKey: 'DrSh', multiRootKey: 'dropShadowMulti'),

  /// A shadow composited inside the layer silhouette.
  innerShadow(rootKey: 'IrSh', multiRootKey: 'innerShadowMulti'),

  /// A glow composited outside the layer silhouette.
  outerGlow(rootKey: 'OrGl', multiRootKey: 'outerGlowMulti'),

  /// A glow composited inside the layer silhouette.
  innerGlow(rootKey: 'IrGl', multiRootKey: 'innerGlowMulti'),

  /// Bevel, emboss, contour, and texture settings.
  bevelAndEmboss(rootKey: 'ebbl', multiRootKey: 'bevelEmbossMulti'),

  /// Photoshop's Satin effect, historically named Chrome FX.
  satin(rootKey: 'ChFX', multiRootKey: 'satinMulti'),

  /// A solid-color overlay.
  colorOverlay(rootKey: 'SoFi', multiRootKey: 'solidFillMulti'),

  /// A gradient overlay.
  gradientOverlay(rootKey: 'GrFl', multiRootKey: 'gradientFillMulti'),

  /// A pattern overlay.
  patternOverlay(rootKey: 'patternFill', multiRootKey: 'patternFillMulti'),

  /// A stroke whose paint may be solid, gradient, or patterned.
  stroke(rootKey: 'FrFX', multiRootKey: 'frameFXMulti'),

  /// A forward-compatible effect key not recognized by this release.
  unknown(rootKey: null, multiRootKey: null);

  /// Key and descriptor class Photoshop writes for a single instance.
  final String? rootKey;

  /// Key Photoshop writes for a list of several instances.
  final String? multiRootKey;

  /// Creates an effect family stored under the given keys.
  const PsLayerEffectKind({
    required this.rootKey,
    required this.multiRootKey,
  });

  /// Maps legacy four-character and modern multi-instance keys to a family.
  static PsLayerEffectKind fromKey(String key) => switch (key) {
    'DrSh' || 'dropShadow' || 'dropShadowMulti' => dropShadow,
    'IrSh' || 'innerShadow' || 'innerShadowMulti' => innerShadow,
    'OrGl' || 'outerGlow' || 'outerGlowMulti' => outerGlow,
    'IrGl' || 'innerGlow' || 'innerGlowMulti' => innerGlow,
    'ebbl' || 'bevelEmboss' || 'bevelEmbossMulti' => bevelAndEmboss,
    'ChFX' || 'chromeFX' || 'satin' || 'satinMulti' => satin,
    'SoFi' || 'solidFill' || 'solidFillMulti' => colorOverlay,
    'GrFl' || 'gradientFill' || 'gradientFillMulti' => gradientOverlay,
    'patternFill' || 'patternFillMulti' => patternOverlay,
    'FrFX' || 'frameFX' || 'frameFXMulti' => stroke,
    _ => unknown,
  };
}

/// Placement of a Photoshop layer stroke.
enum PsStrokePosition {
  /// Draws the stroke inside the layer edge.
  inside('InsF'),

  /// Centers the stroke on the layer edge.
  center('CtrF'),

  /// Draws the stroke outside the layer edge.
  outside('OutF');

  /// Photoshop `FStl` enumeration identifier.
  final String identifier;

  /// Creates a position stored as [identifier].
  const PsStrokePosition(this.identifier);

  /// Maps an `FStl` identifier, treating unknown values as [outside].
  static PsStrokePosition fromIdentifier(String? identifier) => switch (identifier) {
    'InsF' => inside,
    'CtrF' => center,
    _ => outside,
  };
}

/// Geometry used by a gradient effect.
enum PsGradientStyle {
  /// A straight linear gradient.
  linear('Lnr '),

  /// A radial gradient.
  radial('Rdl '),

  /// An angle gradient.
  angle('Angl'),

  /// A reflected linear gradient.
  reflected('Rflc'),

  /// A diamond gradient.
  diamond('Dmnd');

  /// Photoshop `GrdT` enumeration identifier.
  final String identifier;

  /// Creates a style stored as [identifier].
  const PsGradientStyle(this.identifier);

  /// Maps a `GrdT` identifier, treating unknown values as [linear].
  static PsGradientStyle fromIdentifier(String? identifier) => switch (identifier) {
    'Rdl ' => radial,
    'Angl' => angle,
    'Rflc' => reflected,
    'Dmnd' => diamond,
    _ => linear,
  };
}

/// One layer-effect instance extracted without discarding descriptor fields.
final class PsLayerEffect {
  /// Key used by the parent `Lefx` descriptor.
  final String key;

  /// Zero-based instance position for an effect family.
  final int instanceIndex;

  /// Known semantic effect family.
  final PsLayerEffectKind kind;

  /// Complete effect descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable effect view.
  const PsLayerEffect({
    required this.key,
    required this.instanceIndex,
    required this.kind,
    required this.descriptor,
  });

  /// Creates a Photoshop-compatible effect of [kind] with common settings.
  ///
  /// Parameters irrelevant to [kind] are ignored. Bevel and Emboss uses
  /// [color] and [opacity] for its highlight and [opacity] for its shadow.
  factory PsLayerEffect.create({
    required PsLayerEffectKind kind,
    bool enabled = true,
    String blendMode = 'Nrml',
    double opacity = 100,
    PsColor? color,
    double size = 5,
    double angle = 90,
    double distance = 0,
    double spread = 0,
    double noise = 0,
    bool useGlobalAngle = true,
    PsStrokePosition strokePosition = PsStrokePosition.outside,
    PsGradient? gradient,
    PsGradientStyle gradientStyle = PsGradientStyle.linear,
    PsPatternReference? pattern,
    bool reverse = false,
    bool dither = false,
    bool aligned = true,
    double scale = 100,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final String? classId = kind.rootKey;
    if (classId == null) {
      throw ArgumentError.value(kind, 'kind', 'Unknown effects cannot be created');
    }
    final PsDescriptorValue colorValue = PsObjectValue(value: (color ?? _black()).descriptor);
    final List<PsDescriptorItem> items = [
      PsDescriptorItem(
        key: 'enab',
        value: PsBooleanValue(value: enabled),
      ),
      const PsDescriptorItem(key: 'present', value: PsBooleanValue(value: true)),
      const PsDescriptorItem(key: 'showInDialog', value: PsBooleanValue(value: true)),
      if (kind != PsLayerEffectKind.bevelAndEmboss) ...[
        PsDescriptorItem(
          key: 'Md  ',
          value: PsEnumeratedValue(typeId: 'BlnM', value: blendMode),
        ),
        PsDescriptorItem(key: 'Opct', value: _percent(opacity)),
      ],
      ...switch (kind) {
        PsLayerEffectKind.dropShadow || PsLayerEffectKind.innerShadow => [
          PsDescriptorItem(key: 'Clr ', value: colorValue),
          PsDescriptorItem(
            key: 'uglg',
            value: PsBooleanValue(value: useGlobalAngle),
          ),
          PsDescriptorItem(key: 'lagl', value: _angle(angle)),
          PsDescriptorItem(key: 'Dstn', value: _pixels(distance)),
          PsDescriptorItem(key: 'Ckmt', value: _pixels(spread)),
          PsDescriptorItem(key: 'blur', value: _pixels(size)),
          PsDescriptorItem(key: 'Nose', value: _percent(noise)),
          const PsDescriptorItem(key: 'AntA', value: PsBooleanValue(value: false)),
          PsDescriptorItem(key: 'TrnS', value: _linearContour()),
          const PsDescriptorItem(key: 'layerConceals', value: PsBooleanValue(value: true)),
        ],
        PsLayerEffectKind.outerGlow || PsLayerEffectKind.innerGlow => [
          PsDescriptorItem(key: 'Clr ', value: colorValue),
          const PsDescriptorItem(
            key: 'GlwT',
            value: PsEnumeratedValue(typeId: 'BETE', value: 'SfBL'),
          ),
          PsDescriptorItem(key: 'Ckmt', value: _pixels(spread)),
          PsDescriptorItem(key: 'blur', value: _pixels(size)),
          PsDescriptorItem(key: 'Nose', value: _percent(noise)),
          PsDescriptorItem(key: 'ShdN', value: _percent(0)),
          const PsDescriptorItem(key: 'AntA', value: PsBooleanValue(value: false)),
          PsDescriptorItem(key: 'TrnS', value: _linearContour()),
          PsDescriptorItem(key: 'Inpr', value: _percent(50)),
          if (kind == PsLayerEffectKind.innerGlow)
            const PsDescriptorItem(
              key: 'glwS',
              value: PsEnumeratedValue(typeId: 'IGSr', value: 'SrcE'),
            ),
        ],
        PsLayerEffectKind.colorOverlay => [
          PsDescriptorItem(key: 'Clr ', value: colorValue),
        ],
        PsLayerEffectKind.gradientOverlay => [
          PsDescriptorItem(
            key: 'Grad',
            value: PsObjectValue(value: (gradient ?? _defaultGradient(color ?? _black())).descriptor),
          ),
          PsDescriptorItem(key: 'Angl', value: _angle(angle)),
          PsDescriptorItem(
            key: 'Type',
            value: PsEnumeratedValue(typeId: 'GrdT', value: gradientStyle.identifier),
          ),
          PsDescriptorItem(
            key: 'Rvrs',
            value: PsBooleanValue(value: reverse),
          ),
          PsDescriptorItem(
            key: 'Dthr',
            value: PsBooleanValue(value: dither),
          ),
          PsDescriptorItem(
            key: 'Algn',
            value: PsBooleanValue(value: aligned),
          ),
          PsDescriptorItem(key: 'Scl ', value: _percent(scale)),
          PsDescriptorItem(
            key: 'Ofst',
            value: PsObjectValue(
              value: PsPoint.create(horizontal: offsetX, vertical: offsetY, unit: '#Prc').descriptor,
            ),
          ),
        ],
        PsLayerEffectKind.patternOverlay => [
          PsDescriptorItem(
            key: 'Ptrn',
            value: PsObjectValue(
              value: (pattern ?? PsPatternReference.create(name: '', id: '')).descriptor,
            ),
          ),
          PsDescriptorItem(key: 'Scl ', value: _percent(scale)),
          PsDescriptorItem(
            key: 'Algn',
            value: PsBooleanValue(value: aligned),
          ),
          PsDescriptorItem(
            key: 'phase',
            value: PsObjectValue(
              value: PsPoint.create(horizontal: offsetX, vertical: offsetY).descriptor,
            ),
          ),
        ],
        PsLayerEffectKind.stroke => [
          PsDescriptorItem(
            key: 'Styl',
            value: PsEnumeratedValue(typeId: 'FStl', value: strokePosition.identifier),
          ),
          PsDescriptorItem(
            key: 'PntT',
            value: PsEnumeratedValue(
              typeId: 'FrFl',
              value: gradient != null ? 'GrFl' : (pattern != null ? 'Ptrn' : 'SClr'),
            ),
          ),
          PsDescriptorItem(key: 'Sz  ', value: _pixels(size)),
          PsDescriptorItem(key: 'Clr ', value: colorValue),
          const PsDescriptorItem(key: 'overprint', value: PsBooleanValue(value: false)),
          if (gradient != null)
            PsDescriptorItem(
              key: 'Grad',
              value: PsObjectValue(value: gradient.descriptor),
            )
          else if (pattern != null)
            PsDescriptorItem(
              key: 'Ptrn',
              value: PsObjectValue(value: pattern.descriptor),
            ),
        ],
        PsLayerEffectKind.satin => [
          PsDescriptorItem(key: 'Clr ', value: colorValue),
          PsDescriptorItem(key: 'lagl', value: _angle(angle)),
          PsDescriptorItem(key: 'Dstn', value: _pixels(distance)),
          PsDescriptorItem(key: 'blur', value: _pixels(size)),
          const PsDescriptorItem(key: 'AntA', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'Invr', value: PsBooleanValue(value: false)),
          PsDescriptorItem(key: 'MpgS', value: _linearContour()),
        ],
        PsLayerEffectKind.bevelAndEmboss => [
          const PsDescriptorItem(
            key: 'hglM',
            value: PsEnumeratedValue(typeId: 'BlnM', value: 'Scrn'),
          ),
          PsDescriptorItem(key: 'hglC', value: colorValue),
          PsDescriptorItem(key: 'hglO', value: _percent(opacity)),
          const PsDescriptorItem(
            key: 'sdwM',
            value: PsEnumeratedValue(typeId: 'BlnM', value: 'Mltp'),
          ),
          PsDescriptorItem(
            key: 'sdwC',
            value: PsObjectValue(value: _black().descriptor),
          ),
          PsDescriptorItem(key: 'sdwO', value: _percent(opacity)),
          const PsDescriptorItem(
            key: 'bvlT',
            value: PsEnumeratedValue(typeId: 'bvlT', value: 'SfBL'),
          ),
          const PsDescriptorItem(
            key: 'bvlS',
            value: PsEnumeratedValue(typeId: 'BESl', value: 'InrB'),
          ),
          PsDescriptorItem(
            key: 'uglg',
            value: PsBooleanValue(value: useGlobalAngle),
          ),
          PsDescriptorItem(key: 'lagl', value: _angle(angle)),
          PsDescriptorItem(key: 'Lald', value: _angle(30)),
          PsDescriptorItem(key: 'srgR', value: _percent(100)),
          PsDescriptorItem(key: 'blur', value: _pixels(size)),
          const PsDescriptorItem(
            key: 'bvlD',
            value: PsEnumeratedValue(typeId: 'BESs', value: 'In  '),
          ),
          PsDescriptorItem(key: 'TrnS', value: _linearContour()),
          const PsDescriptorItem(key: 'antialiasGloss', value: PsBooleanValue(value: false)),
          PsDescriptorItem(key: 'Sftn', value: _pixels(0)),
          const PsDescriptorItem(key: 'useShape', value: PsBooleanValue(value: false)),
          const PsDescriptorItem(key: 'useTexture', value: PsBooleanValue(value: false)),
        ],
        PsLayerEffectKind.unknown => const <PsDescriptorItem>[],
      },
    ];
    return PsLayerEffect(
      key: classId,
      instanceIndex: 0,
      kind: kind,
      descriptor: PsDescriptor(name: '\u0000', classId: classId, items: items),
    );
  }

  /// Whether Photoshop marks this effect as enabled.
  bool? get enabled => descriptor.booleanValue('enab');

  /// Whether Photoshop records this effect as present in the dialog.
  bool? get present => descriptor.booleanValue('present');

  /// Whether Photoshop records this effect as visible in the style dialog.
  bool? get shownInDialog => descriptor.booleanValue('showInDialog');

  /// Effect blend mode stored under `Md  `, when applicable.
  PsDescriptorEnumeration? get blendMode => descriptor.enumerationValue('Md  ');

  /// Effect opacity stored under `Opct`, when applicable.
  PsDescriptorNumber? get opacity => descriptor.numberValue('Opct');

  /// Effect scale stored under `Scl `, when applicable.
  PsDescriptorNumber? get scale => descriptor.numberValue('Scl ');

  /// Primary angle stored under `Angl` or legacy local-light key `lagl`.
  PsDescriptorNumber? get angle => descriptor.numberValue('Angl') ?? descriptor.numberValue('lagl');

  /// Whether the effect uses the document's global lighting angle.
  bool? get usesGlobalAngle => descriptor.booleanValue('uglg');

  /// Lighting altitude stored under `Lald`, when applicable.
  PsDescriptorNumber? get altitude => descriptor.numberValue('Lald');

  /// Effect distance stored under `Dstn`, when applicable.
  PsDescriptorNumber? get distance => descriptor.numberValue('Dstn');

  /// Visual size stored as `blur` or stroke-specific `Sz  `.
  PsDescriptorNumber? get size => descriptor.numberValue('blur') ?? descriptor.numberValue('Sz  ');

  /// Shadow or glow choke/spread stored under `Ckmt`.
  PsDescriptorNumber? get chokeOrSpread => descriptor.numberValue('Ckmt');

  /// Effect noise stored under `Nose`, when applicable.
  PsDescriptorNumber? get noise => descriptor.numberValue('Nose');

  /// Glow jitter stored under `ShdN`, when applicable.
  PsDescriptorNumber? get jitter => descriptor.numberValue('ShdN');

  /// Contour input range stored under `Inpr`, when applicable.
  PsDescriptorNumber? get inputRange => descriptor.numberValue('Inpr');

  /// Bevel depth stored under `srgR`, when applicable.
  PsDescriptorNumber? get depth => descriptor.numberValue('srgR');

  /// Bevel softness stored under `Sftn`, when applicable.
  PsDescriptorNumber? get softness => descriptor.numberValue('Sftn');

  /// Bevel texture depth stored under `textureDepth`, when applicable.
  PsDescriptorNumber? get textureDepth => descriptor.numberValue('textureDepth');

  /// Whether the primary contour is anti-aliased.
  bool? get antiAliased => descriptor.booleanValue('AntA');

  /// Whether the bevel gloss contour is anti-aliased.
  bool? get glossAntiAliased => descriptor.booleanValue('antialiasGloss');

  /// Whether the source layer knocks out an outer shadow.
  bool? get layerConceals => descriptor.booleanValue('layerConceals');

  /// Whether Satin reverses its tonal mapping.
  bool? get inverted => descriptor.booleanValue('Invr');

  /// Whether a gradient direction is reversed.
  bool? get reversed => descriptor.booleanValue('Rvrs');

  /// Whether a gradient or pattern is aligned with the layer.
  bool? get aligned => descriptor.booleanValue('Algn');

  /// Whether a stroke pattern is linked with the layer.
  bool? get linked => descriptor.booleanValue('Lnkd');

  /// Whether gradient dithering is enabled.
  bool? get dithered => descriptor.booleanValue('Dthr');

  /// Whether Bevel and Emboss applies its contour sub-effect.
  bool? get usesShape => descriptor.booleanValue('useShape');

  /// Whether Bevel and Emboss applies its texture sub-effect.
  bool? get usesTexture => descriptor.booleanValue('useTexture');

  /// Whether a bevel texture is inverted.
  bool? get textureInverted => descriptor.booleanValue('InvT');

  /// Glow technique stored under `GlwT`, when applicable.
  PsDescriptorEnumeration? get glowTechnique => descriptor.enumerationValue('GlwT');

  /// Inner-glow source stored under `glwS`, when applicable.
  PsDescriptorEnumeration? get innerGlowSource => descriptor.enumerationValue('glwS');

  /// Bevel technique stored under `bvlT`, when applicable.
  PsDescriptorEnumeration? get bevelTechnique => descriptor.enumerationValue('bvlT');

  /// Bevel style stored under `bvlS`, when applicable.
  PsDescriptorEnumeration? get bevelStyle => descriptor.enumerationValue('bvlS');

  /// Bevel direction stored under `bvlD`, when applicable.
  PsDescriptorEnumeration? get bevelDirection => descriptor.enumerationValue('bvlD');

  /// Gradient geometry stored under `Type`, when applicable.
  PsDescriptorEnumeration? get gradientType => descriptor.enumerationValue('Type');

  /// Stroke position stored under `Styl`, when applicable.
  PsDescriptorEnumeration? get strokePosition => descriptor.enumerationValue('Styl');

  /// Stroke paint source stored under `PntT`, when applicable.
  PsDescriptorEnumeration? get strokePaintType => descriptor.enumerationValue('PntT');

  /// Bevel highlight blend mode stored under `hglM`.
  PsDescriptorEnumeration? get highlightBlendMode => descriptor.enumerationValue('hglM');

  /// Bevel highlight opacity stored under `hglO`.
  PsDescriptorNumber? get highlightOpacity => descriptor.numberValue('hglO');

  /// Bevel shadow blend mode stored under `sdwM`.
  PsDescriptorEnumeration? get shadowBlendMode => descriptor.enumerationValue('sdwM');

  /// Bevel shadow opacity stored under `sdwO`.
  PsDescriptorNumber? get shadowOpacity => descriptor.numberValue('sdwO');

  /// Primary color stored under `Clr `, when applicable.
  PsColor? get color => colorAt('Clr ');

  /// Bevel highlight color stored under `hglC`, when applicable.
  PsColor? get highlightColor => colorAt('hglC');

  /// Bevel shadow color stored under `sdwC`, when applicable.
  PsColor? get shadowColor => colorAt('sdwC');

  /// Gradient definition stored under `Grad`, when applicable.
  PsGradient? get gradient {
    final PsDescriptor? value = descriptor.objectValue('Grad');
    return value == null ? null : PsGradient.fromDescriptor(value);
  }

  /// Pattern reference stored under `Ptrn`, when applicable.
  PsPatternReference? get pattern {
    final PsDescriptor? value = descriptor.objectValue('Ptrn');
    return value == null ? null : PsPatternReference.fromDescriptor(value);
  }

  /// Pattern or gradient phase stored under `phase`, when applicable.
  PsPoint? get phase => _pointAt('phase');

  /// Gradient offset stored under `Ofst`, when applicable.
  PsPoint? get offset => _pointAt('Ofst');

  /// Transparency or gloss contour stored under `TrnS`, when applicable.
  PsContour? get transparencyContour => contourAt('TrnS');

  /// Mapping contour stored under `MpgS`, when applicable.
  PsContour? get mappingContour => contourAt('MpgS');

  /// Returns any numeric parameter stored under [key].
  PsDescriptorNumber? number(String key) => descriptor.numberValue(key);

  /// Returns any Boolean parameter stored under [key].
  bool? boolean(String key) => descriptor.booleanValue(key);

  /// Returns any enumeration parameter stored under [key].
  PsDescriptorEnumeration? enumeration(String key) => descriptor.enumerationValue(key);

  /// Returns any nested descriptor stored under [key].
  PsDescriptor? object(String key) => descriptor.objectValue(key);

  /// Returns a color object stored under [key].
  PsColor? colorAt(String key) {
    final PsDescriptor? value = descriptor.objectValue(key);
    return value == null ? null : PsColor.fromDescriptor(value);
  }

  /// Returns a contour object stored under [key].
  PsContour? contourAt(String key) {
    final PsDescriptor? value = descriptor.objectValue(key);
    return value == null ? null : PsContour.fromDescriptor(value);
  }

  /// Returns a point object stored under [key].
  PsPoint? _pointAt(String key) {
    final PsDescriptor? value = descriptor.objectValue(key);
    return value == null ? null : PsPoint.fromDescriptor(value);
  }

  /// Returns opaque RGB black.
  static PsColor _black() => PsColor.rgb(red: 0, green: 0, blue: 0);

  /// Returns a percentage unit float.
  static PsDescriptorValue _percent(double value) => PsUnitFloatValue(unit: '#Prc', value: value);

  /// Returns a pixel unit float.
  static PsDescriptorValue _pixels(double value) => PsUnitFloatValue(unit: '#Pxl', value: value);

  /// Returns an angle unit float.
  static PsDescriptorValue _angle(double value) => PsUnitFloatValue(unit: '#Ang', value: value);

  /// Returns Photoshop's default linear contour as a descriptor value.
  static PsDescriptorValue _linearContour() => PsObjectValue(value: PsContour.linear().descriptor);

  /// Returns an opaque two-stop gradient from black to [color].
  static PsGradient _defaultGradient(PsColor color) => PsGradient.custom(
    colorStops: [
      PsGradientColorStop.create(color: _black(), location: 0),
      PsGradientColorStop.create(color: color, location: 4096),
    ],
    transparencyStops: [
      PsGradientTransparencyStop.create(opacity: 100, location: 0),
      PsGradientTransparencyStop.create(opacity: 100, location: 4096),
    ],
  );
}

/// The complete `Lefx` object and source-ordered typed effect views.
final class PsLayerEffects {
  /// Complete `Lefx` descriptor.
  final PsDescriptor descriptor;

  /// Global layer-effect scale, normally expressed in percent.
  final PsDescriptorNumber? scale;

  /// Master switch controlling all effects, when stored.
  final bool? masterEnabled;

  /// Every recognized or forward-compatible effect object in source order.
  final List<PsLayerEffect> effects;

  /// Descriptor items not interpreted as global settings or effect objects.
  final List<PsDescriptorItem> unmodeledItems;

  /// Creates an immutable layer-effects view.
  PsLayerEffects({
    required this.descriptor,
    required this.scale,
    required this.masterEnabled,
    required List<PsLayerEffect> effects,
    required List<PsDescriptorItem> unmodeledItems,
  }) : effects = List<PsLayerEffect>.unmodifiable(effects),
       unmodeledItems = List<PsDescriptorItem>.unmodifiable(unmodeledItems);

  /// Creates typed views over every effect object in [descriptor].
  factory PsLayerEffects.fromDescriptor(PsDescriptor descriptor) {
    final List<PsLayerEffect> effects = [];
    final List<PsDescriptorItem> unmodeledItems = [];
    final Map<PsLayerEffectKind, int> instanceCounts = {};
    for (final PsDescriptorItem item in descriptor.items) {
      if (item.key == 'Scl ' || item.key == 'masterFXSwitch') {
        continue;
      }
      final PsLayerEffectKind kind = PsLayerEffectKind.fromKey(item.key);
      final List<PsDescriptor> instances = item.value.asObjects();
      final bool resemblesEffect = kind != PsLayerEffectKind.unknown || item.key.endsWith('Multi');
      if (instances.isEmpty || (!resemblesEffect && item.value is! PsObjectValue)) {
        unmodeledItems.add(item);
        continue;
      }
      int nextIndex = instanceCounts[kind] ?? 0;
      for (final PsDescriptor instance in instances) {
        effects.add(
          PsLayerEffect(
            key: item.key,
            instanceIndex: nextIndex,
            kind: kind,
            descriptor: instance,
          ),
        );
        nextIndex++;
      }
      instanceCounts[kind] = nextIndex;
    }
    return PsLayerEffects(
      descriptor: descriptor,
      scale: descriptor.numberValue('Scl '),
      masterEnabled: descriptor.booleanValue('masterFXSwitch'),
      effects: effects,
      unmodeledItems: unmodeledItems,
    );
  }

  /// Returns every effect belonging to [kind].
  List<PsLayerEffect> effectsOf(PsLayerEffectKind kind) => List<PsLayerEffect>.unmodifiable(effects.where((effect) => effect.kind == kind));

  /// Returns the first effect belonging to [kind], when present.
  PsLayerEffect? firstEffectOf(PsLayerEffectKind kind) {
    for (final PsLayerEffect effect in effects) {
      if (effect.kind == kind) {
        return effect;
      }
    }
    return null;
  }

  /// Serializes [effects] as `Lefx` root items grouped by family.
  ///
  /// A family with one instance is written under its singular key, and a
  /// family with several instances under its multi-instance list key. Unknown
  /// effects are skipped because Photoshop has no key for them.
  static List<PsDescriptorItem> rootItems(Iterable<({PsLayerEffectKind kind, PsDescriptor descriptor})> effects) {
    final List<PsDescriptorItem> result = [];
    for (final PsLayerEffectKind kind in PsLayerEffectKind.values) {
      final String? rootKey = kind.rootKey;
      final String? multiRootKey = kind.multiRootKey;
      final List<PsDescriptor> matches = [
        for (final effect in effects)
          if (effect.kind == kind) effect.descriptor,
      ];
      if (rootKey == null || multiRootKey == null || matches.isEmpty) {
        continue;
      }
      result.add(
        matches.length == 1
            ? PsDescriptorItem(
                key: rootKey,
                value: PsObjectValue(value: matches.single),
              )
            : PsDescriptorItem(
                key: multiRootKey,
                value: PsListValue(values: [for (final PsDescriptor match in matches) PsObjectValue(value: match)]),
              ),
      );
    }
    return result;
  }
}

/// One Photoshop Blend If channel range.
final class PsBlendRange {
  /// Referenced Photoshop channel identifier, when decoded.
  final String? channel;

  /// Lower black split point for the source layer.
  final int? sourceBlackLow;

  /// Upper black split point for the source layer.
  final int? sourceBlackHigh;

  /// Lower white split point for the source layer.
  final int? sourceWhiteLow;

  /// Upper white split point for the source layer.
  final int? sourceWhiteHigh;

  /// Lower black split point for underlying layers.
  final int? destinationBlackLow;

  /// Upper black split point for underlying layers.
  final int? destinationBlackHigh;

  /// Lower white split point for underlying layers.
  final int? destinationWhiteLow;

  /// Upper white split point for underlying layers.
  final int? destinationWhiteHigh;

  /// Complete source descriptor.
  final PsDescriptor descriptor;

  /// Creates an immutable Blend If range.
  const PsBlendRange({
    required this.channel,
    required this.sourceBlackLow,
    required this.sourceBlackHigh,
    required this.sourceWhiteLow,
    required this.sourceWhiteHigh,
    required this.destinationBlackLow,
    required this.destinationBlackHigh,
    required this.destinationWhiteLow,
    required this.destinationWhiteHigh,
    required this.descriptor,
  });

  /// Creates a `Blnd` range for [channel], such as `Gry ` or `Rd  `.
  factory PsBlendRange.create({
    required String channel,
    required int sourceBlackLow,
    required int sourceBlackHigh,
    required int sourceWhiteLow,
    required int sourceWhiteHigh,
    required int destinationBlackLow,
    required int destinationBlackHigh,
    required int destinationWhiteLow,
    required int destinationWhiteHigh,
  }) => PsBlendRange.fromDescriptor(
    PsDescriptor(
      name: '\u0000',
      classId: 'Blnd',
      items: [
        PsDescriptorItem(
          key: 'Chnl',
          value: PsReferenceValue(
            values: [
              PsEnumeratedReferenceValue(
                name: '',
                classId: 'Chnl',
                typeId: 'Chnl',
                value: channel,
              ),
            ],
          ),
        ),
        PsDescriptorItem(
          key: 'SrcB',
          value: PsIntegerValue(value: sourceBlackLow),
        ),
        PsDescriptorItem(
          key: 'Srcl',
          value: PsIntegerValue(value: sourceBlackHigh),
        ),
        PsDescriptorItem(
          key: 'SrcW',
          value: PsIntegerValue(value: sourceWhiteLow),
        ),
        PsDescriptorItem(
          key: 'Srcm',
          value: PsIntegerValue(value: sourceWhiteHigh),
        ),
        PsDescriptorItem(
          key: 'DstB',
          value: PsIntegerValue(value: destinationBlackLow),
        ),
        PsDescriptorItem(
          key: 'Dstl',
          value: PsIntegerValue(value: destinationBlackHigh),
        ),
        PsDescriptorItem(
          key: 'DstW',
          value: PsIntegerValue(value: destinationWhiteLow),
        ),
        PsDescriptorItem(
          key: 'Dstt',
          value: PsIntegerValue(value: destinationWhiteHigh),
        ),
      ],
    ),
  );

  /// Creates a typed view over one Photoshop Blend If [descriptor].
  factory PsBlendRange.fromDescriptor(PsDescriptor descriptor) => PsBlendRange(
    channel: _channelFromReference(descriptor.value('Chnl')),
    sourceBlackLow: descriptor.integerValue('SrcB'),
    sourceBlackHigh: descriptor.integerValue('Srcl'),
    sourceWhiteLow: descriptor.integerValue('SrcW'),
    sourceWhiteHigh: descriptor.integerValue('Srcm'),
    destinationBlackLow: descriptor.integerValue('DstB'),
    destinationBlackHigh: descriptor.integerValue('Dstl'),
    destinationWhiteLow: descriptor.integerValue('DstW'),
    destinationWhiteHigh: descriptor.integerValue('Dstt'),
    descriptor: descriptor,
  );

  /// Extracts an enumerated channel from a descriptor reference [value].
  static String? _channelFromReference(PsDescriptorValue? value) {
    if (value is! PsReferenceValue) {
      return null;
    }
    for (final PsDescriptorValue item in value.values) {
      if (item case PsEnumeratedReferenceValue(:final String value)) {
        return value;
      }
    }
    return null;
  }
}

/// Layer blending options stored in a `blendOptions` descriptor.
final class PsBlendOptions {
  /// Keys represented by first-class blending-option fields.
  static const Set<String> _modeledKeys = {
    'Opct',
    'Md  ',
    'fillOpacity',
    'blendClipped',
    'blendInterior',
    'knockout',
    'transparencyShapesLayer',
    'layerMaskAsGlobalMask',
    'vectorMaskAsGlobalMask',
    'Blnd',
    'channelRestrictions',
  };

  /// Complete `blendOptions` descriptor.
  final PsDescriptor descriptor;

  /// Master layer opacity, normally expressed in percent.
  final PsDescriptorNumber? opacity;

  /// Layer blend mode.
  final PsDescriptorEnumeration? blendMode;

  /// Layer fill opacity, normally expressed in percent.
  final PsDescriptorNumber? fillOpacity;

  /// Whether clipped layers are blended as a group.
  final bool? blendsClippedLayers;

  /// Whether interior effects are blended as a group.
  final bool? blendsInteriorEffects;

  /// Layer knockout mode.
  final PsDescriptorEnumeration? knockout;

  /// Whether layer transparency shapes the layer.
  final bool? transparencyShapesLayer;

  /// Whether the layer mask hides effects.
  final bool? layerMaskHidesEffects;

  /// Whether the vector mask hides effects.
  final bool? vectorMaskHidesEffects;

  /// Blend If ranges in source order.
  final List<PsBlendRange> blendRanges;

  /// Channel restriction enumerations in source order.
  final List<PsDescriptorEnumeration> channelRestrictions;

  /// Descriptor items not represented by a typed field.
  final List<PsDescriptorItem> unmodeledItems;

  /// Creates an immutable blending-options view.
  PsBlendOptions({
    required this.descriptor,
    required this.opacity,
    required this.blendMode,
    required this.fillOpacity,
    required this.blendsClippedLayers,
    required this.blendsInteriorEffects,
    required this.knockout,
    required this.transparencyShapesLayer,
    required this.layerMaskHidesEffects,
    required this.vectorMaskHidesEffects,
    required List<PsBlendRange> blendRanges,
    required List<PsDescriptorEnumeration> channelRestrictions,
    required List<PsDescriptorItem> unmodeledItems,
  }) : blendRanges = List<PsBlendRange>.unmodifiable(blendRanges),
       channelRestrictions = List<PsDescriptorEnumeration>.unmodifiable(channelRestrictions),
       unmodeledItems = List<PsDescriptorItem>.unmodifiable(unmodeledItems);

  /// Creates typed views over a Photoshop blending-options [descriptor].
  factory PsBlendOptions.fromDescriptor(PsDescriptor descriptor) => PsBlendOptions(
    descriptor: descriptor,
    opacity: descriptor.numberValue('Opct'),
    blendMode: descriptor.enumerationValue('Md  '),
    fillOpacity: descriptor.numberValue('fillOpacity'),
    blendsClippedLayers: descriptor.booleanValue('blendClipped'),
    blendsInteriorEffects: descriptor.booleanValue('blendInterior'),
    knockout: descriptor.enumerationValue('knockout'),
    transparencyShapesLayer: descriptor.booleanValue('transparencyShapesLayer'),
    layerMaskHidesEffects: descriptor.booleanValue('layerMaskAsGlobalMask'),
    vectorMaskHidesEffects: descriptor.booleanValue('vectorMaskAsGlobalMask'),
    blendRanges: [
      for (final PsDescriptorValue value in descriptor.listValue('Blnd') ?? const <PsDescriptorValue>[])
        if (value case PsObjectValue(:final PsDescriptor value)) PsBlendRange.fromDescriptor(value),
    ],
    channelRestrictions: [
      for (final PsDescriptorValue value in descriptor.listValue('channelRestrictions') ?? const <PsDescriptorValue>[])
        if (value.asEnumeration() case final PsDescriptorEnumeration enumeration) enumeration,
    ],
    unmodeledItems: descriptor.items.where((item) => !_modeledKeys.contains(item.key)).toList(growable: false),
  );
}
