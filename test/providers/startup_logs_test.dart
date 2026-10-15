import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/easytier.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native startup event reaches application logs and export', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nativeService = Service();
    final forwarder = _ServiceEventForwarder();
    final consumer = _LogsEventConsumer(container);
    nativeService.addListener(forwarder);
    coreEventManager.addListener(consumer);
    addTearDown(() {
      nativeService.removeListener(forwarder);
      coreEventManager.removeListener(consumer);
    });

    const payload = '[EasyTier] waiting for virtual IPv4 and peers';
    final nativeEvent = json.encode({
      'method': 'message',
      'data': {
        'type': 'log',
        'data': {
          'LogLevel': 'warning',
          'Payload': payload,
          'dateTime': '2026-10-13T01:33:00.000Z',
        },
      },
    });
    const codec = StandardMethodCodec();
    final handled = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          nativeService.methodChannel.name,
          codec.encodeMethodCall(MethodCall('event', nativeEvent)),
          (ByteData? response) {
            try {
              if (response != null) codec.decodeEnvelope(response);
              handled.complete();
            } catch (error, stack) {
              handled.completeError(error, stack);
            }
          },
        );
    await handled.future;
    await Future<void>.delayed(Duration.zero);

    final logs = container.read(logsProvider).list;
    expect(logs.single.payload, payload);
    expect(logs.single.logLevel, LogLevel.warning);
    final exported = await encodeLogsTask(logs);
    expect(exported, contains(payload));
    expect(exported, contains('warning'));
  });

  test('logs stay bounded and manual clear still works', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final logs = container.read(logsProvider.notifier);
    for (var index = 0; index < maxLength + 2; index++) {
      logs.add(Log.app('[STARTUP] entry $index'));
    }

    expect(container.read(logsProvider).length, maxLength);
    expect(container.read(logsProvider)[0].payload, '[STARTUP] entry 2');
    logs.clear();
    expect(container.read(logsProvider).list, isEmpty);
    expect(container.read(logsProvider).maxLength, maxLength);
  });

  test('background retry errors remain exportable without popups; failures still notify', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final consumer = _LogsEventConsumer(container);
    coreEventManager.addListener(consumer);
    addTearDown(() => coreEventManager.removeListener(consumer));
    const payloads = [
      '[EasyTier] [Core] 5[Rust:peer_task] hole punching task aborted JoinError::Cancelled(Id(123))',
      '[EasyTier] [Core] 5[Rust:peer_manager] forward packet error Err(PeerNoConnectionError(42))',
      '[EasyTier] 启动失败: 节点连接超时\n内核日志: 5[Rust:peer] failed',
      '[EasyTier] VPN 套接字保护失败',
      '[VPN] 创建失败',
      'Start Mixed(http+socks) server error: address already in use',
    ];
    for (final payload in payloads) {
      coreEventManager.sendEvent(CoreEvent(type: CoreEventType.log, data: {
        'LogLevel': 'error', 'Payload': payload,
        'dateTime': '2026-10-13T07:57:01.000Z',
      }));
    }
    await Future<void>.delayed(Duration.zero);
    final logs = container.read(logsProvider).list;
    expect(logs.length, payloads.length);
    expect(logs.every((log) => log.logLevel == LogLevel.error), true);
    expect(consumer.notifications, payloads.skip(2).toList());
    final exported = await encodeLogsTask(logs);
    expect(exported, contains('JoinError::Cancelled'));
    expect(exported, contains('PeerNoConnection'));
  });

  test('profile setup retains startup logs while clearing requests', () {
    final setup = _ProfileSetupRecorder();
    final container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        setupActionProvider.overrideWith(() => setup),
      ],
    );
    addTearDown(container.dispose);
    final startup = Log.app('[STARTUP] ET-LOG-20261015-1 start requested');
    container.read(logsProvider.notifier).add(startup);
    container.read(requestsProvider.notifier).addRequest(
      TrackerInfo(
        id: 'before-profile-change',
        start: DateTime(2026, 10, 13),
        metadata: const Metadata(),
        chains: const [],
        rule: 'DIRECT',
        rulePayload: '',
      ),
    );

    container.read(setupActionProvider.notifier).fullSetup();

    expect(setup.applied, true);
    expect(container.read(logsProvider).list, [startup]);
    expect(container.read(logsProvider).maxLength, maxLength);
    expect(container.read(requestsProvider).list, isEmpty);
  });

  test('startup marker precedes the core check and uninitialized return', () async {
    var loggedBeforeCoreCheck = false;
    late ProviderContainer container;
    container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(
            easyTier: EasyTierProps(
              enable: true,
              networkName: 'private-name',
              networkSecret: 'private-secret',
            ),
          ),
        ),
        coreActionProvider.overrideWith(
          () => _CoreCheckRecorder(() {
            loggedBeforeCoreCheck = container
                .read(logsProvider)
                .list
                .any((log) => log.payload.contains('ET-LOG-20261015-1'));
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(setupActionProvider.notifier).updateStatus(true);

    final payload = container.read(logsProvider).list.first.payload;
    expect(loggedBeforeCoreCheck, true);
    expect(payload, contains('initialized=false'));
    expect(payload, contains('easyTier=true'));
    expect(payload, contains('mixedPort=7890'));
    expect(payload, isNot(contains('private-name')));
    expect(payload, isNot(contains('private-secret')));
  });

  test('core check failure is exported with escaped secrets redacted', () async {
    const secret = 'test"key\\value';
    final encoded = jsonEncode(secret);
    final error = 'core failed: ${encoded.substring(1, encoded.length - 1)}';
    final container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(
            easyTier: EasyTierProps(networkSecret: secret),
          ),
        ),
        coreActionProvider.overrideWith(
          () => _CoreCheckRecorder(() => throw error),
        ),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(setupActionProvider.notifier).updateStatus(true),
      throwsA(redactEasyTierSecret(error, secret)),
    );
    final exported = await encodeLogsTask(container.read(logsProvider).list);
    expect(exported, contains('[STARTUP] core check failed: core failed: [已隐藏]'));
    expect(exported, isNot(contains(secret)));
    expect(exported, isNot(contains(encoded.substring(1, encoded.length - 1))));
  });
}

class _ServiceEventForwarder with ServiceListener {
  @override
  void onServiceEvent(CoreEvent event) => coreEventManager.sendEvent(event);
}

class _LogsEventConsumer with CoreEventListener {
  final ProviderContainer container;
  final notifications = <String>[];

  _LogsEventConsumer(this.container);

  @override
  void onLog(Log log) => dispatchCoreLog(
    log,
    record: container.read(logsProvider.notifier).add,
    notify: notifications.add,
  );
}

class _ProfileSetupRecorder extends SetupAction {
  bool applied = false;

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    FutureOr<void> Function()? preloadInvoke,
  }) async {
    applied = force;
  }
}

class _CoreCheckRecorder extends CoreAction {
  final void Function() onCheck;

  _CoreCheckRecorder(this.onCheck);

  @override
  Future<bool> tryStartCore([bool start = false]) async {
    onCheck();
    return false;
  }
}
