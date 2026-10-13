import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/config/easytier.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String easyTierStatusText(BuildContext context, String status) {
  final l10n = context.appLocalizations;
  return switch (status) {
    'ready' => l10n.easyTierPeersRunning,
    'starting' => l10n.easyTierPeersStarting,
    'stale' => l10n.easyTierPeersStale,
    'unavailable' => l10n.easyTierPeersUnavailable,
    _ => l10n.easyTierPeersStopped,
  };
}

class EasyTierDetailsPage extends ConsumerWidget {
  const EasyTierDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final props = ref.watch(appSettingProvider.select((state) => state.easyTier));
    return CommonScaffold(
      title: 'EasyTier',
      actions: [
        IconButton(
          tooltip: context.appLocalizations.easyTierConfiguration,
          onPressed: () => BaseNavigator.push(context, const EasyTierPage()),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: EasyTierDetailsBody(
              state: ref.watch(easyTierRoutesProvider),
              networkName: props.networkName,
              enabled: props.enable,
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

  const EasyTierDetailsBody({
    super.key,
    required this.state,
    required this.networkName,
    required this.enabled,
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
            _ => l10n.easyTierPeersStoppedHint,
          };
    final secondaryStyle = context.textTheme.bodyMedium?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommonCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.easyTierNetworkName, style: secondaryStyle),
                const SizedBox(height: 4),
                SelectableText(
                  networkName.isNotEmpty ? networkName : 'EasyTier',
                  style: context.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      live ? Icons.check_circle_outline : Icons.info_outline,
                      size: 18,
                      color: context.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        enabled ? easyTierStatusText(context, status) : l10n.easyTierDashboardDisabled,
                        style: secondaryStyle,
                      ),
                    ),
                  ],
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
                    style: context.textTheme.titleMedium?.copyWith(
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
            child: Text(l10n.easyTierPeerCount(peers.length), style: context.textTheme.titleSmall),
          ),
          if (peers.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) => Grid(
                crossAxisCount: constraints.maxWidth >= 720 ? 8 : 4,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                children: [
                  for (final peer in peers)
                    GridItem(
                      crossAxisCellCount: 4,
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
    final secondaryStyle = context.textTheme.bodyMedium?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return CommonCard(
      key: ValueKey('easytier-peer-${peer.peerId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        peer.hostname.isNotEmpty ? peer.hostname : l10n.easyTierPeerUnnamed(peer.peerId),
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        peer.ipv4 ?? l10n.easyTierPeerNoIpv4,
                        style: secondaryStyle?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(l10n.delay, style: context.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      delayText,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    direct ? l10n.easyTierPeerDirect : l10n.easyTierPeerRelay,
                    style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSecondaryContainer),
                  ),
                ),
                if (live && direct && peer.protocols.isNotEmpty)
                  Text(peer.protocols.join(' / '), style: secondaryStyle),
              ],
            ),
            if (live && direct && peer.connections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.easyTierConnectionAddresses, style: context.textTheme.bodySmall),
              const SizedBox(height: 4),
              for (final address in peer.connections)
                SelectableText(address, style: context.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
