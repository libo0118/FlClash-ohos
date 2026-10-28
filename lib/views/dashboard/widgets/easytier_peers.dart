import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/config/easytier.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/easytier/easytier.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'intranet_ip.dart' show copyToClipboard;

class EasyTierDashboardTile extends ConsumerStatefulWidget {
  const EasyTierDashboardTile({super.key});

  @override
  ConsumerState<EasyTierDashboardTile> createState() =>
      _EasyTierDashboardTileState();
}

class _EasyTierDashboardTileState extends ConsumerState<EasyTierDashboardTile> {
  var _pending = false;

  Future<void> _change(bool value) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await updateEasyTierSettings(context, ref, enable: value);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(ohosVpnRunningProvider);
    return EasyTierIpTile(
      state: ref.watch(easyTierRoutesProvider),
      enabled: ref.watch(
        appSettingProvider.select((state) => state.easyTier.enable),
      ),
      vpnRunning: vpn.isLoading || vpn.hasError ? null : vpn.value,
      pending: _pending,
      onChanged: _pending ? null : _change,
      onTap: () => BaseNavigator.push(context, const EasyTierDetailsPage()),
    );
  }
}

class EasyTierIpTile extends StatelessWidget {
  final EasyTierRoutesState state;
  final bool enabled;
  final bool? vpnRunning;
  final bool pending;
  final VoidCallback onTap;
  final ValueChanged<bool>? onChanged;

  const EasyTierIpTile({
    super.key,
    required this.state,
    required this.enabled,
    required this.onTap,
    this.vpnRunning = true,
    this.pending = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final density = DashboardDensityScope.of(context);
    final scale = DashboardDensityScope.scaleOf(context);
    final mobile = !density.isDesktop;
    final status = switch (vpnRunning) {
      null => 'unknown',
      false => 'stopped',
      true => state.peerStatus,
    };
    final address = enabled && status == 'ready' ? state.virtualIpv4 : null;
    final loading = enabled && (status == 'starting' || status == 'loading');
    final subtitle = pending
        ? l10n.loading
        : !enabled
        ? l10n.easyTierDashboardDisabled
        : status == 'loading'
        ? l10n.loading
        : easyTierStatusText(context, status);
    final figure = mobile
        ? (style: AppTextStyle.title1, top: 12.0)
        : density.isCompact
        ? (style: AppTextStyle.title2, top: 8.0)
        : (style: AppTextStyle.title2, top: 10.0);
    final row = density.isCompact
        ? (
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            titleStart: 12.0,
            radius: 16.0,
            icon: 32.0,
          )
        : (
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            titleStart: 14.0,
            radius: 20.0,
            icon: 38.0,
          );
    final style = DashboardText.figure(
      context,
      figure.style,
    ).copyWith(letterSpacing: 0);
    return DashboardCard(
      key: const ValueKey('easytier-dashboard-entry'),
      semanticLabel: 'EasyTier · $subtitle',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: 'EasyTier',
            chevron: true,
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.copy,
                tooltip: l10n.copy,
                onPressed: address == null
                    ? null
                    : () => copyToClipboard(context, address),
              ),
            ],
          ),
          SizedBox(height: figure.top),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: figure.style.leading * scale,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: loading
                  ? SkeletonText(width: 120, style: style)
                  : address != null
                  ? DashboardFitText(address, style: style)
                  : Text(
                      enabled && status == 'ready'
                          ? l10n.easyTierPeerNoIpv4
                          : '—',
                      style: enabled && status == 'ready'
                          ? AppTextStyle.subheadline
                                .of(context)
                                .copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                )
                          : style.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                    ),
            ),
          ),
          if (mobile) const SizedBox(height: 14) else const Spacer(),
          LayoutBuilder(
            builder: (context, constraints) {
              final showIcon = DashboardSwitchRow.iconFits(
                context,
                width: constraints.maxWidth,
                iconSize: row.icon,
                padding: row.padding,
                titles: [l10n.status],
              );
              return DashboardSwitchRow(
                key: const ValueKey('easytier-dashboard-toggle'),
                glyph: AppGlyphs.devices,
                title: l10n.status,
                subtitle: subtitle,
                value: enabled,
                iconSize: row.icon,
                padding: showIcon
                    ? row.padding
                    : row.padding.copyWith(left: row.titleStart),
                radius: row.radius,
                showIcon: showIcon,
                onTap: onChanged == null ? null : () => onChanged!(!enabled),
                onChanged: onChanged,
              );
            },
          ),
        ],
      ),
    );
  }
}
