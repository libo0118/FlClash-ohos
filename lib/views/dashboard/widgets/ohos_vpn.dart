import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

class OhosVpnCard extends ConsumerWidget {
  const OhosVpnCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OhosVpnControl(
    running: ref.watch(ohosVpnRunningProvider),
    ready: ref.watch(initProvider) && ref.watch(profilesProvider).isNotEmpty,
    onRefresh: () => ref.invalidate(ohosVpnRunningProvider),
    onToggle: (enable) async {
      if (enable) {
        ref
            .read(vpnSettingProvider.notifier)
            .update((state) => state.copyWith(enable: true));
      }
      await ref.read(setupActionProvider.notifier).setRunning(enable);
    },
  );
}

class OhosVpnControl extends StatefulWidget {
  const OhosVpnControl({
    super.key,
    required this.running,
    required this.ready,
    required this.onToggle,
    required this.onRefresh,
  });

  final AsyncValue<bool> running;
  final bool ready;
  final Future<void> Function(bool enable) onToggle;
  final VoidCallback onRefresh;

  @override
  State<OhosVpnControl> createState() => _OhosVpnControlState();
}

class _OhosVpnControlState extends State<OhosVpnControl> {
  bool? _pendingTarget;
  bool _failed = false;

  Future<void> _toggle() async {
    if (_pendingTarget != null ||
        (!widget.ready && widget.running.value != true) ||
        widget.running.isLoading)
      return;
    final target = widget.running.value != true;
    setState(() {
      _pendingTarget = target;
      _failed = false;
    });
    try {
      await widget.onToggle(target);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _pendingTarget = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final busy = _pendingTarget != null;
    final status = switch (_pendingTarget) {
      true => l10n.startVpn,
      false => l10n.stopVpn,
      null when _failed || widget.running.hasError => l10n.vpnActionFailed,
      null when !widget.ready && widget.running.value != true =>
        l10n.vpnNotReady,
      null when widget.running.isLoading => l10n.unknown,
      null => widget.running.value == true ? l10n.connected : l10n.disconnected,
    };
    final action = widget.running.value == true ? l10n.stop : l10n.start;
    return DashboardCard(
      semanticLabel: 'VPN · $status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          const DashboardCardHeader(glyph: AppGlyphs.vpn, title: 'VPN'),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  status,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(
                        color: _failed || widget.running.hasError
                            ? context.colorScheme.error
                            : context.colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (widget.running.hasError)
                IconButton(
                  tooltip: l10n.retry,
                  onPressed: busy ? null : widget.onRefresh,
                  icon: const GlyphIcon(AppGlyphs.refresh),
                )
              else
                FilledButton(
                  onPressed:
                      busy ||
                          (!widget.ready && widget.running.value != true) ||
                          widget.running.isLoading
                      ? null
                      : _toggle,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CommonCircleLoading(),
                        )
                      : Text(action),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
