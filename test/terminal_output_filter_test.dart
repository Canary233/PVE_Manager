import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/utils/terminal_output_filter.dart';

void main() {
  const query = '\x1bP+q6E616D65\x1b\\';

  test('removes the unsupported terminal-name DCS query', () {
    final filter = TerminalOutputFilter();

    expect(filter.add('before${query}after'), 'beforeafter');
  });

  test('handles every split in DCS introducer, payload, and terminator', () {
    const input = 'before${query}after';
    for (var split = 0; split <= input.length; split++) {
      final filter = TerminalOutputFilter();
      final result =
          filter.add(input.substring(0, split)) +
          filter.add(input.substring(split));

      expect(result, 'beforeafter', reason: 'split at $split');
    }
  });

  test('handles single-character chunks and consecutive DCS strings', () {
    final filter = TerminalOutputFilter();
    final result = 'a$query${query}b'.split('').map(filter.add).join();

    expect(result, 'ab');
  });

  test('preserves text, Unicode, CSI, OSC, and terminal status queries', () {
    const input =
        '中🙂文\r\n\x1b[31mred\x1b[0m\x1b[6n'
        '\x1b]0;title\x07\x1b]2;other\x1b\\\x1b7\x1b8';
    final filter = TerminalOutputFilter();

    expect(input.split('').map(filter.add).join(), input);
  });

  test('accepts eight-bit DCS and ST including mixed terminators', () {
    final filter = TerminalOutputFilter();

    expect(
      filter.add('a\x90hidden\x9cb\x1bPhidden\x9cc\x90hidden\x1b\\d'),
      'abcd',
    );
  });

  test('CAN and SUB cancel DCS and allow subsequent output', () {
    for (final cancel in ['\x18', '\x1a']) {
      final filter = TerminalOutputFilter();

      expect(filter.add('a\x1bPhidden${cancel}b'), 'ab');
      expect(filter.add('c\x1bPhidden\x1b${cancel}d'), 'cd');
    }
  });

  test('preserves a new escape sequence that interrupts a DCS', () {
    final filter = TerminalOutputFilter();

    expect(filter.add('a\x1bPhidden\x1b[31mred\x1b[0m'), 'a\x1b[31mred\x1b[0m');
  });

  test('reset discards partial DCS or ESC from a previous connection', () {
    for (final partial in ['\x1b', '\x1bPpending', '\x1bPpending\x1b']) {
      final filter = TerminalOutputFilter();
      expect(filter.add(partial), isEmpty);

      filter.reset();

      expect(filter.add('clean'), 'clean');
    }
  });
}
