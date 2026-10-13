import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';

import 'interface.dart';

class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;

  Completer<bool> _connectedCompleter = Completer();

  CoreLib._internal();

  @override
  Future<String> preload() async {
    if (_connectedCompleter.isCompleted) {
      return 'core is connected';
    }
    final res = await service?.init();
    if (res?.isEmpty != true) {
      return res ?? '';
    }
    _connectedCompleter.complete(true);
    final syncRes = await service?.syncState(
      globalState.container.read(sharedStateProvider),
    );
    return syncRes ?? '';
  }

  factory CoreLib() {
    _instance ??= CoreLib._internal();
    return _instance!;
  }

  @override
  FutureOr<bool> destroy() async {
    return true;
  }

  @override
  Future<bool> shutdown(_) async {
    if (!_connectedCompleter.isCompleted) {
      return false;
    }
    _connectedCompleter = Completer();
    return service?.shutdown() ?? true;
  }

  @override
  Future<bool> startListener() async {
    try {
      commonPrint.log('[STARTUP] requesting Mihomo listener');
      final listenerStarted = await super.startListener();
      commonPrint.log('[STARTUP] Mihomo listener result=$listenerStarted');
      commonPrint.log('[STARTUP] requesting native VPN service');
      final started = await service?.start();
      commonPrint.log('[STARTUP] native VPN service result=$started');
      if (system.isOhos && started != true) {
        throw currentAppLocalizations.easyTierStartFailed;
      }
      return true;
    } catch (error) {
      commonPrint.log('[STARTUP] startup failed; cleaning Mihomo listener');
      // Keep the startup failure if listener cleanup also fails.
      await super.stopListener().catchError((_) => false);
      if (error is PlatformException) {
        throw error.message?.isNotEmpty == true
            ? error.message!
            : currentAppLocalizations.easyTierStartFailed;
      }
      rethrow;
    }
  }

  @override
  Future<bool> stopListener() async {
    commonPrint.log('[STARTUP] stopping Mihomo listener and native VPN service');
    await super.stopListener();
    await service?.stop();
    commonPrint.log('[STARTUP] listener/native service cleanup completed');
    return true;
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    final result = await service
        ?.invokeAction(Action(id: id, method: method, data: data))
        .withTimeout(onTimeout: () => null);
    if (result == null) {
      return null;
    }
    return parasResult<T>(result);
  }

  @override
  Completer get completer => _connectedCompleter;
}

CoreLib? get coreLib => system.isAndroid || system.isOhos ? CoreLib() : null;
