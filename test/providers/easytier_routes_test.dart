import 'package:fl_clash/providers/easytier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

Map<String, Object> snapshot(
  int revision, {
  String sessionId = 'session-1',
  String status = 'ready',
  List<String> cidrs = const [],
}) => {
  'sessionId': sessionId,
  'revision': revision,
  'status': status,
  'cidrs': cidrs,
};

List<String> privateCidrs(int start, int count) =>
    List.generate(count, (index) {
      final value = start + index;
      return '10.${value >> 8}.${value & 255}.0/24';
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late EasyTierRoutes routes;
  setUp(() {
    container = ProviderContainer();
    routes = container.read(easyTierRoutesProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('reset before first event rejects an old configuration snapshot', () {
    routes.reset();
    final late = {
      ...snapshot(2, cidrs: ['192.168.6.0/24']),
      'configTag': 'old-config',
    };
    expect(routes.applySnapshot(late, expectedConfigTag: 'new-config'), false);
    expect(container.read(easyTierRoutesProvider).sessionId, isNull);
    expect(
      routes.applySnapshot({
        ...late,
        'sessionId': 'new-session',
        'configTag': 'new-config',
      }, expectedConfigTag: 'new-config'),
      true,
    );
  });

  test('first ready accepts virtual, direct and relayed subnet routes', () {
    expect(
      routes.applySnapshot(
        snapshot(
          2,
          cidrs: [
            '192.168.6.0/24',
            '10.126.126.10/24',
            '10.126.126.31/24',
            '192.168.6.183/24',
          ],
        ),
      ),
      true,
    );
    final state = container.read(easyTierRoutesProvider);
    expect(state.sessionId, 'session-1');
    expect(state.revision, 2);
    expect(state.status, 'ready');
    expect(state.activeCidrs, ['10.126.126.0/24', '192.168.6.0/24']);
    expect(state.blockedCidrs, isEmpty);
    expect(() => state.activeCidrs.add('10.1.0.0/16'), throwsUnsupportedError);
    expect(() => state.blockedCidrs.clear(), throwsUnsupportedError);
  });

  test('route changes add, withdraw and recover without losing guards', () {
    expect(routes.applySnapshot(snapshot(0, status: 'starting')), false);
    expect(
      routes.applySnapshot(snapshot(1, cidrs: ['10.126.126.10/24'])),
      true,
    );
    expect(
      routes.applySnapshot(
        snapshot(2, cidrs: ['10.126.126.0/24', '192.168.6.0/24']),
      ),
      true,
    );
    expect(routes.applySnapshot(snapshot(3, cidrs: ['192.168.6.0/24'])), true);
    expect(container.read(easyTierRoutesProvider).activeCidrs, [
      '192.168.6.0/24',
    ]);
    expect(container.read(easyTierRoutesProvider).blockedCidrs, [
      '10.126.126.0/24',
    ]);
    expect(routes.applySnapshot(snapshot(4)), true);
    expect(container.read(easyTierRoutesProvider).blockedCidrs, [
      '10.126.126.0/24',
      '192.168.6.0/24',
    ]);
    expect(
      routes.applySnapshot(
        snapshot(5, cidrs: ['10.126.126.31/24', '192.168.6.183/24']),
      ),
      true,
    );
    expect(container.read(easyTierRoutesProvider).blockedCidrs, isEmpty);
  });

  test(
    'unchanged sorted route sets update revision without requesting reload',
    () {
      routes.applySnapshot(
        snapshot(1, cidrs: ['192.168.6.0/24', '10.126.126.0/24']),
      );
      expect(
        routes.applySnapshot(
          snapshot(2, cidrs: ['10.126.126.10/24', '192.168.6.183/24']),
        ),
        false,
      );
      expect(container.read(easyTierRoutesProvider).revision, 2);
      final before = container.read(easyTierRoutesProvider);
      expect(routes.applySnapshot(snapshot(2)), false);
      expect(routes.applySnapshot(snapshot(1, status: 'stopped')), false);
      expect(container.read(easyTierRoutesProvider), same(before));
    },
  );

  test(
    'stop is terminal and a restart keeps known routes until rediscovered',
    () {
      routes.applySnapshot(
        snapshot(1, cidrs: ['10.126.126.0/24', '192.168.6.0/24']),
      );
      expect(routes.applySnapshot(snapshot(2, status: 'stopped')), true);
      expect(container.read(easyTierRoutesProvider).activeCidrs, isEmpty);
      expect(
        routes.applySnapshot(snapshot(3, cidrs: ['10.126.126.0/24'])),
        false,
      );
      expect(container.read(easyTierRoutesProvider).status, 'stopped');
      expect(
        routes.applySnapshot(
          snapshot(0, sessionId: 'session-2', status: 'starting'),
        ),
        false,
      );
      expect(container.read(easyTierRoutesProvider).blockedCidrs, [
        '10.126.126.0/24',
        '192.168.6.0/24',
      ]);
      expect(
        routes.applySnapshot(
          snapshot(1, sessionId: 'session-2', cidrs: ['10.126.126.0/24']),
        ),
        true,
      );
      final before = container.read(easyTierRoutesProvider);
      expect(routes.applySnapshot(snapshot(99)), false);
      expect(container.read(easyTierRoutesProvider), same(before));
      expect(before.blockedCidrs, ['192.168.6.0/24']);
    },
  );

  test(
    'new ready may coalesce starting and immediately replaces active routes',
    () {
      routes.applySnapshot(snapshot(1, cidrs: ['192.168.6.0/24']));
      expect(
        routes.applySnapshot(
          snapshot(2, sessionId: 'session-2', cidrs: ['10.126.126.0/24']),
        ),
        true,
      );
      final state = container.read(easyTierRoutesProvider);
      expect(state.activeCidrs, ['10.126.126.0/24']);
      expect(state.blockedCidrs, ['192.168.6.0/24']);
      expect(
        routes.applySnapshot(snapshot(99, cidrs: ['192.168.6.0/24'])),
        false,
      );
    },
  );

  test(
    'crash stop blocks known routes and configuration reset retires callbacks',
    () {
      routes.applySnapshot(snapshot(1, cidrs: ['192.168.6.0/24']));
      expect(routes.markStopped(), true);
      expect(container.read(easyTierRoutesProvider).blockedCidrs, [
        '192.168.6.0/24',
      ]);
      expect(
        routes.applySnapshot(snapshot(2, cidrs: ['192.168.6.0/24'])),
        false,
      );
      expect(routes.reset(), true);
      final reset = container.read(easyTierRoutesProvider);
      expect(reset.sessionId, isNull);
      expect(reset.activeCidrs, isEmpty);
      expect(reset.blockedCidrs, isEmpty);
      expect(
        routes.applySnapshot(snapshot(99, cidrs: ['192.168.6.0/24'])),
        false,
      );
      expect(container.read(easyTierRoutesProvider), same(reset));
      expect(
        routes.applySnapshot(
          snapshot(0, sessionId: 'new-config', cidrs: ['10.126.126.0/24']),
        ),
        true,
      );
      expect(container.read(easyTierRoutesProvider).blockedCidrs, isEmpty);
    },
  );

  test(
    'invalid route strings are dropped individually at the trust boundary',
    () {
      expect(
        routes.applySnapshot(
          snapshot(
            1,
            cidrs: [
              '192.168.6.183/24',
              '0.0.0.0/0',
              '8.8.8.0/24',
              '127.0.0.1/8',
              '172.16.0.0/12',
              '172.19.0.0/30',
              'fd00::/64',
              'not-a-route',
            ],
          ),
        ),
        true,
      );
      expect(container.read(easyTierRoutesProvider).activeCidrs, [
        '192.168.6.0/24',
      ]);
    },
  );

  test('malformed or oversized snapshots preserve the last complete state', () {
    routes.applySnapshot(snapshot(1, cidrs: ['192.168.6.0/24']));
    final before = container.read(easyTierRoutesProvider);
    final malformed = <Map>[
      {},
      {...snapshot(2), 'sessionId': ''},
      {...snapshot(2), 'sessionId': 42},
      {...snapshot(2), 'revision': -1},
      {...snapshot(2), 'revision': 1.5},
      {...snapshot(2), 'status': 'unknown'},
      {...snapshot(2), 'cidrs': '192.168.6.0/24'},
      {
        ...snapshot(2),
        'cidrs': ['192.168.6.0/24', 42],
      },
      snapshot(2, cidrs: List.filled(4097, '192.168.6.0/24')),
      snapshot(2, cidrs: privateCidrs(0, 513)),
    ];
    for (final invalid in malformed) {
      expect(routes.applySnapshot(invalid), false, reason: invalid.toString());
      expect(container.read(easyTierRoutesProvider), same(before));
    }
    expect(
      routes.applySnapshot(
        snapshot(2, cidrs: List.filled(4096, '192.168.6.183/24')),
      ),
      false,
    );
    expect(container.read(easyTierRoutesProvider).revision, 2);
  });

  test(
    'the 512 route bound includes withdrawn routes across churn and restarts',
    () {
      final known = privateCidrs(0, 512);
      expect(routes.applySnapshot(snapshot(1, cidrs: known)), true);
      expect(routes.applySnapshot(snapshot(2)), true);
      final before = container.read(easyTierRoutesProvider);
      expect(before.blockedCidrs.length, 512);
      expect(
        routes.applySnapshot(
          snapshot(3, sessionId: 'session-2', cidrs: privateCidrs(512, 1)),
        ),
        false,
      );
      expect(container.read(easyTierRoutesProvider), same(before));
      expect(routes.applySnapshot(snapshot(3, cidrs: [known.first])), true);
      expect(container.read(easyTierRoutesProvider).blockedCidrs.length, 511);
      expect(routes.reset(), true);
      expect(
        routes.applySnapshot(
          snapshot(0, sessionId: 'session-2', cidrs: privateCidrs(512, 1)),
        ),
        true,
      );
    },
  );
}
