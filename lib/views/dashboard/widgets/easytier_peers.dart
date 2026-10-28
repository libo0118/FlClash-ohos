import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/easytier/easytier.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

class EasyTierDashboardTile extends ConsumerWidget {
  const EasyTierDashboardTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => EasyTierCompactTile(
    state: ref.watch(easyTierRoutesProvider),
    enabled: ref.watch(
      appSettingProvider.select((state) => state.easyTier.enable),
    ),
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
    final showCount =
        enabled &&
        (status == 'ready' ||
            (status != 'starting' &&
                status != 'stopped' &&
                state.peers.isNotEmpty));
    final subtitle = enabled
        ? [
            easyTierStatusText(context, status),
            if (showCount) l10n.easyTierPeerCountCompact(state.peers.length),
          ].join(' · ')
        : l10n.easyTierDashboardDisabled;
    return DashboardCard(
      key: const ValueKey('easytier-dashboard-entry'),
      semanticLabel: 'EasyTier · $subtitle',
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: 'EasyTier',
            chevron: true,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
