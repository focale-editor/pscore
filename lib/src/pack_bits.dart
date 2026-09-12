import 'dart:typed_data';

import 'package:pscore/src/binary.dart';
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

  /// Returns the largest encoding a row of [rowBytes] can produce.
  ///
  /// Incompressible data costs one control byte per 128 literal bytes, so this
  /// bound lets a caller size one buffer up front instead of growing it.
  static int maxEncodedLength(int rowBytes) => rowBytes + (rowBytes + 127) ~/ 128 + 1;

  /// Encodes one [row] with the PackBits run-length algorithm.
  static Uint8List encodeRow(Uint8List row) {
    final Uint8List output = Uint8List(maxEncodedLength(row.length));
    return Uint8List.sublistView(output, 0, encodeRowInto(row, output, 0));
  }

  /// Encodes [row] into [output] at [start] and returns the next write offset.
  ///
  /// [output] must have at least [maxEncodedLength] bytes available beyond
  /// [start]. Writing into a caller-owned buffer lets a whole image be encoded
  /// without allocating per row or per run, which dominates the cost of
  /// compressing large planes.
  static int encodeRowInto(Uint8List row, Uint8List output, int start) {
    int write = start;
    int offset = 0;
    while (offset < row.length) {
      int runLength = _repeatedRunLength(row, offset);
      if (runLength >= 3) {
        output[write++] = 257 - runLength;
        output[write++] = row[offset];
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
      output[write++] = literalLength - 1;
      output.setRange(write, write + literalLength, row, literalStart);
      write += literalLength;
    }
    return write;
  }

  /// Decodes a complete table-prefixed sequence of PackBits rows.
  static Uint8List decodeRows(
    Uint8List input, {
    required int rowBytes,
    required int rowCount,
    bool wideRowLengths = false,
  }) {
    final ({Uint8List data, int bytesRead}) decoded = decodeRowsPrefix(
      input,
      rowBytes: rowBytes,
      rowCount: rowCount,
      wideRowLengths: wideRowLengths,
    );
    if (decoded.bytesRead != input.length) {
      throw PsFormatException(
        message: 'Unexpected bytes after PackBits rows',
        source: input,
        offset: decoded.bytesRead,
      );
    }
    return decoded.data;
  }

  /// Decodes table-prefixed rows from the beginning of [input].
  static ({Uint8List data, int bytesRead}) decodeRowsPrefix(
    Uint8List input, {
    required int rowBytes,
    required int rowCount,
    bool wideRowLengths = false,
  }) {
    final PsBinaryReader reader = PsBinaryReader(bytes: input);
    final Uint8List data = decodeRowsReader(
      reader,
      rowBytes: rowBytes,
      rowCount: rowCount,
      wideRowLengths: wideRowLengths,
    );
    return (data: data, bytesRead: reader.offset);
  }

  /// Decodes table-prefixed rows at the current [reader] position.
  static Uint8List decodeRowsReader(
    PsBinaryReader reader, {
    required int rowBytes,
    required int rowCount,
    bool wideRowLengths = false,
  }) {
    _validateDecodedRowGeometry(rowBytes, rowCount);
    final List<int> lengths = <int>[];
    for (int row = 0; row < rowCount; row++) {
      lengths.add(wideRowLengths ? reader.readUint32() : reader.readUint16());
    }
    final Uint8List output = Uint8List(rowBytes * rowCount);
    for (int row = 0; row < rowCount; row++) {
      final Uint8List decoded = decodeRow(
        reader.readView(lengths[row]),
        decodedLength: rowBytes,
      );
      output.setRange(row * rowBytes, (row + 1) * rowBytes, decoded);
    }
    return output;
  }

  /// Encodes rows and prefixes their 16-bit or 32-bit encoded lengths.
  static Uint8List encodeRows(
    Uint8List input, {
    required int rowBytes,
    required int rowCount,
    bool wideRowLengths = false,
  }) {
    _validateEncodedRowGeometry(rowBytes, rowCount);
    final int expectedLength = rowBytes * rowCount;
    if (input.length != expectedLength) {
      throw PsWriteException(
        message: 'PackBits row input has ${input.length} bytes; expected $expectedLength',
      );
    }
    final int lengthBytes = wideRowLengths ? 4 : 2;
    final int tableBytes = rowCount * lengthBytes;
    final Uint8List output = Uint8List(tableBytes + rowCount * maxEncodedLength(rowBytes));
    final ByteData table = ByteData.sublistView(output, 0, tableBytes);
    int outputOffset = tableBytes;
    for (int row = 0; row < rowCount; row++) {
      final int encodedStart = outputOffset;
      outputOffset = encodeRowInto(
        Uint8List.sublistView(input, row * rowBytes, (row + 1) * rowBytes),
        output,
        outputOffset,
      );
      final int encodedLength = outputOffset - encodedStart;
      if (!wideRowLengths && encodedLength > 0xffff) {
        throw const PsWriteException(
          message: 'A PackBits row exceeds the unsigned 16-bit length capacity',
        );
      }
      if (wideRowLengths) {
        table.setUint32(row * lengthBytes, encodedLength);
      } else {
        table.setUint16(row * lengthBytes, encodedLength);
      }
    }
    final Uint8List result = Uint8List.sublistView(output, 0, outputOffset);
    return outputOffset * 2 < output.length ? Uint8List.fromList(result) : result;
  }

  /// Returns the repeated run at [offset], capped to PackBits' maximum.
  static int _repeatedRunLength(Uint8List row, int offset) {
    int length = 1;
    while (offset + length < row.length && length < 128 && row[offset + length] == row[offset]) {
      length++;
    }
    return length;
  }

  /// Rejects negative row geometry before allocation or iteration.
  static void _validateDecodedRowGeometry(int rowBytes, int rowCount) {
    if (rowBytes < 0 || rowCount < 0) {
      throw const PsFormatException(
        message: 'PackBits row width and count cannot be negative',
      );
    }
  }

  /// Rejects negative row geometry before sizing an encoded buffer.
  static void _validateEncodedRowGeometry(int rowBytes, int rowCount) {
    if (rowBytes < 0 || rowCount < 0) {
      throw const PsWriteException(
        message: 'PackBits row width and count cannot be negative',
      );
    }
  }
}
