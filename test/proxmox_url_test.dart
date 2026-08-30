import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/utils/proxmox_url.dart';
import 'package:pve_manager/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('normalizes a host without a scheme to the default API port', () {
    expect(normalizeOrigin('pve.example'), 'https://pve.example:8006');
  });

  test('rejects malformed addresses without throwing from validation', () {
    expect(validateOrigin(l10n, 'https://[invalid'), l10n.invalidAddress);
    expect(validateOrigin(l10n, 'https://'), l10n.invalidAddress);
  });

  test('reports explicitly unsupported schemes', () {
    expect(validateOrigin(l10n, 'ftp://pve.example'), l10n.unsupportedScheme);
  });

  test('normalization throws a format error for invalid input', () {
    expect(() => normalizeOrigin('https://[invalid'), throwsFormatException);
  });
}
