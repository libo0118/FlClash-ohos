import 'dart:async';

import 'package:fl_clash/common/profile_update_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile writes are serialized and continue after a failure', () async {
    final first = Completer<void>();
    final order = <int>[];
    final queue = ProfileUpdateQueue(
      canRefresh: () => true,
      refresh: () async {},
      onError: (error, stack) => fail('$error'),
    );
    addTearDown(queue.dispose);
    final failing = queue.run(() async {
      order.add(1);
      await first.future;
      throw StateError('invalid profile');
    });
    final check = expectLater(failing, throwsStateError);
    final second = queue.run(() async => order.add(2));
    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);
    first.complete();
    await check;
    await second;
    expect(order, [1, 2]);
    expect(await queue.run(() async => false), false);
  });

  testWidgets('startup queues the latest routes without waiting on reload', (
    tester,
  ) async {
    var ready = false;
    var revision = 1;
    final applied = <int>[];
    final startupDone = Completer<void>();
    final queue = ProfileUpdateQueue(
      canRefresh: () => ready,
      refresh: () async => applied.add(revision),
      onError: (error, stack) => fail('$error'),
    );
    addTearDown(queue.dispose);
    final startup = queue.run(() async {
      queue.requestRefresh();
      revision = 2;
      queue.requestRefresh();
      await startupDone.future;
      ready = true;
      queue.resumeRefresh();
    });
    await tester.pump(const Duration(seconds: 1));
    expect(applied, isEmpty);
    startupDone.complete();
    await tester.pump();
    await startup;
    await tester.pump(const Duration(milliseconds: 250));
    expect(applied, [2]);
  });

  testWidgets('changes during a refresh follow it without parallel writes', (
    tester,
  ) async {
    var revision = 1;
    final applied = <int>[];
    final firstDone = Completer<void>();
    final queue = ProfileUpdateQueue(
      canRefresh: () => true,
      refresh: () async {
        applied.add(revision);
        if (applied.length == 1) await firstDone.future;
      },
      onError: (error, stack) => fail('$error'),
    );
    addTearDown(queue.dispose);
    queue.requestRefresh();
    await tester.pump(const Duration(milliseconds: 250));
    revision = 2;
    queue.requestRefresh();
    revision = 3;
    queue.requestRefresh();
    await tester.pump(const Duration(milliseconds: 250));
    expect(applied, [1]);
    firstDone.complete();
    await tester.pump();
    expect(applied, [1, 3]);
  });

  testWidgets('stop defers refresh, resume retries, dispose cancels', (
    tester,
  ) async {
    var ready = true;
    var count = 0;
    final queue = ProfileUpdateQueue(
      canRefresh: () => ready,
      refresh: () async {
        count++;
      },
      onError: (error, stack) => fail('$error'),
    );
    queue.requestRefresh();
    ready = false;
    await tester.pump(const Duration(milliseconds: 250));
    expect(count, 0);
    ready = true;
    queue.resumeRefresh();
    await tester.pump(const Duration(milliseconds: 250));
    expect(count, 1);
    queue.requestRefresh();
    queue.dispose();
    await tester.pump(const Duration(milliseconds: 250));
    expect(count, 1);
  });
}
