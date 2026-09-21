import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/services/airport/airport.dart';
import 'package:fl_clash/services/profile_source_mutation.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

/// Airport business cards: account session, dashboard data, check-in and
/// subscription import are separate from the Mihomo profile list.
class AirportOverview extends ConsumerWidget {
  const AirportOverview({super.key});

  static const _presets = [
    _AirportPreset(
      kind: AirportKind.ikun,
      name: 'iKun',
      caption: '流量、到期时间与每日签到同步',
      icon: Icons.bolt_rounded,
      color: Color(0xFF5B61FF),
    ),
    _AirportPreset(
      kind: AirportKind.pokemon,
      name: 'Pokemon',
      caption: '账户、订阅、8.8兑换与每日签到同步',
      icon: Icons.catching_pokemon_rounded,
      color: Color(0xFF2CC7C9),
    ),
  ];

  AirportAccountState _account(
    AirportAccountsState state,
    _AirportPreset preset,
  ) => state.forKind(preset.kind);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surge = SurgeTheme.of(context);
    final profiles = ref.watch(profilesProvider);
    final accounts = ref.watch(airportAccountsProvider);
    final boundCount = _presets.fold<int>(
      0,
      (total, preset) => total + _account(accounts, preset).accounts.length,
    );
    final attentionCount = _presets.fold<int>(
      0,
      (total, preset) =>
          total +
          _account(accounts, preset)
              .accounts
              .where((account) => account.error != null || account.requiresLogin)
              .length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '账户与订阅',
                style: context.typography.sectionTitle.copyWith(
                  color: surge.textPrimary,
                ),
              ),
            ),
            _SectionBadge(
              label: attentionCount > 0
                  ? '$attentionCount 项待处理'
                  : '$boundCount 个账号已绑定',
              color: attentionCount > 0 ? surge.orange : surge.primary,
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _showManualSubscriptionImport(context, ref),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('添加订阅'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final cards = <Widget>[];
            for (final preset in _presets) {
              final accountState = _account(accounts, preset);
              if (accountState.accounts.isEmpty) {
                cards.add(
                  _AirportCard(
                    preset: preset,
                    profile: _findProfile(profiles, preset),
                    record: null,
                    onOpen: () => _openAccountPanel(context, preset),
                    onAddProfile: () => _openAccountPanel(context, preset),
                  ),
                );
                continue;
              }
              for (final record in accountState.accounts) {
                cards.add(
                  _AirportCard(
                    preset: preset,
                    profile: _findProfile(profiles, preset, record),
                    record: record,
                    onOpen: () => _openAccountPanel(
                      context,
                      preset,
                      accountId: record.id,
                    ),
                    onAddProfile: () => _openAccountPanel(
                      context,
                      preset,
                      accountId: record.id,
                    ),
                  ),
                );
              }
            }
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Profile? _findProfile(
    List<Profile> profiles,
    _AirportPreset preset, [
    AirportAccountRecord? record,
  ]) {
    final subscriptionUrl = record?.snapshot?.subscriptionUrl;
    if (subscriptionUrl != null) {
      for (final profile in profiles) {
        if (profile.url == subscriptionUrl) return profile;
      }
    }
    for (final profile in profiles) {
      final key = preset.name.toLowerCase();
      if (profile.realLabel.toLowerCase().contains(key) ||
          profile.url.toLowerCase().contains(key)) {
        return profile;
      }
    }
    return null;
  }

  Future<void> _openAccountPanel(
    BuildContext context,
    _AirportPreset preset,
    {
    String? accountId,
    }
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AirportAccountPanel(
        preset: preset,
        accountId: accountId,
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  const _SectionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: context.typography.badgeLabel.copyWith(color: color),
      ),
    );
  }
}

