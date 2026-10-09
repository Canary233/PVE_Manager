import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';

/// Keeps PVE credentials and certificate handling out of the embedded browser.
class ProxmoxConsoleProxy {
  ProxmoxConsoleProxy._(this._server, this._client)
    : authCookie = _randomToken(),
      authCookieName = 'PVEConsole_${_randomToken()}',
      _origin = Uri.parse(_client.origin) {
    _httpClient
      ..connectionTimeout = _timeout
      ..autoUncompress = false
      ..badCertificateCallback = (certificate, host, port) =>
          _client.ignoreCertificateErrors && host == _origin.host;
    _server.listen((request) {
      unawaited(_handleRequest(request));
    });
  }

  final HttpServer _server;
  final ProxmoxClient _client;
  final Uri _origin;
  final HttpClient _httpClient = HttpClient();
  final Set<WebSocket> _sockets = {};
  final String authCookie;
  final String authCookieName;
  bool _closed = false;

  static const _timeout = Duration(seconds: 15);
  static const _browserCompatibilityScript = '''
<script>
(() => {
  if (typeof window.VideoDecoder !== 'function') return;
  const decoder = window.VideoDecoder;
  const isConfigSupported = decoder.isConfigSupported.bind(decoder);
  decoder.isConfigSupported = (config) => {
    // WebView's H.264 probe can hang noVNC startup; use its other encodings.
    if (/^avc[13]\\./i.test(config.codec || '')) {
      return Promise.resolve({ supported: false, config });
    }
    return isConfigSupported(config);
  };
})();
</script>
''';
  static const _hopByHopHeaders = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };

  Uri get origin =>
      Uri(scheme: 'http', host: _server.address.address, port: _server.port);

  static Future<ProxmoxConsoleProxy> start(ProxmoxClient client) async {
    // Validate authentication before allocating a listener.
    client.consoleAuthenticationHeaders;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return ProxmoxConsoleProxy._(server, client);
  }

  Uri consoleUri(Uri uri) {
    if (uri.origin != _origin.origin) {
      throw ArgumentError.value(uri, 'uri', 'Not a console on this server');
    }
    return origin.resolveUri(
      Uri(
        path: uri.path,
        queryParameters: {
          ...uri.queryParameters,
          // PVE defaults noVNC to WSS, but only the loopback hop uses WS.
          if (uri.queryParameters['novnc'] == '1') 'encrypt': '0',
        },
      ),
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _httpClient.close(force: true);
    await Future.wait(_sockets.toList().map(_closeSocket));
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final requestOrigin = request.headers.value('origin');
      final authorized = request.cookies.any(
        (cookie) => cookie.name == authCookieName && cookie.value == authCookie,
      );
      if (_closed ||
          !authorized ||
          request.headers.value(HttpHeaders.hostHeader) != origin.authority ||
          (requestOrigin != null && requestOrigin != origin.origin)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      // Resolve paths only, never an absolute URL supplied by the browser.
      final upstreamUri = _origin.replace(
        path: request.uri.path,
        query: request.uri.hasQuery ? request.uri.query : null,
        fragment: null,
      );
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _forwardWebSocket(request, upstreamUri);
      } else {
        await _forwardHttp(request, upstreamUri);
      }
    } on Object catch (error, stackTrace) {
      if (!_closed) {
        if (kDebugMode) {
          debugPrintStack(
            label:
                'Console ${request.method} ${request.uri.path} failed '
                '(${error.runtimeType})',
            stackTrace: stackTrace,
          );
        }
        try {
          request.response.statusCode = HttpStatus.badGateway;
          request.response.write('Console upstream connection failed.');
          await request.response.close();
        } on Object {
          // The WebView may already have closed this request.
        }
      }
    }
  }

  Future<void> _forwardHttp(HttpRequest request, Uri uri) async {
    final upstream = await _httpClient
        .openUrl(request.method, uri)
        .timeout(_timeout);
    upstream.followRedirects = false;
    final consoleDocument =
        request.method == 'GET' &&
        uri.path == '/' &&
        uri.queryParameters['novnc'] == '1';
    final connectionHeaders = _connectionHeaders(request.headers);
    request.headers.forEach((name, values) {
      if (_hopByHopHeaders.contains(name) ||
          connectionHeaders.contains(name) ||
          name == HttpHeaders.hostHeader ||
          name == HttpHeaders.cookieHeader ||
          name == HttpHeaders.authorizationHeader ||
          name == 'csrfpreventiontoken') {
        return;
      }
      upstream.headers.set(name, values);
    });
    if (request.headers.value('origin') != null) {
      upstream.headers.set('origin', _origin.origin);
    }
    final referer = request.headers.value(HttpHeaders.refererHeader);
    if (referer != null) {
      final localReferer = Uri.tryParse(referer);
      if (localReferer != null && localReferer.origin == origin.origin) {
        upstream.headers.set(
          HttpHeaders.refererHeader,
          _origin.replace(path: localReferer.path, query: localReferer.query),
        );
      }
    }
    _client.consoleAuthenticationHeaders.forEach(upstream.headers.set);
    if (consoleDocument) {
      upstream.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    }
    await upstream.addStream(request).timeout(_timeout);
    final response = await upstream.close().timeout(_timeout);
    final location = response.headers.value(HttpHeaders.locationHeader);
    final target = location == null ? null : uri.resolve(location);
    if (target != null && target.origin != _origin.origin) {
      await response.drain<void>();
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    String? consoleHtml;
    if (consoleDocument &&
        response.statusCode == HttpStatus.ok &&
        response.headers.contentType?.mimeType == 'text/html') {
      Stream<List<int>> body = response;
      final encoding = response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (encoding == 'gzip') {
        body = body.transform(gzip.decoder);
      } else if (encoding == 'deflate') {
        body = body.transform(zlib.decoder);
      }
      final html = await utf8.decoder.bind(body).join().timeout(_timeout);
      consoleHtml = html.replaceFirstMapped(
        RegExp(r'<head\b[^>]*>', caseSensitive: false),
        (match) => '${match[0]}\n$_browserCompatibilityScript',
      );
    }
    request.response.statusCode = response.statusCode;
    final responseConnectionHeaders = _connectionHeaders(response.headers);
    response.headers.forEach((name, values) {
      if (!_hopByHopHeaders.contains(name) &&
          !responseConnectionHeaders.contains(name) &&
          name != HttpHeaders.setCookieHeader &&
          name != HttpHeaders.locationHeader &&
          !(consoleHtml != null &&
              {
                HttpHeaders.contentLengthHeader,
                HttpHeaders.contentEncodingHeader,
                HttpHeaders.etagHeader,
              }.contains(name))) {
        request.response.headers.set(name, values);
      }
    });
    if (target != null) {
      request.response.headers.set(
        HttpHeaders.locationHeader,
        consoleUri(target).toString(),
      );
    }
    if (consoleHtml != null) {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(consoleHtml);
    } else {
      await request.response.addStream(response);
    }
    await request.response.close();
  }

  Future<void> _forwardWebSocket(HttpRequest request, Uri uri) async {
    final protocols = request.headers
        .value('sec-websocket-protocol')
        ?.split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final upstream = await WebSocket.connect(
      uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString(),
      protocols: protocols,
      headers: {
        ..._client.consoleAuthenticationHeaders,
        'origin': _origin.origin,
      },
      customClient: _httpClient,
    ).timeout(_timeout);
    _sockets.add(upstream);
    WebSocket? downstream;
    final subscriptions = <StreamSubscription<dynamic>>[];
    try {
      if (_closed) {
        return;
      }
      downstream = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (offered) =>
            offered.contains(upstream.protocol) ? upstream.protocol : null,
      );
      _sockets.add(downstream);
      void pipe(WebSocket source, WebSocket target) {
        subscriptions.add(
          source.listen(
            (message) {
              if (target.readyState == WebSocket.open) {
                target.add(message);
              }
            },
            onDone: () => unawaited(_closeSocket(target)),
            onError: (Object error) => unawaited(_closeSocket(target)),
          ),
        );
      }

      pipe(upstream, downstream);
      pipe(downstream, upstream);
      await Future.wait([upstream.done, downstream.done]);
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      _sockets.remove(upstream);
      await _closeSocket(upstream);
      if (downstream != null) {
        _sockets.remove(downstream);
        await _closeSocket(downstream);
      }
    }
  }

  static Set<String> _connectionHeaders(HttpHeaders headers) =>
      (headers[HttpHeaders.connectionHeader] ?? const <String>[])
          .expand((value) => value.split(','))
          .map((value) => value.trim().toLowerCase())
          .toSet();

  static Future<void> _closeSocket(WebSocket socket) async {
    try {
      await socket.close(WebSocketStatus.goingAway).timeout(_timeout);
    } on Object {
      // Closing a console also closes any in-flight socket handshake.
    }
  }

  static String _randomToken() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
