import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/core/widgets/error_state.dart';
import 'package:pve_manager/data/models/guest_config.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';

const _cpuTypeOptions = <String>[
  'host',
  'kvm64',
  'qemu64',
  'max',
  'x86-64-v2',
  'x86-64-v2-AES',
  'x86-64-v3',
  'x86-64-v4',
  'athlon',
  'EPYC',
  'EPYC-Genoa',
  'EPYC-Genoa-v2',
  'EPYC-IBPB',
  'EPYC-Milan',
  'EPYC-Milan-v2',
  'EPYC-Milan-v3',
  'EPYC-Rome',
  'EPYC-Rome-v2',
  'EPYC-Rome-v3',
  'Opteron_G1',
  'Opteron_G2',
  'Opteron_G3',
  'Opteron_G4',
  'Opteron_G5',
  'Broadwell',
  'Broadwell-IBRS',
  'Broadwell-noTSX',
  'Broadwell-noTSX-IBRS',
  'Cascadelake-Server',
  'Cascadelake-Server-noTSX',
  'Conroe',
  'Haswell',
  'Haswell-IBRS',
  'Haswell-noTSX',
  'Haswell-noTSX-IBRS',
  'Icelake-Client',
  'Icelake-Client-noTSX',
  'Icelake-Server',
  'Icelake-Server-noTSX',
  'IvyBridge',
  'IvyBridge-IBRS',
  'Nehalem',
  'Nehalem-IBRS',
  'Penryn',
  'SandyBridge',
  'SandyBridge-IBRS',
  'SapphireRapids',
  'Skylake-Client',
  'Skylake-Client-IBRS',
  'Skylake-Client-noTSX-IBRS',
  'Skylake-Server',
  'Skylake-Server-IBRS',
  'Skylake-Server-noTSX-IBRS',
  'Westmere',
  'Westmere-IBRS',
];

const _qemuModelKeys = <String>[
  'virtio',
  'e1000',
  'e1000-82540em',
  'e1000-82544gc',
  'e1000-82545em',
  'i82551',
  'i82557b',
  'i82559er',
  'ne2k_isa',
  'ne2k_pci',
  'pcnet',
  'rtl8139',
  'vmxnet3',
];

const _lxcFeatureOptions = <_LxcFeatureOption>[
  _LxcFeatureOption(
    key: 'keyctl',
    storageKey: 'keyctl',
    requiresUnprivileged: true,
  ),
  _LxcFeatureOption(key: 'nesting', storageKey: 'nesting'),
  _LxcFeatureOption(key: 'nfs', storageKey: 'mount'),
  _LxcFeatureOption(key: 'cifs', storageKey: 'mount'),
  _LxcFeatureOption(key: 'fuse', storageKey: 'fuse'),
  _LxcFeatureOption(key: 'mknod', storageKey: 'mknod', experimental: true),
];

class _LxcFeatureOption {
  const _LxcFeatureOption({
    required this.key,
    required this.storageKey,
    this.requiresUnprivileged = false,
    this.experimental = false,
  });

  final String key;
  final String storageKey;
  final bool requiresUnprivileged;
  final bool experimental;
}

class GuestConfigScreen extends StatefulWidget {
  const GuestConfigScreen({
    required this.client,
    required this.guest,
    this.embedded = false,
    this.onBack,
    super.key,
  });

  final ProxmoxClient client;
  final PveResource guest;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<GuestConfigScreen> createState() => _GuestConfigScreenState();
}

class _GuestConfigScreenState extends State<GuestConfigScreen> {
  late Future<GuestConfig> _configFuture;
  GuestConfig? _lastConfig;
  bool _isSaving = false;
  bool _isConfigLoading = false;
  int _configGeneration = 0;

  @override
  void initState() {
    super.initState();
    _configFuture = _loadConfig();
  }