class _AirportPreset {
  const _AirportPreset({
    required this.kind,
    required this.name,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final AirportKind kind;
  final String name;
  final String caption;
  final IconData icon;
  final Color color;
}

class _AirportCard extends StatelessWidget {
  const _AirportCard({
    required this.preset,
    required this.profile,
    required this.record,
    required this.onOpen,
    required this.onAddProfile,
  });

  final _AirportPreset preset;
  final Profile? profile;
  final AirportAccountRecord? record;
  final VoidCallback onOpen;
  final VoidCallback onAddProfile;

  String _trafficText(AirportSnapshot? snapshot) {
    final info = profile?.subscriptionInfo;
    if (snapshot != null && snapshot.total > 0) {
      return '${_formatBytes(snapshot.used)} / ${_formatBytes(snapshot.total)}';
    }
    if (info == null || info.total <= 0) return '等待同步面板信息';
    return '${_formatBytes(info.upload + info.download)} / ${_formatBytes(info.total)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    final connected = record != null;
    final snapshot = record?.snapshot;
    final error = record?.error;
    final requiresLogin = record?.requiresLogin ?? false;
    final loading = record?.loading ?? false;
    final status = error != null
        ? requiresLogin
            ? '需要重新绑定'
            : '同步失败'
        : snapshot?.checkinDone == true
            ? '今日已签到'
            : connected
                ? '已绑定${snapshot == null ? '' : ' · 已同步'}'
                : '未绑定账户';
    final subscriptionStatus = _subscriptionStatus(snapshot);
    final info = profile?.subscriptionInfo;
    final total = snapshot?.total ?? info?.total ?? 0;
    final used = snapshot?.used ??
        ((info?.upload ?? 0) + (info?.download ?? 0));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surge.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: surge.separator.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: preset.color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: preset.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(preset.icon, color: preset.color, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: context.typography.itemLabel.copyWith(
                        color: surge.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: context.typography.badgeLabel.copyWith(
                        color: error != null ? surge.orange : preset.color,
                      ),
                    ),
                    if (connected && snapshot?.accountLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        snapshot!.accountLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.compactDescription.copyWith(
                          color: surge.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: preset.color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            preset.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.typography.compactDescription.copyWith(
              color: surge.textSecondary,
            ),
          ),
          if (connected) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _AirportTag(
                  icon: Icons.link_rounded,
                  label: subscriptionStatus,
                  color: snapshot?.subscriptionUrl != null
                      ? surge.green
                      : surge.textSecondary,
                ),
                _AirportTag(
                  icon: snapshot?.checkinDone == true
                      ? Icons.task_alt_rounded
                      : Icons.event_available_rounded,
                  label: snapshot?.checkinDone == true
                      ? '今日已签到'
                      : '待签到',
                  color: snapshot?.checkinDone == true
                      ? surge.green
                      : surge.orange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _accountSummary(snapshot),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.compactDescription.copyWith(
                color: surge.textSecondary,
              ),
            ),
            if (total > 0) ...[
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: (used / total).clamp(0.0, 1.0).toDouble(),
                  backgroundColor: preset.color.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(preset.color),
                ),
              ),
            ],
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.typography.badgeLabel.copyWith(color: Colors.orange),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: Icon(
                    connected && !requiresLogin
                        ? Icons.dashboard_customize_rounded
                        : Icons.person_add_alt_1_rounded,
                    size: 17,
                  ),
                  label: Text(
                    requiresLogin
                        ? '重新绑定账户'
                        : connected
                            ? '账户中心'
                            : '绑定账户',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: preset.color,
                    backgroundColor: preset.color.withValues(alpha: 0.05),
                    side: BorderSide(color: preset.color.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: connected ? '打开账号管理' : '添加账号',
                onPressed: onAddProfile,
                icon: Icon(Icons.link_rounded, color: preset.color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _accountSummary(AirportSnapshot? snapshot) {
    if (snapshot == null) return '等待同步账户数据';
    final expiry = snapshot.expireAt == null
        ? null
        : '到期 ${snapshot.expireAt!.toLocal().toString().split(' ').first}';
    return [
      _trafficText(snapshot),
      if (expiry != null) expiry,
    ].join(' · ');
  }

  String _subscriptionStatus(AirportSnapshot? snapshot) {
    if (record == null) return '订阅待绑定';
    if (snapshot?.subscriptionUrl == null) return '等待订阅发现';
    if (profile != null) return '已接入节点列表';
    return '订阅已发现';
  }
}

class _AirportTag extends StatelessWidget {
  const _AirportTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.typography.badgeLabel.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _AirportAccountPanel extends ConsumerWidget {
  const _AirportAccountPanel({required this.preset, this.accountId});

  final _AirportPreset preset;
  final String? accountId;

  Future<void> _login(
    BuildContext context,
    WidgetRef ref, {
    String? replaceAccountId,
  }) async {
    final site = airportSite(preset.kind);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在自动选择最快的可用入口…')),
          ],
        ),
      ),
    );
    final baseUrl = await ref
        .read(airportAccountsProvider.notifier)
        .findBestEntry(
          preset.kind,
          preferredBaseUrl: accountId == null
              ? null
              : ref
                  .read(airportAccountsProvider)
                  .forKind(preset.kind)
                  .accountById(accountId!)
                  ?.session
                  .baseUrl,
        );
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    final resolvedBaseUrl = baseUrl ?? site.defaultBaseUrl;
    if (baseUrl == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('入口测速未完成，正在尝试默认入口')),
      );
    }
    if (!context.mounted) return;
    final session = await Navigator.of(context).push<AirportSession>(
      MaterialPageRoute(
        builder: (_) => AirportLoginPage(
          site: site,
          baseUrl: resolvedBaseUrl,
        ),
      ),
    );
    if (session == null || !context.mounted) return;
    final savedId = await ref
        .read(airportAccountsProvider.notifier)
        .saveSession(session, replaceAccountId: replaceAccountId);
    if (!context.mounted) return;
    final accountState = ref.read(airportAccountsProvider).forKind(preset.kind);
    final account = accountState.accountById(savedId);
    if (account == null) return;
    final subscriptionUrl = account.snapshot?.subscriptionUrl;
    if (subscriptionUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录成功，但暂未发现订阅地址，可在账户中心刷新或手动粘贴')),
      );
      return;
    }
    await _importSubscription(
      context,
      ref,
      subscriptionUrl,
      account.session!,
      accountId: savedId,
    );
  }

