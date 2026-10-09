import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
import 'package:pscore/src/exceptions.dart';

/// Settings of a Photoshop adjustment stored in the same binary layout in
/// PSD adjustment layers and in standalone preset files.
///
/// Levels (`levl`, `.alv`), hue/saturation (`hue2`, `.ahu`), selective color
/// (`selc`, `.asv`), and channel mixer (`mixr`, `.cha`) share one encoding.
sealed class PsAdjustmentSettings {
  /// Creates an adjustment settings base value.
  const PsAdjustmentSettings();
}

/// One channel record of a levels adjustment.
final class PsLevelRecord {
  /// Input black point.
  final int inputFloor;

  /// Input white point.
  final int inputCeiling;

  /// Output black point.
  final int outputFloor;

  /// Output white point.
  final int outputCeiling;

  /// Gamma encoded as hundredths, where 100 means 1.0.
  final int gamma;

  /// Creates one levels record.
  const PsLevelRecord({
    this.inputFloor = 0,
    this.inputCeiling = 255,
    this.outputFloor = 0,
    this.outputCeiling = 255,
    this.gamma = 100,
  });

  /// Gamma converted to its user-facing floating-point value.
  double get gammaValue => gamma / 100;

  /// Whether this record leaves its channel unchanged.
  bool get isIdentity => inputFloor == 0 && inputCeiling == 255 && outputFloor == 0 && outputCeiling == 255 && gamma == 100;
}

