import 'dart:typed_data';

import 'package:pscore/src/exceptions.dart';

/// Encodes and decodes the PackBits run-length format used by Photoshop.
abstract final class PsPackBitsCodec {
  /// Decodes one PackBits [input] row into exactly [decodedLength] bytes.
  static Uint8List decodeRow(
    Uint8List input, {
    required int decodedLength,
  }) {
    if (decodedLength < 0) {
      throw const PsFormatException(message: 'A PackBits row cannot have a negative decoded length');
    }
    final Uint8List output = Uint8List(decodedLength);
    int inputOffset = 0;
    int outputOffset = 0;
    while (inputOffset < input.length && outputOffset < decodedLength) {
      final int header = input[inputOffset++];
      if (header <= 127) {
        final int count = header + 1;
        if (inputOffset + count > input.length || outputOffset + count > decodedLength) {
          throw const PsFormatException(message: 'Invalid PackBits literal run');
        }
        output.setRange(outputOffset, outputOffset + count, input, inputOffset);
        inputOffset += count;
        outputOffset += count;
      } else if (header >= 129) {
        final int count = 257 - header;
        if (inputOffset >= input.length || outputOffset + count > decodedLength) {
          throw const PsFormatException(message: 'Invalid PackBits repeated run');
        }
        output.fillRange(outputOffset, outputOffset + count, input[inputOffset++]);
        outputOffset += count;
      }
    }
    if (inputOffset != input.length || outputOffset != decodedLength) {
      throw PsFormatException(
        message: 'PackBits row decoded to $outputOffset bytes; expected $decodedLength',
        source: input,
        offset: inputOffset,
      );
    }
    return output;
  }

  /// Encodes one [row] with the PackBits run-length algorithm.
  static Uint8List encodeRow(Uint8List row) {
    final BytesBuilder output = BytesBuilder(copy: false);
    int offset = 0;
    while (offset < row.length) {
      int runLength = _repeatedRunLength(row, offset);
      if (runLength >= 3) {
        output.add(<int>[257 - runLength, row[offset]]);
        offset += runLength;
        continue;
      }

      final int literalStart = offset;
      offset += runLength;
      while (offset < row.length && offset - literalStart < 128) {
        runLength = _repeatedRunLength(row, offset);
        if (runLength >= 3) {
          break;
        }
        final int remaining = 128 - (offset - literalStart);
        offset += runLength.clamp(1, remaining);
      }
      final int literalLength = offset - literalStart;
      output
        ..add(<int>[literalLength - 1])
        ..add(Uint8List.sublistView(row, literalStart, offset));
    }
    return output.takeBytes();
  }

  /// Returns the repeated run at [offset], capped to PackBits' maximum.
  static int _repeatedRunLength(Uint8List row, int offset) {
    int length = 1;
    while (offset + length < row.length && length < 128 && row[offset + length] == row[offset]) {
      length++;
    }
    return length;
  }
}
