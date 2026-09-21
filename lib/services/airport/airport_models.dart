import 'dart:convert';

enum AirportKind { ikun, pokemon }

extension AirportKindX on AirportKind {
  String get key => switch (this) {
        AirportKind.ikun => 'ikun',
        AirportKind.pokemon => 'pokemon',
      };

  String get label => switch (this) {
        AirportKind.ikun => 'iKun',
        AirportKind.pokemon => 'Pokemon',
      };
}

class AirportSiteDefinition {
  const AirportSiteDefinition({
    required this.kind,
    required this.title,
    required this.description,
    required this.defaultBaseUrl,
    required this.alternateBaseUrls,
    required this.loginPath,
  });

  final AirportKind kind;
  final String title;
  final String description;
  final String defaultBaseUrl;
  final List<String> alternateBaseUrls;
  final String loginPath;

  List<String> get baseUrls => [defaultBaseUrl, ...alternateBaseUrls];

  String loginUrl(String baseUrl) {
    final normalized = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$normalized$loginPath';
  }
}

/// These are only discovery defaults. Airport domains change frequently, so
/// the UI always allows users to switch to another official entry point.
const airportSiteDefinitions = <AirportSiteDefinition>[
  AirportSiteDefinition(
    kind: AirportKind.ikun,
    title: 'iKun机场',
    description: '绑定账户后自动同步流量、到期时间与每日签到',
    // The official status page currently lists ikuuu.top as the primary
    // domain and ikuuu.pw as the backup.  Keep the list ordered by that
    // published priority; findBestEntry still probes every candidate and
    // selects the fastest one that actually serves a login form.
    defaultBaseUrl: 'https://ikuuu.top',
    alternateBaseUrls: [
      'https://ikuuu.pw',
      'https://ikuuu.co',
      'https://ikuuu.ltd',
      'https://ikuuu.fyi',
      'https://ikuuu.win',
      'https://ikuuu.foo',
      'https://ikuuu.de',
    ],
    loginPath: '/auth/login',
  ),
  AirportSiteDefinition(
    kind: AirportKind.pokemon,
    title: '宝可梦机场',
    description: '绑定账户后同步 V2Board / XBoard 的账户、签到与订阅',
    defaultBaseUrl: 'https://web2.52pokemon.cc',
    alternateBaseUrls: [
      'https://love.52pokemon.cc',
      'https://web4.52pokemon.cc',
      'https://web1.52pokemon.cc',
      'https://web1.52pokemon66.cc',
      'https://web2.go52pokemon.com',
      'https://52pokemon.yunjnet.com',
      'https://web1.go52pokemon.com',
    ],
    loginPath: '/#/login',
  ),
];

AirportSiteDefinition airportSite(AirportKind kind) =>
    airportSiteDefinitions.firstWhere((site) => site.kind == kind);

class AirportSession {
  const AirportSession({
    required this.kind,
    required this.baseUrl,
    required this.cookie,
    this.localStorageJson = '{}',
    this.updatedAt,
  });

  final AirportKind kind;
  final String baseUrl;
  final String cookie;
  final String localStorageJson;
  final DateTime? updatedAt;