/// Levels settings: 29 standard channel records and optional extended ones.
base class PsLevels extends PsAdjustmentSettings {
  /// Number of standard records every levels payload holds.
  static const int standardRecordCount = 29;

  /// Main format version, normally 2.
  final int version;

  /// The 29 standard channel records: the composite, then one per channel.
  final List<PsLevelRecord> records;

  /// Photoshop CS extended channel records, following a `Lvls` marker.
  final List<PsLevelRecord> extendedRecords;

  /// Extended-record format version, normally 3.
  final int extendedVersion;

  /// Uninterpreted bytes following the decoded records.
  final Uint8List trailingData;

  /// Creates levels settings.
  PsLevels({
    this.version = 2,
    required this.records,
    this.extendedRecords = const [],
    this.extendedVersion = 3,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  /// Creates the 29 neutral records expected by Photoshop.
  factory PsLevels.identity() => PsLevels(records: List<PsLevelRecord>.unmodifiable(List<PsLevelRecord>.filled(standardRecordCount, const PsLevelRecord())));
}

/// Three signed hue, saturation, and lightness values.
final class PsHueSaturationValues {
  /// Hue change.
  final int hue;

  /// Saturation change.
  final int saturation;

  /// Lightness change.
  final int lightness;

  /// Creates one value triplet.
  const PsHueSaturationValues({this.hue = 0, this.saturation = 0, this.lightness = 0});
}

/// One editable color range of a hue/saturation adjustment.
final class PsHueSaturationRange {
  /// Four range boundaries in degrees: fall-off start, range start, range end, fall-off end.
  final List<int> boundaries;

  /// Changes applied within the range.
  final PsHueSaturationValues values;

  /// Creates one hue/saturation range.
  const PsHueSaturationRange({required this.boundaries, this.values = const PsHueSaturationValues()});
}

/// Hue/saturation settings.
base class PsHueSaturation extends PsAdjustmentSettings {
  /// Number of color ranges every payload holds.
  static const int rangeCount = 6;

  /// Format version, normally 2.
  final int version;

  /// Whether Photoshop uses the colorization controls.
  final bool colorize;

  /// Colorization values.
  final PsHueSaturationValues colorization;

  /// Master changes.
  final PsHueSaturationValues master;

  /// Six red-through-magenta color ranges.
  final List<PsHueSaturationRange> ranges;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates hue/saturation settings.
  PsHueSaturation({
    this.version = 2,
    this.colorize = false,
    this.colorization = const PsHueSaturationValues(),
    this.master = const PsHueSaturationValues(),
    required this.ranges,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);
}

/// A cyan, magenta, yellow, and black selective-color correction.
final class PsSelectiveColorCorrection {
  /// Cyan correction.
  final int cyan;

  /// Magenta correction.
  final int magenta;

  /// Yellow correction.
  final int yellow;

  /// Black correction.
  final int black;

  /// Creates one correction record.
  const PsSelectiveColorCorrection({this.cyan = 0, this.magenta = 0, this.yellow = 0, this.black = 0});
}

/// Selective-color settings.
base class PsSelectiveColor extends PsAdjustmentSettings {
  /// Number of correction records every payload holds.
  static const int correctionCount = 10;

  /// Format version, normally 1.
  final int version;

  /// Whether corrections are absolute instead of relative.
  final bool absolute;

  /// Reserved record followed by red, yellow, green, cyan, blue, magenta,
  /// white, neutral, and black corrections.
  final List<PsSelectiveColorCorrection> corrections;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates selective-color settings.
  PsSelectiveColor({
    this.version = 1,
    this.absolute = false,
    required this.corrections,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);
}

/// One output channel of a channel-mixer adjustment.
final class PsChannelMixerOutput {
  /// Four source-channel percentages.
  final List<int> channels;

  /// Constant percentage added to the output.
  final int constant;

  /// Creates one output row.
  const PsChannelMixerOutput({required this.channels, this.constant = 0});
}

/// Channel-mixer settings.
base class PsChannelMixer extends PsAdjustmentSettings {
  /// Number of output rows every payload holds.
  static const int outputCount = 4;

  /// Format version, normally 1.
  final int version;

  /// Whether the output is monochrome.
  final bool monochrome;

  /// Four RGB or CMYK output rows.
  final List<PsChannelMixerOutput> outputs;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates channel-mixer settings.
  PsChannelMixer({
    this.version = 1,
    this.monochrome = false,
    required this.outputs,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);
}

/// Reads and writes the binary adjustment settings shared by PSD blocks and preset files.
///
/// Readers consume the whole remaining input, keeping unrecognized bytes in
/// `trailingData`.
abstract final class PsAdjustmentSettingsCodec {
  /// Reads levels settings.
  static PsLevels readLevels(PsBinaryReader reader) {
    final int version = reader.readUint16();
    final List<PsLevelRecord> records = [for (int index = 0; index < PsLevels.standardRecordCount; index++) _readLevelRecord(reader)];
    final List<PsLevelRecord> extended = [];
    int extendedVersion = 3;
    if (reader.remaining >= 8 && String.fromCharCodes(Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + 4)) == 'Lvls') {
      reader.skip(4);
      extendedVersion = reader.readUint16();
      final int count = reader.readUint16();
      for (int index = PsLevels.standardRecordCount; index < count; index++) {
        extended.add(_readLevelRecord(reader));
      }
    }
    return PsLevels(
      version: version,
      records: records,
      extendedRecords: extended,
      extendedVersion: extendedVersion,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Writes levels settings.
  static void writeLevels(PsBinaryWriter writer, PsLevels levels) {
    if (levels.records.length != PsLevels.standardRecordCount) {
      throw const PsWriteException(message: 'Levels adjustments require exactly 29 standard records');
    }
    writer.writeUint16(levels.version);
    for (final PsLevelRecord record in levels.records) {
      _writeLevelRecord(writer, record);
    }
    if (levels.extendedRecords.isNotEmpty) {
      writer
        ..writeString('Lvls')
        ..writeUint16(levels.extendedVersion)
        ..writeUint16(PsLevels.standardRecordCount + levels.extendedRecords.length);
      for (final PsLevelRecord record in levels.extendedRecords) {
        _writeLevelRecord(writer, record);
      }
    }
    writer.writeBytes(levels.trailingData);
  }

  /// Reads hue/saturation settings.
  static PsHueSaturation readHueSaturation(PsBinaryReader reader) {
    final int version = reader.readUint16();
    final bool colorize = reader.readUint8() != 0;
    reader.readUint8();
    final PsHueSaturationValues colorization = _readHueValues(reader);
    final PsHueSaturationValues master = _readHueValues(reader);
    final List<PsHueSaturationRange> ranges = [
      for (int index = 0; index < PsHueSaturation.rangeCount; index++)
        PsHueSaturationRange(
          boundaries: [for (int boundary = 0; boundary < 4; boundary++) reader.readInt16()],
          values: _readHueValues(reader),
        ),
    ];
    return PsHueSaturation(
      version: version,
      colorize: colorize,
      colorization: colorization,
      master: master,
      ranges: ranges,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Writes hue/saturation settings.
  static void writeHueSaturation(PsBinaryWriter writer, PsHueSaturation settings) {
    if (settings.ranges.length != PsHueSaturation.rangeCount) {
      throw const PsWriteException(message: 'Hue/saturation adjustments require exactly six ranges');
    }
    writer
      ..writeUint16(settings.version)
      ..writeUint8(settings.colorize ? 1 : 0)
      ..writeUint8(0);
    _writeHueValues(writer, settings.colorization);
    _writeHueValues(writer, settings.master);
    for (final PsHueSaturationRange range in settings.ranges) {
      if (range.boundaries.length != 4) {
        throw const PsWriteException(message: 'Each hue/saturation range requires four boundaries');
      }
      range.boundaries.forEach(writer.writeInt16);
      _writeHueValues(writer, range.values);
    }
    writer.writeBytes(settings.trailingData);
  }

  /// Reads selective-color settings.
  static PsSelectiveColor readSelectiveColor(PsBinaryReader reader) => PsSelectiveColor(
    version: reader.readUint16(),
    absolute: reader.readUint16() != 0,
    corrections: [
      for (int index = 0; index < PsSelectiveColor.correctionCount; index++)
        PsSelectiveColorCorrection(cyan: reader.readInt16(), magenta: reader.readInt16(), yellow: reader.readInt16(), black: reader.readInt16()),
    ],
    trailingData: reader.readBytes(reader.remaining),
  );

  /// Writes selective-color settings.
  static void writeSelectiveColor(PsBinaryWriter writer, PsSelectiveColor settings) {
    if (settings.corrections.length != PsSelectiveColor.correctionCount) {
      throw const PsWriteException(message: 'Selective color adjustments require exactly ten correction records');
    }
    writer
      ..writeUint16(settings.version)
      ..writeUint16(settings.absolute ? 1 : 0);
    for (final PsSelectiveColorCorrection correction in settings.corrections) {
      writer
        ..writeInt16(correction.cyan)
        ..writeInt16(correction.magenta)
        ..writeInt16(correction.yellow)
        ..writeInt16(correction.black);
    }
    writer.writeBytes(settings.trailingData);
  }

  /// Reads channel-mixer settings.
  static PsChannelMixer readChannelMixer(PsBinaryReader reader) => PsChannelMixer(
    version: reader.readUint16(),
    monochrome: reader.readUint16() != 0,
    outputs: [
      for (int output = 0; output < PsChannelMixer.outputCount; output++)
        PsChannelMixerOutput(
          channels: [for (int channel = 0; channel < 4; channel++) reader.readInt16()],
          constant: reader.readInt16(),
        ),
    ],
    trailingData: reader.readBytes(reader.remaining),
  );

  /// Writes channel-mixer settings.
  static void writeChannelMixer(PsBinaryWriter writer, PsChannelMixer settings) {
    if (settings.outputs.length != PsChannelMixer.outputCount || settings.outputs.any((output) => output.channels.length != 4)) {
      throw const PsWriteException(message: 'Channel mixer adjustments require four output rows of four channels');
    }
    writer
      ..writeUint16(settings.version)
      ..writeUint16(settings.monochrome ? 1 : 0);
    for (final PsChannelMixerOutput output in settings.outputs) {
      output.channels.forEach(writer.writeInt16);
      writer.writeInt16(output.constant);
    }
    writer.writeBytes(settings.trailingData);
  }

  /// Encodes [settings] of any kind into a new buffer.
  static Uint8List encode(PsAdjustmentSettings settings) {
    final PsBinaryWriter writer = PsBinaryWriter();
    switch (settings) {
      case PsLevels():
        writeLevels(writer, settings);
      case PsHueSaturation():
        writeHueSaturation(writer, settings);
      case PsSelectiveColor():
        writeSelectiveColor(writer, settings);
      case PsChannelMixer():
        writeChannelMixer(writer, settings);
    }
    return writer.takeBytes();
  }

  /// Reads one levels channel record.
  static PsLevelRecord _readLevelRecord(PsBinaryReader reader) => PsLevelRecord(
    inputFloor: reader.readUint16(),
    inputCeiling: reader.readUint16(),
    outputFloor: reader.readUint16(),
    outputCeiling: reader.readUint16(),
    gamma: reader.readUint16(),
  );

  /// Writes one levels channel record.
  static void _writeLevelRecord(PsBinaryWriter writer, PsLevelRecord record) {
    writer
      ..writeUint16(record.inputFloor)
      ..writeUint16(record.inputCeiling)
      ..writeUint16(record.outputFloor)
      ..writeUint16(record.outputCeiling)
      ..writeUint16(record.gamma);
  }

  /// Reads one hue, saturation, and lightness triplet.
  static PsHueSaturationValues _readHueValues(PsBinaryReader reader) => PsHueSaturationValues(
    hue: reader.readInt16(),
    saturation: reader.readInt16(),
    lightness: reader.readInt16(),
  );

  /// Writes one hue, saturation, and lightness triplet.
  static void _writeHueValues(PsBinaryWriter writer, PsHueSaturationValues values) {
    writer
      ..writeInt16(values.hue)
      ..writeInt16(values.saturation)
      ..writeInt16(values.lightness);
  }
}