  Future<void> _importSubscription(
    BuildContext context,
    WidgetRef ref,
    String url,
    AirportSession session,
    {
    String? accountId,
    }
  ) async {
    final normalizedUrl = normalizeProfileSourceUrl(
      url,
      baseUrl: session.baseUrl,
    );
    if (normalizedUrl == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('机场返回的订阅地址无效，请先刷新账户数据')),
        );
      }
      return;
    }
    final headers = <String, String>{
      if (session.cookie.trim().isNotEmpty) 'Cookie': session.cookie,
      if (session.accessToken != null)
        'Authorization': 'Bearer ${session.accessToken}',
      'Referer': '${session.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/',
      'Origin': session.baseUrl.replaceFirst(RegExp(r'/+$'), ''),
    };
    final profiles = ref.read(profilesProvider);
    Profile? existing;
    for (final profile in profiles) {
      if (profile.url == normalizedUrl) {
        existing = profile;
        break;
      }
    }
    final label = '${preset.name}${accountLabelFor(ref, preset.kind, accountId)}';
    final profile = existing == null
        ? await ref.read(profilesActionProvider.notifier).addProfileFormURL(
            normalizedUrl,
            label: label,
            headers: headers,
          )
        : await _refreshExistingProfile(
            ref,
            existing,
            label: label,
            headers: headers,
          );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          profile == null ? '订阅导入失败，请检查登录状态或订阅地址' : '订阅已导入并保存登录态',
        ),
      ),
    );
  }

  String accountLabelFor(
    WidgetRef ref,
    AirportKind kind,
    String? accountId,
  ) {
    final label = ref
        .read(airportAccountsProvider)
        .forKind(kind)
        .accountById(accountId ?? '')
        ?.snapshot
        ?.accountLabel
        ?.trim();
    return label == null || label.isEmpty ? '' : ' · $label';
  }

  Future<Profile?> _refreshExistingProfile(
    WidgetRef ref,
    Profile existing, {
    required String label,
    required Map<String, String> headers,
  }) async {
    final updated = existing.copyWith(
      label: label,
      sourceHeaders: headers,
      autoUpdate: true,
    );
    final outcome = await ref
        .read(profilesActionProvider.notifier)
        .updateProfile(updated, publishInput: true);
    return outcome == ProfileSourceMutationOutcome.superseded ? null : updated;
  }

  Future<void> _redeemPokemonGiftCard(
    BuildContext context,
    WidgetRef ref,
    AirportSession session,
    String accountId,
  ) async {
    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('领取 8.8 免费套餐'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('宝可梦机场每月免费 8.8 套餐需要输入当月兑换码。兑换成功后会自动刷新套餐和订阅地址。'),
            const SizedBox(height: 14),
            TextField(
              controller: codeController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '兑换码',
                hintText: '请输入礼品卡兑换码',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = codeController.text.trim();
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            icon: const Icon(Icons.redeem_rounded),
            label: const Text('兑换'),
          ),
        ],
      ),
    );
    codeController.dispose();
    if (code == null || !context.mounted) return;

    final result = await ref
        .read(airportAccountsProvider.notifier)
        .redeemGiftCard(
          AirportKind.pokemon,
          code,
          accountId: accountId,
        );
    if (!context.mounted) return;
    final error = ref
        .read(airportAccountsProvider)
        .forKind(AirportKind.pokemon)
        .accountById(accountId)
        ?.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result?.message ?? error ?? '兑换失败，请检查兑换码')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = airportSite(preset.kind);
    final account = ref.watch(
      airportAccountsProvider.select((state) => state.forKind(preset.kind)),
    );
    final record = accountId == null
        ? account.activeAccount
        : account.accountById(accountId!);
    final snapshot = record?.snapshot;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${site.title}账户',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (record != null)
                  IconButton(
                    tooltip: '移除本机登录会话',
                    onPressed: () => ref
                        .read(airportAccountsProvider.notifier)
                        .remove(preset.kind, accountId: record.id),
                    icon: const Icon(Icons.logout_rounded),
                  ),
              ],
            ),
            Text(site.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (record != null) ...[
              _AccountIdentityHeader(
                label: record.displayLabel,
                accountId: record.id,
              ),
              const SizedBox(height: 12),
            ],
            if (snapshot != null) ...[
              _InfoRow(label: '账户', value: snapshot.accountLabel ?? '已登录'),
              _InfoRow(
                label: '流量',
                value: snapshot.total > 0
                    ? '${_formatBytes(snapshot.used)} / ${_formatBytes(snapshot.total)}'
                    : '面板未返回流量数据',
              ),
              if (snapshot.expireAt != null)
                _InfoRow(
                  label: '到期',
                  value: snapshot.expireAt!.toLocal().toString().split(' ').first,
                ),
              if (snapshot.message != null)
                _InfoRow(label: '最近结果', value: snapshot.message!),
              const SizedBox(height: 8),
            ],
            if (record == null || record.requiresLogin)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => _login(
                      context,
                      ref,
                      replaceAccountId: record?.id,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      record?.requiresLogin == true ? '重新绑定账户' : '绑定账户',
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => _showManualSubscriptionImport(
                      context,
                      ref,
                      defaultLabel: preset.name,
                    ),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('手动导入订阅链接'),
                  ),
                ],
              )
            else ...[
              if (preset.kind == AirportKind.pokemon && record != null) ...[
                OutlinedButton.icon(
                  onPressed: record.loading
                      ? null
                      : () => _redeemPokemonGiftCard(
                            context,
                            ref,
                            record.session,
                            record.id,
                          ),
                  icon: const Icon(Icons.redeem_rounded),
                  label: const Text('领取 8.8 免费套餐'),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: record.loading || record.checkedInToday
                          ? null
                          : () => ref
                              .read(airportAccountsProvider.notifier)
                              .checkIn(preset.kind, accountId: record.id),
                      icon: const Icon(Icons.task_alt_rounded),
                      label: Text(
                        record.checkedInToday ? '今日已签到' : '立即签到',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: '刷新账户数据',
                    onPressed: record.loading
                        ? null
                        : () => ref
                            .read(airportAccountsProvider.notifier)
                            .sync(preset.kind, accountId: record.id),
                    icon: const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
              if (snapshot?.subscriptionUrl != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _importSubscription(
                    context,
                    ref,
                    snapshot!.subscriptionUrl!,
                    record.session,
                    accountId: record.id,
                  ),
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: const Text('导入订阅到节点列表'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: snapshot.subscriptionUrl!),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('订阅地址已复制')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('复制订阅地址'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: () => _showManualSubscriptionImport(
                  context,
                  ref,
                  defaultLabel: preset.name,
                  headers: _sessionHeaders(record.session),
                ),
                icon: const Icon(Icons.link_rounded),
                label: const Text('手动导入订阅链接'),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => _login(
                  context,
                  ref,
                  replaceAccountId: record.id,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('重新登录此账号'),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _login(context, ref),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('添加另一个账号'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, String> _sessionHeaders(AirportSession session) {
    return {
      if (session.cookie.trim().isNotEmpty) 'Cookie': session.cookie,
      if (session.accessToken != null)
        'Authorization': 'Bearer ${session.accessToken}',
      'Referer': '${session.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/',
      'Origin': session.baseUrl.replaceFirst(RegExp(r'/+$'), ''),
    };
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _ManualSubscriptionInput {
  const _ManualSubscriptionInput({required this.url, this.label});

  final String url;
  final String? label;
}

Future<void> _showManualSubscriptionImport(
  BuildContext context,
  WidgetRef ref, {
  String? defaultLabel,
  Map<String, String> headers = const {},
}) async {
  final urlController = TextEditingController();
  final labelController = TextEditingController(text: defaultLabel ?? '');
  final result = await showDialog<_ManualSubscriptionInput>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导入订阅链接'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: '订阅名称（可选）',
                hintText: '例如：iKun 主订阅',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: '订阅链接',
                hintText: '粘贴完整的 https:// 订阅地址',
                suffixIcon: IconButton(
                  tooltip: '从剪贴板粘贴',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final value = data?.text?.trim();
                    if (value != null && value.isNotEmpty) {
                      urlController.text = value;
                      urlController.selection = TextSelection.collapsed(
                        offset: value.length,
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 Clash / Mihomo、V2Ray 等机场订阅格式。',
              style: dialogContext.typography.compactDescription.copyWith(
                color: SurgeTheme.of(dialogContext).textSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            final url = urlController.text.trim();
            if (url.isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('请先粘贴订阅链接')),
              );
              return;
            }
            Navigator.of(dialogContext).pop(
              _ManualSubscriptionInput(
                url: url,
                label: labelController.text.trim().isEmpty
                    ? null
                    : labelController.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('导入'),
        ),
      ],
    ),
  );
  urlController.dispose();
  labelController.dispose();
  if (result == null || !context.mounted) return;

  final normalized = normalizeProfileSourceUrl(result.url);
  if (normalized == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('订阅地址无效，请粘贴完整的 http(s) 链接')),
    );
    return;
  }
  try {
    final profile = await ref
        .read(profilesActionProvider.notifier)
        .addProfileFormURL(
          normalized,
          label: result.label,
          headers: headers,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(profile == null ? '订阅导入失败，请检查链接' : '订阅已导入'),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('订阅导入失败：$error')),
    );
  }
}

class _AccountIdentityHeader extends StatelessWidget {
  const _AccountIdentityHeader({required this.label, required this.accountId});

  final String label;
  final String accountId;

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surge.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: surge.separator),
      ),
      child: Row(
        children: [
          Icon(Icons.account_circle_rounded, color: surge.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.itemLabel.copyWith(
                color: surge.textPrimary,
              ),
            ),
          ),
          Text(
            '账号 ${accountId.substring(
              0,
              accountId.length < 6 ? accountId.length : 6,
            )}',
            style: context.typography.badgeLabel.copyWith(
              color: surge.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
