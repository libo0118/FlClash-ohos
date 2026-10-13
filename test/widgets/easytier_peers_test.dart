import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/easytier.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/easytier_peers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('easytier-render');
const _direct = EasyTierPeer(
  peerId: '42',
  hostname: 'office-gateway',
  ipv4: '10.126.126.42',
  connectionType: 'direct',
  latencyMs: 12.4,
  protocols: ['TCP'],
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
  String session = 'session-1',
  List<EasyTierPeer> peers = const [_direct, _relay],
}) => EasyTierRoutesState(
  sessionId: session,
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
    loader.addFont(
      File(fontPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await loader.load();
  });

  testWidgets('shows selectable IPs, node count and measured direct delay', (
    tester,
  ) async {
    await _pumpCard(tester, _state());

    expect(_selectable('10.126.126.159'), findsOneWidget);
    expect(_selectable('10.126.126.42'), findsOneWidget);
    expect(_selectable('office-gateway'), findsOneWidget);
    expect(find.text('Discovered nodes: 2'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('TCP'), findsOneWidget);
    expect(find.text('Delay 12 ms'), findsOneWidget);
    expect(find.text('Delay —'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopped and starting states hide old nodes and delay', (
    tester,
  ) async {
    await _pumpCard(tester, _state(status: 'stopped'));
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Start the VPN to view node status.'), findsOneWidget);
    expect(_selectable('10.126.126.42'), findsNothing);
    expect(_selectable('10.126.126.159'), findsNothing);
    expect(find.textContaining('Delay'), findsNothing);

    await _pumpCard(tester, _state(status: 'starting'));
    expect(find.text('Connecting'), findsOneWidget);
    expect(_selectable('10.126.126.42'), findsNothing);
    expect(find.textContaining('Delay'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale and unavailable nodes do not show old latency as live', (
    tester,
  ) async {
    for (final status in ['stale', 'unavailable']) {
      await _pumpCard(tester, _state(status: status));
      expect(_selectable('10.126.126.42'), findsOneWidget);
      expect(find.text('Delay 12 ms'), findsNothing);
      expect(find.text('Delay —'), findsNWidgets(2));
      expect(find.text('TCP'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('running empty state explains that no other nodes were found', (
    tester,
  ) async {
    await _pumpCard(tester, _state(peers: []));
    expect(find.text('Discovered nodes: 0'), findsOneWidget);
    expect(find.text('No other nodes discovered yet.'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('initially shows three nodes and expands or collapses all', (
    tester,
  ) async {
    await _pumpCard(tester, _state(peers: _nodes()), size: const Size(390, 1200));
    expect(_selectable('10.126.126.44'), findsOneWidget);
    expect(_selectable('10.126.126.45'), findsNothing);
    await tester.tap(find.text('Show all 5 nodes'));
    await tester.pumpAndSettle();
    expect(_selectable('10.126.126.45'), findsOneWidget);
    expect(_selectable('Node 46'), findsOneWidget);
    expect(_selectable('IPv4 not assigned'), findsOneWidget);
    await tester.tap(find.text('Collapse nodes'));
    await tester.pumpAndSettle();
    expect(_selectable('10.126.126.45'), findsNothing);

    await tester.tap(find.text('Show all 5 nodes'));
    await tester.pumpAndSettle();
    await _pumpCard(
      tester,
      _state(peers: _nodes(), session: 'session-2'),
      size: const Size(390, 1200),
    );
    expect(_selectable('10.126.126.45'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 px and enlarged text wrap long names and statuses', (
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
    );
    for (final status in ['ready', 'unavailable', 'stale']) {
      await _pumpCard(
        tester,
        _state(status: status, peers: const [peer]),
        size: const Size(320, 1200),
        textScale: 1.6,
        networkName: 'warehouse-production-network-with-a-long-name',
      );
      expect(_selectable(longName), findsOneWidget);
      expect(_selectable('192.168.255.254'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'exports real card renders in phone, wide and enlarged-text layouts',
    (tester) async {
      final cases = [
        ('phone-dark', const Size(390, 900), Brightness.dark, 1.0, 'ready'),
        ('phone-light', const Size(390, 900), Brightness.light, 1.0, 'ready'),
        ('wide', const Size(960, 800), Brightness.light, 1.0, 'ready'),
        ('phone-large-text', const Size(320, 1200), Brightness.dark, 1.6, 'ready'),
        ('phone-stale', const Size(390, 900), Brightness.dark, 1.0, 'stale'),
        ('phone-stopped', const Size(390, 900), Brightness.light, 1.0, 'stopped'),
      ];
      for (final (name, size, brightness, textScale, status) in cases) {
        await _pumpCard(
          tester,
          _state(status: status, peers: _nodes()),
          size: size,
          brightness: brightness,
          textScale: textScale,
          locale: const Locale('zh', 'CN'),
        );
        expect(tester.takeException(), isNull, reason: name);
        await _capture(tester, visualDir!, name);
      }
    },
    skip: visualDir == null || visualDir.isEmpty,
  );
}

Finder _selectable(String text) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == text,
);

Future<void> _pumpCard(
  WidgetTester tester,
  EasyTierRoutesState state, {
  Size size = const Size(390, 900),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Locale locale = const Locale('en'),
  String networkName = 'office-net',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(defaultPrimaryColor),
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.content,
        ),
        fontFamily: Platform.environment['EASYTIER_TEST_FONT'] == null
            ? null
            : 'EasyTierTestCjk',
      ),
      builder: (context, child) {
        globalState.theme = CommonTheme.of(context, textScale);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
      home: RepaintBoundary(
        key: _captureKey,
        child: Scaffold(
          appBar: AppBar(
            title: Builder(
              builder: (context) => Text(AppLocalizations.of(context).dashboard),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: EasyTierPeersCard(state: state, networkName: networkName),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String directory, String name) async {
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
