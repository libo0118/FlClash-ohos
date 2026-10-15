import 'package:fl_clash/common/profile_update_queue.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  late ProviderContainer container;
  late _QueuedSetupAction setup;

  setUp(() {
    setup = _QueuedSetupAction();
    container = ProviderContainer(
      overrides: [setupActionProvider.overrideWith(() => setup)],
    );
    container.read(setupActionProvider.notifier);
  });
  tearDown(() => container.dispose());

  testWidgets('initialization resumes the latest pending routes', (tester) async {
    setup.receiveRoutes(1);
    setup.receiveRoutes(2);
    await tester.pump(const Duration(seconds: 1));
    expect(setup.applied, isEmpty);
    expect(setup.resumes, 0);

    container.read(initProvider.notifier).value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(setup.resumes, 1);
    expect(setup.applied, [2]);

    await tester.pump(const Duration(seconds: 1));
    expect(setup.applied, [2]);
  });

  testWidgets('readiness without pending routes does not reload', (tester) async {
    container.read(initProvider.notifier).value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(setup.resumes, 1);
    expect(setup.applied, isEmpty);
  });

  testWidgets('losing readiness before the timer defers the reload', (tester) async {
    setup.receiveRoutes(1);
    container.read(initProvider.notifier).value = true;
    await tester.pump();
    container.read(initProvider.notifier).value = false;
    await tester.pump(const Duration(milliseconds: 250));
    expect(setup.applied, isEmpty);

    container.read(initProvider.notifier).value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(setup.applied, [1]);
  });

  for (final stopped in [true, false]) {
    testWidgets('readiness keeps ${stopped ? 'stopped' : 'disabled'} routes pending',
        (tester) async {
      setup.running = !stopped;
      setup.enabled = stopped;
      setup.receiveRoutes(1);
      container.read(initProvider.notifier).value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(setup.applied, isEmpty);

      setup.running = true;
      setup.enabled = true;
      setup.resumeEasyTierRouteRefresh();
      await tester.pump(const Duration(milliseconds: 250));
      expect(setup.applied, [1]);
    });
  }
}

// Exercise the real readiness listener with the production queue, without OHOS.
class _QueuedSetupAction extends SetupAction {
  bool running = true;
  bool enabled = true;
  int revision = 0;
  int resumes = 0;
  final applied = <int>[];
  late final queue = ProfileUpdateQueue(
    canRefresh: () => ref.read(initProvider) && running && enabled,
    refresh: () async => applied.add(revision),
    onError: (error, stack) => fail('$error'),
  );

  @override
  void build() {
    super.build();
    ref.onDispose(queue.dispose);
  }

  void receiveRoutes(int next) {
    revision = next;
    queue.requestRefresh();
  }

  @override
  void resumeEasyTierRouteRefresh() {
    resumes++;
    queue.resumeRefresh();
  }
}
