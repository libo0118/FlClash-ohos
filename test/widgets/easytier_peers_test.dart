import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/easytier_peers.dart';
import 'package:fl_clash/views/config/easytier.dart';
import 'package:fl_clash/views/easytier/easytier.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _captureKey = ValueKey('easytier-render');
const _entryKey = ValueKey('easytier-dashboard-entry');
const _direct = EasyTierPeer(
  peerId: '42',
  hostname: 'office-gateway',
  ipv4: '10.126.126.42',
  connectionType: 'direct',
  latencyMs: 12.4,
  protocols: ['TCP'],
  connections: ['TCP 192.168.6.159:45000 → 192.168.6.183:11010'],
);
const _relay = EasyTierPeer(
  peerId: '43',
  hostname: 'warehouse-server',
  ipv4: '10.126.126.43',
  connectionType: 'relay',
  latencyMs: null,
);

List<EasyTierPeer> _nodes() => [
  _direct,
  _relay,
  const EasyTierPeer(
    peerId: '44', hostname: 'workstation', ipv4: '10.126.126.44',
    connectionType: 'direct', latencyMs: 2.6, protocols: ['UDP'],
  ),
  const EasyTierPeer(
    peerId: '45', hostname: 'nas', ipv4: '10.126.126.45',
    connectionType: 'relay', latencyMs: null,
  ),
  const EasyTierPeer(
    peerId: '46', hostname: '', ipv4: null,
    connectionType: 'direct', latencyMs: null,
  ),
];

