import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/models/guest_config.dart';

void main() {
  test('matches indexed configuration keys using decimal indices', () {
    const schema = GuestConfigEditSchema(
      parameters: {'net[n]', 'scsi[n]'},
      isAvailable: true,
    );

    expect(schema.isEditable('net0'), isTrue);
    expect(schema.isEditable('net12'), isTrue);
    expect(schema.isEditable('scsi30'), isTrue);
    for (final key in [
      'net',
      'netn',
      'net-1',
      'net+1',
      'net0x10',
      'net1extra',
    ]) {
      expect(schema.isEditable(key), isFalse, reason: key);
    }
  });

  test('handles overlapping wildcard prefixes and suffixes safely', () {
    const schema = GuestConfigEditSchema(
      parameters: {'disk[n]disk', 'device.[n].option'},
      isAvailable: true,
    );

    expect(schema.isEditable('disk'), isFalse);
    expect(schema.isEditable('disk0disk'), isTrue);
    expect(schema.isEditable('device.2.option'), isTrue);
    expect(schema.isEditable('deviceX2Yoption'), isFalse);
  });

  test('anchors alternatives to the complete configuration key', () {
    const schema = GuestConfigEditSchema(
      parameters: {'memory|cores', 'net[0-9]+', '['},
      isAvailable: true,
    );

    expect(schema.isEditable('memory'), isTrue);
    expect(schema.isEditable('cores'), isTrue);
    expect(schema.isEditable('net10'), isTrue);
    expect(schema.isEditable('memory_extra'), isFalse);
    expect(schema.isEditable('extra_cores'), isFalse);
    expect(schema.isEditable('unknown'), isFalse);
  });

  test('collects only PUT parameters from nested option schemas', () {
    final schema = GuestConfigEditSchema.fromOptions({
      'info': {
        'GET': {
          'parameters': {
            'properties': {'digest': <String, Object?>{}},
          },
        },
        'PUT': {
          'parameters': {
            'properties': {'net[n]': <String, Object?>{}, 'memory': {}},
          },
        },
      },
    });

    expect(schema.isAvailable, isTrue);
    expect(schema.isEditable('memory'), isTrue);
    expect(schema.isEditable('net0'), isTrue);
    expect(schema.isEditable('digest'), isFalse);
  });
}
