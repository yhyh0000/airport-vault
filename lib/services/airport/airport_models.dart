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
    // ikuuu.top currently serves an expired TLS certificate. Keep the
    // certificate-valid mirror as the first entry so WebView can load the
    // login page without asking users to diagnose a browser error.
    defaultBaseUrl: 'https://ikuuu.pw',
    alternateBaseUrls: [
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
    } catch (_) {}
    return null;
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
}
