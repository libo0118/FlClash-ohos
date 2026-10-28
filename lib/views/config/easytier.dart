import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/easytier.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EasyTierPage extends StatelessWidget {
  const EasyTierPage({super.key});

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: context.appLocalizations.easyTierConfiguration,
    body: Builder(
      builder: (context) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: const [EasyTierSettings()],
      ),
    ),
  );
}

Future<void> updateEasyTierSettings(
  BuildContext context,
  WidgetRef ref, {
  bool? enable,
  bool? ipv6,
}) async {
  final l10n = context.appLocalizations;
  if (ref.read(isStartProvider)) {
    context.showNotifier(l10n.easyTierStopBeforeEditing);
    return;
  }
  var props = ref.read(appSettingProvider).easyTier;
  if (ipv6 != null) {
    props = props.copyWith(ipv6: ipv6);
  } else if (enable == null || (enable && !isEasyTierConfigValid(props))) {
    final result = await showFormSheet<EasyTierProps>(
      context: context,
      builder: (_) => EasyTierConfigurationDialog(
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
      context.showNotifier(l10n.portConflictTip);
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

class EasyTierSettings extends ConsumerWidget {
  const EasyTierSettings({super.key});

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
      'stopped' => l10n.easyTierRoutesStopped,
      _ => l10n.easyTierPeersUnavailableHint,
    };
    return Column(
      children: [
        generateSection(
          items: [
            ConfigToggleItem(
              title: (l) => 'EasyTier',
              selector: appSettingProvider.select(
                (state) => state.easyTier.enable,
              ),
              onChanged: (ref, value) =>
                  updateEasyTierSettings(context, ref, enable: value),
            ),
            ListItem(
              title: Text(l10n.easyTierConfiguration),
              subtitle: Text(
                props.networkName.isEmpty ? l10n.none : props.networkName,
              ),
              onTap: () => updateEasyTierSettings(context, ref),
            ),
          ],
          footer: l10n.easyTierDescription,
        ),
        generateSection(
          items: [
            ConfigToggleItem(
              title: (l) => l.easyTierIpv6,
              selector: appSettingProvider.select(
                (state) => state.easyTier.ipv6,
              ),
              onChanged: (ref, value) =>
                  updateEasyTierSettings(context, ref, ipv6: value),
            ),
          ],
          footer: l10n.easyTierIpv6Description,
        ),
        if (props.enable)
          generateSection(
            title: l10n.easyTierLearnedCidrs,
            items: [
              ListItem(
                title: SelectableText(
                  routes.activeCidrs.isEmpty
                      ? l10n.easyTierRoutesEmpty
                      : routes.activeCidrs.join('\n'),
                ),
              ),
              if (routes.blockedCidrs.isNotEmpty)
                ListItem(
                  title: Text(l10n.easyTierBlockedCidrs),
                  subtitle: SelectableText(routes.blockedCidrs.join('\n')),
                ),
            ],
            footer: routeStatus,
          ),
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
  String? _error;
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
    final l10n = context.appLocalizations;
    final peers = splitEasyTierLines(_peers.text);
    final cidrs = splitEasyTierLines(_cidrs.text);
    final error = _name.text.trim().isEmpty
        ? l10n.emptyTip(l10n.easyTierNetworkName)
        : _secret.text.trim().isEmpty
        ? l10n.emptyTip(l10n.easyTierNetworkSecret)
        : peers.isEmpty || !peers.every(isEasyTierPeerUrl)
        ? l10n.easyTierInvalidPeers
        : !cidrs.every(isEasyTierCidr)
        ? l10n.easyTierInvalidCidrs
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      widget.props.copyWith(
        networkName: _name.text.trim(),
        networkSecret: _secret.text,
        peerUrls: peers,
        cidrs: cidrs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return FormPage(
      title: l10n.easyTierConfiguration,
      onSave: _save,
      error: _error,
      children: [
        generateSection(
          items: [
            FormRow(
              title: l10n.easyTierNetworkName,
              trailing: FormRowTextField(
                controller: _name,
                autocorrect: false,
                inputFormatters: TextInputLimits.limit(128),
                textInputAction: TextInputAction.next,
              ),
            ),
            FormRow(
              title: l10n.easyTierNetworkSecret,
              trailing: FormRowSecretTextField(
                controller: _secret,
                inputFormatters: TextInputLimits.limit(256),
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
          footer: l10n.easyTierConfigureHint,
        ),
        generateSection(
          title: l10n.easyTierPeerUrls,
          items: [
            ListItem(
              title: TextFormField(
                controller: _peers,
                autocorrect: false,
                maxLines: null,
                decoration: const InputDecoration.collapsed(
                  hintText: 'tcp://vpn.example.com:11010',
                ),
              ),
            ),
          ],
        ),
        generateSection(
          title: l10n.easyTierCidrs,
          items: [
            ListItem(
              title: TextFormField(
                controller: _cidrs,
                autocorrect: false,
                maxLines: null,
                decoration: const InputDecoration.collapsed(
                  hintText: '10.144.144.0/24\n192.168.50.0/24',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
