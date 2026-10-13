import 'dart:ui' show FontFeature;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/easytier.dart';
import 'package:fl_clash/widgets/card.dart';
import 'package:flutter/material.dart';

class EasyTierPeersCard extends StatefulWidget {
  final EasyTierRoutesState state;
  final String networkName;
  final bool enabled;
  final VoidCallback? onSettings;

  const EasyTierPeersCard({
    super.key,
    required this.state,
    required this.networkName,
    this.enabled = true,
    this.onSettings,
  });

  @override
  State<EasyTierPeersCard> createState() => _EasyTierPeersCardState();
}

class _EasyTierPeersCardState extends State<EasyTierPeersCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(EasyTierPeersCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.networkName != widget.networkName ||
        oldWidget.state.sessionId != widget.state.sessionId) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    if (!widget.enabled) {
      return CommonCard(
        child: ListTile(
          leading: const Icon(Icons.hub_outlined),
          title: const Text('EasyTier'),
          subtitle: Text(l10n.easyTierDashboardDisabled),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onSettings,
        ),
      );
    }
    final state = widget.state;
    final status = state.peerStatus;
    final live = status == 'ready';
    final peers = status == 'stopped' || status == 'starting'
        ? const <EasyTierPeer>[]
        : state.peers;
    final shown = _expanded ? peers : peers.take(3).toList();
    final statusText = switch (status) {
      'ready' => l10n.easyTierPeersRunning,
      'starting' => l10n.easyTierPeersStarting,
      'stale' => l10n.easyTierPeersStale,
      'unavailable' => l10n.easyTierPeersUnavailable,
      _ => l10n.easyTierPeersStopped,
    };
    final statusIcon = switch (status) {
      'ready' => Icons.check_circle_outline,
      'starting' => Icons.sync,
      'stale' => Icons.schedule,
      'unavailable' => Icons.info_outline,
      _ => Icons.pause_circle_outline,
    };
    final message = switch (status) {
      'starting' => l10n.easyTierPeersStartingHint,
      'stale' => l10n.easyTierPeersStaleHint,
      'unavailable' => l10n.easyTierPeersUnavailableHint,
      'ready' => peers.isEmpty ? l10n.easyTierPeersEmpty : null,
      _ => l10n.easyTierPeersStoppedHint,
    };
    final secondaryStyle = context.textTheme.bodyMedium?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );

    return CommonCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, color: context.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('EasyTier', style: context.textTheme.titleSmall),
                ),
                if (widget.onSettings != null)
                  IconButton(
                    tooltip: l10n.easyTierConfiguration,
                    onPressed: widget.onSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 18),
                    const SizedBox(width: 6),
                    Flexible(child: Text(statusText, style: secondaryStyle)),
                  ],
                ),
                if (live || peers.isNotEmpty)
                  Text(
                    l10n.easyTierPeerCount(peers.length),
                    style: secondaryStyle,
                  ),
              ],
            ),
            if (widget.networkName.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(widget.networkName, style: secondaryStyle),
            ],
            if (state.virtualIpv4 != null &&
                status != 'stopped' &&
                status != 'starting') ...[
              const SizedBox(height: 8),
              Text(l10n.easyTierLocalIpv4, style: secondaryStyle),
              const SizedBox(height: 2),
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
            for (final peer in shown) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              _EasyTierPeerRow(peer: peer, live: live),
            ],
            if (peers.length > 3) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(
                    _expanded
                        ? l10n.easyTierPeersCollapse
                        : l10n.easyTierPeersShowAll(peers.length),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EasyTierPeerRow extends StatelessWidget {
  final EasyTierPeer peer;
  final bool live;

  const _EasyTierPeerRow({required this.peer, required this.live});

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
    return Column(
      key: ValueKey('easytier-peer-${peer.peerId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          peer.ipv4 ?? l10n.easyTierPeerNoIpv4,
          style: context.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          peer.hostname.isNotEmpty
              ? peer.hostname
              : l10n.easyTierPeerUnnamed(peer.peerId),
          style: secondaryStyle,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              direct ? l10n.easyTierPeerDirect : l10n.easyTierPeerRelay,
              style: secondaryStyle,
            ),
            if (live && direct && peer.protocols.isNotEmpty)
              Text(peer.protocols.join(' / '), style: secondaryStyle),
            Text(
              '${l10n.delay} $delayText',
              style: secondaryStyle?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (live && direct && peer.connections.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(l10n.easyTierConnectionAddresses, style: secondaryStyle),
          for (final address in peer.connections)
            SelectableText(address, style: secondaryStyle),
        ],
      ],
    );
  }
}
