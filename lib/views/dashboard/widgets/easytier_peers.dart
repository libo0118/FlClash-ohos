import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/easytier/easytier.dart';
import 'package:fl_clash/widgets/card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EasyTierDashboardTile extends ConsumerWidget {
  const EasyTierDashboardTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => EasyTierCompactTile(
    state: ref.watch(easyTierRoutesProvider),
    enabled: ref.watch(appSettingProvider.select((state) => state.easyTier.enable)),
    onTap: () => BaseNavigator.push(context, const EasyTierDetailsPage()),
  );
}

class EasyTierCompactTile extends StatelessWidget {
  final EasyTierRoutesState state;
  final bool enabled;
  final VoidCallback onTap;

  const EasyTierCompactTile({
    super.key,
    required this.state,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final status = state.peerStatus;
    final showCount = enabled &&
        (status == 'ready' || (status != 'starting' && status != 'stopped' && state.peers.isNotEmpty));
    final subtitle = enabled
        ? [easyTierStatusText(context, status), if (showCount) l10n.easyTierPeerCountCompact(state.peers.length)].join(' · ')
        : l10n.easyTierDashboardDisabled;
    return CommonCard(
      key: const ValueKey('easytier-dashboard-entry'),
      onPressed: onTap,
      child: ListTile(
        minTileHeight: 72,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(Icons.hub_outlined, color: context.colorScheme.primary),
        title: Text('EasyTier', style: context.textTheme.titleSmall),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
