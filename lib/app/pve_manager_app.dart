import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pve_manager/core/settings/auto_refresh_settings.dart';
import 'package:pve_manager/core/theme/platform_dynamic_color.dart';
import 'package:pve_manager/data/repositories/app_settings_repository.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/view/home/home_screen.dart';

class PveManagerApp extends StatefulWidget {
  const PveManagerApp({super.key});

  @override
  State<PveManagerApp> createState() => _PveManagerAppState();
}

class _PveManagerAppState extends State<PveManagerApp> {
  static const Locale _chineseLocale = Locale('zh');

  final AppSettingsRepository _settingsRepository =
      AppSettingsRepository.instance;

  Locale _locale = _chineseLocale;
  final ValueNotifier<Duration> _autoRefreshInterval = ValueNotifier<Duration>(
    defaultAutoRefreshInterval,
  );
  ColorScheme? _lightDynamic;
  ColorScheme? _darkDynamic;
  bool _settingsChanged = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_loadDynamicColors());
  }

  Future<void> _loadDynamicColors() async {
    final schemes = await loadPlatformColorSchemes();
    if (!mounted || schemes == null) {
      return;
    }
    setState(() {
      _lightDynamic = schemes.light;
      _darkDynamic = schemes.dark;
    });
  }

  Future<void> _loadSettings() async {
    try {
      final autoRefreshInterval = await _settingsRepository
          .getAutoRefreshInterval();
      if (mounted && !_settingsChanged) {
        _autoRefreshInterval.value = autoRefreshInterval;
      }
    } on Object {
      // Keep the default interval if platform preferences are unavailable.
    }
  }

  void _setLocale(Locale locale) {
    if (_locale == locale) {
      return;
    }
    setState(() {
      _locale = locale;
    });
  }

  Future<void> _setAutoRefreshInterval(Duration interval) async {
    await _settingsRepository.setAutoRefreshInterval(interval);
    _settingsChanged = true;
    if (mounted) {
      _autoRefreshInterval.value = interval;
    }
  }

  @override
  void dispose() {
    _autoRefreshInterval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme =
        _lightDynamic ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xff256f78),
          brightness: Brightness.light,
        );
    final darkScheme =
        _darkDynamic ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xff256f78),
          brightness: Brightness.dark,
        );

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _buildTheme(lightScheme),
      darkTheme: _buildTheme(darkScheme),
      home: HomeScreen(
        locale: _locale,
        onLocaleChanged: _setLocale,
        autoRefreshIntervalListenable: _autoRefreshInterval,
        onAutoRefreshIntervalChanged: _setAutoRefreshInterval,
      ),
    );
  }

  ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}
