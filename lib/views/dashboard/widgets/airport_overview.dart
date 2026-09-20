import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/services/airport/airport.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      caption: '账户、订阅与每日签到同步',
      icon: Icons.catching_pokemon_rounded,
      color: Color(0xFF2CC7C9),
    ),
  ];

  void _toProfiles() {
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(PageLabel.profiles);
  }

  AirportAccountState _account(
    AirportAccountsState state,
    _AirportPreset preset,
  ) => state.forKind(preset.kind);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surge = SurgeTheme.of(context);
    final profiles = ref.watch(profilesProvider);
    final accounts = ref.watch(airportAccountsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '机场业务',
                style: context.typography.sectionTitle.copyWith(
                  color: surge.textPrimary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _toProfiles,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('导入订阅'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final cards = _presets
                .map(
                  (preset) => _AirportCard(
                    preset: preset,
                    profile: _findProfile(profiles, preset),
                    account: _account(accounts, preset),
                    onOpen: () => _openAccountPanel(context, preset),
                    onAddProfile: _toProfiles,
                  ),
                )
                .toList();
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

  Profile? _findProfile(List<Profile> profiles, _AirportPreset preset) {
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
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AirportAccountPanel(preset: preset),
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
    required this.account,
    required this.onOpen,
    required this.onAddProfile,
  });

  final _AirportPreset preset;
  final Profile? profile;
  final AirportAccountState account;
  final VoidCallback onOpen;
  final VoidCallback onAddProfile;

  String _trafficText() {
    final info = profile?.subscriptionInfo;
    final snapshot = account.snapshot;
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
    final connected = account.isConnected;
    final status = account.error != null
        ? account.requiresLogin
            ? '需要重新绑定'
            : '同步失败'
        : account.snapshot?.checkinDone == true
            ? '今日已签到'
            : connected
                ? '已绑定${account.snapshot == null ? '' : ' · 已同步'}'
                : '未绑定账户';
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
                        color: account.error != null ? Colors.orange : preset.color,
                      ),
                    ),
                    if (connected && account.snapshot?.accountLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        account.snapshot!.accountLabel!,
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
              if (account.loading)
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
            const SizedBox(height: 8),
            Text(
              _accountSummary(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.typography.compactDescription.copyWith(
                color: surge.textSecondary,
              ),
            ),
          ],
          if (account.error != null) ...[
            const SizedBox(height: 8),
            Text(
              account.error!,
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
                    connected && !account.requiresLogin
                        ? Icons.dashboard_customize_rounded
                        : Icons.person_add_alt_1_rounded,
                    size: 17,
                  ),
                  label: Text(
                    account.requiresLogin
                        ? '重新绑定账户'
                        : connected
                            ? '账户中心'
                            : '绑定账户',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: preset.color,
                    side: BorderSide(color: preset.color.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '导入订阅',
                onPressed: onAddProfile,
                icon: Icon(Icons.link_rounded, color: preset.color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _accountSummary() {
    final snapshot = account.snapshot;
    if (snapshot == null) return '等待同步账户数据';
    final expiry = snapshot.expireAt == null
        ? null
        : '到期 ${snapshot.expireAt!.toLocal().toString().split(' ').first}';
    return [
      _trafficText(),
      if (expiry != null) expiry,
    ].join(' · ');
  }
}

class _AirportAccountPanel extends ConsumerWidget {
  const _AirportAccountPanel({required this.preset});

  final _AirportPreset preset;

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final site = airportSite(preset.kind);
    final baseUrl = await _chooseBaseUrl(context, site);
    if (baseUrl == null || !context.mounted) return;
    final session = await Navigator.of(context).push<AirportSession>(
      MaterialPageRoute(
        builder: (_) => AirportLoginPage(
          site: site,
          baseUrl: baseUrl,
        ),
      ),
    );
    if (session == null || !context.mounted) return;
    await ref.read(airportAccountsProvider.notifier).saveSession(session);
  }

  Future<String?> _chooseBaseUrl(
    BuildContext context,
    AirportSiteDefinition site,
  ) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${site.title}入口'),
        children: [
          for (final url in site.baseUrls)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(url),
              child: Row(
                children: [
                  Icon(
                    url == site.defaultBaseUrl
                        ? Icons.star_rounded
                        : Icons.language_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(url),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _importSubscription(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    await ref
        .read(profilesActionProvider.notifier)
        .addProfileFormURL(url, label: preset.name);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = airportSite(preset.kind);
    final account = ref.watch(
      airportAccountsProvider.select((state) => state.forKind(preset.kind)),
    );
    final snapshot = account.snapshot;
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
                if (account.isConnected)
                  IconButton(
                    tooltip: '移除本机登录会话',
                    onPressed: () => ref
                        .read(airportAccountsProvider.notifier)
                        .remove(preset.kind),
                    icon: const Icon(Icons.logout_rounded),
                  ),
              ],
            ),
            Text(site.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
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
            if (!account.isConnected || account.requiresLogin)
              FilledButton.icon(
                onPressed: () => _login(context, ref),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  account.requiresLogin ? '重新绑定账户' : '绑定账户',
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: account.loading
                          ? null
                          : () => ref
                              .read(airportAccountsProvider.notifier)
                              .checkIn(preset.kind),
                      icon: const Icon(Icons.task_alt_rounded),
                      label: Text(snapshot?.checkinDone == true ? '再次签到' : '立即签到'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: '刷新账户数据',
                    onPressed: account.loading
                        ? null
                        : () => ref
                            .read(airportAccountsProvider.notifier)
                            .sync(preset.kind),
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
                  ),
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: const Text('导入订阅到节点列表'),
                ),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => _login(context, ref),
                child: const Text('更新登录会话'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
