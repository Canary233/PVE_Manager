/// Removes DCS strings unsupported by the pinned xterm parser.
///
/// Feed decoded output in socket order. State survives chunk boundaries without
/// retaining DCS payloads; [reset] starts a new terminal connection. Queries are
/// ignored rather than answered with capabilities the terminal may not support.
class TerminalOutputFilter {
  _OutputState _state = _OutputState.text;

  String add(String text) {
    final output = StringBuffer();
    for (final code in text.codeUnits) {
      switch (_state) {
        case _OutputState.text:
          _consumeText(code, output);
        case _OutputState.escape:
          _consumeEscape(code, output);
        case _OutputState.dcs:
          if (code == 0x1b) {
            _state = _OutputState.dcsEscape;
          } else if (_endsDcs(code)) {
            _state = _OutputState.text;
          }
        case _OutputState.dcsEscape:
          if (code == 0x5c || _endsDcs(code)) {
            _state = _OutputState.text;
          } else {
            // An ESC starts a new escape sequence when it is not the string
            // terminator. Preserve it so a cancelled DCS cannot eat later CSI.
            _consumeEscape(code, output);
          }
      }
    }
    return output.toString();
  }

  void reset() => _state = _OutputState.text;

  void _consumeText(int code, StringBuffer output) {
    if (code == 0x1b) {
      _state = _OutputState.escape;
    } else if (code == 0x90) {
      _state = _OutputState.dcs;
    } else {
      output.writeCharCode(code);
      _state = _OutputState.text;
    }
  }

  void _consumeEscape(int code, StringBuffer output) {
    if (code == 0x50) {
      _state = _OutputState.dcs;
    } else {
      output.writeCharCode(0x1b);
      _consumeText(code, output);
    }
  }

  // CAN/SUB cancel a control string; ST is its eight-bit terminator.
  bool _endsDcs(int code) => code == 0x18 || code == 0x1a || code == 0x9c;
}

enum _OutputState { text, escape, dcs, dcsEscape }
