import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

void dispatchCoreLog(
  Log log, {
  required void Function(Log) record,
  required void Function(String) notify,
}) {
  record(log);
  // EasyTier connection retries are diagnostics; explicit service failures still notify.
  if (log.logLevel == LogLevel.error &&
      !log.payload.startsWith('[EasyTier] [Core] ')) {
    notify(log.payload);
  }
}

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  void log(String? text, {LogLevel logLevel = LogLevel.info}) {
    final payload = '[APP] $text';
    debugPrint(payload);
    if (!globalState.isAttach) {
      return;
    }
    globalState.container
        .read(logsProvider.notifier)
        .add(Log.app(payload).copyWith(logLevel: logLevel));
  }
}

final commonPrint = CommonPrint();
