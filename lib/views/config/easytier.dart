import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/easytier.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EasyTierPage extends StatelessWidget {
  const EasyTierPage({super.key});

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: 'EasyTier',
    body: ListView(children: const [EasyTierSettings()]),
  );
}

class EasyTierSettings extends ConsumerWidget {
  const EasyTierSettings({super.key});

  Future<void> _update(
    BuildContext context,
    WidgetRef ref, {
    bool? enable,
    bool? ipv6,
  }) async {
    final l10n = context.appLocalizations;
    if (ref.read(isStartProvider)) {
      globalState.showNotifier(l10n.easyTierStopBeforeEditing);
      return;
    }
    var props = ref.read(appSettingProvider).easyTier;
    if (ipv6 != null) {
      props = props.copyWith(ipv6: ipv6);
    } else if (enable == null || (enable && !isEasyTierConfigValid(props))) {
      final result = await globalState.showCommonDialog<EasyTierProps>(
        child: EasyTierConfigurationDialog(
          props: props.copyWith(enable: enable ?? props.enable),
        ),
      );
      if (result == null || !context.mounted) return;
      props = result;
    } else {
      props = props.copyWith(enable: enable);
    }
    if (props.enable) {
      final patch = ref.read(patchClashConfigProvider);
      if ([
        patch.mixedPort,
        patch.port,
        patch.socksPort,
        patch.redirPort,
        patch.tproxyPort,
      ].contains(easyTierSocksPort)) {
        globalState.showNotifier(l10n.portConflictTip);
        return;
      }
      ref
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(enable: true));
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.rule));
    }
    final nextProps = props;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(easyTier: nextProps));
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final props = ref.watch(
      appSettingProvider.select((state) => state.easyTier),
    );
    final routes = ref.watch(easyTierRoutesProvider);
    final routeStatus = switch (routes.status) {
      'starting' => l10n.easyTierRoutesStarting,
      'ready' => l10n.easyTierRoutesReady,
      _ => l10n.easyTierRoutesStopped,
    };
    return Column(
      children: [
        ListItem.switchItem(
          title: const Text('EasyTier'),
          subtitle: Text(l10n.easyTierDescription),
          delegate: SwitchDelegate(
            value: props.enable,
            onChanged: (value) => _update(context, ref, enable: value),
          ),
        ),
        const Divider(height: 0),
        ListItem(
          title: Text(l10n.easyTierConfiguration),
          subtitle: Text(
            props.networkName.isEmpty
                ? l10n.easyTierConfigureHint
                : [props.networkName, ...props.cidrs].join('\n'),
          ),
          onTap: () => _update(context, ref),
        ),
        const Divider(height: 0),
        ListItem.switchItem(
          title: Text(l10n.easyTierIpv6),
          subtitle: Text(l10n.easyTierIpv6Description),
          delegate: SwitchDelegate(
            value: props.ipv6,
            onChanged: (value) => _update(context, ref, ipv6: value),
          ),
        ),
        if (props.enable) ...[
          const Divider(height: 0),
          ListItem(
            title: Text(l10n.easyTierLearnedCidrs),
            subtitle: SelectableText(
              '$routeStatus\n${routes.activeCidrs.isEmpty ? l10n.easyTierRoutesEmpty : routes.activeCidrs.join('\n')}',
            ),
          ),
          if (routes.blockedCidrs.isNotEmpty)
            ListItem(
              title: Text(l10n.easyTierBlockedCidrs),
              subtitle: SelectableText(routes.blockedCidrs.join('\n')),
            ),
        ],
      ],
    );
  }
}

class EasyTierConfigurationDialog extends StatefulWidget {
  final EasyTierProps props;

  const EasyTierConfigurationDialog({super.key, required this.props});

  @override
  State<EasyTierConfigurationDialog> createState() =>
      _EasyTierConfigurationDialogState();
}

class _EasyTierConfigurationDialogState
    extends State<EasyTierConfigurationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _secret;
  late final TextEditingController _peers;
  late final TextEditingController _cidrs;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.props.networkName);
    _secret = TextEditingController(text: widget.props.networkSecret);
    _peers = TextEditingController(text: widget.props.peerUrls.join('\n'));
    _cidrs = TextEditingController(text: widget.props.cidrs.join('\n'));
  }

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    _peers.dispose();
    _cidrs.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      widget.props.copyWith(
        networkName: _name.text.trim(),
        networkSecret: _secret.text,
        peerUrls: splitEasyTierLines(_peers.text),
        cidrs: splitEasyTierLines(_cidrs.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return CommonDialog(
      title: l10n.easyTierConfiguration,
      actions: [TextButton(onPressed: _save, child: Text(l10n.save))],
      child: Form(
        key: _formKey,
        child: Wrap(
          runSpacing: 16,
          children: [
            Text(l10n.easyTierConfigureHint),
            TextFormField(
              controller: _name,
              maxLength: 128,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.easyTierNetworkName,
              ),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : l10n.emptyTip(l10n.easyTierNetworkName),
            ),
            TextFormField(
              controller: _secret,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 256,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.easyTierNetworkSecret,
              ),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : l10n.emptyTip(l10n.easyTierNetworkSecret),
            ),
            TextFormField(
              controller: _peers,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.easyTierPeerUrls,
                hintText: 'tcp://vpn.example.com:11010',
              ),
              validator: (value) {
                final peers = splitEasyTierLines(value ?? '');
                return peers.isNotEmpty && peers.every(isEasyTierPeerUrl)
                    ? null
                    : l10n.easyTierInvalidPeers;
              },
            ),
            TextFormField(
              controller: _cidrs,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.easyTierCidrs,
                hintText: '10.144.144.0/24\n192.168.50.0/24',
              ),
              validator: (value) {
                final cidrs = splitEasyTierLines(value ?? '');
                return cidrs.every(isEasyTierCidr)
                    ? null
                    : l10n.easyTierInvalidCidrs;
              },
            ),
          ],
        ),
      ),
    );
  }
}
