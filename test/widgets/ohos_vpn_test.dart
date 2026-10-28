import 'dart:async';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/dashboard/widgets/ohos_vpn.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  Future<void> pumpControl(
    WidgetTester tester, {
    AsyncValue<bool> running = const AsyncData(false),
    bool ready = true,
    required Future<void> Function(bool) onToggle,
    VoidCallback? onRefresh,
  }) async {
    await tester.pumpWidget(
      TestApp(
        homeBuilder: (child) => Scaffold(
          body: Center(child: SizedBox(width: 328, child: child)),
        ),
        child: OhosVpnControl(
          running: running,
          ready: ready,
          onToggle: onToggle,
          onRefresh: onRefresh ?? () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('only authoritative state displays connected', (tester) async {
    var changes = 0;
    final operation = Completer<void>();
    await pumpControl(
      tester,
      onToggle: (enable) {
        expect(enable, isTrue);
        changes++;
        return operation.future;
      },
    );
    expect(find.text('Disconnected'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Starting VPN…'), findsOneWidget);
    expect(find.byType(CommonCircleLoading), findsOneWidget);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    expect(changes, 1);
    operation.complete();
    await tester.pump();
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.byType(CommonCircleLoading), findsNothing);
    await pumpControl(
      tester,
      running: const AsyncData(true),
      onToggle: (_) async {},
    );
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('starting the card restores the disabled VPN setting first', (
    tester,
  ) async {
    final setup = _StartingSetup();
    final container = ProviderContainer(
      overrides: [
        vpnSettingProvider.overrideWithBuild(
          (_, _) => const VpnProps(enable: false),
        ),
        initProvider.overrideWithBuild((_, _) => true),
        profilesProvider.overrideWith(
          () => TestProfiles(const [
            Profile(id: 1, autoUpdateDuration: Duration.zero),
          ]),
        ),
        ohosVpnRunningProvider.overrideWith((_) async => false),
        setupActionProvider.overrideWith(() => setup),
      ],
    );
    addTearDown(container.dispose);
    final setting = container.listen(vpnSettingProvider, (_, _) {});
    addTearDown(setting.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold(body: OhosVpnCard())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(container.read(vpnSettingProvider).enable, isTrue);
    expect(setup.enabledAtStart, isTrue);
    expect(find.text('Connected'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed actions clear progress and permit retry', (tester) async {
    await pumpControl(
      tester,
      onToggle: (_) async => throw StateError('failure'),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(
      find.text('VPN change failed. Check the logs and retry.'),
      findsOneWidget,
    );
    expect(find.byType(CommonCircleLoading), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown and not ready never display success', (tester) async {
    await pumpControl(
      tester,
      running: const AsyncLoading(),
      onToggle: (_) async {},
    );
    expect(find.text('Unknown'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await pumpControl(tester, ready: false, onToggle: (_) async {});
    expect(
      find.text(
        'Finish initialization and select a profile to control the VPN.',
      ),
      findsOneWidget,
    );
    expect(find.text('Connected'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('failed native status offers a refresh', (tester) async {
    var refreshes = 0;
    await pumpControl(
      tester,
      running: AsyncError(StateError('unavailable'), StackTrace.empty),
      onToggle: (_) async {},
      onRefresh: () => refreshes++,
    );
    await tester.tap(find.byTooltip('Retry'));
    expect(refreshes, 1);
    expect(find.text('Connected'), findsNothing);
  });

  testWidgets(
    'a previous connected value is not shown during refresh failure',
    (tester) async {
      var refreshes = 0;
      var request = Completer<bool>();
      final status = FutureProvider<bool>((_) => request.future);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: Scaffold(
              body: Consumer(
                builder: (_, ref, _) => OhosVpnControl(
                  running: ref.watch(status),
                  ready: true,
                  onToggle: (_) async {},
                  onRefresh: () => refreshes++,
                ),
              ),
            ),
          ),
        ),
      );
      request.complete(true);
      await tester.pump();
      expect(find.text('Connected'), findsOneWidget);
      request = Completer<bool>();
      container.invalidate(status);
      await tester.pump();
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Unknown'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      request.completeError(StateError('unavailable'), StackTrace.empty);
      await tester.pump();
      expect(find.text('Connected'), findsNothing);
      await tester.tap(find.byTooltip('Retry'));
      expect(refreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposal during an action leaves no pending callback error', (
    tester,
  ) async {
    final operation = Completer<void>();
    await pumpControl(tester, onToggle: (_) => operation.future);
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    operation.completeError(StateError('disposed'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _StartingSetup extends SetupAction {
  bool? enabledAtStart;

  @override
  void build() {}

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    expect(running, isTrue);
    enabledAtStart = ref.read(vpnSettingProvider).enable;
    return true;
  }
}
