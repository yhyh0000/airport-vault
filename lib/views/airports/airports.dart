import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/services/airport/airport.dart';
import 'package:fl_clash/views/dashboard/widgets/airport_overview.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The dedicated airport account warehouse.
///
/// The dashboard keeps a compact airport summary, while this page owns the
/// full account, check-in and subscription-source workflow.
class AirportsView extends StatelessWidget {
  const AirportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    return CommonScaffold(
      title: '机场',
      titleVariant: SlAppBarTitleVariant.root,
      backgroundColor: surge.background,
      appBarActions: const [],
      body: ColoredBox(
        color: surge.background,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            SurgeBottomNavLayout.mainPageBottomPadding(context) + 28,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AirportWarehouseHero(),
                  const SizedBox(height: 16),
                  const AirportOverview(),
                  const SizedBox(height: 18),
                  _AirportWorkflowCard(surge: surge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AirportWarehouseHero extends ConsumerWidget {
  const _AirportWarehouseHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(airportAccountsProvider);
    final connected = AirportKind.values
        .where((kind) => accounts.forKind(kind).isConnected)
        .length;
    final subscriptions = AirportKind.values
        .where((kind) => accounts.forKind(kind).snapshot?.subscriptionUrl != null)
        .length;
    final attention = AirportKind.values.where((kind) {
      final account = accounts.forKind(kind);
      return account.error != null || account.requiresLogin;
    }).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17213F), Color(0xFF3347A8)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF17213F).withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.inventory_2_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '机场账户仓',
                      style: context.typography.cardTitle.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '账户、订阅、签到与入口状态集中管理',
                      style: context.typography.compactDescription.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '同步全部机场',
                onPressed: () async {
                  final notifier = ref.read(airportAccountsProvider.notifier);
                  for (final kind in AirportKind.values) {
                    await notifier.sync(kind);
                  }
                },
                color: Colors.white,
                icon: const Icon(Icons.sync_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _VaultMetric(value: '$connected/2', label: '已绑定'),
              ),
              Expanded(
                child: _VaultMetric(value: '$subscriptions', label: '订阅已发现'),
              ),
              Expanded(
                child: _VaultMetric(
                  value: '$attention',
                  label: '待处理',
                  warning: attention > 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaultMetric extends StatelessWidget {
  const _VaultMetric({
    required this.value,
    required this.label,
    this.warning = false,
  });

  final String value;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.typography.cardTitle.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: context.typography.badgeLabel.copyWith(
            color: warning
                ? const Color(0xFFFFD166)
                : Colors.white.withValues(alpha: 0.68),
          ),
        ),
      ],
    );
  }
}
class _AirportWorkflowCard extends StatelessWidget {
  const _AirportWorkflowCard({required this.surge});

  final SurgeTheme surge;

  @override
  Widget build(BuildContext context) {
    return SurgeCard(
      padding: const EdgeInsets.all(16),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '登录后的自动流程',
            style: context.typography.cardTitle.copyWith(
              color: surge.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '登录成功不是终点，机场钥仓会继续发现并验证订阅。',
            style: context.typography.compactDescription.copyWith(
              color: surge.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _WorkflowStep(label: '保存会话', icon: Icons.lock_rounded),
              _WorkflowStep(label: '同步资料', icon: Icons.sync_rounded),
              _WorkflowStep(label: '发现订阅', icon: Icons.search_rounded),
              _WorkflowStep(
                label: '自动导入',
                icon: Icons.download_done_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: surge.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surge.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF5B61FF)),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.typography.badgeLabel.copyWith(
              color: surge.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
