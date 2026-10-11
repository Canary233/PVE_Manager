import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/utils/terminal_output_filter.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('pinned xterm renders an unsupported DCS query as text', () {
    final terminal = Terminal();

    terminal.write('\x1bP+q6E616D65\x1b\\');

    expect(terminal.buffer.getText().trim(), '+q6E616D65');
  });

  test('filtered DCS does not leak text and leaves status replies enabled', () {
    final replies = <String>[];
    final terminal = Terminal(onOutput: replies.add);
    final filter = TerminalOutputFilter();

    terminal.write(filter.add('\x1bP+q6E616D65\x1b\\login: \x1b[6n'));

    expect(terminal.buffer.getText().trim(), 'login:');
    expect(replies, hasLength(1));
    expect(replies.single, matches(r'^\x1b\[\d+;\d+R$'));
  });

  test(
    'decoding fragmented UTF-8 before filtering preserves terminal text',
    () async {
      final terminal = Terminal();
      final filter = TerminalOutputFilter();
      final bytes = utf8.encode('中文\x1bP+q6E616D65\x1b\\🙂login: ');

      await for (final text in const Utf8Decoder().bind(
        Stream<List<int>>.fromIterable(bytes.map((byte) => [byte])),
      )) {
        terminal.write(filter.add(text));
      }

      expect(terminal.buffer.getText().trim(), '中文🙂login:');
    },
  );

  test(
    'terminal survives scroll-region reverse index followed by line feeds',
    () {
      final terminal = Terminal(maxLines: 10000);

      terminal
        ..resize(56, 27)
        ..resize(105, 35)
        ..write('\x1b[?2026h\x1b[1;35r\x1b[1;1H')
        ..write('\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM')
        ..write('\x1b[r\x1b[1;9r\x1b[1;1H\r\n');

      for (var i = 0; i < 12; i++) {
        terminal.write('\x1b[;m\x1b[K\x1b[m\x1b[m\x1b[0m\r\n');
      }
    },
  );
}
