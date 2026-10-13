import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _RouteListener with CoreEventListener {
  final snapshots = <Map<String, dynamic>>[];

  @override
  void onEasyTierRoutes(Map<String, dynamic> snapshot) => snapshots.add(snapshot);
}

void main() {
  test('native route envelope reaches its listener; malformed data is ignored',
      () async {
    final listener = _RouteListener();
    coreEventManager.addListener(listener);
    addTearDown(() => coreEventManager.removeListener(listener));
    final snapshot = <String, dynamic>{
      'sessionId': 'test-session',
      'revision': 1,
      'status': 'ready',
      'cidrs': ['192.168.6.0/24'],
    };
    coreEventManager.sendEvent(CoreEvent.fromJson({
      'type': 'easyTierRoutes',
      'data': snapshot,
    }));
    coreEventManager.sendEvent(CoreEvent.fromJson({
      'type': 'easyTierRoutes',
      'data': 'invalid',
    }));
    await Future<void>.delayed(Duration.zero);
    expect(listener.snapshots, [snapshot]);
  });
}
