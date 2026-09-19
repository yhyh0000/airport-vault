import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'airport_models.dart';

class AirportSessionStore {
  const AirportSessionStore();

  static const _storage = FlutterSecureStorage();

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

  Future<void> delete(AirportKind kind) => _storage.delete(key: _key(kind));

  String _key(AirportKind kind) => 'airport_vault_session_${kind.key}';
}
