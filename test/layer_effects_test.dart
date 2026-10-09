import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises shared layer-style resources and effect views.
void main() {
  group('style resources', () {
    test('creates RGB colors that read back through the typed view', () {
      final PsColor color = PsColor.rgb(red: 10, green: 20, blue: 30);

      check(color.colorSpace).equals(PsColorSpace.rgb);
      check(color.descriptor.classId).equals('RGBC');
      check(color.red).equals(10);
      check(color.green).equals(20);
      check(color.blue).equals(30);
    });

    test('creates every process color space and approximates it in sRGB', () {
      final List<PsColor> colors = [
        PsColor.cmyk(cyan: 0, magenta: 100, yellow: 100, black: 0),
        PsColor.grayscale(gray: 25),
        PsColor.hsb(hue: 240, saturation: 100, brightness: 50),
        PsColor.lab(lightness: 100, a: 0, b: 0),
      ];

      check(colors.map((color) => color.descriptor.classId).toList()).deepEquals(['CMYC', 'Grsc', 'HSBC', 'LbCl']);
      check(colors[2].descriptor.value('H   ')).isA<PsUnitFloatValue>().has((value) => value.unit, 'unit').equals('#Ang');
      final List<List<int>?> rgb = [
        for (final PsColor color in colors)
          switch (color.toRgb()) {
            (:final double red, :final double green, :final double blue) => [red.round(), green.round(), blue.round()],
            null => null,
          },
      ];
      check(rgb).deepEquals([
        [255, 0, 0],
        [191, 191, 191],
        [0, 0, 128],
        [255, 255, 255],
      ]);
    });

    test('cannot approximate book colors or incomplete descriptors', () {
      check(PsColor.fromDescriptor(const PsDescriptor(name: '', classId: 'BkCl')).toRgb()).isNull();
      check(PsColor.fromDescriptor(const PsDescriptor(name: '', classId: 'RGBC')).toRgb()).isNull();
    });

    test('reads non-RGB colors without inventing RGB components', () {
      final PsColor color = PsColor.fromDescriptor(
        const PsDescriptor(
          name: '',
          classId: 'Grsc',
          items: <PsDescriptorItem>[PsDescriptorItem(key: 'Gry ', value: PsDoubleValue(value: 40))],
        ),
      );

      check(color.colorSpace).equals(PsColorSpace.grayscale);
      check(color.component('Gry ')?.value).equals(40);
      check(color.red).isNull();
    });

    test('creates custom gradients whose stops read back', () {
      final PsGradient gradient = PsGradient.custom(
        name: 'Sunset',
        colorStops: <PsGradientColorStop>[
          PsGradientColorStop.create(color: PsColor.rgb(red: 255, green: 0, blue: 0), location: 0),
          PsGradientColorStop.create(color: PsColor.rgb(red: 0, green: 0, blue: 255), location: 4096, midpoint: 30),
        ],
        transparencyStops: <PsGradientTransparencyStop>[PsGradientTransparencyStop.create(opacity: 80, location: 2048)],
      );

      check(gradient.name).equals('Sunset');
      check(gradient.form).equals(PsGradientForm.customStops);
      check(gradient.smoothness).equals(4096);
      check(gradient.colorStops).length.equals(2);
      check(gradient.colorStops[1].midpoint).equals(30);
      check(gradient.colorStops[1].color?.blue).equals(255);
      check(gradient.transparencyStops.single.opacity?.value).equals(80);
      check(gradient.transparencyStops.single.location).equals(2048);
    });

    test('accepts floating-point stop locations', () {
      final PsGradientColorStop stop = PsGradientColorStop.fromDescriptor(
        const PsDescriptor(
          name: '',
          classId: 'Clrt',
          items: <PsDescriptorItem>[PsDescriptorItem(key: 'Lctn', value: PsDoubleValue(value: 1024.4))],
        ),
      );

      check(stop.location).equals(1024);
    });

    test('creates the default linear contour, points, and pattern references', () {
      final PsContour contour = PsContour.linear();
      final PsPoint point = PsPoint.create(horizontal: 5, vertical: -3, unit: '#Prc');
      final PsPatternReference pattern = PsPatternReference.create(name: 'Dots', id: 'dots-id');

      check(contour.name).equals('Linear');
      check(contour.points.map((point) => point.horizontal?.value)).deepEquals(<double>[0, 255]);
      check(point.horizontal?.unit).equals('#Prc');
      check(point.vertical?.value).equals(-3);
      check(pattern.name).equals('Dots');
      check(pattern.id).equals('dots-id');
    });
  });

  group('layer effects', () {
    test('creates effects whose typed view reads every common setting', () {
      final PsLayerEffect effect = PsLayerEffect.create(
        kind: PsLayerEffectKind.stroke,
        blendMode: 'Mltp',
        opacity: 40,
        color: PsColor.rgb(red: 1, green: 2, blue: 3),
        size: 6,
        strokePosition: PsStrokePosition.inside,
      );

      check(effect.key).equals('FrFX');
      check(effect.descriptor.classId).equals('FrFX');
      check(effect.enabled).equals(true);
      check(effect.blendMode?.value).equals('Mltp');
      check(effect.opacity?.value).equals(40);
      check(effect.size?.value).equals(6);
      check(effect.color?.green).equals(2);
      check(effect.strokePosition?.value).equals(PsStrokePosition.inside.identifier);
      check(effect.strokePaintType?.value).equals('SClr');
    });

    test('stores bevel highlight settings under their dedicated keys', () {
      final PsLayerEffect bevel = PsLayerEffect.create(kind: PsLayerEffectKind.bevelAndEmboss, opacity: 70);

      check(bevel.blendMode).isNull();
      check(bevel.highlightOpacity?.value).equals(70);
      check(bevel.shadowColor?.red).equals(0);
      check(bevel.transparencyContour?.name).equals('Linear');
    });

    test('rejects unknown effects that Photoshop has no key for', () {
      check(() => PsLayerEffect.create(kind: PsLayerEffectKind.unknown)).throws<ArgumentError>();
    });

    test('groups repeated families under multi-instance keys and reads them back', () {
      final List<PsDescriptorItem> items = PsLayerEffects.rootItems(<({PsLayerEffectKind kind, PsDescriptor descriptor})>[
        for (final double opacity in <double>[20, 60]) (kind: PsLayerEffectKind.dropShadow, descriptor: PsLayerEffect.create(kind: PsLayerEffectKind.dropShadow, opacity: opacity).descriptor),
        (kind: PsLayerEffectKind.colorOverlay, descriptor: PsLayerEffect.create(kind: PsLayerEffectKind.colorOverlay).descriptor),
        (kind: PsLayerEffectKind.unknown, descriptor: const PsDescriptor(name: '', classId: 'null')),
      ]);
      final PsLayerEffects effects = PsLayerEffects.fromDescriptor(
        PsDescriptor(
          name: '',
          classId: 'null',
          items: <PsDescriptorItem>[
            const PsDescriptorItem(key: 'masterFXSwitch', value: PsBooleanValue(value: false)),
            ...items,
          ],
        ),
      );

      check(items.map((item) => item.key)).deepEquals(<String>['dropShadowMulti', 'SoFi']);
      check(effects.masterEnabled).equals(false);
      check(effects.effectsOf(PsLayerEffectKind.dropShadow).map((effect) => effect.instanceIndex)).deepEquals(<int>[0, 1]);
      check(effects.effectsOf(PsLayerEffectKind.dropShadow)[1].opacity?.value).equals(60);
      check(effects.firstEffectOf(PsLayerEffectKind.colorOverlay)?.key).equals('SoFi');
    });

    test('maps legacy, modern, and multi-instance keys to one family', () {
      for (final String key in <String>['ChFX', 'chromeFX', 'satin', 'satinMulti']) {
        check(PsLayerEffectKind.fromKey(key)).equals(PsLayerEffectKind.satin);
      }
      check(PsLayerEffectKind.fromKey('futureFX')).equals(PsLayerEffectKind.unknown);
    });
  });

  group('blending options', () {
    test('creates Blend If ranges that read back through the options view', () {
      final PsBlendRange range = PsBlendRange.create(
        channel: 'Gry ',
        sourceBlackLow: 0,
        sourceBlackHigh: 10,
        sourceWhiteLow: 200,
        sourceWhiteHigh: 255,
        destinationBlackLow: 5,
        destinationBlackHigh: 15,
        destinationWhiteLow: 240,
        destinationWhiteHigh: 250,
      );
      final PsBlendOptions options = PsBlendOptions.fromDescriptor(
        PsDescriptor(
          name: '',
          classId: 'blendOptions',
          items: <PsDescriptorItem>[
            PsDescriptorItem(
              key: 'Blnd',
              value: PsListValue(values: <PsDescriptorValue>[PsObjectValue(value: range.descriptor)]),
            ),
            const PsDescriptorItem(key: 'custom', value: PsBooleanValue(value: true)),
          ],
        ),
      );

      check(options.blendRanges.single.channel).equals('Gry ');
      check(options.blendRanges.single.sourceWhiteLow).equals(200);
      check(options.blendRanges.single.destinationWhiteHigh).equals(250);
      check(options.unmodeledItems.map((item) => item.key)).deepEquals(<String>['custom']);
    });
  });
}
