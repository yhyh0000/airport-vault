import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/dashboard/widgets/airport_overview.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

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

class _AirportWarehouseHero extends StatelessWidget {
  const _AirportWarehouseHero();

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B61FF), Color(0xFF343DAE)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B61FF).withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
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
                  '账户、订阅、签到和入口状态集中管理',
                  style: context.typography.compactDescription.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.cloud_done_rounded,
            color: surge.background.withValues(alpha: 0.9),
          ),
        ],
      ),
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
