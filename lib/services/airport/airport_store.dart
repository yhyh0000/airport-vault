import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'airport_models.dart';

class AirportSessionStore {
  const AirportSessionStore();

  static const _storage = FlutterSecureStorage();

  Future<AirportAccountStoreData> readAccounts(AirportKind kind) async {
    final raw = await _storage.read(key: _accountsKey(kind));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final list = decoded['accounts'];
          if (list is List) {
            final accounts = list
                .whereType<Map>()
                .map(
                  (item) => AirportAccountRecord.fromJson(
                    Map<String, Object?>.from(item),
                  ),
                )
                .where((item) => item.session.kind == kind)
                .where((item) => item.id.isNotEmpty)
                .toList();
            return AirportAccountStoreData(
              accounts: accounts,
              activeAccountId: decoded['activeAccountId']?.toString(),
            );
          }
        }
      } catch (_) {}
    }

    // Migrate the original one-session-per-airport format on first read.
    final legacy = await read(kind);
    if (legacy == null) return const AirportAccountStoreData();
    return AirportAccountStoreData(
      accounts: [
        AirportAccountRecord(
          id: accountIdFor(legacy),
          session: legacy,
        ),
      ],
    );
  }

  Future<void> writeAccounts(
    AirportKind kind,
    List<AirportAccountRecord> accounts, {
    required String? activeAccountId,
  }) async {
    await _storage.write(
      key: _accountsKey(kind),
      value: jsonEncode({
        'activeAccountId': activeAccountId,
        'accounts': accounts.map((item) => item.toJson()).toList(),
      }),
    );
  }

  Future<AirportSession?> read(AirportKind kind) async {
    final raw = await _storage.read(key: _key(kind));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AirportSession.fromJson(Map<String, Object?>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  Future<void> write(AirportSession session) async {
    await _storage.write(key: _key(session.kind), value: jsonEncode(session.toJson()));
  }

  Future<void> delete(AirportKind kind) async {
    await _storage.delete(key: _accountsKey(kind));
    await _storage.delete(key: _key(kind));
  }

  String accountIdFor(AirportSession session) {
    final input = '${session.kind.key}|${session.baseUrl}|'
        '${session.cookie}|${session.localStorageJson}';
    return sha1.convert(utf8.encode(input)).toString().substring(0, 16);
  }

  String _key(AirportKind kind) => 'airport_vault_session_${kind.key}';

  String _accountsKey(AirportKind kind) => 'airport_vault_accounts_${kind.key}';
}

class AirportAccountStoreData {
  const AirportAccountStoreData({
    this.accounts = const [],
    this.activeAccountId,
  });

  final List<AirportAccountRecord> accounts;
  final String? activeAccountId;
}