  @override
  void didUpdateWidget(GuestConfigScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guest.id != widget.guest.id ||
        oldWidget.guest.node != widget.guest.node ||
        oldWidget.client != widget.client) {
      _lastConfig = null;
      _configFuture = _loadConfig();
    }
  }

  Future<GuestConfig> _loadConfig() async {
    final generation = ++_configGeneration;
    _isConfigLoading = true;
    try {
      final config = await widget.client.getGuestConfig(widget.guest);
      if (mounted && generation == _configGeneration) {
        _lastConfig = config;
      }
      return config;
    } finally {
      if (generation == _configGeneration) {
        _isConfigLoading = false;
      }
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (!mounted || (_isConfigLoading && !force)) {
      return;
    }
    final future = _loadConfig();
    setState(() {
      _configFuture = future;
    });
    try {
      await future;
    } on Object {
      // FutureBuilder renders failures while retaining the last configuration.
    }
  }

  Future<void> _editItem(String key, String value) async {
    if (widget.guest.type == 'qemu' && key == 'memory') {
      await _editMemory();
      return;
    }
    if (widget.guest.type == 'qemu' && key == 'cpu') {
      await _editCpu();
      return;
    }
    if (widget.guest.type == 'qemu' && key == 'boot') {
      await _editBootOrder(value);
      return;
    }
    if (_isNetworkKey(key)) {
      await _editNetwork(key, value);
      return;
    }
    if (widget.guest.type == 'lxc' && key == 'features') {
      await _editFeatures(value);
      return;
    }

    final options = _configOptions(key);
    final optionValue = _optionValue(key, value);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        if (options.isNotEmpty) {
          return _ConfigOptionDialog(
            title: _configLabel(context.l10n, key),
            configKey: key,
            value: optionValue,
            options: options,
          );
        }
        return _ConfigValueDialog(
          title: _configLabel(context.l10n, key),
          initialValue: value,
        );
      },
    );

    final updatedValue = _mergeOptionValue(key, value, result);
    if (result == null || updatedValue == value || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.client.updateGuestConfig(widget.guest, key, updatedValue);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.configSaved)));
      await _refresh(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editNetwork(String key, String value) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NetworkConfigDialog(
        value: value,
        isQemu: widget.guest.type == 'qemu',
      ),
    );
    if (result == null || result == value || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.client.updateGuestConfig(widget.guest, key, result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.configSaved)));
      await _refresh(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editCpu() async {
    final guestConfig = _lastConfig;
    if (guestConfig == null) {
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _CpuConfigDialog(config: guestConfig),
    );
    if (result == null || result.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.client.updateGuestConfigValues(widget.guest, result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.configSaved)));
      await _refresh(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editBootOrder(String value) async {
    final guestConfig = _lastConfig;
    if (guestConfig == null) {
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _BootOrderDialog(config: guestConfig.values, initialValue: value),
    );
    if (result == null || result == value || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.client.updateGuestConfig(widget.guest, 'boot', result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.configSaved)));
      await _refresh(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editMemory() async {
    final guestConfig = _lastConfig;
    if (guestConfig == null) {
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _MemoryConfigDialog(config: guestConfig),
    );
    if (result == null || result.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.client.updateGuestConfigValues(widget.guest, result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.configSaved)));
      await _refresh(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editFeatures(String value) async {
    final guestConfig = _lastConfig;
    if (guestConfig == null) {
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _LxcFeaturesDialog(config: guestConfig, initialValue: value),
    );
    if (result == null || result == value || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.client.updateGuestConfig(widget.guest, 'features', result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.configSaved)));
      await _refresh(force: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded && widget.onBack != null
            ? BackButton(onPressed: widget.onBack)
            : null,
        title: Text(l10n.hardwareConfig),
      ),
      body: Stack(
        children: [
          FutureBuilder<GuestConfig>(
            key: ValueKey((widget.client, widget.guest.id, widget.guest.node)),
            future: _configFuture,
            builder: (context, snapshot) {
              final guestConfig = snapshot.data ?? _lastConfig;
              if (snapshot.connectionState == ConnectionState.waiting &&
                  guestConfig == null) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError && guestConfig == null) {
                return ErrorState(
                  message: localizedError(l10n, snapshot.error!),
                  onRetry: _refresh,
                );
              }

              final entries = _orderedEntries(guestConfig!.values);
              if (entries.isEmpty) {
                return Center(child: Text(l10n.noData));
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final editable = _isDisplayEditable(guestConfig, entry.key);
                    return Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      child: ListTile(
                        title: Text(
                          _configLabel(l10n, entry.key),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _configDisplayValue(
                            entry.key,
                            entry.value,
                            guestConfig.values,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: editable
                            ? null
                            : Tooltip(
                                message: l10n.notEditable,
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                        enabled: editable,
                        onTap: _isSaving || !editable
                            ? null
                            : () => _editItem(entry.key, entry.value),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (_isSaving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
    if (!widget.embedded || widget.onBack == null) {
      return scaffold;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          widget.onBack?.call();
        }
      },
      child: scaffold,
    );
  }

  String _configLabel(AppLocalizations l10n, String key) {
    if (widget.guest.type == 'lxc' && key == 'ostype') {
      return 'OS';
    }
    return switch (key) {
      'agent' => 'QEMU Guest Agent',
      'arch' => l10n.architecture,
      'bios' => 'BIOS',
      'boot' => l10n.bootOrder,
      'cores' => l10n.cpuCores,
      'cpu' => 'CPU',
      'cpuunits' => l10n.cpuUnits,
      'efidisk0' => 'EFI ${l10n.disk}',
      'features' => l10n.features,
      'machine' => l10n.machine,
      'memory' => l10n.memory,
      'name' || 'hostname' => l10n.serverName,
      _ when _isNetworkKey(key) => l10n.network,
      'ostype' => l10n.osType,
      'onboot' => l10n.onBoot,
      'scsihw' => l10n.scsiController,
      'serial0' || 'serial1' => 'Serial',
      'sockets' => l10n.cpuSockets,
      'tags' => l10n.tags,
      'vga' => l10n.display,
      _ => key,
    };
  }

  List<MapEntry<String, String>> _orderedEntries(Map<String, String> config) {
    final preferredKeys = widget.guest.type == 'qemu'
        ? const <String>[
            'name',
            'tags',
            'cpu',
            'memory',
            'bios',
            'vga',
            'machine',
            'scsihw',
          ]
        : const <String>[
            'hostname',
            'tags',
            'cores',
            'memory',
            'swap',
            'cpulimit',
            'cpuunits',
            'ostype',
            'arch',
            'features',
          ];

    final keys = <String>[
      ...preferredKeys,
      ...config.keys.where(_isNetworkKey).toList()..sort(),
      'onboot',
      ...config.keys.where(_isDiskKey).toList()..sort(_compareDeviceKeys),
      ...config.keys.where(_isPciKey).toList()..sort(_compareDeviceKeys),
    ];

    final seen = <String>{};
    final entries = <MapEntry<String, String>>[];
    for (final key in keys) {
      if (seen.add(key)) {
        final value = _syntheticConfigValue(key, config);
        if (value != null) {
          entries.add(MapEntry(key, value));
        }
      }
    }

    final hiddenKeys = widget.guest.type == 'qemu'
        ? const <String>{
            'balloon',
            'shares',
            'allow-ksm',
            'cores',
            'sockets',
            'affinity',
            'meta',
            'smbios1',
            'vmgenid',
            'numa',
          }
        : const <String>{};
    final remainingKeys = config.keys
        .where((key) => !seen.contains(key) && !hiddenKeys.contains(key))
        .toList();
    remainingKeys.sort((a, b) {
      final rankCompare = _remainingKeyRank(a).compareTo(_remainingKeyRank(b));
      if (rankCompare != 0) {
        return rankCompare;
      }
      return a.compareTo(b);
    });
    for (final key in remainingKeys) {
      entries.add(MapEntry(key, config[key]!));
    }
    return entries;
  }

  int _remainingKeyRank(String key) {
    return switch (key) {
      'name' || 'hostname' => 90,
      'tags' => 91,
      _ => 10,
    };
  }

  String? _syntheticConfigValue(String key, Map<String, String> config) {
    if (config.containsKey(key)) {
      return config[key]!;
    }
    if (key == 'tags') {
      return '';
    }
    if (key == 'onboot') {
      return '0';
    }
    if (widget.guest.type == 'lxc' && key == 'features') {
      return '';
    }
    return null;
  }

  List<String> _configOptions(String key) {
    return switch (key) {
      'bios' => const <String>['seabios', 'ovmf'],
      'cpu' => _cpuTypeOptions,
      'machine' => const <String>['i440fx', 'q35'],
      'scsihw' => const <String>[
        'lsi',
        'lsi53c810',
        'megasas',
        'pvscsi',
        'virtio-scsi-pci',
        'virtio-scsi-single',
      ],
      'vga' => const <String>[
        'std',
        'cirrus',
        'vmware',
        'qxl',
        'virtio',
        'serial0',
        'none',
      ],
      'ostype' => const <String>[
        'l26',
        'l24',
        'solaris',
        'win11',
        'win10',
        'win8',
        'win7',
        'w2k19',
        'w2k16',
        'w2k12',
        'w2k8',
        'wvista',
        'wxp',
        'other',
      ],
      'agent' => const <String>['enabled=1', 'enabled=0'],
      'onboot' => const <String>['enabled', 'disabled'],
      _ => const <String>[],
    };
  }

  bool _isDisplayEditable(GuestConfig config, String key) {
    if (widget.guest.type == 'qemu' && key == 'cpu') {
      return config.isEditable('cpu') ||
          config.isEditable('cores') ||
          config.isEditable('sockets') ||
          config.isEditable('affinity');
    }
    if (widget.guest.type == 'lxc' && (key == 'ostype' || key == 'arch')) {
      return false;
    }
    return config.isEditable(key);
  }

  String _optionValue(String key, String value) {
    if (key == 'cpu') {
      return value.split(',').first;
    }
    if (key == 'machine') {
      final machine = value.split(',').first;
      return machine == 'pc' ? 'i440fx' : machine;
    }
    if (key == 'agent') {
      return _agentEnabled(value) ? 'enabled=1' : 'enabled=0';
    }
    if (key == 'onboot') {
      return value == '1' ? 'enabled' : 'disabled';
    }
    return value;
  }

  String _mergeOptionValue(String key, String originalValue, String? result) {
    if (result == null) {
      return originalValue;
    }
    if (key == 'machine') {
      final machine = result == 'i440fx' ? 'pc' : result;
      final parts = originalValue.split(',');
      if (parts.length <= 1) {
        return machine;
      }
      return [machine, ...parts.skip(1)].join(',');
    }
    if (key == 'agent') {
      return result;
    }
    if (key == 'onboot') {
      return result == 'enabled' ? '1' : '0';
    }
    if (key != 'cpu') {
      return result;
    }

    final parts = originalValue.split(',');
    if (parts.length <= 1) {
      return result;
    }
    return [result, ...parts.skip(1)].join(',');
  }

  String _configDisplayValue(
    String key,
    String value,
    Map<String, String> config,
  ) {
    if (key == 'memory') {
      final mib = int.tryParse(value);
      if (mib != null && mib > 0) {
        return '${(mib / 1024).toStringAsFixed(2)} GiB';
      }
    }
    if (key == 'bios') {
      return switch (value) {
        'ovmf' => 'OVMF (UEFI)',
        'seabios' => 'SeaBIOS',
        _ => value,
      };
    }
    if (key == 'cpu') {
      final parts = <String>[
        if ((config['cores'] ?? '').isNotEmpty)
          '${context.l10n.cpuCores}: ${config['cores']}',
        if ((config['sockets'] ?? '').isNotEmpty)
          '${context.l10n.cpuSockets}: ${config['sockets']}',
        if (value.isNotEmpty)
          '${context.l10n.cpuType}: ${value.split(',').first}',
        if (_cpuAffinity(config).isNotEmpty)
          '${context.l10n.cpuAffinity}: ${_cpuAffinity(config)}',
      ];
      return parts.join(' · ');
    }
    if (key == 'machine') {
      final parts = value.split(',');
      final machine = parts.first == 'pc'
          ? '${context.l10n.defaultValue} (i440fx)'
          : parts.first;
      if (parts.length <= 1) {
        return machine;
      }
      return [machine, ...parts.skip(1)].join(',');
    }
    if (key == 'vga' && value == 'std') {
      return context.l10n.defaultValue;
    }
    if (key == 'agent') {
      return _agentEnabled(value) ? context.l10n.enable : context.l10n.disable;
    }
    if (key == 'onboot') {
      return value == '1' ? context.l10n.enable : context.l10n.disable;
    }
    if (key == 'swap') {
      return _mibDisplayValue(value);
    }
    if (key == 'features') {
      return _featuresDisplayValue(value);
    }
    if (key == 'ostype') {
      return _osTypeLabel(value);
    }
    return value;
  }

  String _featuresDisplayValue(String value) {
    final labels = _selectedLxcFeatureLabels(context, value);
    if (labels.isEmpty) {
      return context.l10n.disable;
    }
    return labels.join(' · ');
  }

  String _mibDisplayValue(String value) {
    final mib = int.tryParse(value);
    if (mib == null) {
      return value;
    }
    if (mib >= 1024) {
      return '${(mib / 1024).toStringAsFixed(2)} GiB';
    }
    return '$mib MiB';
  }

  bool _agentEnabled(String value) {
    final parts = value.split(',');
    final first = parts.first.trim();
    if (first == '0' || first == 'enabled=0') {
      return false;
    }
    return true;
  }

  String _cpuAffinity(Map<String, String> values) {
    final directAffinity = values['affinity'];
    if (directAffinity != null && directAffinity.isNotEmpty) {
      return directAffinity;
    }
    final cpuParts = (values['cpu'] ?? '').split(',');
    for (final part in cpuParts.skip(1)) {
      final trimmed = part.trim();
      if (trimmed.startsWith('affinity=')) {
        return trimmed.substring('affinity='.length);
      }
    }
    return '';
  }

  bool _isNetworkKey(String key) => RegExp(r'^net\d+$').hasMatch(key);
  bool _isDiskKey(String key) {
    return RegExp(
      r'^(ide|sata|scsi|virtio|efidisk|tpmstate|mp)\d+$',
    ).hasMatch(key);
  }

  bool _isPciKey(String key) => RegExp(r'^hostpci\d+$').hasMatch(key);

  int _compareDeviceKeys(String a, String b) {
    final prefixCompare = _devicePrefix(a).compareTo(_devicePrefix(b));
    if (prefixCompare != 0) {
      return prefixCompare;
    }
    return _deviceIndex(a).compareTo(_deviceIndex(b));
  }

  String _devicePrefix(String key) {
    return RegExp(r'^[a-z]+').firstMatch(key)?.group(0) ?? key;
  }

  int _deviceIndex(String key) {
    return int.tryParse(RegExp(r'\d+$').firstMatch(key)?.group(0) ?? '') ?? 0;
  }
}

class _ConfigOptionDialog extends StatelessWidget {
  const _ConfigOptionDialog({
    required this.title,
    required this.configKey,
    required this.value,
    required this.options,
  });

  final String title;
  final String configKey;
  final String value;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final dialogWidth = availableWidth < 360 ? availableWidth : 360.0;
    final listHeight = (options.length * 56.0).clamp(56.0, 420.0).toDouble();

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: dialogWidth,
        height: listHeight,
        child: ListView.builder(
          itemCount: options.length,
          itemBuilder: (context, index) {
            final option = options[index];
            final selected = option == value;
            return ListTile(
              leading: Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(_optionLabel(context, option)),
              onTap: () => Navigator.of(context).pop(option),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }

  String _optionLabel(BuildContext context, String option) {
    if (configKey == 'agent') {
      return option == 'enabled=1' ? context.l10n.enable : context.l10n.disable;
    }
    if (configKey == 'onboot') {
      return option == 'enabled' ? context.l10n.enable : context.l10n.disable;
    }
    if (configKey == 'ostype') {
      return _osTypeLabel(option);
    }
    return option == 'i440fx'
        ? '${context.l10n.defaultValue} (i440fx)'
        : option;
  }
}

String _osTypeLabel(String value) {
  return switch (value) {
    'l26' => 'Linux - 6.x / 2.6 Kernel',
    'l24' => 'Linux - 2.4 Kernel',
    'solaris' => 'Solaris/OpenSolaris/OpenIndiania',
    'win11' => 'Microsoft Windows 11/2022',
    'win10' => 'Microsoft Windows 10/2016/2019',
    'win8' => 'Microsoft Windows 8.x/2012/2012r2',
    'win7' => 'Microsoft Windows 7/2008r2',
    'w2k19' => 'Microsoft Windows Server 2019',
    'w2k16' => 'Microsoft Windows Server 2016',
    'w2k12' => 'Microsoft Windows Server 2012',
    'w2k8' => 'Microsoft Windows Vista/2008',
    'wvista' => 'Microsoft Windows Vista',
    'wxp' => 'Microsoft Windows XP/2003',
    'other' => 'Other OS types',
    _ => value,
  };
}

String _lxcFeatureLabel(BuildContext context, String key) {
  final l10n = context.l10n;
  return switch (key) {
    'keyctl' => l10n.featureKeyctl,
    'nesting' => l10n.featureNesting,
    'nfs' => 'NFS',
    'cifs' => 'SMB/CIFS',
    'fuse' => 'FUSE',
    'mknod' => l10n.featureMknod,
    _ => key,
  };
}

List<String> _selectedLxcFeatureLabels(BuildContext context, String value) {
  final values = _parseLxcFeatures(value);
  final labels = <String>[];
  for (final option in _lxcFeatureOptions) {
    if (_featureEnabled(values, option)) {
      labels.add(_lxcFeatureLabel(context, option.key));
    }
  }
  return labels;
}

Map<String, String> _parseLxcFeatures(String value) {
  final result = <String, String>{};
  for (final part in value.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final index = trimmed.indexOf('=');
    if (index <= 0) {
      result[trimmed] = '1';
      continue;
    }
    result[trimmed.substring(0, index).trim()] = trimmed
        .substring(index + 1)
        .trim();
  }
  return result;
}

bool _featureEnabled(Map<String, String> values, _LxcFeatureOption option) {
  final value = values[option.storageKey];
  if (value == null || value.isEmpty || value == '0') {
    return false;
  }
  if (option.storageKey != 'mount') {
    return value == '1';
  }
  return value
      .split(';')
      .map((part) => part.trim().toLowerCase())
      .contains(option.key);
}

String _buildLxcFeaturesValue(
  String original,
  Map<String, bool> selectedFeatures,
) {
  final values = _parseLxcFeatures(original);
  final mountValues = (values['mount'] ?? '')
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  for (final option in _lxcFeatureOptions) {
    final selected = selectedFeatures[option.key] ?? false;
    if (option.storageKey == 'mount') {
      mountValues.removeWhere(
        (part) => part.toLowerCase() == option.key.toLowerCase(),
      );
      if (selected) {
        mountValues.add(option.key);
      }
    } else if (selected) {
      values[option.storageKey] = '1';
    } else {
      values.remove(option.storageKey);
    }
  }

  if (mountValues.isEmpty) {
    values.remove('mount');
  } else {
    values['mount'] = mountValues.join(';');
  }

  final preferredKeys = <String>['keyctl', 'nesting', 'mount', 'fuse', 'mknod'];
  final remainingKeys =
      values.keys.where((key) => !preferredKeys.contains(key)).toList()..sort();
  return <String>[...preferredKeys, ...remainingKeys]
      .where((key) => values[key]?.isNotEmpty ?? false)
      .map((key) => '$key=${values[key]}')
      .join(',');
}

class _LxcFeaturesDialog extends StatefulWidget {
  const _LxcFeaturesDialog({required this.config, required this.initialValue});

  final GuestConfig config;
  final String initialValue;

  @override
  State<_LxcFeaturesDialog> createState() => _LxcFeaturesDialogState();
}

class _LxcFeaturesDialogState extends State<_LxcFeaturesDialog> {
  late final Map<String, bool> _selected;
  late final bool _unprivileged;

  @override
  void initState() {
    super.initState();
    final values = _parseLxcFeatures(widget.initialValue);
    _selected = {
      for (final option in _lxcFeatureOptions)
        option.key: _featureEnabled(values, option),
    };
    _unprivileged = widget.config.values['unprivileged'] == '1';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final dialogWidth = availableWidth < 420 ? availableWidth : 420.0;
    return AlertDialog(
      title: Text(l10n.editFeatures),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _lxcFeatureOptions)
              CheckboxListTile(
                value: _selected[option.key] ?? false,
                title: Text(_lxcFeatureLabel(context, option.key)),
                subtitle: option.experimental
                    ? Text(l10n.experimental)
                    : option.requiresUnprivileged && !_unprivileged
                    ? Text(l10n.requiresUnprivilegedContainer)
                    : null,
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding: EdgeInsets.zero,
                enabled: _optionEnabled(option),
                onChanged: _optionEnabled(option)
                    ? (value) {
                        setState(() {
                          _selected[option.key] = value ?? false;
                        });
                      }
                    : null,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_buildLxcFeaturesValue(widget.initialValue, _selected)),
          child: Text(l10n.save),
        ),
      ],
    );
  }

  bool _optionEnabled(_LxcFeatureOption option) {
    if (!widget.config.isEditable('features')) {
      return false;
    }
    if (option.requiresUnprivileged && !_unprivileged) {
      return false;
    }
    return true;
  }
}

class _BootOrderDialog extends StatefulWidget {
  const _BootOrderDialog({required this.config, required this.initialValue});

  final Map<String, String> config;
  final String initialValue;

  @override
  State<_BootOrderDialog> createState() => _BootOrderDialogState();
}

class _BootOrderDialogState extends State<_BootOrderDialog> {
  late final List<String> _devices;
  late final List<String> _selected;

  @override
  void initState() {
    super.initState();
    _devices = _bootDevices(widget.config);
    _selected = _bootOrder(
      widget.initialValue,
    ).where(_devices.contains).toList(growable: true);
    if (_selected.isEmpty && _devices.isNotEmpty) {
      _selected.add(_devices.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final dialogWidth = availableWidth < 360 ? availableWidth : 360.0;
    final listHeight = (_devices.length * 72.0).clamp(72.0, 420.0).toDouble();
    return AlertDialog(
      title: Text(l10n.selectBootDevices),
      content: SizedBox(
        width: dialogWidth,
        height: _devices.isEmpty ? 64 : listHeight,
        child: _devices.isEmpty
            ? Center(child: Text(l10n.noBootDevices))
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _devices.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  final selected = _selected.contains(device);
                  return CheckboxListTile(
                    key: ValueKey(device),
                    value: selected,
                    title: Text(device),
                    subtitle: Text(
                      widget.config[device] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle_rounded),
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          if (!_selected.contains(device)) {
                            _selected.add(device);
                          }
                        } else {
                          _selected.remove(device);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop('order=${_selected.join(';')}'),
          child: Text(l10n.save),
        ),
      ],
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final device = _devices.removeAt(oldIndex);
      _devices.insert(newIndex, device);

      final selectedInOrder = _devices
          .where(_selected.contains)
          .toList(growable: false);
      _selected
        ..clear()
        ..addAll(selectedInOrder);
    });
  }

  List<String> _bootOrder(String value) {
    final order = value
        .split(',')
        .firstWhere(
          (part) => part.trim().startsWith('order='),
          orElse: () => value.startsWith('order=') ? value : '',
        );
    if (order.isEmpty) {
      return const <String>[];
    }
    return order
        .replaceFirst('order=', '')
        .split(';')
        .map((device) => device.trim())
        .where((device) => device.isNotEmpty)
        .toList();
  }

  List<String> _bootDevices(Map<String, String> config) {
    final devices = config.keys
        .where((key) => _isBootDevice(key, config[key] ?? ''))
        .toList();
    devices.sort(_compareBootDevices);
    return devices;
  }

  bool _isBootDevice(String key, String value) {
    if (RegExp(r'^(ide|sata|scsi|virtio)\d+$').hasMatch(key)) {
      return true;
    }
    if (RegExp(r'^net\d+$').hasMatch(key)) {
      return true;
    }
    return key.startsWith('efidisk') && value.isNotEmpty;
  }

  int _compareBootDevices(String a, String b) {
    final rankCompare = _bootDeviceRank(a).compareTo(_bootDeviceRank(b));
    if (rankCompare != 0) {
      return rankCompare;
    }
    return _deviceIndex(a).compareTo(_deviceIndex(b));
  }

  int _bootDeviceRank(String key) {
    if (key.startsWith('scsi')) {
      return 0;
    }
    if (key.startsWith('virtio')) {
      return 1;
    }
    if (key.startsWith('sata')) {
      return 2;
    }
    if (key.startsWith('ide')) {
      return 3;
    }
    if (key.startsWith('efidisk')) {
      return 4;
    }
    if (key.startsWith('net')) {
      return 5;
    }
    return 99;
  }

  int _deviceIndex(String key) {
    return int.tryParse(RegExp(r'\d+$').firstMatch(key)?.group(0) ?? '') ?? 0;
  }
}

class _CpuConfigDialog extends StatefulWidget {
  const _CpuConfigDialog({required this.config});

  final GuestConfig config;

  @override
  State<_CpuConfigDialog> createState() => _CpuConfigDialogState();
}

class _CpuConfigDialogState extends State<_CpuConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _coresController;
  late final TextEditingController _socketsController;
  late final TextEditingController _affinityController;
  late String _cpuType;

  @override
  void initState() {
    super.initState();
    final values = widget.config.values;
    _coresController = TextEditingController(text: values['cores'] ?? '');
    _socketsController = TextEditingController(text: values['sockets'] ?? '');
    _affinityController = TextEditingController(text: _cpuAffinity(values));
    _cpuType = _cpuTypeValue(values['cpu'] ?? '');
  }

  @override
  void dispose() {
    _coresController.dispose();
    _socketsController.dispose();
    _affinityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final dialogWidth = availableWidth < 420 ? availableWidth : 420.0;
    return AlertDialog(
      title: Text(l10n.editCpu),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NumberField(
                controller: _coresController,
                label: l10n.cpuCores,
                enabled: widget.config.isEditable('cores'),
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _socketsController,
                label: l10n.cpuSockets,
                enabled: widget.config.isEditable('sockets'),
              ),
              const SizedBox(height: 12),
              _SelectField(
                label: l10n.cpuType,
                value: _cpuType,
                enabled: widget.config.isEditable('cpu'),
                onTap: _selectCpuType,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _affinityController,
                enabled: widget.config.isEditable('affinity'),
                decoration: InputDecoration(labelText: l10n.cpuAffinity),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final original = widget.config.values;
    final values = <String, String>{};

    void setIfEditableAndChanged(String key, String value) {
      if (widget.config.isEditable(key) && (original[key] ?? '') != value) {
        values[key] = value;
      }
    }

    setIfEditableAndChanged('cores', _coresController.text.trim());
    setIfEditableAndChanged('sockets', _socketsController.text.trim());

    if (widget.config.isEditable('cpu')) {
      final affinityInCpu = widget.config.isEditable('affinity')
          ? _cpuAffinityFromValue(original['cpu'] ?? '')
          : _affinityController.text.trim();
      final mergedCpu = _mergeCpuValue(
        original['cpu'] ?? '',
        _cpuType,
        affinityInCpu,
      );
      if ((original['cpu'] ?? '') != mergedCpu) {
        values['cpu'] = mergedCpu;
      }
    }

    if (widget.config.isEditable('affinity')) {
      setIfEditableAndChanged('affinity', _affinityController.text.trim());
    }

    Navigator.of(context).pop(values);
  }

  Future<void> _selectCpuType() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ConfigOptionDialog(
        title: context.l10n.cpuType,
        configKey: 'cpu',
        value: _cpuType,
        options: _availableCpuTypes,
      ),
    );
    if (result == null || result == _cpuType || !mounted) {
      return;
    }
    setState(() {
      _cpuType = result;
    });
  }

  String _cpuTypeValue(String value) {
    final type = value.split(',').first.trim();
    return type.isEmpty ? 'host' : type;
  }

  List<String> get _availableCpuTypes {
    if (_cpuTypeOptions.contains(_cpuType)) {
      return _cpuTypeOptions;
    }
    return <String>[_cpuType, ..._cpuTypeOptions];
  }

  String _cpuAffinity(Map<String, String> values) {
    final directAffinity = values['affinity'];
    if (directAffinity != null && directAffinity.isNotEmpty) {
      return directAffinity;
    }
    final cpuParts = (values['cpu'] ?? '').split(',');
    for (final part in cpuParts.skip(1)) {
      final trimmed = part.trim();
      if (trimmed.startsWith('affinity=')) {
        return trimmed.substring('affinity='.length);
      }
    }
    return '';
  }

  String _cpuAffinityFromValue(String value) {
    final cpuParts = value.split(',');
    for (final part in cpuParts.skip(1)) {
      final trimmed = part.trim();
      if (trimmed.startsWith('affinity=')) {
        return trimmed.substring('affinity='.length);
      }
    }
    return '';
  }

  String _mergeCpuValue(String original, String type, String affinity) {
    final parts = original
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && !part.startsWith('affinity='))
        .toList();
    final extras = parts.length <= 1 ? <String>[] : parts.skip(1).toList();
    if (affinity.isNotEmpty) {
      extras.add('affinity=$affinity');
    }
    return [type, ...extras].join(',');
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _NetworkConfigDialog extends StatefulWidget {
  const _NetworkConfigDialog({required this.value, required this.isQemu});

  final String value;
  final bool isQemu;

  @override
  State<_NetworkConfigDialog> createState() => _NetworkConfigDialogState();
}

class _NetworkConfigDialogState extends State<_NetworkConfigDialog> {
  late final Map<String, String> _initial;
  late final TextEditingController _nameController;
  late final TextEditingController _bridgeController;
  late final TextEditingController _modelController;
  late final TextEditingController _tagController;
  late final TextEditingController _hwaddrController;
  late final TextEditingController _ipController;
  late final TextEditingController _gwController;
  late final TextEditingController _typeController;
  late final TextEditingController _rateController;
  late final TextEditingController _mtuController;
  late final TextEditingController _queuesController;
  late bool _firewall;
  late bool _linkDown;
  late bool _useDhcp;

  @override
  void initState() {
    super.initState();
    _initial = _parseConfigValue(widget.value);
    _nameController = TextEditingController(text: _initial['name'] ?? '');
    _bridgeController = TextEditingController(text: _initial['bridge'] ?? '');
    final model = _networkModel(_initial);
    _modelController = TextEditingController(text: model);
    _tagController = TextEditingController(text: _initial['tag'] ?? '');
    _hwaddrController = TextEditingController(
      text: widget.isQemu ? _initial[model] ?? '' : _initial['hwaddr'] ?? '',
    );
    _useDhcp = (_initial['ip'] ?? '').toLowerCase() == 'dhcp';
    _ipController = TextEditingController(
      text: _useDhcp ? '' : _initial['ip'] ?? '',
    );
    _gwController = TextEditingController(
      text: _useDhcp ? '' : _initial['gw'] ?? '',
    );
    _typeController = TextEditingController(text: _initial['type'] ?? '');
    _rateController = TextEditingController(text: _initial['rate'] ?? '');
    _mtuController = TextEditingController(text: _initial['mtu'] ?? '');
    _queuesController = TextEditingController(text: _initial['queues'] ?? '');
    _firewall = _initial['firewall'] == '1';
    _linkDown = _initial['link_down'] == '1';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bridgeController.dispose();
    _modelController.dispose();
    _tagController.dispose();
    _hwaddrController.dispose();
    _ipController.dispose();
    _gwController.dispose();
    _typeController.dispose();
    _rateController.dispose();
    _mtuController.dispose();
    _queuesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final dialogWidth = availableWidth < 420 ? availableWidth : 420.0;
    return AlertDialog(
      title: Text(l10n.network),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.isQemu ? _qemuFields(l10n) : _lxcFields(l10n),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_buildValue()),
          child: Text(l10n.save),
        ),
      ],
    );
  }

  String _buildValue() {
    final values = Map<String, String>.from(_initial);
    if (widget.isQemu) {
      return _buildQemuValue(values);
    }
    return _buildLxcValue(values);
  }

  List<Widget> _qemuFields(AppLocalizations l10n) {
    return [
      TextField(
        controller: _bridgeController,
        decoration: InputDecoration(labelText: l10n.bridge),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _modelController,
        decoration: InputDecoration(labelText: l10n.model),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _tagController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: l10n.vlanTag),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _hwaddrController,
        decoration: InputDecoration(labelText: l10n.macAddress),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        value: _firewall,
        title: Text(l10n.firewall),
        contentPadding: EdgeInsets.zero,
        onChanged: (value) => setState(() => _firewall = value),
      ),
      SwitchListTile(
        value: _linkDown,
        title: Text(l10n.disconnected),
        contentPadding: EdgeInsets.zero,
        onChanged: (value) => setState(() => _linkDown = value),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _rateController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: l10n.rateLimit),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _mtuController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: l10n.mtu),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _queuesController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: l10n.multiqueue),
      ),
    ];
  }

  List<Widget> _lxcFields(AppLocalizations l10n) {
    return [
      TextField(
        controller: _nameController,
        decoration: InputDecoration(labelText: l10n.networkName),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _bridgeController,
        decoration: InputDecoration(labelText: l10n.bridge),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _hwaddrController,
        decoration: InputDecoration(labelText: l10n.macAddress),
      ),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('DHCP')),
          ButtonSegment(value: false, label: Text('Static')),
        ],
        selected: {_useDhcp},
        onSelectionChanged: (selection) {
          setState(() {
            _useDhcp = selection.first;
          });
        },
      ),
      if (!_useDhcp) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _ipController,
          decoration: InputDecoration(labelText: l10n.ipAddress),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _gwController,
          decoration: InputDecoration(labelText: l10n.gateway),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _typeController,
        decoration: InputDecoration(labelText: l10n.networkType),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        value: _firewall,
        title: Text(l10n.firewall),
        contentPadding: EdgeInsets.zero,
        onChanged: (value) {
          setState(() {
            _firewall = value;
          });
        },
      ),
    ];
  }

  String _buildLxcValue(Map<String, String> values) {
    values['name'] = _nameController.text.trim();
    values['bridge'] = _bridgeController.text.trim();
    values['hwaddr'] = _hwaddrController.text.trim();
    if (_useDhcp) {
      values['ip'] = 'dhcp';
      values.remove('gw');
    } else {
      values['ip'] = _ipController.text.trim();
      values['gw'] = _gwController.text.trim();
    }
    values['type'] = _typeController.text.trim();
    values['firewall'] = _firewall ? '1' : '0';

    const preferredKeys = <String>[
      'name',
      'bridge',
      'firewall',
      'hwaddr',
      'ip',
      'gw',
      'type',
    ];
    final remainingKeys =
        values.keys.where((key) => !preferredKeys.contains(key)).toList()
          ..sort();
    final orderedKeys = <String>[...preferredKeys, ...remainingKeys];
    return orderedKeys
        .where((key) => values[key]?.isNotEmpty ?? false)
        .map((key) => '$key=${values[key]}')
        .join(',');
  }

  String _buildQemuValue(Map<String, String> values) {
    final model = _modelController.text.trim();
    values.removeWhere((key, _) => _qemuModelKeys.contains(key));
    if (model.isNotEmpty) {
      values[model] = _hwaddrController.text.trim();
    }
    values['bridge'] = _bridgeController.text.trim();
    values['tag'] = _tagController.text.trim();
    values['firewall'] = _firewall ? '1' : '0';
    values['link_down'] = _linkDown ? '1' : '0';
    values['rate'] = _rateController.text.trim();
    values['mtu'] = _mtuController.text.trim();
    values['queues'] = _queuesController.text.trim();

    final preferredKeys = <String>[
      ..._qemuModelKeys.where(values.containsKey),
      'bridge',
      'tag',
      'firewall',
      'link_down',
      'rate',
      'mtu',
      'queues',
    ];
    final remainingKeys =
        values.keys.where((key) => !preferredKeys.contains(key)).toList()
          ..sort();
    return <String>[...preferredKeys, ...remainingKeys]
        .where((key) => values[key]?.isNotEmpty ?? false)
        .map((key) => '$key=${values[key]}')
        .join(',');
  }

  String _networkModel(Map<String, String> values) {
    for (final key in _qemuModelKeys) {
      if (values.containsKey(key)) {
        return key;
      }
    }
    return values['model'] ?? 'virtio';
  }

  Map<String, String> _parseConfigValue(String value) {
    final result = <String, String>{};
    for (final part in value.split(',')) {
      final index = part.indexOf('=');
      if (index <= 0) {
        continue;
      }
      result[part.substring(0, index).trim()] = part
          .substring(index + 1)
          .trim();
    }
    return result;
  }
}