EasyTierRoutesState _state({
  String status = 'ready',
  List<EasyTierPeer> peers = const [_direct, _relay],
}) => EasyTierRoutesState(
  sessionId: 'session-1',
  status: status == 'ready' ? 'ready' : 'stopped',
  peerStatus: status,
  virtualIpv4: '10.126.126.159',
  peers: peers,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['EASYTIER_TEST_FONT'];
  final visualDir = Platform.environment['EASYTIER_VISUAL_DIR'];

  setUpAll(() async {
    if (fontPath == null || fontPath.isEmpty) return;
    final loader = FontLoader('EasyTierTestCjk');
    loader.addFont(File(fontPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
    final iconPath = Platform.environment['EASYTIER_TEST_ICON_FONT'];
    if (iconPath != null) {
      final icons = FontLoader('MaterialIcons');
      icons.addFont(File(iconPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
      await icons.load();
    }
  });

  testWidgets('homepage entry is one compact row without network details', (tester) async {
    var opened = 0;
    await _pumpBody(tester, EasyTierCompactTile(state: _state(peers: _nodes()), enabled: true, onTap: () => opened++));
    expect(find.text('Running · 5 nodes'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('ms'), findsNothing);
    expect(tester.getSize(find.byKey(_entryKey)).height, lessThanOrEqualTo(80));
    await tester.tap(find.text('EasyTier'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('homepage entry remains compact and tappable in every state', (tester) async {
    var opened = 0;
    for (final status in ['starting', 'stopped', 'stale', 'unavailable', 'disabled']) {
      await _pumpBody(tester, EasyTierCompactTile(state: _state(status: status), enabled: status != 'disabled', onTap: () => opened++));
      expect(tester.getSize(find.byKey(_entryKey)).height, lessThanOrEqualTo(80));
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.text('EasyTier'));
      expect(tester.takeException(), isNull, reason: status);
    }
    expect(opened, 5);
    expect(find.text('Not enabled'), findsOneWidget);
  });

  testWidgets('entry opens live details, settings, and returns through both pages', (tester) async {
    final container = _container(_state());
    addTearDown(container.dispose);
    await _pumpApp(tester, const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: EasyTierDashboardTile())), container: container);
    await tester.tap(find.text('EasyTier'));
    await tester.pumpAndSettle();
    expect(find.byType(EasyTierDetailsPage), findsOneWidget);
    expect(_selectable('office-gateway'), findsOneWidget);
    await tester.tap(find.byTooltip('EasyTier configuration'));
    await tester.pumpAndSettle();
    expect(find.byType(EasyTierPage), findsOneWidget);
    expect(find.text('EasyTier IPv6'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(EasyTierDetailsPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(EasyTierDashboardTile), findsOneWidget);
    expect(find.byType(EasyTierDetailsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled entry still opens details and configuration', (tester) async {
    final container = _container(_state(), enabled: false);
    addTearDown(container.dispose);
    await _pumpApp(tester, const Scaffold(body: EasyTierDashboardTile()), container: container);
    await tester.tap(find.text('EasyTier'));
    await tester.pumpAndSettle();
    expect(find.text('Not enabled'), findsOneWidget);
    expect(find.text('Enable EasyTier in settings to view network and node status.'), findsOneWidget);
    expect(_selectable('10.126.126.42'), findsNothing);
    await tester.tap(find.byTooltip('EasyTier configuration'));
    await tester.pumpAndSettle();
    expect(find.byType(EasyTierPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail Consumer updates telemetry without reopening the page', (tester) async {
    final container = _container(_state());
    addTearDown(container.dispose);
    await _pumpApp(tester, const EasyTierDetailsPage(), container: container);
    container.read(easyTierRoutesProvider.notifier).applySnapshot({
      'sessionId': 'session-1', 'revision': 1, 'status': 'ready', 'cidrs': [],
      'peerStatus': 'ready', 'capturedAt': DateTime.now().millisecondsSinceEpoch,
      'virtualIpv4': '10.126.126.159',
      'peers': [{
        'peerId': '42', 'hostname': 'updated-gateway', 'ipv4': '10.126.126.42',
        'connectionType': 'direct', 'latencyMs': 7, 'protocols': ['tcp'], 'connections': [],
      }],
    });
    await tester.pumpAndSettle();
    expect(_selectable('updated-gateway'), findsOneWidget);
    expect(_selectable('office-gateway'), findsNothing);
    expect(find.text('7.0 ms'), findsOneWidget);
    expect(find.text('Discovered nodes: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    container.read(easyTierRoutesProvider.notifier).markStopped();
    await tester.pumpAndSettle();
  });

  testWidgets('details show all selectable nodes and measured direct delay', (tester) async {
    await _pumpDetails(tester, _state(peers: _nodes()), size: const Size(390, 1200));
    expect(_selectable('10.126.126.159'), findsOneWidget);
    expect(_selectable('10.126.126.42'), findsOneWidget);
    expect(_selectable('office-gateway'), findsOneWidget);
    expect(_selectable('10.126.126.45'), findsOneWidget);
    expect(_selectable('Node 46'), findsOneWidget);
    expect(_selectable('IPv4 not assigned'), findsOneWidget);
    expect(find.text('Discovered nodes: 5'), findsOneWidget);
    expect(find.text('Direct'), findsNWidgets(3));
    expect(find.text('Relay'), findsNWidgets(2));
    expect(find.text('12 ms'), findsOneWidget);
    expect(find.text('2.6 ms'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(_selectable('TCP 192.168.6.159:45000 → 192.168.6.183:11010'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopped and starting details hide old nodes and local address', (tester) async {
    for (final status in ['stopped', 'starting']) {
      await _pumpDetails(tester, _state(status: status));
      expect(_selectable('10.126.126.42'), findsNothing);
      expect(_selectable('10.126.126.159'), findsNothing);
      expect(find.text('12 ms'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Connecting to the EasyTier network.'), findsOneWidget);
  });

  testWidgets('stale and unavailable details never show old delay or endpoints as live', (tester) async {
    for (final status in ['stale', 'unavailable']) {
      await _pumpDetails(tester, _state(status: status));
      expect(_selectable('10.126.126.42'), findsOneWidget);
      expect(find.text('12 ms'), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('TCP'), findsNothing);
      expect(_selectable('TCP 192.168.6.159:45000 → 192.168.6.183:11010'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('empty details explain that no nodes were discovered', (tester) async {
    await _pumpDetails(tester, _state(peers: []));
    expect(find.text('Discovered nodes: 0'), findsOneWidget);
    expect(find.text('No other nodes discovered yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 px enlarged text wraps names, IPs, endpoints and status', (tester) async {
    const longName = 'warehouse-control-room-long-hostname-0123456789-abcdefghijklmnop';
    const peer = EasyTierPeer(
      peerId: '47', hostname: longName, ipv4: '192.168.255.254',
      connectionType: 'direct', latencyMs: 142.8, protocols: ['TCP', 'UDP'],
      connections: ['TCP [2001:db8:abcd:1234:5678:9012:3456:7890]:54321 → [2001:db8:abcd:ffff::1111]:11010'],
    );
    for (final status in ['ready', 'unavailable', 'stale']) {
      await _pumpDetails(tester, _state(status: status, peers: const [peer]),
        size: const Size(320, 1200), textScale: 1.6,
        networkName: 'warehouse-production-network-with-a-long-name');
      expect(_selectable(longName), findsOneWidget);
      expect(_selectable('192.168.255.254'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: status);
    }
    await _pumpBody(tester, EasyTierCompactTile(state: _state(status: 'unavailable'), enabled: true, onTap: () {}), size: const Size(320, 900), textScale: 1.6);
    expect(find.byKey(_entryKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact entry follows the normal dashboard cards in the real Grid', (tester) async {
    await _pumpApp(tester, _HomepageFixture(state: _state()));
    final entry = tester.getTopLeft(find.byKey(_entryKey)).dy;
    for (final id in ['outbound', 'network', 'traffic', 'intranet']) {
      expect(entry, greaterThan(tester.getBottomLeft(find.byKey(ValueKey(id))).dy));
    }
    expect(tester.getSize(find.byKey(_entryKey)).height, lessThanOrEqualTo(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('EasyTier IPv6 switch persists independently of FlClash IPv6', (tester) async {
    final container = ProviderContainer(overrides: [
      appSettingProvider.overrideWithBuild((_, _) => const AppSettingProps(
        easyTier: EasyTierProps(enable: true, networkName: 'test', networkSecret: 'test', peerUrls: ['tcp://test.invalid:11010']),
      )),
      vpnSettingProvider.overrideWithBuild((_, _) => const VpnProps(ipv6: true)),
      setupActionProvider.overrideWith(_SettingsSetup.new),
    ]);
    addTearDown(container.dispose);
    final vpnState = container.listen(vpnSettingProvider, (_, _) {});
    addTearDown(vpnState.close);
    await _pumpBody(tester, const EasyTierSettings(), container: container);
    expect(container.read(appSettingProvider).easyTier.ipv6, false);
    await tester.tap(find.text('EasyTier IPv6'));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).easyTier.ipv6, true);
    expect(container.read(vpnSettingProvider).ipv6, true);
    await tester.tap(find.text('EasyTier IPv6'));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).easyTier.ipv6, false);
    expect(container.read(vpnSettingProvider).ipv6, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exports real compact homepage and independent details renders', (tester) async {
    for (final (name, brightness, textScale, status) in [
      ('home-dark', Brightness.dark, 1.0, 'ready'),
      ('home-light', Brightness.light, 1.0, 'ready'),
      ('home-large-text', Brightness.dark, 1.6, 'ready'),
      ('home-stale', Brightness.dark, 1.0, 'stale'),
      ('home-disabled', Brightness.light, 1.0, 'disabled'),
    ]) {
      await _pumpApp(tester, _HomepageFixture(state: _state(status: status, peers: _nodes()), enabled: status != 'disabled'),
        size: const Size(390, 900), brightness: brightness, textScale: textScale, locale: const Locale('zh', 'CN'));
      expect(tester.takeException(), isNull, reason: name);
      await _capture(tester, visualDir!, name);
    }
    for (final (name, size, brightness, textScale, status) in [
      ('detail-dark', const Size(390, 900), Brightness.dark, 1.0, 'ready'),
      ('detail-light', const Size(390, 900), Brightness.light, 1.0, 'ready'),
      ('detail-wide', const Size(960, 800), Brightness.light, 1.0, 'ready'),
      ('detail-large-text', const Size(320, 1200), Brightness.dark, 1.6, 'ready'),
      ('detail-stale', const Size(390, 900), Brightness.dark, 1.0, 'stale'),
      ('detail-stopped', const Size(390, 900), Brightness.light, 1.0, 'stopped'),
      ('detail-disabled', const Size(390, 900), Brightness.light, 1.0, 'disabled'),
    ]) {
      final container = _container(_state(status: status, peers: _nodes()), enabled: status != 'disabled');
      await _pumpApp(tester, const Scaffold(body: EasyTierDashboardTile()), container: container,
        size: size, brightness: brightness, textScale: textScale, locale: const Locale('zh', 'CN'));
      await tester.tap(find.text('EasyTier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      await _capture(tester, visualDir!, name);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  }, skip: visualDir == null || visualDir.isEmpty);
}

Finder _selectable(String text) => find.byWidgetPredicate((widget) => widget is SelectableText && widget.data == text);

ProviderContainer _container(EasyTierRoutesState state, {bool enabled = true}) => ProviderContainer(overrides: [
  appSettingProvider.overrideWithBuild((_, _) => AppSettingProps(easyTier: EasyTierProps(enable: enabled, networkName: 'office-net'))),
  easyTierRoutesProvider.overrideWith(() => _RoutesFixture(state)),
  isMobileViewProvider.overrideWithValue(true),
]);

Future<void> _pumpDetails(WidgetTester tester, EasyTierRoutesState state, {
  Size size = const Size(390, 900), double textScale = 1, String networkName = 'office-net',
}) => _pumpBody(tester, EasyTierDetailsBody(state: state, networkName: networkName, enabled: true), size: size, textScale: textScale);

Future<void> _pumpBody(WidgetTester tester, Widget content, {
  Size size = const Size(390, 900), double textScale = 1, ProviderContainer? container,
}) => _pumpApp(tester, Scaffold(appBar: AppBar(title: const Text('Dashboard')), body: SingleChildScrollView(
  padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: content),
)), size: size, textScale: textScale, container: container);

Future<void> _pumpApp(WidgetTester tester, Widget home, {
  Size size = const Size(390, 900), Brightness brightness = Brightness.light,
  double textScale = 1, Locale locale = const Locale('en'), ProviderContainer? container,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (container != null) globalState.container = container;
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate, GlobalWidgetsLocalizations.delegate],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(defaultPrimaryColor), brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.content),
      fontFamily: Platform.environment['EASYTIER_TEST_FONT'] == null ? null : 'EasyTierTestCjk',
    ),
    builder: (context, child) {
      globalState.theme = CommonTheme.of(context, textScale);
      return RepaintBoundary(key: _captureKey, child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!,
      ));
    },
    home: home,
  );
  await tester.pumpWidget(container == null ? app : UncontrolledProviderScope(container: container, child: app));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String directory, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG render returned no bytes');
    await Directory(directory).create(recursive: true);
    await File('$directory/easytier-$name.png').writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

class _RoutesFixture extends EasyTierRoutes {
  final EasyTierRoutesState initial;
  _RoutesFixture(this.initial);

  @override
  EasyTierRoutesState build() {
    super.build();
    return initial;
  }
}

class _SettingsSetup extends SetupAction {
  @override
  void build() {}

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {}
}

class _HomepageFixture extends StatelessWidget {
  final EasyTierRoutesState state;
  final bool enabled;
  const _HomepageFixture({required this.state, this.enabled = true});

  Widget _card(String id, String title, IconData icon, Widget content) => GridItem(
    crossAxisCellCount: 4,
    child: CommonCard(key: ValueKey(id), child: Column(mainAxisSize: MainAxisSize.min, children: [
      InfoHeader(info: Info(label: title, iconData: icon)),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: content),
    ])),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dashboard), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.edit))]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16).copyWith(bottom: 88), child: Grid(
        crossAxisCount: 8, crossAxisSpacing: 14, mainAxisSpacing: 14,
        children: [
          _card('outbound', l10n.outboundMode, Icons.alt_route, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (label, selected) in [(l10n.rule, true), (l10n.global, false), (l10n.direct, false)])
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked), const SizedBox(width: 8), Expanded(child: Text(label))])),
          ])),
          _card('network', l10n.networkDetection, Icons.public, const Text('203.0.113.24')),
          _card('traffic', l10n.trafficUsage, Icons.data_saver_off, Column(children: [
            const Icon(Icons.data_saver_off, size: 56), const SizedBox(height: 12),
            Text('↑ 128 KiB'), const SizedBox(height: 8), Text('↓ 2.4 MiB'),
          ])),
          _card('intranet', l10n.intranetIP, Icons.devices_outlined, const Text('192.168.6.159')),
          GridItem(crossAxisCellCount: 8, child: EasyTierCompactTile(state: state, enabled: enabled, onTap: () {})),
        ],
      )),
      floatingActionButton: FloatingActionButton.extended(onPressed: () {}, icon: const Icon(Icons.pause), label: const Text('00:12:36')),
      bottomNavigationBar: NavigationBar(selectedIndex: 0, destinations: [
        NavigationDestination(icon: const Icon(Icons.dashboard), label: l10n.dashboard),
        NavigationDestination(icon: const Icon(Icons.view_list), label: l10n.proxies),
        NavigationDestination(icon: const Icon(Icons.folder), label: l10n.profile),
        NavigationDestination(icon: const Icon(Icons.handyman), label: l10n.tools),
      ]),
    );
  }
}
