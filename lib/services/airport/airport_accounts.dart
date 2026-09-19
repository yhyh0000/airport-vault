import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'airport_models.dart';
import 'airport_service.dart';
import 'airport_store.dart';

class AirportAccountState {
  const AirportAccountState({
    this.session,
    this.snapshot,
    this.loading = false,
    this.error,
  });

  final AirportSession? session;
  final AirportSnapshot? snapshot;
  final bool loading;
  final String? error;

  bool get isConnected => session != null;

  AirportAccountState copyWith({
    AirportSession? session,
    AirportSnapshot? snapshot,
    bool? loading,
    String? error,
    bool clearSession = false,
    bool clearSnapshot = false,
    bool clearError = false,
  }) {
    return AirportAccountState(
      session: clearSession ? null : session ?? this.session,
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AirportAccountsState {
  const AirportAccountsState({this.accounts = const {}});

  final Map<AirportKind, AirportAccountState> accounts;

  AirportAccountState forKind(AirportKind kind) =>
      accounts[kind] ?? const AirportAccountState();

  AirportAccountsState copyWith(AirportKind kind, AirportAccountState value) {
    return AirportAccountsState(accounts: {...accounts, kind: value});
  }
}

class AirportAccountsNotifier extends Notifier<AirportAccountsState> {
  @override
  AirportAccountsState build() {
    unawaited(_load());
    return const AirportAccountsState();
  }

  final AirportSessionStore _store = const AirportSessionStore();
  final AirportService _service = AirportService();

  Future<void> _load() async {
    for (final kind in AirportKind.values) {
      final session = await _store.read(kind);
      if (session == null) continue;
      state = state.copyWith(
        kind,
        state.forKind(kind).copyWith(session: session),
      );
      unawaited(sync(kind));
    }
  }

  Future<void> saveSession(AirportSession session) async {
    await _store.write(session);
    state = state.copyWith(
      session.kind,
      state.forKind(session.kind).copyWith(
        session: session,
        clearError: true,
      ),
    );
    await sync(session.kind);
  }

  Future<void> remove(AirportKind kind) async {
    await _store.delete(kind);
    state = state.copyWith(kind, const AirportAccountState());
  }

  Future<void> sync(AirportKind kind) async {
    final current = state.forKind(kind);
    final session = current.session;
    if (session == null || current.loading) return;
    state = state.copyWith(
      kind,
      current.copyWith(loading: true, clearError: true),
    );
    try {
      final snapshot = await _service.sync(session);
      state = state.copyWith(
        kind,
        state.forKind(kind).copyWith(loading: false, snapshot: snapshot),
      );
    } catch (error) {
      state = state.copyWith(
        kind,
        state.forKind(kind).copyWith(
          loading: false,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> checkIn(AirportKind kind) async {
    final current = state.forKind(kind);
    final session = current.session;
    if (session == null || current.loading) return;
    state = state.copyWith(
      kind,
      current.copyWith(loading: true, clearError: true),
    );
    try {
      final snapshot = await _service.checkIn(session);
      state = state.copyWith(
        kind,
        state.forKind(kind).copyWith(loading: false, snapshot: snapshot),
      );
    } catch (error) {
      state = state.copyWith(
        kind,
        state.forKind(kind).copyWith(
          loading: false,
          error: error.toString(),
        ),
      );
    }
  }
}

final airportAccountsProvider = NotifierProvider<AirportAccountsNotifier,
    AirportAccountsState>(AirportAccountsNotifier.new);
