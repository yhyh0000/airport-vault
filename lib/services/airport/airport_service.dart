import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/http.dart';
import 'package:fl_clash/common/string.dart';
import 'package:flutter/foundation.dart';

import 'airport_models.dart';

class AirportAuthRequired implements Exception {
  const AirportAuthRequired(this.message);

  final String message;

  @override
  String toString() => message;
}

class AirportRequestFailed implements Exception {
  const AirportRequestFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

class AirportEntryProbe {
  const AirportEntryProbe({
    required this.baseUrl,
    required this.elapsed,
  });

  final String baseUrl;
  final Duration elapsed;
}

class AirportGiftCardResult {
  const AirportGiftCardResult({
    required this.type,
    required this.value,
    required this.message,
  });

  final int? type;
  final num? value;
  final String message;
}

/// Web-compatible adapters for the two initial airports.
///
/// iKun currently exposes an SSPanel-style server-rendered page and
/// `/user/checkin`. Pokemon uses the common V2Board/XBoard API shape. We keep
/// parsing tolerant because both sites change domains and theme markup often.
class AirportService {
  AirportService() {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = FlClashHttpOverrides.handleFindProxy;
        return client;
      },
    );
  }

  final Dio _dio = Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
      headers: const {
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            'Chrome/128.0.0.0 Mobile Safari/537.36 AirportVault/0.1',
      },
    ),
  );

  /// Probes every configured entry in parallel and returns the fastest entry
  /// that looks like the real airport application.  A DNS hit alone is not
  /// enough: maintenance pages, anti-bot guards and navigation-only domains
  /// are rejected before the result is shown to the login WebView.
  Future<AirportEntryProbe?> findBestEntry(
    AirportSiteDefinition site, {
    String? preferredBaseUrl,
  }) async {
    final candidates = <String>[
      if (preferredBaseUrl != null && preferredBaseUrl.trim().isNotEmpty)
        preferredBaseUrl,
      ...site.baseUrls,
    ].map(_normalizeBaseUrl).whereType<String>().toSet().toList();
    if (candidates.isEmpty) return null;

    final probes = await Future.wait(
      candidates.map((baseUrl) => _probeEntry(site, baseUrl)),
    );
    final valid = probes.whereType<AirportEntryProbe>().toList()
      ..sort((a, b) => a.elapsed.compareTo(b.elapsed));
    return valid.isEmpty ? null : valid.first;
  }

  Future<AirportSnapshot> sync(AirportSession session) async {
    return switch (session.kind) {
      AirportKind.ikun => _syncIkun(session),
      AirportKind.pokemon => _syncPokemon(session),
    };
  }

  Future<AirportSnapshot> checkIn(AirportSession session) async {
    final response = session.kind == AirportKind.ikun
        ? await _request(
            session,
            '/user/checkin',
            method: 'POST',
            headers: const {
              'Accept': 'application/json, text/javascript, */*; q=0.01',
              'X-Requested-With': 'XMLHttpRequest',
            },
          )
        : await _pokemonCheckin(session);

    _throwIfAuth(response);
    final body = session.kind == AirportKind.pokemon
        ? _pokemonJsonMap(response.data)
        : _jsonMap(response.data);
    final message = _message(body) ?? _plainMessage(response.data);
    final already = _containsCheckinMessage(message);
    final success = already ||
        body?['ret']?.toString() == '1' ||
        body?['success'] == true ||
        body?['status']?.toString() == 'success';
    if (!success) {
      throw AirportRequestFailed(message ?? '签到接口返回了未知结果');
    }
    final current = await sync(session);
    return current.copyWith(
      checkinDone: true,
      message: message ?? (already ? '今天已经签到' : '签到成功'),
      fetchedAt: DateTime.now(),
    );
  }

  /// Redeems the monthly Pokemon gift card.  The web client calls this a
  /// gift card even though the code is used to grant the free 8.8 package.
  /// This method never guesses a fallback endpoint: it follows the public
  /// frontend contract and refreshes the account separately in the notifier.
  Future<AirportGiftCardResult> redeemGiftCard(
    AirportSession session,
    String code,
  ) async {
    if (session.kind != AirportKind.pokemon) {
      throw const AirportRequestFailed('只有宝可梦机场支持礼品卡兑换');
    }
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      throw const AirportRequestFailed('请输入兑换码');
    }
    final response = await _request(
      session,
      '/user/redeemgiftcard',
      baseUrl: _pokemonApiBaseUrl(session),
      method: 'POST',
      data: FormData.fromMap({'giftcard': normalizedCode}),
    );
    _throwIfAuth(response);
    final json = _pokemonJsonMap(response.data);
    if (json == null) {
      throw const AirportRequestFailed('兑换接口返回了无法识别的结果');
    }
    final type = _numberOrNull(json['type']);
    final value = _numOrNull(json['value']);
    final success = json['data'] == true && type != null && type >= 1 && type <= 5;
    if (!success) {
      throw AirportRequestFailed(_message(json) ?? '兑换码无效或本月已领取');
    }
    return AirportGiftCardResult(
      type: type,
      value: value,
      message: _giftCardSuccessMessage(type, value),
    );
  }

  Future<AirportSnapshot> _syncIkun(AirportSession session) async {
    final response = await _request(session, '/user');
    _throwIfAuth(response);
    final html = _unwrapHtml(response.data?.toString() ?? '');
    if (_looksLikeLoginPage(html, response.realUri.toString())) {
      throw const AirportAuthRequired('iKun 登录状态已失效，请重新绑定账户');
    }
    // SSPanel themes expose the dashboard at /user and profile details at
    // /user/profile.  Read both because the current iKun theme puts traffic
    // on the dashboard but the account label/subscription controls can be on
    // the profile page.
    var extraHtml = '';
    var profileUserInfo = '';
    try {
      final profile = await _request(session, '/user/profile');
      if ((profile.statusCode ?? 500) < 400) {
        final candidate = _unwrapHtml(profile.data?.toString() ?? '');
        if (!_looksLikeLoginPage(candidate, profile.realUri.toString())) {
          extraHtml = candidate;
          profileUserInfo = profile.headers.value('subscription-userinfo') ?? '';
        }
      }
    } on AirportRequestFailed {
      // Older themes do not expose /user/profile.
    }
    var subscribeLogHtml = '';
    try {
      final subscribeLog = await _request(session, '/user/subscribe_log');
      if ((subscribeLog.statusCode ?? 500) < 400) {
        final candidate = _unwrapHtml(subscribeLog.data?.toString() ?? '');
        if (!_looksLikeLoginPage(candidate, subscribeLog.realUri.toString())) {
          subscribeLogHtml = candidate;
        }
      }
    } on AirportRequestFailed {
      // Subscription history is optional on older iKun themes.
    }
    final combined = '$html\n$extraHtml\n$subscribeLogHtml';
    final userInfo = response.headers.value('subscription-userinfo');
    final metadata = '$combined\n${userInfo ?? ''}\n$profileUserInfo';
    final traffic = _parseTraffic(metadata);
    return AirportSnapshot(
      kind: session.kind,
      baseUrl: session.baseUrl,
      accountLabel: _firstMatch(combined, [
        RegExp(r'(?:邮箱|email)[^<:：]{0,12}[:：]?\s*([^<\s]+@[^<\s]+)', caseSensitive: false),
        RegExp(
          r'''class=["'][^"']*user-name[^"']*["'][^>]*>\s*([^<]+)''',
          caseSensitive: false,
        ),
      ]),
      upload: traffic.upload,
      download: traffic.download,
      total: traffic.total,
      expireAt: _parseDate(metadata),
      subscriptionUrl: _findSubscriptionUrl(combined, session.baseUrl),
      checkinDone: _containsCheckinMessage(_stripHtml(combined)),
      message: _firstMatch(combined, [
        RegExp(r'(?:签到|checkin)[^<]{0,100}', caseSensitive: false),
      ]),
      fetchedAt: DateTime.now(),
    );
  }

  Future<AirportSnapshot> _syncPokemon(AirportSession session) async {
    _logPokemonSession(session);
    Response<dynamic>? infoResponse;
    for (final apiBase in _pokemonApiBaseUrls(session)) {
      final response = await _request(
        session,
        '/user/info',
        baseUrl: apiBase,
      );
      _logPokemonResponse('user/info', response);
      if (response.statusCode == 401 || response.statusCode == 419) {
        _throwIfAuth(response);
      }
      if ((response.statusCode ?? 500) < 400) {
        infoResponse = response;
        break;
      }
    }
    if (infoResponse == null) {
      final htmlResponse = await _request(session, '/');
      _throwIfAuth(htmlResponse);
      return _syncHtmlFallback(session, htmlResponse.data?.toString() ?? '');
    }
    _throwIfAuth(infoResponse);
    final info = _pokemonJsonMap(infoResponse.data);
    if (info == null) {
      final htmlResponse = await _request(session, '/');
      _throwIfAuth(htmlResponse);
      return _syncHtmlFallback(session, htmlResponse.data?.toString() ?? '');
    }
    final data = _asMap(info['data']) ?? info;
    final traffic = _parseTrafficMap(data);
    final subscribeUrl = await _getPokemonSubscribeUrl(session);
    return AirportSnapshot(
      kind: session.kind,
      baseUrl: session.baseUrl,
      accountLabel: _stringValue(data, const ['email', 'username', 'name']),
      upload: traffic.upload,
      download: traffic.download,
      total: traffic.total,
      expireAt: _parseEpoch(_numberValue(data, const ['expired_at', 'expire_at', 'expire'])),
      subscriptionUrl: subscribeUrl,
      fetchedAt: DateTime.now(),
    );
  }

  Future<AirportSnapshot> _syncHtmlFallback(
    AirportSession session,
    String html,
  ) async {
    html = _unwrapHtml(html);
    if (_looksLikeLoginPage(html, session.baseUrl)) {
      throw const AirportAuthRequired('宝可梦机场登录状态已失效，请重新绑定账户');
    }
    final traffic = _parseTraffic(html);
    return AirportSnapshot(
      kind: session.kind,
      baseUrl: session.baseUrl,
      accountLabel: _firstMatch(html, [
        RegExp(
          r'(?:邮箱|email)[^<:：]{0,12}[:：]?\s*([^<\s]+@[^<\s]+)',
          caseSensitive: false,
        ),
        RegExp(
          r'(?:用户名|username)[^<:：]{0,12}[:：]?\s*([^<\s]+)',
          caseSensitive: false,
        ),
      ]),
      upload: traffic.upload,
      download: traffic.download,
      total: traffic.total,
      expireAt: _parseDate(html),
      subscriptionUrl: _findSubscriptionUrl(html, session.baseUrl),
      fetchedAt: DateTime.now(),
    );
  }

  Future<Response<dynamic>> _pokemonCheckin(AirportSession session) async {
    for (final apiBase in _pokemonApiBaseUrls(session)) {
      final api = await _request(
        session,
        '/user/checkin',
        baseUrl: apiBase,
        method: 'POST',
        headers: const {'X-Requested-With': 'XMLHttpRequest'},
      );
      if ((api.statusCode ?? 500) < 400) return api;
      if (api.statusCode == 401 || api.statusCode == 419) return api;
    }
    return _request(
      session,
      '/user/checkin',
      method: 'POST',
      headers: const {'X-Requested-With': 'XMLHttpRequest'},
    );
  }

  Future<String?> _getPokemonSubscribeUrl(AirportSession session) async {
    for (final apiBase in _pokemonApiBaseUrls(session)) {
      late final Response<dynamic> response;
      try {
        response = await _request(
          session,
          '/user/getSubscribe',
          baseUrl: apiBase,
        );
      } on AirportRequestFailed {
        continue;
      }
      _logPokemonResponse('user/getSubscribe', response);
      if (response.statusCode == 404 || response.statusCode == 405) continue;
      if (response.statusCode == 401 || response.statusCode == 403) {
        // A theme can expose account info on one host and subscription data on
        // the other. Try the next configured API host before declaring the
        // session expired.
        continue;
      }
      _throwIfAuth(response);
      final json = _pokemonJsonMap(response.data);
      if (json == null) continue;
      final direct = json['data']?.toString().trim();
      if (direct != null && direct.isNotEmpty && direct != 'null') {
        // XBoard themes may return the source as a relative path or with
        // JavaScript escaping, not only as an absolute URL.
        final normalized = normalizeProfileSourceUrl(
          direct,
          baseUrl: session.baseUrl,
        );
        if (normalized != null) return normalized;
      }
      final data = _asMap(json['data']) ?? json;
      final value = _stringValue(
        data,
        const ['subscribe_url', 'subscribeUrl', 'subscription_url', 'url'],
      );
      final normalized = value == null
          ? null
          : _absoluteUrl(value, session.baseUrl);
      if (normalized != null) return normalized;
    }

    // Some XBoard builds already place subscribe_url in localStorage after
    // login. Use it as a local fallback when getSubscribe is protected by a
    // theme-specific gateway.
    return _pokemonStorageSubscribeUrl(session);
  }

  Future<Response<dynamic>> _request(
    AirportSession session,
    String path, {
    String? baseUrl,
    String method = 'GET',
    Map<String, String>? headers,
    Object? data,
  }) async {
    final base = (baseUrl ?? session.baseUrl).replaceFirst(RegExp(r'/+$'), '');
    final sessionBase = session.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final url = path.startsWith('http') ? path : '$base$path';
    final requestHeaders = <String, String>{
      'Referer': '$sessionBase/',
      'Origin': sessionBase,
      if (session.kind == AirportKind.pokemon) 'theme-ua': 'mala-pro',
      if (base == sessionBase && session.cookie.trim().isNotEmpty)
        'Cookie': session.cookie,
      if (session.authorizationHeader != null)
        'Authorization': session.authorizationHeader!,
      ...?headers,
    };
    try {
      return await _dio.request<dynamic>(
        url,
        // iKun's legacy check-in endpoint rejects an empty JSON body with 405.
        // Sending no body also keeps Dio from adding Content-Type.
        data: data,
        // Keep 4xx responses available to the airport adapter.  Pokemon has
        // several V2Board/XBoard deployments where an optional endpoint
        // answers 404/405 and the caller must fall back to HTML or another
        // host.  Dio's default validation throws before those branches can
        // inspect the status code.
        options: Options(
          method: method,
          headers: requestHeaders,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (error) {
      throw AirportRequestFailed(
        error.response?.statusMessage ?? error.message ?? '机场网页暂时无法访问',
      );
    }
  }

  void _logPokemonSession(AirportSession session) {
    if (session.kind != AirportKind.pokemon) return;
    final auth = session.authorizationHeader;
    final apiBase = session.apiBaseUrl;
    var storageKeys = <String>[];
    try {
      final decoded = jsonDecode(session.localStorageJson);
      if (decoded is Map) {
        storageKeys = decoded.keys.map((key) => key.toString()).toList()..sort();
      }
    } catch (_) {}
    debugPrint(
      '[AIRPORT][pokemon] session authPresent=${auth != null} '
      'authLength=${auth?.length ?? 0} cookiePresent=${session.cookie.trim().isNotEmpty} '
      'apiOverride=${apiBase != null} storageKeys=${storageKeys.join(",")}',
    );
  }

  void _logPokemonResponse(String label, Response<dynamic> response) {
    if (response.requestOptions.uri.host.isEmpty) return;
    final raw = response.data;
    final body = raw is String ? raw : '';
    final parsed = _pokemonJsonMap(raw);
    final topKeys = parsed?.keys.map((key) => key.toString()).toList()..sort();
    final data = parsed == null ? null : _asMap(parsed['data']);
    final dataKeys = data?.keys.map((key) => key.toString()).toList()..sort();
    debugPrint(
      '[AIRPORT][pokemon] $label status=${response.statusCode} '
      'host=${response.requestOptions.uri.host} path=${response.requestOptions.uri.path} '
      'bytes=${body.length} rawType=${raw.runtimeType} '
      'jsonKeys=${topKeys?.join(",") ?? "none"} '
      'dataKeys=${dataKeys?.join(",") ?? "none"}',
    );
  }

  Future<AirportEntryProbe?> _probeEntry(
    AirportSiteDefinition site,
    String baseUrl,
  ) async {
    final stopwatch = Stopwatch()..start();
    final path = site.kind == AirportKind.ikun ? site.loginPath : '/';
    try {
      final response = await _dio.get<dynamic>(
        '$baseUrl$path',
        options: Options(
          responseType: ResponseType.plain,
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 7),
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'Referer': '$baseUrl/',
            'Origin': baseUrl,
          },
        ),
      );
      final status = response.statusCode ?? 500;
      final body = _unwrapHtml(response.data?.toString() ?? '').toLowerCase();
      if (status >= 400 || body.trim().isEmpty ||
          !_looksLikeUsableEntry(site.kind, body)) {
        return null;
      }
      return AirportEntryProbe(
        baseUrl: baseUrl,
        elapsed: stopwatch.elapsed,
      );
    } catch (_) {
      return null;
    } finally {
      stopwatch.stop();
    }
  }

  bool _looksLikeUsableEntry(AirportKind kind, String body) {
    if (kind == AirportKind.ikun) {
      // A number of iKun domains are currently alive but only serve the
      // public "latest domains" landing page.  Treating any HTML response
      // as a valid entry makes the WebView open that page instead of the
      // actual auth screen.  Require both credential-field and password
      // markers so redirects/maintenance pages are rejected.
      final hasCredentialField =
          body.contains('name="email"') ||
          body.contains("name='email'") ||
          body.contains('type="email"') ||
          body.contains("type='email'") ||
          body.contains('邮箱') ||
          body.contains('email');
      final hasPasswordField =
          body.contains('name="passwd"') ||
          body.contains("name='passwd'") ||
          body.contains('name="password"') ||
          body.contains("name='password'") ||
          body.contains('type="password"') ||
          body.contains("type='password'") ||
          body.contains('密码') ||
          body.contains('password');
      return hasCredentialField && hasPasswordField;
    }
    // Pokemon is a hash-routed SPA, so the login route is not sent to the
    // server.  Accept the app shell, but reject plain navigation and guard
    // pages that would otherwise look reachable at the TCP level.
    return body.contains('id="app"') ||
        body.contains("id='app'") ||
        body.contains('#/login') ||
        body.contains('登录') ||
        body.contains('password');
  }

  String? _normalizeBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      return null;
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return 'https://${uri.host}$port$path';
  }

  void _throwIfAuth(Response<dynamic> response) {
    final url = response.realUri.toString();
    final body = response.data?.toString() ?? '';
    if (response.statusCode == 401 ||
        response.statusCode == 419 ||
        _looksLikeLoginPage(body, url)) {
      throw const AirportAuthRequired('登录状态已失效，请重新绑定账户');
    }
    if ((response.statusCode ?? 500) >= 400) {
      throw AirportRequestFailed('机场网页返回 HTTP ${response.statusCode}');
    }
  }

  bool _looksLikeLoginPage(String body, String url) {
    final lower = '$url\n${_unwrapHtml(body)}'.toLowerCase();
    return lower.contains('/auth/login') ||
        lower.contains('#/login') ||
        (lower.contains('登录') && lower.contains('密码') && !lower.contains('签到成功'));
  }

  String _unwrapHtml(String source) {
    var current = source;
    for (var i = 0; i < 2; i++) {
      final match = RegExp(
        r'''var\s+originBody\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(current);
      if (match == null) break;
      try {
        final decoded = utf8.decode(base64Decode(match.group(1)!));
        if (decoded == current) break;
        current = decoded;
      } catch (_) {
        break;
      }
    }
    return current;
  }

  Map<String, dynamic>? _jsonMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _pokemonJsonMap(Object? value) {
    final direct = _jsonMap(value);
    if (direct != null) return direct;
    if (value is! String || value.trim().isEmpty) return null;
    try {
      var decoded = utf8.decode(base64Decode(_padBase64(value.trim())));
      for (var i = 0; i < 10; i++) {
        decoded = _decodePokemonLayer(decoded);
      }
      final parsed = jsonDecode(decoded);
      return parsed is Map ? Map<String, dynamic>.from(parsed) : null;
    } catch (_) {
      return null;
    }
  }

  String _decodePokemonLayer(String input) {
    const encrypted =
        'nsz{gAWrkXlx08J6Eq:V4[deO1DQTCwm2oB3ty9jSYI]7RM5bHiUam,c}KuPGpNhZLvF';
    const plain =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,[]{}:';
    final buffer = StringBuffer();
    for (final character in input.split('')) {
      final index = encrypted.indexOf(character);
      buffer.write(index < 0 ? character : plain[index]);
    }
    return buffer.toString();
  }

  String _padBase64(String input) {
    final remainder = input.length % 4;
    return remainder == 0 ? input : '$input${'=' * (4 - remainder)}';
  }

  String _pokemonApiBaseUrl(AirportSession session) {
    final configured = session.apiBaseUrl;
    // Keep local loopback sessions usable in the service tests and local
    // development without allowing arbitrary insecure remote API hosts.
    final baseValue = configured ??
        (session.baseUrl.startsWith('http://127.0.0.1:')
            ? session.baseUrl
            : 'https://api123.136470.xyz');
    final base = baseValue
        .replaceFirst(RegExp(r'/+$'), '');
    return base.endsWith('/api/v1') ? base : '$base/api/v1';
  }

  String? _pokemonStorageSubscribeUrl(AirportSession session) {
    try {
      final decoded = jsonDecode(session.localStorageJson);
      final maps = <Map<String, dynamic>>[
        if (decoded is Map) Map<String, dynamic>.from(decoded),
        if (decoded is Map && decoded['user'] is Map)
          Map<String, dynamic>.from(decoded['user'] as Map),
        if (decoded is Map && decoded['data'] is Map)
          Map<String, dynamic>.from(decoded['data'] as Map),
      ];
      for (final map in maps) {
        final value = _stringValue(
          map,
          const ['subscribe_url', 'subscribeUrl', 'subscription_url'],
        );
        final normalized = value == null
            ? null
            : _absoluteUrl(value, session.baseUrl);
        if (normalized != null) return normalized;
      }
    } catch (_) {}
    return null;
  }

  List<String> _pokemonApiBaseUrls(AirportSession session) {
    final values = <String>[_pokemonApiBaseUrl(session)];
    // Some Pokemon themes serve the API from the web host, while other
    // themes publish a separate API host.  Try the web host after the public
    // API host so a 403 from one deployment does not invalidate the session.
    final webBase = session.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final webApi = webBase.endsWith('/api/v1')
        ? webBase
        : '$webBase/api/v1';
    if (!values.contains(webApi)) values.add(webApi);
    return values;
  }

  int? _numberOrNull(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  num? _numOrNull(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _giftCardSuccessMessage(int type, num? value) {
    return switch (type) {
      1 => '兑换成功，账户余额已增加 ${((value ?? 0) / 100).toStringAsFixed(2)}',
      2 => '兑换成功，订阅时长增加 ${value ?? 0} 天',
      3 => '兑换成功，套餐流量增加 ${value ?? 0} GB',
      4 => '兑换成功，流量已重置',
      5 => '兑换成功，订阅套餐增加 ${value ?? 0} 天',
      _ => '兑换成功',
    };
  }

  Map<String, dynamic>? _asMap(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String? _message(Map<String, dynamic>? json) {
    if (json == null) return null;
    for (final key in const ['msg', 'message', 'error', 'detail']) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final data = _asMap(json['data']);
    return _message(data);
  }

  String? _plainMessage(Object? body) {
    if (body is! String) return null;
    final text = _stripHtml(body).trim();
    if (text.isEmpty) return null;
    return text.substring(0, text.length > 160 ? 160 : text.length);
  }

  bool _containsCheckinMessage(String? message) {
    if (message == null) return false;
    return RegExp(r'已签到|已经签到|今日已签|checked.?in|already', caseSensitive: false).hasMatch(message);
  }

  ({int upload, int download, int total}) _parseTraffic(String source) {
    final text = _stripHtml(source);
    final upload = _bytesAfter(text, const ['upload', '上传']);
    var download = _bytesAfter(text, const ['download', '下载']);
    var total = _bytesAfter(text, const [
      'total',
      '总流量',
      '套餐流量',
      'transfer_enable',
    ]);

    // iKun's current SSPanel theme renders these as text rather than the
    // conventional upload/download/total labels.  Keep the values in the
    // existing snapshot shape so the dashboard can still show used/total.
    final today = _bytesAfter(text, const ['今日已用', 'today']);
    final remaining = _bytesAfter(text, const ['剩余流量', 'remaining']);
    if (download == 0 && today > 0) download = today;
    if (total == 0 && remaining > 0) total = today + remaining;
    return (
      upload: upload,
      download: download,
      total: total,
    );
  }

  ({int upload, int download, int total}) _parseTrafficMap(
    Map<String, dynamic> data,
  ) {
    return (
      upload: _numberValue(data, const ['u', 'upload', 'upload_bytes']),
      download: _numberValue(data, const ['d', 'download', 'download_bytes']),
      total: _numberValue(data, const ['transfer_enable', 'total', 'traffic']),
    );
  }

  int _bytesAfter(String text, List<String> labels) {
    for (final label in labels) {
      final match = RegExp(
        '${RegExp.escape(label)}[^0-9]{0,100}(\\d+(?:\\.\\d+)?)\\s*(TB|GB|MB|KB|B)?',
        caseSensitive: false,
      ).firstMatch(text);
      if (match == null) continue;
      final number = double.tryParse(match.group(1) ?? '');
      if (number == null) continue;
      return _toBytes(number, match.group(2));
    }
    return 0;
  }

  int _numberValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final raw = data[key];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (value != null) return value.round();
    }
    return 0;
  }

  String? _stringValue(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return null;
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }
    return null;
  }

  int _toBytes(double value, String? unit) {
    final multiplier = switch (unit?.toUpperCase()) {
      'TB' => 1024 * 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'MB' => 1024 * 1024,
      'KB' => 1024,
      _ => 1,
    };
    return (value * multiplier).round();
  }

  DateTime? _parseEpoch(int value) {
    if (value <= 0) return null;
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  DateTime? _parseDate(String source) {
    final hit = RegExp(
      r'(?:到期|有效期|有效至|expire|expired_at|expiry)[^0-9]{0,40}(\d{10,13}|20\d{2}[-/]\d{1,2}[-/]\d{1,2})',
      caseSensitive: false,
    ).firstMatch(source);
    if (hit == null) return null;
    final value = hit.group(1)!;
    final epoch = int.tryParse(value);
    if (epoch != null) return _parseEpoch(epoch);
    return DateTime.tryParse(value.replaceAll('/', '-'));
  }

  String? _firstMatch(String source, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      final value = match?.groupCount == 0 ? match?.group(0) : match?.group(1);
      if (value != null && value.trim().isNotEmpty) return _stripHtml(value).trim();
    }
    return null;
  }

  String? _findSubscriptionUrl(String html, String baseUrl) {
    // iKun's current page does not render the real source URL directly. It
    // stores a Base64 value on the client selector and keeps extra query
    // parameters in a sibling attribute. Decode this first so the later
    // loose HTML patterns cannot mistake /user/subscribe_log for a source.
    final encodedTags = RegExp(
      r'''<[^>]+data-clipboard-text-encoded\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    );
    for (final match in encodedTags.allMatches(html)) {
      final tag = match.group(0)!;
      final encoded = match.group(1);
      final decoded = encoded == null ? null : _decodeSubscriptionValue(encoded);
      if (decoded == null) continue;
      final extra = _readHtmlAttribute(tag, 'data-clipboard-text-extra');
      final candidate = _appendSubscriptionExtra(decoded, extra);
      final resolved = _subscriptionCandidate(candidate, baseUrl);
      if (resolved != null) return resolved;
    }

    // Current SSPanel themes sometimes put the real URL in an inline copy
    // handler instead of an href/data attribute.  Scan those raw values before
    // falling back to the older label-oriented patterns.
    final looseCandidates = [
      RegExp(
        r'''https?://[^"'<>\s]+/(?:link|sub)/[^"'<>\s]+''',
        caseSensitive: false,
      ),
      RegExp(
        r'''/(?:link|sub)/[^"'<>\s]+''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:copy|clipboard|订阅|subscription)[\s\S]{0,220}?((?:https?:)?//[^"'<>\s]+)''',
        caseSensitive: false,
      ),
    ];
    for (final pattern in looseCandidates) {
      for (final match in pattern.allMatches(html)) {
        final value = match.groupCount == 0 ? match.group(0) : match.group(1);
        final resolved = value == null
            ? null
            : _subscriptionCandidate(value, baseUrl);
        if (resolved != null) return resolved;
      }
    }
    final directAttributes = RegExp(
      r'''(?:href|data-url|data-clipboard-text|value)=['"]([^'"]*(?:subscribe|subscription|clash|sing-box|/link/|/sub/)[^'"]*)['"]''',
      caseSensitive: false,
    );
    for (final match in directAttributes.allMatches(html)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        final resolved = _subscriptionCandidate(value, baseUrl);
        if (resolved != null) return resolved;
      }
    }
    final patterns = [
      RegExp(
        r'''href=["']([^"']+)["'][^>]{0,240}>[\s\S]{0,240}?(?:订阅|subscription|clash|sing-box)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:data-clipboard-text|data-url|href|value)=["']([^"']*(?:/link/|/sub/)[^"']*)["']''',
        caseSensitive: false,
      ),
      RegExp(r'''(?:订阅地址|订阅链接|subscription)[^a-z0-9]{0,40}(https?://[^\s"'<>]+)''', caseSensitive: false),
      RegExp(
        r'''["'](?:subscribe_url|subscribeUrl|subscription_url)["']\s*:\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final value = match.groupCount == 0 ? match.group(0) : match.group(1);
        final resolved = value == null
            ? null
            : _subscriptionCandidate(value, baseUrl);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  String? _subscriptionCandidate(String value, String baseUrl) {
    final resolved = _absoluteUrl(value, baseUrl);
    if (resolved == null) return null;
    final uri = parseProfileSourceUri(resolved);
    if (uri == null) return null;
    final path = uri.path.toLowerCase();
    // /user/subscribe_log is a navigation page, not a Clash/XBoard source.
    if (path.contains('/subscribe_log') ||
        path == '/user/subscribe' ||
        path.endsWith('/user/subscribe/')) {
      return null;
    }
    final looksLikeSubscription = path.contains('/link/') ||
        path.contains('/sub/') ||
        path.contains('/subscribe') ||
        path.contains('/subscription') ||
        uri.queryParameters.keys.any(
          (key) => const ['token', 'key', 'sub', 'subscription'].contains(
            key.toLowerCase(),
          ),
        );
    return looksLikeSubscription ? resolved : null;
  }

  String? _absoluteUrl(String value, String baseUrl) {
    return normalizeProfileSourceUrl(value, baseUrl: baseUrl);
  }

  String? _readHtmlAttribute(String tag, String name) {
    final match = RegExp(
      '$name\\s*=\\s*[\'\"]([^\'\"]*)[\'\"]',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1)?.trim();
  }

  String? _decodeSubscriptionValue(String value) {
    final encoded = value.trim().replaceAll(' ', '+');
    if (encoded.isEmpty) return null;
    for (final decoder in [base64.decode, base64Url.decode]) {
      try {
        final decoded = utf8.decode(decoder(_padBase64(encoded))).trim();
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {}
    }
    return null;
  }

  String _appendSubscriptionExtra(String value, String? extra) {
    final suffix = extra?.trim().replaceAll('&amp;', '&');
    if (suffix == null || suffix.isEmpty || value.contains(suffix)) return value;
    if (suffix.startsWith('?')) {
      return value.contains('?')
          ? '$value&${suffix.substring(1)}'
          : '$value$suffix';
    }
    if (suffix.startsWith('&')) {
      return value.contains('?') ? '$value$suffix' : '$value?${suffix.substring(1)}';
    }
    return value.contains('?') ? '$value&$suffix' : '$value?$suffix';
  }

  String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
