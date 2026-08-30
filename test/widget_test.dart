import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pve_manager/app/pve_manager_app.dart';
import 'package:pve_manager/core/widgets/usage_line.dart';
import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/models/pve_server_config.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/view/home/widgets/server_card.dart';
import 'package:pve_manager/view/home/widgets/server_form_dialog.dart';

void main() {
  testWidgets('shows the server list home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PveManagerApp());
    await tester.pump();

    expect(find.text('PVE Manager'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsWidgets);
  });

  testWidgets('server card shows last login below username while connecting', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ServerCard(
                server: const PveServerConfig(
                  name: '公网',
                  origin: 'https://canary233.eu.org:442',
                  username: 'root',
                  password: 'secret',
                  realm: 'pam',
                  ignoreCertificateErrors: true,
                  lastConnectedAt: 1783350000000,
                ),
                isConnecting: true,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('root@pam'), findsOneWidget);
    expect(find.textContaining('上次登录：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usage line shows loading animation without stale text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: UsageLine(
              label: '磁盘',
              value: 0,
              text: '- / 512.3 MiB',
              isLoading: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('磁盘'), findsOneWidget);
    expect(find.text('- / 512.3 MiB'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    final indicators = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicators.every((indicator) => indicator.value == null), isTrue);
  });

  testWidgets('server form exposes api token credential fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: ServerFormDialog()),
      ),
    );

    await tester.tap(find.text('API 令牌'));
    await tester.pumpAndSettle();

    expect(find.text('令牌 ID'), findsOneWidget);
    expect(find.text('令牌密钥'), findsOneWidget);
    expect(find.text('用户名'), findsNothing);
    expect(find.text('Realm'), findsNothing);
    expect(find.byIcon(Icons.badge_rounded), findsOneWidget);
  });

  testWidgets('new server form verifies TLS certificates by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: ServerFormDialog()),
      ),
    );

    final certificateSwitch = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(certificateSwitch.value, isFalse);
    expect(find.text('忽略 TLS 证书错误'), findsOneWidget);
    expect(find.textContaining('中间人攻击'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('api token edit form reconstructs the complete token id', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(
          body: ServerFormDialog(
            server: PveServerConfig(
              name: 'API',
              origin: 'https://pve.example:8006',
              username: 'root',
              password: '',
              realm: 'pam',
              authMode: ProxmoxAuthMode.apiToken,
              apiTokenId: 'mobile',
              apiTokenSecret: 'secret-uuid',
              ignoreCertificateErrors: true,
            ),
          ),
        ),
      ),
    );

    final tokenIdFields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .where((field) => field.controller?.text == 'root@pam!mobile');
    expect(tokenIdFields, hasLength(1));
    expect(find.text('用户名'), findsNothing);
    expect(find.text('Realm'), findsNothing);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
