import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/surge/surge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Product-level airport presets. They deliberately contain no real URL or
/// account data; users add their own official subscription link in Profiles.
class AirportOverview extends ConsumerWidget {
  const AirportOverview({super.key});

  static const _presets = [
    _AirportPreset(
      name: 'iKun',
      caption: '适合放置 iKun 的订阅与节点',
      icon: Icons.bolt_rounded,
      color: Color(0xFF5B61FF),
    ),
    _AirportPreset(
      name: 'Pokemon',
      caption: '适合放置 Pokemon 的订阅与节点',
      icon: Icons.catching_pokemon_rounded,
      color: Color(0xFF2CC7C9),
    ),
  ];

  void _toProfiles() {
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(PageLabel.profiles);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surge = SurgeTheme.of(context);
    final profiles = ref.watch(profilesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '我的机场',
                style: context.typography.sectionTitle.copyWith(
                  color: surge.textPrimary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _toProfiles,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加订阅'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _presets.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _AirportCard(
                      preset: _presets[i],
                      profile: _findProfile(profiles, _presets[i]),
                      onAdd: _toProfiles,
                    ),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _presets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _AirportCard(
                      preset: _presets[i],
                      profile: _findProfile(profiles, _presets[i]),
                      onAdd: _toProfiles,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AirportPreset {
  const _AirportPreset({
    required this.name,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String name;
  final String caption;
  final IconData icon;
  final Color color;
}

class _AirportCard extends StatelessWidget {
  const _AirportCard({
    required this.preset,
    required this.profile,
    required this.onAdd,
  });

  final _AirportPreset preset;
  final Profile? profile;
  final VoidCallback onAdd;

  String _trafficText() {
    final info = profile?.subscriptionInfo;
    if (info == null || info.total <= 0) return '等待订阅信息';
    final used = info.upload + info.download;
    return '${_formatBytes(used)} / ${_formatBytes(info.total)}';
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
                      profile == null ? '尚未添加' : '已绑定订阅',
                      style: context.typography.badgeLabel.copyWith(
                        color: preset.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            profile == null
                ? preset.caption
                : '${preset.caption} · ${_trafficText()}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.typography.compactDescription.copyWith(
              color: surge.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.link_rounded, size: 17),
              label: Text(profile == null ? '绑定订阅链接' : '管理订阅'),
              style: OutlinedButton.styleFrom(
                foregroundColor: preset.color,
                side: BorderSide(color: preset.color.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
