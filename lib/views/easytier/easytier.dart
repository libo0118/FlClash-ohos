import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/config/easytier.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String easyTierStatusText(BuildContext context, String status) {
  final l10n = context.appLocalizations;
  return switch (status) {
    'ready' => l10n.easyTierPeersRunning,
    'starting' => l10n.easyTierPeersStarting,
    'stale' => l10n.easyTierPeersStale,
    'unavailable' => l10n.easyTierPeersUnavailable,
    'stopped' => l10n.easyTierPeersStopped,
    _ => l10n.unknown,
  };
}

class EasyTierDetailsPage extends ConsumerWidget {
  const EasyTierDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final props = ref.watch(
      appSettingProvider.select((state) => state.easyTier),
    );
    final vpn = ref.watch(ohosVpnRunningProvider);
    return CommonScaffold(
      title: 'EasyTier',
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.settings,
          tooltip: context.appLocalizations.easyTierConfiguration,
          onPressed: () => BaseNavigator.push(context, const EasyTierPage()),
        ),
      ],
      body: Builder(
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.all(16).copyWith(
            top: context.contentTopPadding,
            bottom: 16 + context.bottomInset,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: EasyTierDetailsBody(
                state: ref.watch(easyTierRoutesProvider),
                networkName: props.networkName,
                enabled: props.enable,
                vpnRunning: vpn.isLoading || vpn.hasError ? null : vpn.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EasyTierDetailsBody extends StatelessWidget {
  final EasyTierRoutesState state;
  final String networkName;
  final bool enabled;
  final bool? vpnRunning;

  const EasyTierDetailsBody({
    super.key,
    required this.state,
    required this.networkName,
    required this.enabled,
    this.vpnRunning,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final status = state.peerStatus;
    final live = enabled && status == 'ready';
    final showData = enabled && status != 'stopped' && status != 'starting';
    final peers = showData ? state.peers : const <EasyTierPeer>[];
    final message = !enabled
        ? l10n.easyTierPeersDisabledHint
        : switch (status) {
            'starting' => l10n.easyTierPeersStartingHint,
            'stale' => l10n.easyTierPeersStaleHint,
            'unavailable' => l10n.easyTierPeersUnavailableHint,
            'ready' => peers.isEmpty ? l10n.easyTierPeersEmpty : null,
            'stopped' => l10n.easyTierPeersStoppedHint,
            _ => l10n.easyTierPeersUnavailableHint,
          };
    final secondaryStyle = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: context.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommonCard(
          radius: AppCorner.xl,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.easyTierNetworkName, style: secondaryStyle),
                const SizedBox(height: 4),
                SelectableText(
                  networkName.isNotEmpty ? networkName : 'EasyTier',
                  style: AppTextStyle.title3.of(context, emphasized: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GlyphIcon(
                      live ? AppGlyphs.check : AppGlyphs.info,
                      size: 18,
                      color: live
                          ? context.colorScheme.success
                          : context.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        enabled
                            ? easyTierStatusText(context, status)
                            : l10n.easyTierDashboardDisabled,
                        style: secondaryStyle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'VPN · ${switch (vpnRunning) {
                    true => l10n.connected,
                    false => l10n.disconnected,
                    null => l10n.unknown,
                  }}',
                  style: secondaryStyle,
                ),
                if (showData && state.virtualIpv4 != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Text(l10n.easyTierLocalIpv4, style: secondaryStyle),
                  const SizedBox(height: 4),
                  SelectableText(
                    state.virtualIpv4!,
                    style: AppTextStyle.title3
                        .of(context)
                        .copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(message, style: secondaryStyle),
                ],
              ],
            ),
          ),
        ),
        if (showData) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              l10n.easyTierPeerCount(peers.length),
              style: AppTextStyle.headline.of(context),
            ),
          ),
          if (peers.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final peer in peers)
                    SizedBox(
                      width: constraints.maxWidth >= 720
                          ? (constraints.maxWidth - 14) / 2
                          : constraints.maxWidth,
                      child: _EasyTierPeerCard(peer: peer, live: live),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _EasyTierPeerCard extends StatelessWidget {
  final EasyTierPeer peer;
  final bool live;

  const _EasyTierPeerCard({required this.peer, required this.live});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final direct = peer.connectionType == 'direct';
    final delay = live && direct ? peer.latencyMs : null;
    final delayText = delay != null && delay.isFinite && delay >= 0
        ? '${delay.toStringAsFixed(delay < 10 ? 1 : 0)} ms'
        : '—';
    final secondaryStyle = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: context.colorScheme.onSurfaceVariant);
    return CommonCard(
      key: ValueKey('easytier-peer-${peer.peerId}'),
      radius: AppCorner.xl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    peer.hostname.isNotEmpty
                        ? peer.hostname
                        : l10n.easyTierPeerUnnamed(peer.peerId),
                    style: AppTextStyle.headline.of(context),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(l10n.delay, style: AppTextStyle.caption1.of(context)),
                    const SizedBox(height: 4),
                    Text(
                      delayText,
                      style: AppTextStyle.headline
                          .of(context)
                          .copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              peer.ipv4 ?? l10n.easyTierPeerNoIpv4,
              style: secondaryStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: context.raisedSurfaceLevel.colorOf(
                      context.colorScheme,
                    ),
                    shape: AppShape.full,
                  ),
                  child: Text(
                    switch (peer.connectionType) {
                      'direct' => l10n.easyTierPeerDirect,
                      'relay' => l10n.easyTierPeerRelay,
                      _ => l10n.unknown,
                    },
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (live && direct && peer.protocols.isNotEmpty)
                  Text(peer.protocols.join(' / '), style: secondaryStyle),
              ],
            ),
            if (live && direct && peer.connections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.easyTierConnectionAddresses,
                style: AppTextStyle.caption1.of(context),
              ),
              const SizedBox(height: 4),
              for (final address in peer.connections)
                SelectableText(
                  address,
                  style: AppTextStyle.caption1.of(context),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
