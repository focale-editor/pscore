import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises the adjustment settings shared by PSD blocks and preset files.
void main() {
  group('PsAdjustmentSettingsCodec', () {
    test('round-trips levels with extended records and trailing bytes', () {
      final PsLevels levels = PsLevels(
        records: [const PsLevelRecord(inputFloor: 10, inputCeiling: 240, gamma: 120), ...List.filled(28, const PsLevelRecord())],
        extendedRecords: const [PsLevelRecord(outputCeiling: 200)],
        trailingData: Uint8List.fromList([7]),
      );

      final Uint8List bytes = PsAdjustmentSettingsCodec.encode(levels);
      final PsLevels decoded = PsAdjustmentSettingsCodec.readLevels(PsBinaryReader(bytes: bytes));

      check(bytes.length).equals(2 + 29 * 10 + 8 + 10 + 1);
      check(decoded.records.first.gammaValue).equals(1.2);
      check(decoded.records.skip(1).every((record) => record.isIdentity)).isTrue();
      check(decoded.extendedRecords.single.outputCeiling).equals(200);
      check(decoded.trailingData).deepEquals([7]);
      check(PsAdjustmentSettingsCodec.encode(decoded)).deepEquals(bytes);
    });

    test('round-trips hue/saturation, selective color, and channel mixer settings', () {
      final PsHueSaturation hue = PsHueSaturation(
        colorize: true,
        colorization: const PsHueSaturationValues(hue: 30, saturation: 25),
        master: const PsHueSaturationValues(lightness: -10),
        ranges: List.filled(6, const PsHueSaturationRange(boundaries: [315, 345, 15, 45], values: PsHueSaturationValues(saturation: 5))),
      );
      final PsSelectiveColor selective = PsSelectiveColor(absolute: true, corrections: [...List.filled(9, const PsSelectiveColorCorrection()), const PsSelectiveColorCorrection(black: -40)]);
      final PsChannelMixer mixer = PsChannelMixer(
        monochrome: true,
        outputs: [
          for (int row = 0; row < 4; row++) PsChannelMixerOutput(channels: [40, 40, 20, 0], constant: row - 2),
        ],
      );

      final Uint8List hueBytes = PsAdjustmentSettingsCodec.encode(hue);
      final PsHueSaturation decodedHue = PsAdjustmentSettingsCodec.readHueSaturation(PsBinaryReader(bytes: hueBytes));
      final PsSelectiveColor decodedSelective = PsAdjustmentSettingsCodec.readSelectiveColor(PsBinaryReader(bytes: PsAdjustmentSettingsCodec.encode(selective)));
      final PsChannelMixer decodedMixer = PsAdjustmentSettingsCodec.readChannelMixer(PsBinaryReader(bytes: PsAdjustmentSettingsCodec.encode(mixer)));

      check(hueBytes.length).equals(100);
      check(decodedHue.colorize).isTrue();
      check(decodedHue.colorization.hue).equals(30);
      check(decodedHue.master.lightness).equals(-10);
      check(decodedHue.ranges.last.boundaries).deepEquals([315, 345, 15, 45]);
      check(decodedSelective.absolute).isTrue();
      check(decodedSelective.corrections.last.black).equals(-40);
      check(decodedMixer.monochrome).isTrue();
      check(decodedMixer.outputs.map((output) => output.constant).toList()).deepEquals([-2, -1, 0, 1]);
    });

    test('rejects settings with the wrong record counts', () {
      check(() => PsAdjustmentSettingsCodec.encode(PsLevels(records: const []))).throws<PsWriteException>();
      check(() => PsAdjustmentSettingsCodec.encode(PsHueSaturation(ranges: const []))).throws<PsWriteException>();
      check(() => PsAdjustmentSettingsCodec.encode(PsSelectiveColor(corrections: const []))).throws<PsWriteException>();
      check(
        () => PsAdjustmentSettingsCodec.encode(
          PsChannelMixer(
            outputs: const [
              PsChannelMixerOutput(channels: [100]),
            ],
          ),
        ),
      ).throws<PsWriteException>();
      check(PsLevels.identity().records).length.equals(29);
    });
  });
}
