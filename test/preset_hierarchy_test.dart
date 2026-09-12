import 'package:checks/checks.dart';
import 'package:pscore/pscore.dart';
import 'package:test/test.dart';

/// Exercises shared Photoshop preset-hierarchy projection.
void main() {
  test('maps nested groups and resolves presets by identifier', () {
    const PsDescriptor root = PsDescriptor(
      name: '',
      classId: 'hierarchy',
      items: <PsDescriptorItem>[
        PsDescriptorItem(
          key: 'hierarchy',
          value: PsListValue(
            values: <PsDescriptorValue>[
              PsObjectValue(
                value: PsDescriptor(
                  name: '',
                  classId: 'Grup',
                  items: <PsDescriptorItem>[
                    PsDescriptorItem(
                      key: 'Nm  ',
                      value: PsStringValue(value: 'Group'),
                    ),
                  ],
                ),
              ),
              PsObjectValue(
                value: PsDescriptor(
                  name: '',
                  classId: 'preset',
                  items: <PsDescriptorItem>[
                    PsDescriptorItem(
                      key: 'zuid',
                      value: PsStringValue(value: 'second'),
                    ),
                  ],
                ),
              ),
              PsObjectValue(
                value: PsDescriptor(name: '', classId: 'groupEnd'),
              ),
            ],
          ),
        ),
      ],
    );
    final List<String> issues = <String>[];

    final List<PsPresetHierarchyEntry> entries = PsPresetHierarchyMapper.decode(
      root: root,
      presets: const <PsPresetIdentity>[
        PsPresetIdentity(name: 'First', id: 'first'),
        PsPresetIdentity(name: 'Second', id: 'second'),
      ],
      maxEntries: 10,
      onIssue: issues.add,
    );

    check(entries).length.equals(3);
    check(entries[0].kind).equals(PsPresetHierarchyEntryKind.groupStart);
    check(entries[1].depth).equals(1);
    check(entries[1].presetIndex).equals(1);
    check(entries[1].name).equals('Second');
    check(entries[2].kind).equals(PsPresetHierarchyEntryKind.groupEnd);
    check(entries[2].depth).equals(0);
    check(issues).isEmpty();
  });
}
