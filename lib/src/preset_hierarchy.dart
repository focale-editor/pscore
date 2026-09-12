import 'package:pscore/src/descriptor.dart';
import 'package:pscore/src/descriptor_access.dart';
import 'package:pscore/src/exceptions.dart';

/// Receives a recoverable preset-hierarchy compatibility issue.
typedef PsPresetHierarchyIssueHandler = void Function(String message);

/// Identifies the role of one Photoshop preset-hierarchy slot.
enum PsPresetHierarchyEntryKind {
  /// Opens a named preset group.
  groupStart,

  /// Closes the most recently opened preset group.
  groupEnd,

  /// Refers to a preset in the surrounding container.
  preset,

  /// Preserves an intentionally empty hierarchy slot.
  empty,

  /// Preserves an object class not understood by this release.
  unknown,
}

/// The identity fields used to resolve a hierarchy entry to a preset.
final class PsPresetIdentity {
  /// User-visible preset name, when known.
  final String? name;

  /// Stable Photoshop identifier, when known.
  final String? id;

  /// Creates immutable preset identity metadata.
  const PsPresetIdentity({
    required this.name,
    required this.id,
  });
}

/// One ordered item from a Photoshop `phry` hierarchy descriptor.
final class PsPresetHierarchyEntry {
  /// Zero-based position in the flattened hierarchy.
  final int index;

  /// Semantic role inferred from the descriptor class.
  final PsPresetHierarchyEntryKind kind;

  /// Zero-based nesting depth at which this item appears.
  final int depth;

  /// Original Photoshop descriptor class, or `null` for an empty slot.
  final String? classId;

  /// User-visible group or preset name, when stored or resolved.
  final String? name;

  /// Photoshop identifier associated with the item, when stored or resolved.
  final String? id;

  /// Index of the referred preset, when it could be resolved.
  final int? presetIndex;

  /// Complete source descriptor, or `null` for an empty slot.
  final PsDescriptor? rawDescriptor;

  /// Creates an immutable hierarchy item.
  const PsPresetHierarchyEntry({
    required this.index,
    required this.kind,
    required this.depth,
    required this.classId,
    required this.name,
    required this.id,
    required this.presetIndex,
    required this.rawDescriptor,
  });
}

