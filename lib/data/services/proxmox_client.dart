import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pve_manager/data/models/guest_action.dart';
import 'package:pve_manager/data/models/guest_config.dart';
import 'package:pve_manager/data/models/guest_rrd_point.dart';
import 'package:pve_manager/data/models/node_log_entry.dart';
import 'package:pve_manager/data/models/node_power_action.dart';
import 'package:pve_manager/data/models/node_rrd_point.dart';
import 'package:pve_manager/data/models/node_status.dart';
import 'package:pve_manager/data/models/node_task.dart';
import 'package:pve_manager/data/models/node_terminal_session.dart';
import 'package:pve_manager/data/models/paged_result.dart';
import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/models/pve_node.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/models/pve_storage.dart';

import 'package:pve_manager/data/services/error_messages.dart';
import 'package:pve_manager/data/services/proxmox_api_exception.dart';

class ProxmoxClient {
  ProxmoxClient({
    required this.origin,
    required this.username,
    required this.password,
    this.realm = 'pam',
    this.authMode = ProxmoxAuthMode.password,
    this.apiTokenId = '',
    this.apiTokenSecret = '',
    this.ignoreCertificateErrors = false,
    this.telemetryCacheDuration = const Duration(seconds: 30),
  }) : _httpClient = HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 15);
    _httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) =>
            ignoreCertificateErrors;
  }

  final String origin;
  final String username;
  final String password;
  final String realm;
  final ProxmoxAuthMode authMode;
  final String apiTokenId;
  final String apiTokenSecret;
  final bool ignoreCertificateErrors;
  final Duration telemetryCacheDuration;
  final HttpClient _httpClient;
  final Stopwatch _cacheClock = Stopwatch()..start();
  bool _closed = false;
  int _sessionGeneration = 0;
  String? _ticket;
  String? _csrfToken;
  bool _apiTokenAuthenticated = false;
  final Map<String, _CachedTelemetry<NodeThermalState>> _nodeThermalStateCache =
      <String, _CachedTelemetry<NodeThermalState>>{};
  final Map<String, Future<NodeThermalState>> _nodeThermalStateRequests =
      <String, Future<NodeThermalState>>{};
  final Map<String, _CachedTelemetry<_GuestDiskUsage>> _guestDiskUsageCache =
      <String, _CachedTelemetry<_GuestDiskUsage>>{};
  final Map<String, Future<_GuestDiskUsage?>> _guestDiskUsageRequests =
      <String, Future<_GuestDiskUsage?>>{};

  static const Duration _requestTimeout = Duration(seconds: 12);

  String get displayHost => Uri.parse(origin).host;
  bool get usesApiToken => authMode == ProxmoxAuthMode.apiToken;
  bool get hasActiveSession =>
      !_closed && (usesApiToken ? _apiTokenAuthenticated : _ticket != null);
  String get host => Uri.parse(origin).host;
  String get _configuredUserId =>
      username.contains('@') ? username : '$username@$realm';
  ProxmoxApiTokenCredentials get _apiTokenCredentials =>
      ProxmoxApiTokenCredentials.fromInput(
        username: username,
        realm: realm,
        tokenId: apiTokenId,
        tokenSecret: apiTokenSecret,
      );
  String get userId =>
      usesApiToken ? _apiTokenCredentials.userId : _configuredUserId;

  Map<String, String> get consoleAuthenticationHeaders {
    if (!hasActiveSession) {
      throw const ProxmoxApiException(ProxmoxErrorCode.sessionExpired);
    }
    if (usesApiToken) {
      return {HttpHeaders.authorizationHeader: _apiTokenAuthorizationValue};
    }
    return {
      HttpHeaders.cookieHeader: 'PVEAuthCookie=$authCookieValue',
      'CSRFPreventionToken': ?_csrfToken,
    };
  }

  ProxmoxClient forkSession() {
    if (!hasActiveSession) {
      throw const ProxmoxApiException(ProxmoxErrorCode.sessionExpired);
    }

    return ProxmoxClient(
        origin: origin,
        username: username,
        password: password,
        realm: realm,
        authMode: authMode,
        apiTokenId: apiTokenId,
        apiTokenSecret: apiTokenSecret,
        ignoreCertificateErrors: ignoreCertificateErrors,
        telemetryCacheDuration: telemetryCacheDuration,
      )
      .._ticket = _ticket
      .._csrfToken = _csrfToken
      .._apiTokenAuthenticated = _apiTokenAuthenticated;
  }

  String get authCookieValue {
    final ticket = _ticket;
    if (ticket == null) {
      throw const ProxmoxApiException(ProxmoxErrorCode.sessionExpired);
    }

    return ticket;
  }

  String get _apiTokenAuthorizationValue {
    return _apiTokenCredentials.authorizationValue;
  }

  Map<String, dynamic> get _authenticatedSocketHeaders {
    if (usesApiToken) {
      return <String, dynamic>{
        HttpHeaders.authorizationHeader: _apiTokenAuthorizationValue,
      };
    }
    return <String, dynamic>{
      HttpHeaders.cookieHeader: 'PVEAuthCookie=$authCookieValue',
    };
  }

  Uri nodeShellConsoleUri(String node) {
    return _consoleUri('/', {
      'console': 'shell',
      'node': node,
      'novnc': '1',
      'resize': 'scale',
      'cmd': 'login',
    });
  }

  Uri guestConsoleUri(PveResource guest) {
    if (!guest.isGuest) {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestConsoleOnly);
    }

    final console = switch (guest.type) {
      'qemu' => 'kvm',
      'lxc' => 'lxc',
      _ => throw const ProxmoxApiException(
        ProxmoxErrorCode.unsupportedResourceType,
      ),
    };

    return _consoleUri('/', {
      'console': console,
      'node': guest.node,
      'vmid': '${guest.vmid}',
      'vmname': guest.name,
      'novnc': '1',
      'resize': 'scale',
    });
  }

  Future<void> login({String? tfaChallenge, String? tfaResponse}) async {
    if (usesApiToken) {
      await _request('GET', '/access/permissions');
      _sessionGeneration++;
      _apiTokenAuthenticated = true;
      return;
    }

    final response = await _request(
      'POST',
      '/access/ticket',
      body: {
        'username': userId,
        'password': _ticketPassword(tfaResponse),
        if (tfaChallenge?.trim().isNotEmpty ?? false)
          'tfa-challenge': tfaChallenge!.trim(),
      },
      needsAuth: false,
    );

    final data = _loginData(response);

    if (_boolValue(data['NeedTFA']) || _isTicketChallenge(data['ticket'])) {
      throw ProxmoxTfaRequiredException(challenge: Map.of(data));
    }

    _storeLoginData(data);
  }

  Future<void> completeTwoFactor(
    ProxmoxTfaRequiredException challenge,
    String response,
  ) async {
    if (challenge.usesTicketChallenge) {
      await login(tfaChallenge: challenge.ticket, tfaResponse: response);
      return;
    }

    final temporaryTicket = challenge.ticket;
    if (temporaryTicket == null || temporaryTicket.isEmpty) {
      throw const ProxmoxApiException(ProxmoxErrorCode.loginTicketMissing);
    }

    final result = await _request(
      'POST',
      '/access/tfa',
      body: {'response': response.trim()},
      authTicket: temporaryTicket,
      csrfToken: challenge.csrfToken,
    );

    final data = _loginData(result);
    data['CSRFPreventionToken'] ??= challenge.csrfToken;
    _storeLoginData(data);
  }

  String _ticketPassword(String? tfaResponse) {
    final response = tfaResponse?.trim();
    if (response == null || response.isEmpty) {
      return password;
    }
    if (response.contains(':')) {
      return response;
    }
    return 'totp:$response';
  }

  Future<List<PveResource>> getResources({String? type}) async {
    final response = await _request(
      'GET',
      '/cluster/resources',
      queryParameters: type == null ? null : {'type': type},
    );
    final data = response['data'];

    if (data is! List) {
      return <PveResource>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(PveResource.fromJson)
        .toList()
      ..sort((a, b) {
        final typeOrder = _typeRank(a.type).compareTo(_typeRank(b.type));
        if (typeOrder != 0) {
          return typeOrder;
        }
        if (a.isGuest && b.isGuest) {
          return (a.vmid ?? 0).compareTo(b.vmid ?? 0);
        }
        return a.name.compareTo(b.name);
      });
  }

  Future<List<PveNode>> getNodes() async {
    final response = await _request('GET', '/nodes');
    final data = response['data'];

    if (data is! List) {
      return <PveNode>[];
    }

    return data.whereType<Map<String, dynamic>>().map(PveNode.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Map<String, dynamic>> getClusterStatus() async {
    final response = await _request('GET', '/cluster/status');
    final data = response['data'];

    if (data is List) {
      final cluster = data.whereType<Map<String, dynamic>>().firstWhere(
        (item) => item['type'] == 'cluster',
        orElse: () => <String, dynamic>{},
      );
      return cluster;
    }

    return <String, dynamic>{};
  }

  Future<bool> canReadStorageConfig() async {
    await _request('GET', '/storage');
    return true;
  }

  Future<PveStorageStatus> getNodeStorageStatus(
    String node,
    String storage,
  ) async {
    final response = await _request(
      'GET',
      '/nodes/${node.trim()}/storage/${storage.trim()}/status',
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw ProxmoxApiException(
        ProxmoxErrorCode.apiFormatInvalid,
        values: {'statusCode': 200},
      );
    }
    return PveStorageStatus.fromJson(data, fallbackStorage: storage.trim());
  }

  Future<PveStorageConfig> getStorageConfig(String storage) async {
    final normalizedStorage = storage.trim();
    final response = await _request('GET', '/storage/$normalizedStorage');
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw ProxmoxApiException(
        ProxmoxErrorCode.apiFormatInvalid,
        values: {'statusCode': 200},
      );
    }
    return PveStorageConfig.fromJson(data, fallbackStorage: normalizedStorage);
  }

  Future<PveStorageDetail> getNodeStorageDetail(
    String node,
    String storage,
  ) async {
    final results = await Future.wait<Object>([
      getNodeStorageStatus(node, storage),
      getStorageConfig(storage),
    ]);
    return PveStorageDetail(
      node: node.trim(),
      status: results[0] as PveStorageStatus,
      config: results[1] as PveStorageConfig,
    );
  }

  Future<List<PveStorageContent>> getNodeStorageContent(
    String node,
    String storage, {
    String? content,
  }) async {
    final response = await _request(
      'GET',
      '/nodes/${node.trim()}/storage/${storage.trim()}/content',
      queryParameters: content == null ? null : {'content': content},
    );
    final data = response['data'];
    if (data is! List) {
      return <PveStorageContent>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(PveStorageContent.fromJson)
        .toList()
      ..sort((a, b) => a.volumeId.compareTo(b.volumeId));
  }

  Future<NodeStatus> getNodeStatus(String node) async {
    final response = await _request('GET', '/nodes/$node/status');
    final data = response['data'];

    if (data is! Map<String, dynamic>) {
      throw const ProxmoxApiException(ProxmoxErrorCode.nodeStatusInvalid);
    }

    return NodeStatus.fromJson(data);
  }

  Future<NodeThermalState> getNodeThermalState(String node) async {
    final cached = cachedNodeThermalState(node);
    if (cached != null) {
      return cached;
    }

    final pending = _nodeThermalStateRequests[node];
    if (pending != null) {
      return pending;
    }

    final request = _fetchNodeThermalState(node);
    _nodeThermalStateRequests[node] = request;
    return request;
  }

  NodeThermalState? cachedNodeThermalState(String node) {
    final cached = _nodeThermalStateCache[node];
    if (cached == null || !_isFresh(cached) || cached.value.isEmpty) {
      return null;
    }
    return cached.value;
  }

  void preloadNodeThermalStates(Iterable<String> nodes) {
    final uniqueNodes = nodes
        .map((node) => node.trim())
        .where((node) => node.isNotEmpty)
        .toSet();

    for (final node in uniqueNodes) {
      if (cachedNodeThermalState(node) != null ||
          _nodeThermalStateRequests.containsKey(node)) {
        continue;
      }
      unawaited(
        getNodeThermalState(node).catchError((Object _) {
          return const NodeThermalState.empty();
        }),
      );
    }
  }

  void preloadClusterNodeThermalStates() {
    unawaited(() async {
      try {
        final nodes = await getNodes();
        preloadNodeThermalStates(nodes.map((node) => node.name));
      } on Object {
        // SMART details are optional; connection should not wait on preloading.
      }
    }());
  }

  Future<void> preloadClusterGuestDiskUsage() async {
    try {
      final resources = await getResources(type: 'vm');
      await preloadGuestDiskUsage(resources);
    } on Object {
      // Guest agent disk details are optional and should not block connection.
    }
  }

  Future<void> preloadGuestDiskUsage(Iterable<PveResource> guests) async {
    final futures = <Future<_GuestDiskUsage?>>[];

    for (final guest in guests) {
      if (!_shouldLoadGuestDiskUsage(guest)) {
        continue;
      }

      final key = _guestDiskUsageCacheKey(guest);
      if (key == null || _cachedGuestDiskUsage(guest) != null) {
        continue;
      }

      futures.add(_getQemuGuestAgentDiskUsage(guest));
    }

    if (futures.isEmpty) {
      return;
    }

    await Future.wait(futures);
  }

  PveResource applyCachedGuestDiskUsage(PveResource guest) {
    final usage = _cachedGuestDiskUsage(guest);
    if (usage == null) {
      return guest;
    }
    return guest.copyWith(diskUsed: usage.used, diskTotal: usage.total);
  }

  Future<NodeThermalState> _fetchNodeThermalState(String node) async {
    try {
      final thermalState = await _fetchNodeThermalStateFromApi(node);
      if (!thermalState.isEmpty) {
        _nodeThermalStateCache[node] = _cache(thermalState);
      }
      return thermalState;
    } finally {
      _nodeThermalStateRequests.remove(node);
    }
  }

  Future<NodeThermalState> _fetchNodeThermalStateFromApi(String node) async {
    final results = await Future.wait<Object>([
      getNodeStatus(node),
      _request('GET', '/nodes/$node/disks/list'),
    ]);
    final nodeThermalState = (results[0] as NodeStatus).thermalState;
    final diskListResponse = results[1] as Map<String, dynamic>;
    final diskList = diskListResponse['data'];
    if (diskList is! List) {
      return nodeThermalState;
    }

    final disks = diskList
        .whereType<Map<String, dynamic>>()
        .where((disk) => _diskDevicePath(disk).isNotEmpty)
        .toList();
    final smartResults = await Future.wait(
      disks.map((disk) async {
        final device = _diskDevicePath(disk);
        try {
          final response = await _request(
            'GET',
            '/nodes/$node/disks/smart',
            queryParameters: {'disk': device},
          );
          return _PveDiskSmartResult(disk: disk, response: response);
        } on Object {
          return _PveDiskSmartResult(disk: disk);
        }
      }),
    );

    final diskOutput = StringBuffer();
    for (final result in smartResults) {
      _writePveDiskSmartOutput(diskOutput, result);
    }
    final diskThermalState = NodeThermalState.fromJson(diskOutput.toString());
    return NodeThermalState(
      sensors: <NodeTemperatureSensor>[
        ...nodeThermalState.sensors,
        ...diskThermalState.sensors,
      ],
      diskInfos: <NodeDiskInfo>[
        ...nodeThermalState.diskInfos,
        ...diskThermalState.diskInfos,
      ],
    );
  }

  Future<List<NodeRrdPoint>> getNodeRrdData(
    String node, {
    String timeframe = 'hour',
  }) async {
    final response = await _request(
      'GET',
      '/nodes/$node/rrddata',
      queryParameters: {'timeframe': timeframe, 'cf': 'AVERAGE'},
    );
    final data = response['data'];

    if (data is! List) {
      return <NodeRrdPoint>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(NodeRrdPoint.fromJson)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<List<GuestRrdPoint>> getGuestRrdData(
    PveResource guest, {
    String timeframe = 'hour',
  }) async {
    if (!guest.isGuest) {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestActionOnly);
    }

    final guestPath = switch (guest.type) {
      'qemu' => 'qemu',
      'lxc' => 'lxc',
      _ => throw const ProxmoxApiException(
        ProxmoxErrorCode.unsupportedResourceType,
      ),
    };

    final response = await _request(
      'GET',
      '/nodes/${guest.node}/$guestPath/${guest.vmid}/rrddata',
      queryParameters: {'timeframe': timeframe, 'cf': 'AVERAGE'},
    );
    final data = response['data'];

    if (data is! List) {
      return <GuestRrdPoint>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(GuestRrdPoint.fromJson)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<PveResource> getGuestCurrentStatus(PveResource guest) async {
    if (!guest.isGuest) {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestActionOnly);
    }

    final guestPath = switch (guest.type) {
      'qemu' => 'qemu',
      'lxc' => 'lxc',
      _ => throw const ProxmoxApiException(
        ProxmoxErrorCode.unsupportedResourceType,
      ),
    };

    final response = await _request(
      'GET',
      '/nodes/${guest.node}/$guestPath/${guest.vmid}/status/current',
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return guest;
    }

    final currentStatus = guest.mergeStatus(data);
    if (!_shouldLoadGuestDiskUsage(currentStatus)) {
      return currentStatus;
    }

    final agentDiskUsage = await _getQemuGuestAgentDiskUsage(
      currentStatus,
      useCached: false,
    );
    if (agentDiskUsage == null) {
      return currentStatus;
    }

    return currentStatus.copyWith(
      diskUsed: agentDiskUsage.used,
      diskTotal: agentDiskUsage.total,
    );
  }

  Future<_GuestDiskUsage?> _getQemuGuestAgentDiskUsage(
    PveResource guest, {
    bool useCached = true,
  }) async {
    final key = _guestDiskUsageCacheKey(guest);
    if (key == null) {
      return null;
    }

    if (useCached) {
      final cached = _cachedGuestDiskUsage(guest);
      if (cached != null) {
        return cached;
      }
    }

    final pending = _guestDiskUsageRequests[key];
    if (pending != null) {
      return pending;
    }

    final request = _fetchQemuGuestAgentDiskUsage(guest, key);
    _guestDiskUsageRequests[key] = request;
    return request;
  }

  Future<_GuestDiskUsage?> _fetchQemuGuestAgentDiskUsage(
    PveResource guest,
    String key,
  ) async {
    try {
      final response = await _request(
        'GET',
        '/nodes/${guest.node}/qemu/${guest.vmid}/agent/get-fsinfo',
      );
      final usage = _parseGuestAgentDiskUsage(response['data']);
      if (usage != null) {
        _guestDiskUsageCache[key] = _cache(usage);
      }
      return usage;
    } on Object {
      return _cachedGuestDiskUsage(guest);
    } finally {
      _guestDiskUsageRequests.remove(key);
    }
  }

  Future<GuestConfig> getGuestConfig(PveResource guest) async {
    if (!guest.isGuest) {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestActionOnly);
    }

    final guestPath = _guestApiPath(guest);
    final path = '/nodes/${guest.node}/$guestPath/${guest.vmid}/config';
    final response = await _request('GET', path);
    final data = response['data'];

    var editSchema = const GuestConfigEditSchema.unavailable();
    try {
      final optionsResponse = await _request('OPTIONS', path);
      editSchema = GuestConfigEditSchema.fromOptions(optionsResponse['data']);
    } on ProxmoxApiException {
      editSchema = const GuestConfigEditSchema.unavailable();
    }

    if (data is! Map<String, dynamic>) {
      return GuestConfig(
        values: const <String, String>{},
        editSchema: editSchema,
      );
    }

    final config = <String, String>{};
    for (final entry in data.entries) {
      if (entry.key == 'digest') {
        continue;
      }
      config[entry.key] = entry.value?.toString() ?? '';
    }
    return GuestConfig(values: config, editSchema: editSchema);
  }

  Future<void> updateGuestConfig(
    PveResource guest,
    String key,
    String value,
  ) async {
    await updateGuestConfigValues(guest, {key: value});
  }

  Future<void> updateGuestConfigValues(
    PveResource guest,
    Map<String, String> values,
  ) async {
    if (!guest.isGuest) {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestActionOnly);
    }
    if (values.isEmpty) {
      return;
    }

    final guestPath = _guestApiPath(guest);
    await _request(
      'PUT',
      '/nodes/${guest.node}/$guestPath/${guest.vmid}/config',
      body: values,
    );
  }

  Future<PagedResult<NodeTask>> getNodeTasks(
    String node, {
    int start = 0,
    int limit = 20,
  }) async {
    final response = await _getWithParameterFallback(
      '/nodes/$node/tasks',
      queryParameters: {'start': '$start', 'limit': '$limit'},
    );
    final data = response.body['data'];

    if (data is! List) {
      return const PagedResult<NodeTask>(items: <NodeTask>[], hasMore: false);
    }

    final items = data
        .whereType<Map<String, dynamic>>()
        .map(NodeTask.fromJson)
        .toList();
    final visibleItems = response.usedFallback
        ? items.take(limit).toList()
        : items;

    return PagedResult<NodeTask>(
      items: visibleItems,
      hasMore: !response.usedFallback && items.length >= limit,
      nextStart: !response.usedFallback ? start + visibleItems.length : null,
    );
  }

  /// Reads the newest logs, or entries preceding the returned cursor/boundary.
  /// [start] is the exclusive upper line offset used by legacy syslog pages.
  Future<PagedResult<NodeLogEntry>> getNodeSyslog(
    String node, {
    int? start,
    String? beforeCursor,
    int limit = 30,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    if (start != null && beforeCursor != null) {
      throw ArgumentError('Use a cursor or a line boundary, not both');
    }
    if (start != null) {
      if (start <= 0) {
        return const PagedResult<NodeLogEntry>(items: [], hasMore: false);
      }
      final pageSize = limit.clamp(1, start);
      return _getNodeSyslogPage(node, start: start - pageSize, limit: pageSize);
    }

    try {
      return await _getNodeJournalPage(
        node,
        beforeCursor: beforeCursor,
        limit: limit,
      );
    } on ProxmoxApiException catch (error) {
      final status = error.values['statusCode'];
      // Older PVE versions may not expose journal. Never mask permission,
      // connection or pagination failures by restarting with another source.
      if (beforeCursor != null ||
          error.code != ProxmoxErrorCode.requestFailed ||
          (status != HttpStatus.notFound &&
              status != HttpStatus.notImplemented)) {
        rethrow;
      }
      return _getLatestNodeSyslog(node, limit: limit);
    }
  }

  Future<PagedResult<NodeLogEntry>> _getNodeJournalPage(
    String node, {
    String? beforeCursor,
    required int limit,
  }) async {
    // Unlike syslog, journal seeks directly to the tail/cursor without
    // counting all historical entries for every page.
    final response = await _request(
      'GET',
      '/nodes/$node/journal',
      queryParameters: {
        'lastentries': '$limit',
        'endcursor': ?beforeCursor,
      },
    );
    // Streamed journal failures can still carry HTTP 200.
    if (response['success'] == 0 || response['success'] == false) {
      throw ProxmoxApiException(
        ProxmoxErrorCode.requestFailed,
        message: response['error']?.toString(),
      );
    }
    final data = response['data'];
    if (data is! List || data.any((line) => line is! String)) {
      throw const ProxmoxApiException(ProxmoxErrorCode.apiFormatInvalid);
    }
    if (data.isEmpty) {
      return const PagedResult<NodeLogEntry>(items: [], hasMore: false);
    }
    if (data.length < 2) {
      throw const ProxmoxApiException(ProxmoxErrorCode.apiFormatInvalid);
    }

    // The first/last strings are opaque cursors; the middle is chronological
    // rendered log text, matching Proxmox's JournalView wire format.
    final oldestCursor = data.first as String;
    final lines = data.sublist(1, data.length - 1).cast<String>();
    final items = <NodeLogEntry>[
      for (var index = lines.length - 1; index >= 0; index--)
        NodeLogEntry(lineNumber: index + 1, text: lines[index]),
    ];
    final hasMore =
        items.length >= limit &&
        oldestCursor.isNotEmpty &&
        oldestCursor != beforeCursor;
    return PagedResult<NodeLogEntry>(
      items: items,
      hasMore: hasMore,
      nextCursor: hasMore ? oldestCursor : null,
    );
  }

  Future<PagedResult<NodeLogEntry>> _getLatestNodeSyslog(
    String node, {
    required int limit,
  }) async {
    final response = await _getWithParameterFallback(
      '/nodes/$node/syslog',
      queryParameters: {'start': '0', 'limit': '1'},
    );
    final data = response.body['data'];

    if (data is! List) {
      return const PagedResult<NodeLogEntry>(
        items: <NodeLogEntry>[],
        hasMore: false,
      );
    }

    final total = _intValue(response.body['total']);
    if (response.usedFallback || total <= 0) {
      final items =
          data
              .whereType<Map<String, dynamic>>()
              .map(NodeLogEntry.fromJson)
              .toList()
            ..sort((a, b) => b.lineNumber.compareTo(a.lineNumber));
      return PagedResult<NodeLogEntry>(
        items: items.take(limit).toList(),
        hasMore: false,
      );
    }

    final start = total > limit ? total - limit : 0;
    return _getNodeSyslogPage(node, start: start, limit: limit);
  }

  Future<PagedResult<NodeLogEntry>> _getNodeSyslogPage(
    String node, {
    required int start,
    required int limit,
  }) async {
    final response = await _getWithParameterFallback(
      '/nodes/$node/syslog',
      queryParameters: {'start': '$start', 'limit': '$limit'},
    );
    final data = response.body['data'];

    if (data is! List) {
      return const PagedResult<NodeLogEntry>(
        items: <NodeLogEntry>[],
        hasMore: false,
      );
    }

    final items =
        data
            .whereType<Map<String, dynamic>>()
            .map(NodeLogEntry.fromJson)
            .toList()
          ..sort((a, b) => b.lineNumber.compareTo(a.lineNumber));
    final visibleItems = response.usedFallback
        ? items.take(limit).toList()
        : items;

    return PagedResult<NodeLogEntry>(
      items: visibleItems,
      hasMore: !response.usedFallback && start > 0 && visibleItems.isNotEmpty,
      nextStart: !response.usedFallback && start > 0 && visibleItems.isNotEmpty
          ? start
          : null,
    );
  }

  Future<NodeTerminalSession> createNodeTerminalSession(String node) async {
    return _createTerminalSession(nodeTerminalApiPath(node));
  }

  Future<NodeTerminalSession> createGuestTerminalSession(
    PveResource guest,
  ) async {
    return _createTerminalSession(guestTerminalApiPath(guest));
  }

  String nodeTerminalApiPath(String node) {
    return '/nodes/$node';
  }

  String guestTerminalApiPath(PveResource guest) {
    if (!guest.isGuest || guest.type != 'lxc') {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestActionOnly);
    }

    return '/nodes/${guest.node}/lxc/${guest.vmid}';
  }

  Future<ProxmoxTerminalConnection> connectTerminalWebSocket({
    required String apiPath,
    required NodeTerminalSession session,
  }) async {
    final client = _createHttpClient();
    try {
      final socket = await WebSocket.connect(
        _terminalWebSocketUri(apiPath, session).toString(),
        protocols: const <String>['binary'],
        headers: _authenticatedSocketHeaders,
        customClient: client,
      ).timeout(_requestTimeout);

      return ProxmoxTerminalConnection(socket, client);
    } on Object {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> executeNodePowerAction(
    String node,
    NodePowerAction action,
  ) async {
    await _request(
      'POST',
      '/nodes/$node/status',
      body: {'command': action.command},
    );
  }

  Future<void> executeGuestAction(PveResource guest, GuestAction action) async {
    if (!guest.isGuest) {
      throw const ProxmoxApiException(ProxmoxErrorCode.guestActionOnly);
    }

    final path = switch (guest.type) {
      'qemu' => '/nodes/${guest.node}/qemu/${guest.vmid}/status/${action.api}',
      'lxc' => '/nodes/${guest.node}/lxc/${guest.vmid}/status/${action.api}',
      _ => throw const ProxmoxApiException(
        ProxmoxErrorCode.unsupportedResourceType,
      ),
    };

    await _request('POST', path);
  }

  String _guestApiPath(PveResource guest) {
    return switch (guest.type) {
      'qemu' => 'qemu',
      'lxc' => 'lxc',
      _ => throw const ProxmoxApiException(
        ProxmoxErrorCode.unsupportedResourceType,
      ),
    };
  }

  Future<_ApiResponse> _getWithParameterFallback(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    try {
      final body = await _request(
        'GET',
        path,
        queryParameters: queryParameters,
      );
      return _ApiResponse(body: body, usedFallback: false);
    } on ProxmoxApiException catch (error) {
      if (queryParameters == null || !_isParameterVerificationFailure(error)) {
        rethrow;
      }
      final body = await _request('GET', path);
      return _ApiResponse(body: body, usedFallback: true);
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _clearSession();
    _nodeThermalStateCache.clear();
    _guestDiskUsageCache.clear();
    _cacheClock.stop();
    _httpClient.close(force: true);
  }

  void _clearSession() {
    _sessionGeneration++;
    _ticket = null;
    _csrfToken = null;
    _apiTokenAuthenticated = false;
  }

  Future<NodeTerminalSession> _createTerminalSession(String apiPath) async {
    final response = await _request('POST', '$apiPath/termproxy');
    final data = response['data'];

    if (data is! Map<String, dynamic>) {
      throw const ProxmoxApiException(ProxmoxErrorCode.terminalSessionInvalid);
    }

    return NodeTerminalSession.fromJson(data);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? body,
    Map<String, String>? queryParameters,
    bool needsAuth = true,
    String? authTicket,
    String? csrfToken,
  }) async {
    if (_closed ||
        (needsAuth && !usesApiToken && authTicket == null && _ticket == null)) {
      throw const ProxmoxApiException(ProxmoxErrorCode.sessionExpired);
    }
    final sessionGeneration = _sessionGeneration;
    final usesSession = needsAuth && authTicket == null && hasActiveSession;
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
    };

    if (needsAuth) {
      if (authTicket != null) {
        headers[HttpHeaders.cookieHeader] = 'PVEAuthCookie=$authTicket';
        if (method != 'GET' && csrfToken != null) {
          headers['CSRFPreventionToken'] = csrfToken;
        }
      } else if (usesApiToken) {
        headers[HttpHeaders.authorizationHeader] = _apiTokenAuthorizationValue;
      } else {
        final ticket = _ticket;
        if (ticket == null) {
          throw const ProxmoxApiException(ProxmoxErrorCode.sessionExpired);
        }
        headers[HttpHeaders.cookieHeader] = 'PVEAuthCookie=$ticket';
        final token = csrfToken ?? _csrfToken;
        if (method != 'GET' && token != null) {
          headers['CSRFPreventionToken'] = token;
        }
      }
    }

    final uri = _apiUri(path, queryParameters: queryParameters);
    var abandoned = false;
    final opening = _httpClient.openUrl(method, uri).then((request) {
      if (abandoned) {
        // A Future timeout does not cancel the underlying connection attempt.
        request.done.ignore();
        request.abort();
      }
      return request;
    });
    final request = await opening.timeout(
      _requestTimeout,
      onTimeout: () {
        abandoned = true;
        throw TimeoutException('Proxmox connection timed out.');
      },
    );
    request.followRedirects = false;
    headers.forEach(request.headers.set);

    if (body != null) {
      final payload = Uri(queryParameters: body).query;
      final payloadBytes = utf8.encode(payload);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.contentLength = payloadBytes.length;
      request.add(payloadBytes);
    } else if (method != 'GET') {
      request.contentLength = 0;
    }

    final response = await request.close().timeout(
      _requestTimeout,
      onTimeout: () {
        final error = TimeoutException('Proxmox request timed out.');
        request.abort(error);
        throw error;
      },
    );
    if (response.statusCode == HttpStatus.unauthorized && usesSession) {
      if (_sessionGeneration == sessionGeneration) {
        _clearSession();
      }
      await response.listen(null).cancel();
      throw const ProxmoxApiException(ProxmoxErrorCode.sessionExpired);
    }

    final content = await response
        .transform(utf8.decoder)
        .timeout(_requestTimeout)
        .join();

    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      throw ProxmoxApiException(
        ProxmoxErrorCode.redirectResponse,
        values: {
          'statusCode': response.statusCode,
          'location': location == null ? '' : ' -> $location',
        },
      );
    }

    final Object decoded;
    try {
      decoded = content.isEmpty ? <String, dynamic>{} : jsonDecode(content);
    } on FormatException {
      throw nonJsonResponseException(uri, response, content);
    }

    if (decoded is! Map<String, dynamic>) {
      throw ProxmoxApiException(
        ProxmoxErrorCode.apiFormatInvalid,
        values: {'statusCode': response.statusCode},
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message']?.toString();
      throw ProxmoxApiException(
        ProxmoxErrorCode.requestFailed,
        message: message == null || message.isEmpty ? null : message,
        values: {'statusCode': response.statusCode},
      );
    }

    return decoded;
  }

  Map<String, dynamic> _loginData(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw const ProxmoxApiException(ProxmoxErrorCode.loginResponseInvalid);
    }
    return data;
  }

  void _storeLoginData(Map<String, dynamic> data) {
    final ticket = data['ticket'];
    final csrfToken = data['CSRFPreventionToken'];
    if (ticket is! String ||
        ticket.isEmpty ||
        csrfToken is! String ||
        csrfToken.isEmpty) {
      throw const ProxmoxApiException(ProxmoxErrorCode.loginTicketMissing);
    }
    _ticket = ticket;
    _csrfToken = csrfToken;
    _sessionGeneration++;
  }

  Uri _apiUri(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(origin);
    final apiPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: [
        'api2',
        'json',
        ...apiPath.split('/').where((segment) => segment.isNotEmpty),
      ],
      queryParameters: queryParameters,
    );
  }

  Uri _consoleUri(String path, Map<String, String> queryParameters) {
    final base = Uri.parse(origin);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
      queryParameters: queryParameters,
    );
  }

  Uri _terminalWebSocketUri(String apiPath, NodeTerminalSession session) {
    final base = Uri.parse(origin);
    final normalizedPath = apiPath.startsWith('/')
        ? apiPath.substring(1)
        : apiPath;
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: [
        'api2',
        'json',
        ...normalizedPath.split('/').where((segment) => segment.isNotEmpty),
        'vncwebsocket',
      ],
      queryParameters: {'port': '${session.port}', 'vncticket': session.ticket},
    );
  }

  HttpClient _createHttpClient() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              ignoreCertificateErrors;
  }

  static int _typeRank(String type) {
    return switch (type) {
      'node' => 0,
      'qemu' => 1,
      'lxc' => 2,
      'storage' => 3,
      _ => 4,
    };
  }

  _GuestDiskUsage? _cachedGuestDiskUsage(PveResource guest) {
    final key = _guestDiskUsageCacheKey(guest);
    if (key == null) {
      return null;
    }
    final cached = _guestDiskUsageCache[key];
    return cached != null && _isFresh(cached) ? cached.value : null;
  }

  _CachedTelemetry<T> _cache<T>(T value) =>
      _CachedTelemetry(value, _cacheClock.elapsed + telemetryCacheDuration);

  bool _isFresh<T>(_CachedTelemetry<T> cached) =>
      !_closed && _cacheClock.elapsed < cached.expiresAt;

  static bool _shouldLoadGuestDiskUsage(PveResource guest) {
    return guest.type == 'qemu' &&
        guest.vmid != null &&
        guest.status == 'running';
  }

  static String? _guestDiskUsageCacheKey(PveResource guest) {
    final vmid = guest.vmid;
    if (guest.type != 'qemu' || vmid == null) {
      return null;
    }
    return '${guest.node}/$vmid';
  }

  static _GuestDiskUsage? _parseGuestAgentDiskUsage(Object? value) {
    final entries = _guestAgentFileSystems(value);
    if (entries.isEmpty) {
      return null;
    }

    var used = 0;
    var total = 0;
    final seenMounts = <String>{};

    for (final entry in entries) {
      if (!_isRealGuestFileSystem(entry)) {
        continue;
      }

      final entryTotal = _intValue(
        entry['total-bytes'] ?? entry['total_bytes'] ?? entry['total'],
      );
      final entryUsed = _intValue(
        entry['used-bytes'] ?? entry['used_bytes'] ?? entry['used'],
      );
      if (entryTotal <= 0 || entryUsed < 0) {
        continue;
      }

      final mountKey = _guestFileSystemMountKey(entry);
      if (mountKey != null && !seenMounts.add(mountKey)) {
        continue;
      }

      used += entryUsed > entryTotal ? entryTotal : entryUsed;
      total += entryTotal;
    }

    if (total <= 0) {
      return null;
    }
    return _GuestDiskUsage(used: used, total: total);
  }

  static List<Map<String, dynamic>> _guestAgentFileSystems(Object? value) {
    final rawEntries = switch (value) {
      {'result': final Object? result} => result,
      {'data': final Object? data} => data,
      _ => value,
    };
    if (rawEntries is! Iterable) {
      return const <Map<String, dynamic>>[];
    }
    return rawEntries.whereType<Map<String, dynamic>>().toList();
  }

  static bool _isRealGuestFileSystem(Map<String, dynamic> entry) {
    final type = entry['type']?.toString().trim().toLowerCase();
    const pseudoTypes = <String>{
      'autofs',
      'bpf',
      'cgroup',
      'cgroup2',
      'configfs',
      'debugfs',
      'devpts',
      'devtmpfs',
      'efivarfs',
      'fusectl',
      'hugetlbfs',
      'mqueue',
      'nsfs',
      'proc',
      'pstore',
      'ramfs',
      'securityfs',
      'squashfs',
      'sysfs',
      'tmpfs',
      'tracefs',
    };
    if (type == null || type.isEmpty) {
      return true;
    }
    return !pseudoTypes.contains(type);
  }

  static String? _guestFileSystemMountKey(Map<String, dynamic> entry) {
    final mountpoint = entry['mountpoint']?.toString().trim();
    if (mountpoint != null && mountpoint.isNotEmpty) {
      return mountpoint.toLowerCase();
    }
    final name = entry['name']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      return name.toLowerCase();
    }
    return null;
  }

  static bool _isParameterVerificationFailure(ProxmoxApiException error) {
    if (error.code != ProxmoxErrorCode.requestFailed) {
      return false;
    }
    return error.message?.toLowerCase().contains(
          'parameter verification failed',
        ) ??
        false;
  }

  static int _intValue(Object? value) {
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final normalized = value?.toString().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  static bool _isTicketChallenge(Object? value) {
    return value?.toString().contains(':!tfa!') ?? false;
  }

  static String _diskDevicePath(Map<String, dynamic> disk) {
    return disk['devpath']?.toString().trim() ?? '';
  }

  static void _writePveDiskSmartOutput(
    StringBuffer output,
    _PveDiskSmartResult result,
  ) {
    final device = _diskDevicePath(result.disk);
    if (device.isEmpty) {
      return;
    }

    final diskType = result.disk['type']?.toString().toLowerCase() ?? '';
    output.writeln(
      diskType == 'nvme' ? 'smartctl $device -d nvme' : 'smartctl $device',
    );
    final model = _normalizePveDiskModel(result.disk['model']);
    if (model.isNotEmpty) {
      output.writeln(
        diskType == 'nvme' ? 'Model Number: $model' : 'Device Model: $model',
      );
    }

    final data = result.response?['data'];
    if (data is! Map<String, dynamic>) {
      return;
    }
    final temperature = _pveSmartTemperature(data);
    if (temperature != null) {
      output.writeln('Current Drive Temperature: $temperature C');
    }
  }

  static String _normalizePveDiskModel(Object? value) {
    return value
            ?.toString()
            .trim()
            .replaceAll(RegExp(r'^_+|_+$'), '')
            .replaceAll('_', ' ') ??
        '';
  }

  static num? _pveSmartTemperature(Map<String, dynamic> data) {
    final directTemperature = data['temperature'];
    if (directTemperature is num) {
      return directTemperature;
    }
    final parsedDirectTemperature = num.tryParse(
      directTemperature?.toString() ?? '',
    );
    if (parsedDirectTemperature != null) {
      return parsedDirectTemperature;
    }

    final text = data['text']?.toString() ?? '';
    final textTemperature = RegExp(
      r'^Temperature:\s*([-+]?\d+(?:\.\d+)?)\s*(?:C|Celsius)\b',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    if (textTemperature != null) {
      return num.tryParse(textTemperature.group(1)!);
    }

    final attributes = data['attributes'];
    if (attributes is! List) {
      return null;
    }
    Map<String, dynamic>? temperatureAttribute;
    for (final attribute in attributes.whereType<Map<String, dynamic>>()) {
      final id = attribute['id']?.toString();
      final name = attribute['name']?.toString().toLowerCase() ?? '';
      if (id == '194' || name == 'temperature_celsius') {
        temperatureAttribute = attribute;
        break;
      }
      if (temperatureAttribute == null &&
          name.contains('temperature') &&
          !name.contains('throttle')) {
        temperatureAttribute = attribute;
      }
    }
    if (temperatureAttribute == null) {
      return null;
    }

    final raw = temperatureAttribute['raw']?.toString() ?? '';
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    if (match != null) {
      return num.tryParse(match.group(0)!);
    }
    return null;
  }
}

class _PveDiskSmartResult {
  const _PveDiskSmartResult({required this.disk, this.response});

  final Map<String, dynamic> disk;
  final Map<String, dynamic>? response;
}

class _ApiResponse {
  const _ApiResponse({required this.body, required this.usedFallback});

  final Map<String, dynamic> body;
  final bool usedFallback;
}

class _GuestDiskUsage {
  const _GuestDiskUsage({required this.used, required this.total});

  final int used;
  final int total;
}

class _CachedTelemetry<T> {
  const _CachedTelemetry(this.value, this.expiresAt);

  final T value;
  final Duration expiresAt;
}

class ProxmoxTerminalConnection {
  ProxmoxTerminalConnection(this.socket, this._httpClient);

  final WebSocket socket;
  final HttpClient _httpClient;

  Future<void> close([int? code, String? reason]) async {
    try {
      await socket.close(code, reason);
    } finally {
      _httpClient.close(force: true);
    }
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}
