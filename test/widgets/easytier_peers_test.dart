import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/widgets/outbound_mode.dart';
import 'package:fl_clash/views/dashboard/widgets/ohos_vpn.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/easytier_peers.dart';
import 'package:fl_clash/views/config/easytier.dart';
import 'package:fl_clash/views/easytier/easytier.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';
import '../helpers/app_paths.dart';

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
    peerId: '44',
    hostname: 'workstation',
    ipv4: '10.126.126.44',
    connectionType: 'direct',
    latencyMs: 2.6,
    protocols: ['UDP'],
  ),
  const EasyTierPeer(
    peerId: '45',
    hostname: 'nas',
    ipv4: '10.126.126.45',
    connectionType: 'relay',
    latencyMs: null,
  ),
  const EasyTierPeer(
    peerId: '46',
    hostname: '',
    ipv4: null,
    connectionType: 'direct',
    latencyMs: null,
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
    final directory = await Directory.systemTemp.createTemp('easytier_widgets');
    addTearDown(() => directory.delete(recursive: true));
    await useAppPaths(directory);
    if (fontPath == null || fontPath.isEmpty) return;
    final loader = FontLoader('EasyTierTestCjk');
    loader.addFont(
      File(fontPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await loader.load();
    final iconPath = Platform.environment['EASYTIER_TEST_ICON_FONT'];
    if (iconPath != null) {
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          iconPath,
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await icons.load();
    }
  });

  testWidgets('homepage entry is one compact row without network details', (
    tester,
  ) async {
    var opened = 0;
    await _pumpBody(
      tester,
      EasyTierCompactTile(
        state: _state(peers: _nodes()),
        enabled: true,
        onTap: () => opened++,
      ),
    );
    expect(find.text('Running · 5 nodes'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('ms'), findsNothing);
    expect(tester.getSize(find.byKey(_entryKey)).height, lessThanOrEqualTo(80));
    await tester.tap(find.text('EasyTier'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('homepage entry remains compact and tappable in every state', (
    tester,
  ) async {
    var opened = 0;
    for (final status in [
      'starting',
      'stopped',
      'stale',
      'unavailable',
      'disabled',
    ]) {
      await _pumpBody(
        tester,
        EasyTierCompactTile(
          state: _state(status: status),
          enabled: status != 'disabled',
          onTap: () => opened++,
        ),
      );
      expect(
        tester.getSize(find.byKey(_entryKey)).height,
        lessThanOrEqualTo(80),
      );
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.text('EasyTier'));
      expect(tester.takeException(), isNull, reason: status);
    }
    expect(opened, 5);
    expect(find.text('Not enabled'), findsOneWidget);
  });

  testWidgets(
    'entry opens live details, settings, and returns through both pages',
    (tester) async {
      final container = _container(_state());
      addTearDown(container.dispose);
      await _pumpApp(
        tester,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: EasyTierDashboardTile(),
          ),
        ),
        container: container,
      );
      await tester.tap(find.text('EasyTier'));
      await tester.pumpAndSettle();
      expect(find.byType(EasyTierDetailsPage), findsOneWidget);
      expect(_selectable('office-gateway'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Network name')).dy,
        greaterThan(
          tester.getBottomLeft(find.byTooltip('EasyTier configuration')).dy,
        ),
      );
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
    },
  );

  testWidgets('disabled entry still opens details and configuration', (
    tester,
  ) async {
    final container = _container(_state(), enabled: false);
    addTearDown(container.dispose);
    await _pumpApp(
      tester,
      const Scaffold(body: EasyTierDashboardTile()),
      container: container,
    );
    await tester.tap(find.text('EasyTier'));
    await tester.pumpAndSettle();
    expect(find.text('Not enabled'), findsOneWidget);
    expect(
      find.text('Enable EasyTier in settings to view network and node status.'),
      findsOneWidget,
    );
    expect(_selectable('10.126.126.42'), findsNothing);
    await tester.tap(find.byTooltip('EasyTier configuration'));
    await tester.pumpAndSettle();
    expect(find.byType(EasyTierPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail Consumer updates telemetry without reopening the page', (
    tester,
  ) async {
    final container = _container(_state());
    addTearDown(container.dispose);
    await _pumpApp(tester, const EasyTierDetailsPage(), container: container);
    container.read(easyTierRoutesProvider.notifier).applySnapshot({
      'sessionId': 'session-1',
      'revision': 1,
      'status': 'ready',
      'cidrs': [],
      'peerStatus': 'ready',
      'capturedAt': DateTime.now().millisecondsSinceEpoch,
      'virtualIpv4': '10.126.126.159',
      'peers': [
        {
          'peerId': '42',
          'hostname': 'updated-gateway',
          'ipv4': '10.126.126.42',
          'connectionType': 'direct',
          'latencyMs': 7,
          'protocols': ['tcp'],
          'connections': [],
        },
      ],
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

  testWidgets('details show all selectable nodes and measured direct delay', (
    tester,
  ) async {
    await _pumpDetails(
      tester,
      _state(peers: _nodes()),
      size: const Size(390, 1200),
    );
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
    expect(
      _selectable('TCP 192.168.6.159:45000 → 192.168.6.183:11010'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopped and starting details hide old nodes and local address', (
    tester,
  ) async {
    for (final status in ['stopped', 'starting']) {
      await _pumpDetails(tester, _state(status: status));
      expect(_selectable('10.126.126.42'), findsNothing);
      expect(_selectable('10.126.126.159'), findsNothing);
      expect(find.text('12 ms'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Connecting to the EasyTier network.'), findsOneWidget);
  });

  testWidgets(
    'stale and unavailable details never show old delay or endpoints as live',
    (tester) async {
      for (final status in ['stale', 'unavailable']) {
        await _pumpDetails(tester, _state(status: status));
        expect(_selectable('10.126.126.42'), findsOneWidget);
        expect(find.text('12 ms'), findsNothing);
        expect(find.text('—'), findsNWidgets(2));
        expect(find.text('TCP'), findsNothing);
        expect(
          _selectable('TCP 192.168.6.159:45000 → 192.168.6.183:11010'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('empty details explain that no nodes were discovered', (
    tester,
  ) async {
    await _pumpDetails(tester, _state(peers: []));
    expect(find.text('Discovered nodes: 0'), findsOneWidget);
    expect(find.text('No other nodes discovered yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 dp enlarged text wraps names, IPs, endpoints and status', (
    tester,
  ) async {
    const longName =
        'warehouse-control-room-long-hostname-0123456789-abcdefghijklmnop';
    const peer = EasyTierPeer(
      peerId: '47',
      hostname: longName,
      ipv4: '192.168.255.254',
      connectionType: 'direct',
      latencyMs: 142.8,
      protocols: ['TCP', 'UDP'],
      connections: [
        'TCP [2001:db8:abcd:1234:5678:9012:3456:7890]:54321 → [2001:db8:abcd:ffff::1111]:11010',
      ],
    );
    for (final status in ['ready', 'unavailable', 'stale']) {
      await _pumpDetails(
        tester,
        _state(status: status, peers: const [peer]),
        size: const Size(320, 1200),
        textScale: 1.6,
        networkName: 'warehouse-production-network-with-a-long-name',
      );
      expect(_selectable(longName), findsOneWidget);
      expect(_selectable('192.168.255.254'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: status);
    }
    await _pumpBody(
      tester,
      EasyTierCompactTile(
        state: _state(status: 'unavailable'),
        enabled: true,
        onTap: () {},
      ),
      size: const Size(320, 900),
      textScale: 1.6,
    );
    expect(find.byKey(_entryKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact entry follows the saved cards in the real dashboard', (
    tester,
  ) async {
    await _pumpApp(tester, _HomepageFixture(state: _state()));
    final entry = tester.getTopLeft(find.byKey(_entryKey)).dy;
    for (final type in [OutboundModeCard, OhosVpnControl]) {
      expect(entry, greaterThan(tester.getBottomLeft(find.byType(type)).dy));
    }
    expect(tester.getSize(find.byKey(_entryKey)).height, lessThanOrEqualTo(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('EasyTier IPv6 switch persists independently of FlClash IPv6', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(
            easyTier: EasyTierProps(
              enable: true,
              networkName: 'test',
              networkSecret: 'test',
              peerUrls: ['tcp://test.invalid:11010'],
            ),
          ),
        ),
        vpnSettingProvider.overrideWithBuild(
          (_, _) => const VpnProps(ipv6: true),
        ),
        setupActionProvider.overrideWith(_SettingsSetup.new),
      ],
    );
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

  testWidgets('OHOS dashboard editor removes and restores the EasyTier card', (
    tester,
  ) async {
    final container = _container(_state());
    addTearDown(container.dispose);
    await _pumpApp(
      tester,
      _HomepageFixture(state: _state()),
      container: container,
      size: const Size(390, 1400),
    );
    final original = container.read(appSettingProvider).dashboardWidgets;
    await tester.tap(find.byTooltip('Edit dashboard'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byTooltip('Remove EasyTier'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      container.read(appSettingProvider).dashboardWidgets,
      original.where((item) => item != DashboardWidget.easyTier).toList(),
    );
    final saved = AppSettingProps.fromJson(
      jsonDecode(jsonEncode(container.read(appSettingProvider).toJson()))
          as Map<String, Object?>,
    );
    expect(saved.dashboardWidgets, isNot(contains(DashboardWidget.easyTier)));
    final add = find.byTooltip('Add EasyTier');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump(const Duration(milliseconds: 800));
    expect(container.read(appSettingProvider).dashboardWidgets, original);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('OHOS native refresh never falls back to optimistic running', (
    tester,
  ) async {
    var request = Completer<bool>()..complete(true);
    final container = _container(_state(), vpnStatus: (_) => request.future);
    addTearDown(container.dispose);
    await _pumpApp(
      tester,
      _HomepageFixture(state: _state()),
      container: container,
    );
    expect(find.text('Running'), findsOneWidget);
    request = Completer<bool>();
    container.invalidate(ohosVpnRunningProvider);
    await tester.pump();
    expect(container.read(isStartProvider), isTrue);
    expect(container.read(ohosVpnRunningProvider).hasValue, isTrue);
    expect(find.text('Unknown'), findsNWidgets(2));
    expect(find.text('Running'), findsNothing);
    expect(find.text('Connected'), findsNothing);
    request.completeError(StateError('native unavailable'), StackTrace.empty);
    await tester.pump();
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(OhosVpnControl),
        matching: find.byTooltip('Retry'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exports real compact homepage and independent details renders', (
    tester,
  ) async {
    for (final (name, brightness, textScale, status) in [
      ('home-dark', Brightness.dark, 1.0, 'ready'),
      ('home-light', Brightness.light, 1.0, 'ready'),
      ('home-large-text', Brightness.dark, 1.6, 'ready'),
      ('home-stale', Brightness.dark, 1.0, 'stale'),
      ('home-disabled', Brightness.light, 1.0, 'disabled'),
      ('home-loading', Brightness.light, 1.0, 'loading'),
    ]) {
      await _pumpApp(
        tester,
        _HomepageFixture(
          state: _state(status: status, peers: _nodes()),
          enabled: status != 'disabled',
        ),
        size: const Size(390, 900),
        brightness: brightness,
        textScale: textScale,
        locale: const Locale('zh', 'CN'),
      );
      expect(tester.takeException(), isNull, reason: name);
      await _capture(tester, visualDir!, name);
    }
    await _pumpApp(
      tester,
      _HomepageFixture(state: _state()),
      size: const Size(360, 900),
      brightness: Brightness.light,
      locale: const Locale('zh', 'CN'),
    );
    await _capture(tester, visualDir!, 'home-narrow');
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is GlyphIcon && widget.glyph == AppGlyphs.edit,
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await _capture(tester, visualDir, 'home-edit');
    final previousCounts = globalState.lastConfigCounts;
    addTearDown(() => globalState.lastConfigCounts = previousCounts);
    globalState.lastConfigCounts = (groups: 0, proxies: 0, rules: 0);
    await _pumpApp(
      tester,
      _HomepageFixture(state: _state(), platform: SupportPlatform.Linux),
      size: const Size(1280, 900),
      brightness: Brightness.light,
      locale: const Locale('zh', 'CN'),
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, visualDir, 'home-desktop');
    globalState.lastConfigCounts = previousCounts;
    for (final brightness in Brightness.values) {
      final container = _container(_state(status: 'stopped'), running: false);
      addTearDown(container.dispose);
      await _pumpApp(
        tester,
        const EasyTierPage(),
        container: container,
        size: const Size(360, 900),
        brightness: brightness,
        locale: const Locale('zh', 'CN'),
      );
      await _capture(tester, visualDir, 'settings-${brightness.name}');
      await tester.tap(find.widgetWithText(ListItem, 'EasyTier 配置'));
      await tester.pumpAndSettle();
      expect(find.byType(EasyTierConfigurationDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, visualDir, 'configuration-${brightness.name}');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    for (final (name, size, brightness, textScale, status) in [
      ('detail-dark', const Size(390, 900), Brightness.dark, 1.0, 'ready'),
      ('detail-light', const Size(390, 900), Brightness.light, 1.0, 'ready'),
      ('detail-wide', const Size(960, 800), Brightness.light, 1.0, 'ready'),
      (
        'detail-large-text',
        const Size(320, 1200),
        Brightness.dark,
        1.6,
        'ready',
      ),
      ('detail-stale', const Size(390, 900), Brightness.dark, 1.0, 'stale'),
      (
        'detail-stopped',
        const Size(390, 900),
        Brightness.light,
        1.0,
        'stopped',
      ),
      (
        'detail-disabled',
        const Size(390, 900),
        Brightness.light,
        1.0,
        'disabled',
      ),
    ]) {
      final container = _container(
        _state(status: status, peers: _nodes()),
        enabled: status != 'disabled',
      );
      await _pumpApp(
        tester,
        const Scaffold(body: EasyTierDashboardTile()),
        container: container,
        size: size,
        brightness: brightness,
        textScale: textScale,
        locale: const Locale('zh', 'CN'),
      );
      await tester.tap(find.text('EasyTier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      await _capture(tester, visualDir, name);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  }, skip: visualDir == null || visualDir.isEmpty);
}

Finder _selectable(String text) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == text,
);

ProviderContainer _container(
  EasyTierRoutesState state, {
  bool enabled = true,
  bool running = true,
  Future<bool> Function(Ref)? vpnStatus,
}) => ProviderContainer(
  overrides: [
    appSettingProvider.overrideWithBuild(
      (_, _) => AppSettingProps(
        easyTier: EasyTierProps(
          enable: enabled,
          networkName: 'office-net',
          networkSecret: 'test-secret',
          peerUrls: const ['tcp://gateway.invalid:11010'],
        ),
        dashboardWidgets: const [
          DashboardWidget.currentOutbound,
          DashboardWidget.outboundMode,
          DashboardWidget.vpnButton,
          DashboardWidget.easyTier,
        ],
      ),
    ),
    easyTierRoutesProvider.overrideWith(() => _RoutesFixture(state)),
    profilesProvider.overrideWith(
      () => TestProfiles(const [
        Profile(
          id: 1,
          label: 'Office subscription',
          autoUpdateDuration: Duration.zero,
        ),
      ]),
    ),
    currentProfileIdProvider.overrideWithBuild((_, _) => 1),
    localIpProvider.overrideWithBuild((_, _) => '192.168.6.159'),
    initProvider.overrideWithBuild((_, _) => true),
    runTimeProvider.overrideWithBuild((_, _) => running ? 120000 : null),
    coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
    suspendProvider.overrideWithValue(false),
    outboundIpProbeProvider.overrideWith(
      () => _IpsFixture(loading: state.peerStatus == 'loading'),
    ),
    ipQualityProvider.overrideWith(
      (_, ip) async => IpQuality(
        ip: ip,
        source: IpQualitySource.ipLocate,
        type: IpType.residential,
        organization: 'Office Broadband',
        asn: 64512,
      ),
    ),
    ohosVpnRunningProvider.overrideWith(vpnStatus ?? (ref) async => running),
    setupActionProvider.overrideWith(_SettingsSetup.new),
  ],
);

Future<void> _pumpDetails(
  WidgetTester tester,
  EasyTierRoutesState state, {
  Size size = const Size(390, 900),
  double textScale = 1,
  String networkName = 'office-net',
}) => _pumpBody(
  tester,
  EasyTierDetailsBody(state: state, networkName: networkName, enabled: true),
  size: size,
  textScale: textScale,
);

Future<void> _pumpBody(
  WidgetTester tester,
  Widget content, {
  Size size = const Size(390, 900),
  double textScale = 1,
  ProviderContainer? container,
}) => _pumpApp(
  tester,
  Scaffold(
    appBar: AppBar(title: const Text('Dashboard')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SizedBox(width: double.infinity, child: content),
    ),
  ),
  size: size,
  textScale: textScale,
  container: container,
);

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 900),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Locale locale = const Locale('en'),
  ProviderContainer? container,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (home is _HomepageFixture && container == null) {
    container = _container(home.state, enabled: home.enabled);
    addTearDown(container.dispose);
  }
  if (container == null) {
    container = _container(_state());
    addTearDown(container.dispose);
  }
  globalState.container = container;
  container.read(viewSizeProvider.notifier).value = size;
  final app = TestApp(
    locale: locale,
    theme: ThemeData(
      colorScheme: seededColorScheme(
        seedColor: const Color(defaultPrimaryColor),
        brightness: brightness,
      ),
      fontFamily: Platform.environment['EASYTIER_TEST_FONT'] == null
          ? null
          : 'EasyTierTestCjk',
    ).withAppShapes.withAppSurfaces.withAppTypography,
    appBuilder: (context, child) => RepaintBoundary(
      key: _captureKey,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    ),
    child: home,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: app),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _capture(
  WidgetTester tester,
  String directory,
  String name,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG render returned no bytes');
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/easytier-$name.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
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

class _IpsFixture extends OutboundIpProbe {
  _IpsFixture({this.loading = false});

  final bool loading;

  @override
  RoutedProbeState<String, IpInfo> build() => RoutedProbeState({
    routedOutbound: loading
        ? const ProbeEntry(phase: ProbePhase.probing)
        : const ProbeEntry(
            phase: ProbePhase.fresh,
            value: IpInfo(ip: '203.0.113.159', countryCode: 'CN'),
          ),
  });

  @override
  void watch(String target) {}

  @override
  void unwatch(String target) {}
}

class _HomepageFixture extends StatelessWidget {
  final EasyTierRoutesState state;
  final bool enabled;
  final SupportPlatform platform;
  const _HomepageFixture({
    required this.state,
    this.enabled = true,
    this.platform = SupportPlatform.ohos,
  });

  @override
  Widget build(BuildContext context) => DashboardView(platform: platform);
}