  AirportSession copyWith({
    String? baseUrl,
    String? cookie,
    String? localStorageJson,
    DateTime? updatedAt,
  }) {
    return AirportSession(
      kind: kind,
      baseUrl: baseUrl ?? this.baseUrl,
      cookie: cookie ?? this.cookie,
      localStorageJson: localStorageJson ?? this.localStorageJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String? get accessToken {
    try {
      final decoded = jsonDecode(localStorageJson);
      if (decoded is! Map) return null;
      for (final key in const [
        'token',
        'auth_token',
        'access_token',
        'accessToken',
      ]) {
        final value = decoded[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      final user = decoded['user'];
      if (user is Map) {
        final value = user['token']?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    } catch (_) {}
    return null;
  }

  /// Pokemon's web client stores the API credential as `auth_data`, while
  /// older airport pages store a bare token.  Keep the original value when it
  /// already contains the Bearer scheme so callers can send the same header
  /// as the official web client.
  String? get authorizationHeader {
    try {
      final decoded = jsonDecode(localStorageJson);
      if (decoded is Map) {
        final raw = decoded['auth_data']?.toString().trim();
        if (raw != null && raw.isNotEmpty) {
          return raw.toLowerCase().startsWith('bearer ')
              ? raw
              : 'Bearer $raw';
        }
      }
    } catch (_) {}
    final token = accessToken;
    return token == null ? null : 'Bearer $token';
  }

  /// The Pokemon web app allows an API host override in localStorage.  It is
  /// optional; the public production configuration is the fallback.
  String? get apiBaseUrl {
    try {
      final decoded = jsonDecode(localStorageJson);
      if (decoded is! Map) return null;
      final value = decoded['api_base_url']?.toString().trim();
      if (value == null || value.isEmpty) return null;
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
      if (uri.scheme != 'https') return null;
      final port = uri.hasPort ? ':${uri.port}' : '';
      final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
      return '${uri.scheme}://${uri.host}$port$path';
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
        'kind': kind.key,
        'baseUrl': baseUrl,
        'cookie': cookie,
        'localStorageJson': localStorageJson,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory AirportSession.fromJson(Map<String, Object?> json) {
    final kind = AirportKind.values.firstWhere(
      (item) => item.key == json['kind'],
      orElse: () => AirportKind.ikun,
    );
    return AirportSession(
      kind: kind,
      baseUrl: json['baseUrl']?.toString() ?? airportSite(kind).defaultBaseUrl,
      cookie: json['cookie']?.toString() ?? '',
      localStorageJson: json['localStorageJson']?.toString() ?? '{}',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class AirportSnapshot {
  const AirportSnapshot({
    required this.kind,
    required this.baseUrl,
    this.accountLabel,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expireAt,
    this.subscriptionUrl,
    this.checkinDone = false,
    this.message,
    this.fetchedAt,
  });

  final AirportKind kind;
  final String baseUrl;
  final String? accountLabel;
  final int upload;
  final int download;
  final int total;
  final DateTime? expireAt;
  final String? subscriptionUrl;
  final bool checkinDone;
  final String? message;
  final DateTime? fetchedAt;

  int get used => upload + download;

  AirportSnapshot copyWith({
    String? accountLabel,
    int? upload,
    int? download,
    int? total,
    DateTime? expireAt,
    String? subscriptionUrl,
    bool? checkinDone,
    String? message,
    DateTime? fetchedAt,
  }) {
    return AirportSnapshot(
      kind: kind,
      baseUrl: baseUrl,
      accountLabel: accountLabel ?? this.accountLabel,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expireAt: expireAt ?? this.expireAt,
      subscriptionUrl: subscriptionUrl ?? this.subscriptionUrl,
      checkinDone: checkinDone ?? this.checkinDone,
      message: message ?? this.message,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'kind': kind.key,
        'baseUrl': baseUrl,
        'accountLabel': accountLabel,
        'upload': upload,
        'download': download,
        'total': total,
        'expireAt': expireAt?.toIso8601String(),
        'subscriptionUrl': subscriptionUrl,
        'checkinDone': checkinDone,
        'message': message,
        'fetchedAt': fetchedAt?.toIso8601String(),
      };

  factory AirportSnapshot.fromJson(Map<String, Object?> json) {
    final kind = AirportKind.values.firstWhere(
      (item) => item.key == json['kind'],
      orElse: () => AirportKind.ikun,
    );
    return AirportSnapshot(
      kind: kind,
      baseUrl: json['baseUrl']?.toString() ?? airportSite(kind).defaultBaseUrl,
      accountLabel: json['accountLabel']?.toString(),
      upload: _intValue(json['upload']),
      download: _intValue(json['download']),
      total: _intValue(json['total']),
      expireAt: DateTime.tryParse(json['expireAt']?.toString() ?? ''),
      subscriptionUrl: json['subscriptionUrl']?.toString(),
      checkinDone: json['checkinDone'] == true,
      message: json['message']?.toString(),
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? ''),
    );
  }
}

int _intValue(Object? value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// A persisted airport account.  One airport can own several of these
/// records; the selected account is managed by AirportAccountsState.
class AirportAccountRecord {
  const AirportAccountRecord({
    required this.id,
    required this.session,
    this.snapshot,
    this.lastCheckInAt,
    this.loading = false,
    this.error,
    this.requiresLogin = false,
  });

  final String id;
  final AirportSession session;
  final AirportSnapshot? snapshot;
  final DateTime? lastCheckInAt;
  final bool loading;
  final String? error;
  final bool requiresLogin;

  bool get checkedInToday {
    final value = lastCheckInAt;
    if (value == null) {
      final fetchedAt = snapshot?.fetchedAt;
      if (fetchedAt == null || snapshot?.checkinDone != true) return false;
      final now = DateTime.now();
      return fetchedAt.year == now.year &&
          fetchedAt.month == now.month &&
          fetchedAt.day == now.day;
    }
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  String get displayLabel {
    final label = snapshot?.accountLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return '机场账号';
  }

  AirportAccountRecord copyWith({
    AirportSession? session,
    AirportSnapshot? snapshot,
    DateTime? lastCheckInAt,
    bool? loading,
    String? error,
    bool? requiresLogin,
    bool clearError = false,
    bool clearSnapshot = false,
    bool clearLastCheckInAt = false,
  }) {
    return AirportAccountRecord(
      id: id,
      session: session ?? this.session,
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      lastCheckInAt:
          clearLastCheckInAt ? null : lastCheckInAt ?? this.lastCheckInAt,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      requiresLogin: requiresLogin ?? this.requiresLogin,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'session': session.toJson(),
        'snapshot': snapshot?.toJson(),
        'lastCheckInAt': lastCheckInAt?.toIso8601String(),
        'loading': false,
        'error': error,
        'requiresLogin': requiresLogin,
      };

  factory AirportAccountRecord.fromJson(Map<String, Object?> json) {
    final sessionJson = json['session'];
    final snapshotJson = json['snapshot'];
    final session = sessionJson is Map
        ? AirportSession.fromJson(Map<String, Object?>.from(sessionJson))
        : AirportSession(
            kind: AirportKind.ikun,
            baseUrl: airportSite(AirportKind.ikun).defaultBaseUrl,
            cookie: '',
          );
    return AirportAccountRecord(
      id: json['id']?.toString() ?? '',
      session: session,
      snapshot: snapshotJson is Map
          ? AirportSnapshot.fromJson(Map<String, Object?>.from(snapshotJson))
          : null,
      lastCheckInAt: DateTime.tryParse(json['lastCheckInAt']?.toString() ?? ''),
      loading: false,
      error: json['error']?.toString(),
      requiresLogin: json['requiresLogin'] == true,
    );
  }
}
