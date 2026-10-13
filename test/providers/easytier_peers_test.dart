import 'package:fl_clash/providers/easytier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

Map<String, Object?> telemetry(int revision, {String status = 'ready'}) => {
  'sessionId': 'session-1', 'revision': revision, 'status': status,
  'cidrs': ['192.168.6.0/24'], 'peerStatus': status,
  'capturedAt': DateTime.now().millisecondsSinceEpoch,
  'virtualIpv4': '10.126.126.159',
  'peers': [
    {'peerId': '42', 'hostname': 'office', 'ipv4': '10.126.126.42',
      'connectionType': 'direct', 'latencyMs': 12.5, 'protocols': ['tcp']},
    {'peerId': '43', 'hostname': 'nas', 'ipv4': '10.126.126.43',
      'connectionType': 'relay', 'latencyMs': 7, 'protocols': []},
  ],
};

void main() {
  test('peer heartbeats update display without a rule reload', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final routes = container.read(easyTierRoutesProvider.notifier);
    expect(routes.applySnapshot(telemetry(1)), true);
    var state = container.read(easyTierRoutesProvider);
    expect(state.virtualIpv4, '10.126.126.159');
    expect(state.peers.first.latencyMs, 12.5);
    expect(state.peers.first.protocols, ['TCP']);
    expect(state.peers.last.latencyMs, isNull);
    final changed = telemetry(2);
    ((changed['peers'] as List).first as Map)['latencyMs'] = 23.7;
    expect(routes.applySnapshot(changed), false);
    state = container.read(easyTierRoutesProvider);
    expect(state.peers.first.latencyMs, 23.7);
    expect(state.activeCidrs, ['192.168.6.0/24']);
    expect(() => state.peers.clear(), throwsUnsupportedError);
    expect(() => state.peers.first.protocols.clear(), throwsUnsupportedError);
    expect(routes.applySnapshot(telemetry(1)), false);
    expect(container.read(easyTierRoutesProvider).peers.first.latencyMs, 23.7);
  });

  test('bad display payload never prevents valid route updates', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final routes = container.read(easyTierRoutesProvider.notifier);
    routes.applySnapshot(telemetry(1));
    final bad = telemetry(2)
      ..['cidrs'] = ['192.168.7.0/24']
      ..['peers'] = ['malformed'];
    expect(routes.applySnapshot(bad), true);
    final state = container.read(easyTierRoutesProvider);
    expect(state.peerStatus, 'unavailable');
    expect(state.peers, isEmpty);
    expect(state.activeCidrs, ['192.168.7.0/24']);
    expect(state.blockedCidrs, ['192.168.6.0/24']);
  });

  testWidgets('expiry preserves routes and reset cancels the timer', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final routes = container.read(easyTierRoutesProvider.notifier);
    routes.applySnapshot(telemetry(1));
    await tester.pump(const Duration(seconds: 11));
    final state = container.read(easyTierRoutesProvider);
    expect(state.peerStatus, 'stale');
    expect(state.status, 'ready');
    expect(state.activeCidrs, ['192.168.6.0/24']);
    expect(state.blockedCidrs, isEmpty);
    expect(state.peers.first.hostname, 'office');
    expect(routes.applySnapshot(telemetry(2)), false);
    expect(container.read(easyTierRoutesProvider).peerStatus, 'ready');
    routes.reset();
    await tester.pump(const Duration(seconds: 11));
    expect(container.read(easyTierRoutesProvider).peerStatus, 'stopped');
  });

  test('old replay and invalid telemetry cannot look current', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final routes = container.read(easyTierRoutesProvider.notifier);
    final old = telemetry(1)
      ..['capturedAt'] = DateTime.now().millisecondsSinceEpoch - 60000;
    routes.applySnapshot(old);
    expect(container.read(easyTierRoutesProvider).peerStatus, 'stale');
    routes.applySnapshot(telemetry(2)..['virtualIpv4'] = 'invalid');
    expect(container.read(easyTierRoutesProvider).peerStatus, 'unavailable');
    routes.applySnapshot(telemetry(3, status: 'stopped'));
    expect(container.read(easyTierRoutesProvider).peers, isEmpty);
    expect(container.read(easyTierRoutesProvider).virtualIpv4, isNull);
    expect(routes.applySnapshot(telemetry(4)), false);
    expect(container.read(easyTierRoutesProvider).peerStatus, 'stopped');
  });
}