/// Converts a generic Photoshop `phry` descriptor into typed hierarchy entries.
abstract final class PsPresetHierarchyMapper {
  /// Decodes the ordered list stored under the root `hierarchy` key.
  static List<PsPresetHierarchyEntry> decode({
    required PsDescriptor root,
    required List<PsPresetIdentity> presets,
    required int maxEntries,
    required PsPresetHierarchyIssueHandler onIssue,
    String formatLabel = 'Photoshop',
    String presetLabel = 'a preset',
  }) {
    final PsDescriptorValue? hierarchyValue = root.value('hierarchy');
    if (hierarchyValue == null) {
      onIssue('The phry descriptor has no hierarchy item');
      return const <PsPresetHierarchyEntry>[];
    }
    if (hierarchyValue is! PsListValue) {
      onIssue('The phry hierarchy item is ${hierarchyValue.type}, not a list');
      return const <PsPresetHierarchyEntry>[];
    }
    if (hierarchyValue.values.length > maxEntries) {
      throw PsFormatException(
        message: '$formatLabel hierarchy entry count ${hierarchyValue.values.length} exceeds the configured $maxEntries limit',
      );
    }

    // Indexing the presets once keeps resolution linear; scanning the list for
    // every entry made a large library cost time quadratic in its preset count.
    final Map<String, int> presetIndicesById = <String, int>{};
    for (int index = 0; index < presets.length; index++) {
      final String? presetId = presets[index].id;
      if (presetId != null && presetId.isNotEmpty) {
        presetIndicesById[presetId] = index;
      }
    }

    final List<PsPresetHierarchyEntry> entries = <PsPresetHierarchyEntry>[];
    int depth = 0;
    int nextPresetIndex = 0;
    for (int index = 0; index < hierarchyValue.values.length; index++) {
      final PsDescriptorValue value = hierarchyValue.values[index];
      final PsDescriptor? descriptor = value.asObject();
      if (descriptor == null) {
        entries.add(
          PsPresetHierarchyEntry(
            index: index,
            kind: PsPresetHierarchyEntryKind.empty,
            depth: depth,
            classId: null,
            name: null,
            id: null,
            presetIndex: null,
            rawDescriptor: null,
          ),
        );
        if (value is! PsRawValue || value.value.isNotEmpty) {
          onIssue('Hierarchy entry ${index + 1} uses unsupported value type ${value.type}');
        }
        continue;
      }

      final String classId = descriptor.classId;
      final String? name = _firstString(descriptor, const <String>['Nm  ', 'name']);
      final String? id = _firstString(descriptor, const <String>['zuid', 'Idnt', 'identifier']);
      switch (classId) {
        case 'Grup':
        case 'group':
        case 'groupStart':
          entries.add(
            _entry(
              index: index,
              kind: PsPresetHierarchyEntryKind.groupStart,
              depth: depth,
              descriptor: descriptor,
              name: name,
              id: id,
            ),
          );
          depth++;
        case 'groupEnd':
          if (depth == 0) {
            onIssue('Hierarchy entry ${index + 1} closes a group that was not open');
          } else {
            depth--;
          }
          entries.add(
            _entry(
              index: index,
              kind: PsPresetHierarchyEntryKind.groupEnd,
              depth: depth,
              descriptor: descriptor,
              name: name,
              id: id,
            ),
          );
        case 'preset':
          final int? presetIndex = _presetIndex(
            presetCount: presets.length,
            presetIndicesById: presetIndicesById,
            id: id,
            fallback: nextPresetIndex,
          );
          if (presetIndex == null) {
            onIssue('Hierarchy preset ${index + 1} cannot be mapped to $presetLabel');
          } else if (presetIndex >= nextPresetIndex) {
            nextPresetIndex = presetIndex + 1;
          }
          final PsPresetIdentity? preset = presetIndex == null ? null : presets[presetIndex];
          entries.add(
            _entry(
              index: index,
              kind: PsPresetHierarchyEntryKind.preset,
              depth: depth,
              descriptor: descriptor,
              name: name ?? preset?.name,
              id: id ?? preset?.id,
              presetIndex: presetIndex,
            ),
          );
        case 'null':
        case '':
          entries.add(
            _entry(
              index: index,
              kind: PsPresetHierarchyEntryKind.empty,
              depth: depth,
              descriptor: descriptor,
              name: name,
              id: id,
            ),
          );
        default:
          onIssue('Hierarchy entry ${index + 1} uses unknown class "$classId"');
          entries.add(
            _entry(
              index: index,
              kind: PsPresetHierarchyEntryKind.unknown,
              depth: depth,
              descriptor: descriptor,
              name: name,
              id: id,
            ),
          );
      }
    }
    if (depth != 0) {
      onIssue('$formatLabel hierarchy ends with $depth unclosed group${depth == 1 ? '' : 's'}');
    }
    return List<PsPresetHierarchyEntry>.unmodifiable(entries);
  }

  /// Creates one hierarchy entry whose source object is known.
  static PsPresetHierarchyEntry _entry({
    required int index,
    required PsPresetHierarchyEntryKind kind,
    required int depth,
    required PsDescriptor descriptor,
    required String? name,
    required String? id,
    int? presetIndex,
  }) => PsPresetHierarchyEntry(
    index: index,
    kind: kind,
    depth: depth,
    classId: descriptor.classId,
    name: name,
    id: id,
    presetIndex: presetIndex,
    rawDescriptor: descriptor,
  );

  /// Returns the first nonempty string stored under one of [keys].
  static String? _firstString(PsDescriptor descriptor, List<String> keys) {
    for (final String key in keys) {
      final String? value = descriptor.stringValue(key);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  /// Resolves a preset by [id] before applying its sequential [fallback].
  static int? _presetIndex({
    required int presetCount,
    required Map<String, int> presetIndicesById,
    required String? id,
    required int fallback,
  }) {
    if (id != null && id.isNotEmpty) {
      final int? matched = presetIndicesById[id];
      if (matched != null) {
        return matched;
      }
    }
    return fallback < presetCount ? fallback : null;
  }
}
