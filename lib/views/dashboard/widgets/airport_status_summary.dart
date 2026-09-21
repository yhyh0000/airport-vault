import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/services/airport/airport.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A read-only dashboard summary for airport accounts.
///
/// Account login, check-in and subscription import belong to the airport page.
/// Keeping this widget action-light prevents the dashboard from becoming a
/// second airport management page.
class AirportStatusSummary extends ConsumerWidget {
  const AirportStatusSummary({super.key});

  static const _items = [
    _AirportStatusItem(
      kind: AirportKind.ikun,
      name: 'iKun',
      color: Color(0xFF5B61FF),
      icon: Icons.bolt_rounded,
    ),
    _AirportStatusItem(
      kind: AirportKind.pokemon,
      name: 'Pokemon',
      color: Color(0xFF2CC7C9),
      icon: Icons.catching_pokemon_rounded,
    ),
  ];

  void _openAirports() {
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(PageLabel.airports);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surge = SurgeTheme.of(context);
    final accounts = ref.watch(airportAccountsProvider);

    return SurgeCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '机场状态',
                  style: context.typography.sectionTitle.copyWith(
                    color: surge.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openAirports,
                child: const Text('管理机场'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '账户登录、签到与订阅导入统一在机场页面处理',
            style: context.typography.compactDescription.copyWith(
              color: surge.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              final children = [
                for (final item in _items)
                  Expanded(
                    child: _StatusTile(
                      item: item,
                      status: _status(accounts.forKind(item.kind)),
                    ),
                  ),
              ];
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusTile(
                      item: _items[0],
                      status: _status(accounts.forKind(_items[0].kind)),
                    ),
                    const SizedBox(height: 8),
                    _StatusTile(
                      item: _items[1],
                      status: _status(accounts.forKind(_items[1].kind)),
                    ),
                  ],
                );
              }
              return Row(
                children: [children[0], const SizedBox(width: 8), children[1]],
              );
            },
          ),
        ],
      ),
    );
  }

  String _status(dynamic account) {
    if (!account.isConnected) return '未绑定';
    final total = account.accounts.length;
    final loading = account.accounts.where((item) => item.loading).length;
    final errors = account.accounts.where((item) => item.error != null).length;
    final signed = account.accounts.where((item) => item.checkedInToday).length;
    if (loading > 0) return '$total 个账号 · 同步中 $loading';
    if (errors > 0) return '$total 个账号 · $errors 项异常';
    if (signed == total) return '$total 个账号 · 今日已签到';
    return '$total 个账号 · $signed 个已签到';
  }
}

class _AirportStatusItem {
  const _AirportStatusItem({
    required this.kind,
    required this.name,
    required this.color,
    required this.icon,
  });

  final AirportKind kind;
  final String name;
  final Color color;
  final IconData icon;
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.item, required this.status});

  final _AirportStatusItem item;
  final String status;

  @override
  Widget build(BuildContext context) {
    final surge = SurgeTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: item.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: context.typography.itemLabel.copyWith(
                color: surge.textPrimary,
              ),
            ),
          ),
          Text(
            status,
            style: context.typography.badgeLabel.copyWith(color: item.color),
          ),
        ],
      ),
    );
  }
}
