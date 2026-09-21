import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'airport_models.dart';
import 'airport_service.dart';
import 'airport_store.dart';

/// All accounts for one airport.  Accounts are independent records; the
/// optional active id only remembers which card was opened most recently.
class AirportAccountState {
  const AirportAccountState({
    this.accounts = const [],
    this.activeAccountId,
  });

  final List<AirportAccountRecord> accounts;
  final String? activeAccountId;

  AirportAccountRecord? get activeAccount {
    if (accounts.isEmpty) return null;
    for (final account in accounts) {
      if (account.id == activeAccountId) return account;
    }
    return accounts.first;
  }

  AirportAccountRecord? accountById(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  AirportSession? get session => activeAccount?.session;
  AirportSnapshot? get snapshot => activeAccount?.snapshot;
  bool get isConnected => accounts.isNotEmpty;
  bool get loading => accounts.any((account) => account.loading);
  bool get requiresLogin => accounts.any((account) => account.requiresLogin);
  String? get error {
    for (final account in accounts) {
      if (account.error != null) return account.error;
    }
    return null;
  }

  AirportAccountState copyWith({
    List<AirportAccountRecord>? accounts,
    String? activeAccountId,
  }) {
    return AirportAccountState(
      accounts: accounts ?? this.accounts,
      activeAccountId: activeAccountId ?? this.activeAccountId,
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
      final stored = await _store.readAccounts(kind);
      if (stored.accounts.isEmpty) continue;
      final activeId = stored.accounts.any(
        (account) => account.id == stored.activeAccountId,
      )
          ? stored.activeAccountId
          : stored.accounts.first.id;
      state = state.copyWith(
        kind,
        AirportAccountState(
          accounts: stored.accounts,
          activeAccountId: activeId,
        ),
      );
      // Refresh every saved account, not only one selected account.
      unawaited(sync(kind));
    }
  }

  Future<void> _persist(AirportKind kind, AirportAccountState value) {
    return _store.writeAccounts(
      kind,
      value.accounts,
      activeAccountId: value.activeAccount?.id,
    );
  }

  List<AirportAccountRecord> _replaceRecord(
    List<AirportAccountRecord> accounts,
    AirportAccountRecord replacement,
  ) {
    return [
      for (final account in accounts)
        if (account.id == replacement.id) replacement else account,
    ];
  }

  Future<String> saveSession(
    AirportSession session, {
    String? replaceAccountId,
  }) async {
    final current = state.forKind(session.kind);
    final id = replaceAccountId ?? _store.accountIdFor(session);
    final record = AirportAccountRecord(id: id, session: session);
    final next = current.copyWith(
      accounts: [
        ...current.accounts.where((account) => account.id != id),
        record,
      ],
      activeAccountId: id,
    );
    state = state.copyWith(session.kind, next);
    await _persist(session.kind, next);
    await sync(session.kind, accountId: id);
    return id;
  }

  Future<void> selectAccount(AirportKind kind, String accountId) async {
    final current = state.forKind(kind);
    if (current.accountById(accountId) == null) return;
    final next = current.copyWith(activeAccountId: accountId);
    state = state.copyWith(kind, next);
    await _persist(kind, next);
  }

  Future<String?> findBestEntry(
    AirportKind kind, {
    String? preferredBaseUrl,
  }) async {
    final result = await _service.findBestEntry(
      airportSite(kind),
      preferredBaseUrl: preferredBaseUrl,
    );
    return result?.baseUrl;
  }

  Future<void> remove(AirportKind kind, {String? accountId}) async {
    final current = state.forKind(kind);
    final id = accountId ?? current.activeAccount?.id;
    if (id == null) return;
    final accounts = current.accounts.where((item) => item.id != id).toList();
    final next = current.copyWith(
      accounts: accounts,
      activeAccountId: accounts.isEmpty ? null : accounts.first.id,
    );
    state = state.copyWith(kind, next);
    await _persist(kind, next);
    if (next.isConnected) await sync(kind);
  }

  Future<void> sync(AirportKind kind, {String? accountId}) async {
    if (accountId == null) {
      final ids = state.forKind(kind).accounts.map((item) => item.id).toList();
      for (final id in ids) {
        await sync(kind, accountId: id);
      }
      return;
    }

    final current = state.forKind(kind);
    final record = current.accountById(accountId);
    if (record == null || record.loading) return;
    final loadingRecord = record.copyWith(loading: true, clearError: true);
    final loadingState = current.copyWith(
      accounts: _replaceRecord(current.accounts, loadingRecord),
    );
    state = state.copyWith(kind, loadingState);
    try {
      final snapshot = await _service.sync(record.session);
      final refreshed = snapshot.copyWith(
        checkinDone: snapshot.checkinDone || record.checkedInToday,
      );
      final latest = state.forKind(kind);
      final updatedRecord = record.copyWith(
        snapshot: refreshed,
        lastCheckInAt:
            snapshot.checkinDone ? DateTime.now() : record.lastCheckInAt,
        loading: false,
        clearError: true,
        requiresLogin: false,
      );
      final next = latest.copyWith(
        accounts: _replaceRecord(latest.accounts, updatedRecord),
      );
      state = state.copyWith(kind, next);
      await _persist(kind, next);
    } catch (error) {
      final latest = state.forKind(kind);
      final failedRecord = record.copyWith(
        loading: false,
        error: error.toString(),
        requiresLogin: error is AirportAuthRequired,
      );
      state = state.copyWith(
        kind,
        latest.copyWith(accounts: _replaceRecord(latest.accounts, failedRecord)),
      );
    }
  }

  Future<void> checkIn(AirportKind kind, {String? accountId}) async {
    final current = state.forKind(kind);
    final record = accountId == null
        ? current.activeAccount
        : current.accountById(accountId);
    if (record == null || record.loading || record.checkedInToday) return;
    final loadingState = current.copyWith(
      accounts: _replaceRecord(current.accounts, record.copyWith(
        loading: true,
        clearError: true,
      )),
    );
    state = state.copyWith(kind, loadingState);
    try {
      final snapshot = await _service.checkIn(record.session);
      final latest = state.forKind(kind);
      final updatedRecord = record.copyWith(
        snapshot: snapshot.copyWith(checkinDone: true),
        lastCheckInAt: DateTime.now(),
        loading: false,
        clearError: true,
        requiresLogin: false,
      );
      final next = latest.copyWith(
        accounts: _replaceRecord(latest.accounts, updatedRecord),
      );
      state = state.copyWith(kind, next);
      await _persist(kind, next);
    } catch (error) {
      final latest = state.forKind(kind);
      final failedRecord = record.copyWith(
        loading: false,
        error: error.toString(),
        requiresLogin: error is AirportAuthRequired,
      );
      state = state.copyWith(
        kind,
        latest.copyWith(accounts: _replaceRecord(latest.accounts, failedRecord)),
      );
    }
  }

  Future<AirportGiftCardResult?> redeemGiftCard(
    AirportKind kind,
    String code, {
    String? accountId,
  }) async {
    final current = state.forKind(kind);
    final record = accountId == null
        ? current.activeAccount
        : current.accountById(accountId);
    if (record == null || record.loading) return null;
    state = state.copyWith(
      kind,
      current.copyWith(accounts: _replaceRecord(
        current.accounts,
        record.copyWith(loading: true, clearError: true),
      )),
    );
    try {
      final result = await _service.redeemGiftCard(record.session, code);
      final latest = state.forKind(kind);
      state = state.copyWith(
        kind,
        latest.copyWith(accounts: _replaceRecord(
          latest.accounts,
          record.copyWith(loading: false, clearError: true),
        )),
      );
      await sync(kind, accountId: record.id);
      return result;
    } catch (error) {
      final latest = state.forKind(kind);
      state = state.copyWith(
        kind,
        latest.copyWith(accounts: _replaceRecord(
          latest.accounts,
          record.copyWith(
            loading: false,
            error: error.toString(),
            requiresLogin: error is AirportAuthRequired,
          ),
        )),
      );
      return null;
    }
  }
}

final airportAccountsProvider = NotifierProvider<AirportAccountsNotifier,
    AirportAccountsState>(AirportAccountsNotifier.new);
