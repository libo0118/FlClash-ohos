import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AndroidManager extends ConsumerStatefulWidget {
  final Widget child;

  const AndroidManager({super.key, required this.child});

  @override
  ConsumerState<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends ConsumerState<AndroidManager>
    with ServiceListener {
  bool _cardActionPending = false;

  @override
  void initState() {
    super.initState();
    service?.addListener(this);
    if (system.isOhos) {
      ref.listenManual(initProvider, (prev, next) {
        service?.setVpnCardReady(next);
      }, fireImmediately: true);
    }
    ref.listenManual(appSettingProvider.select((state) => state.hidden), (
      prev,
      next,
    ) {
      app?.updateExcludeFromRecents(next);
    }, fireImmediately: true);
    ref.listenManual(sharedStateProvider, (prev, next) {
      if (prev != next) {
        debouncer.call(FunctionTag.saveSharedFile, () async {
          preferences.saveShareState(next);
        }, duration: const Duration(seconds: 1));
        if (prev?.needSyncSharedState != next.needSyncSharedState) {
          service?.syncState(next.needSyncSharedState);
        }
      }
    });
  }

  @override
  Future<void> dispose() async {
    service?.removeListener(this);
    if (system.isOhos) service?.setVpnCardReady(false);
    super.dispose();
  }

  @override
  void onServiceEvent(CoreEvent event) {
    coreEventManager.sendEvent(event);
    super.onServiceEvent(event);
  }

  @override
  void onServiceCrash(String message) {
    coreEventManager.sendEvent(
      CoreEvent(type: CoreEventType.crash, data: message),
    );
    super.onServiceCrash(message);
  }

  @override
  Future<void> onVpnCardAction(bool enable) async {
    if (!system.isOhos || _cardActionPending) return;
    _cardActionPending = true;
    var status = '';
    try {
      if (!ref.read(initProvider) ||
          (enable && (ref.read(profilesProvider).isEmpty ||
              !ref.read(vpnSettingProvider).enable))) {
        status = 'openRequired';
      } else {
        final running = await service?.getRunTime() != null;
        if (running != enable) {
          await ref.read(setupActionProvider.notifier).updateStatus(enable);
        }
        if ((await service?.getRunTime() != null) != enable) status = 'failed';
      }
    } catch (_) {
      status = 'failed';
    } finally {
      _cardActionPending = false;
      await service?.completeVpnCardAction(status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