class _MemoryConfigDialog extends StatefulWidget {
  const _MemoryConfigDialog({required this.config});

  final GuestConfig config;

  @override
  State<_MemoryConfigDialog> createState() => _MemoryConfigDialogState();
}

class _MemoryConfigDialogState extends State<_MemoryConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _memoryController;
  late final TextEditingController _minimumMemoryController;
  late final TextEditingController _sharesController;
  late bool _ballooningEnabled;
  late bool _ksmEnabled;
  late final bool _sharesEditable;
  late final bool _ksmEditable;

  @override
  void initState() {
    super.initState();
    final values = widget.config.values;
    final memory = values['memory'] ?? '';
    final balloon = values['balloon'];
    _memoryController = TextEditingController(text: memory);
    _minimumMemoryController = TextEditingController(
      text: balloon == null || balloon == '0' ? memory : balloon,
    );
    _sharesController = TextEditingController(text: values['shares']);
    _ballooningEnabled = balloon != '0';
    _ksmEnabled = values['allow-ksm'] != '0';
    _sharesEditable = widget.config.isEditable('shares');
    _ksmEditable = widget.config.isEditable('allow-ksm');
  }

  @override
  void dispose() {
    _memoryController.dispose();
    _minimumMemoryController.dispose();
    _sharesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final availableWidth = MediaQuery.sizeOf(context).width - 80;
    final dialogWidth = availableWidth < 420 ? availableWidth : 420.0;
    return AlertDialog(
      title: Text(l10n.editMemory),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NumberField(
                controller: _memoryController,
                label: l10n.memoryMib,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _minimumMemoryController,
                label: l10n.minimumMemoryMib,
                enabled: _ballooningEnabled,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _sharesController,
                label: l10n.memoryShares,
                hintText: l10n.defaultMemoryShares,
                required: false,
                enabled: _ballooningEnabled && _sharesEditable,
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _ballooningEnabled,
                title: Text(l10n.ballooningDevice),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                onChanged: (value) {
                  setState(() {
                    _ballooningEnabled = value ?? true;
                    if (_ballooningEnabled &&
                        _minimumMemoryController.text.trim().isEmpty) {
                      _minimumMemoryController.text = _memoryController.text
                          .trim();
                    }
                  });
                },
              ),
              CheckboxListTile(
                value: _ksmEnabled,
                title: Text(l10n.allowKsm),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                onChanged: _ksmEditable
                    ? (value) {
                        setState(() {
                          _ksmEnabled = value ?? true;
                        });
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final original = widget.config.values;
    final memory = _memoryController.text.trim();
    final minimumMemory = _minimumMemoryController.text.trim();
    final shares = _sharesController.text.trim();
    final values = <String, String>{};
    final deleteKeys = <String>[];

    void setIfChanged(String key, String value) {
      if ((original[key] ?? '') != value) {
        values[key] = value;
      }
    }

    setIfChanged('memory', memory);
    setIfChanged('balloon', _ballooningEnabled ? minimumMemory : '0');

    if (_sharesEditable) {
      if (shares.isEmpty) {
        deleteKeys.add('shares');
      } else {
        setIfChanged('shares', shares);
      }
    }

    if (_ksmEditable) {
      setIfChanged('allow-ksm', _ksmEnabled ? '1' : '0');
    }

    if (deleteKeys.isNotEmpty) {
      values['delete'] = deleteKeys.join(',');
    }

    Navigator.of(context).pop(values);
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.hintText,
    this.enabled = true,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool enabled;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, hintText: hintText),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) {
          return required ? context.l10n.configValue : null;
        }
        final number = int.tryParse(text);
        if (number == null || number <= 0) {
          return context.l10n.configValue;
        }
        return null;
      },
    );
  }
}

class _ConfigValueDialog extends StatefulWidget {
  const _ConfigValueDialog({required this.title, required this.initialValue});

  final String title;
  final String initialValue;

  @override
  State<_ConfigValueDialog> createState() => _ConfigValueDialogState();
}

class _ConfigValueDialogState extends State<_ConfigValueDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(labelText: l10n.configValue),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
