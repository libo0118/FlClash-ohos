import 'dart:convert';

import 'package:fl_clash/common/easytier.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const enabledEasyTier = EasyTierProps(
  enable: true,
  networkName: 'office',
  networkSecret: 'secret',
  peerUrls: ['tcp://vpn.example.com:11010'],
  cidrs: ['10.144.144.0/24', '192.168.50.0/24'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('route identity changes with credentials, not manual supplements', () {
    final tag = easyTierRouteConfigTag(enabledEasyTier);
    expect(tag.length, 64);
    expect(tag, isNot(contains(enabledEasyTier.networkSecret)));
    expect(easyTierRouteConfigTag(enabledEasyTier.copyWith(cidrs: [])), tag);
    for (final props in [
      enabledEasyTier.copyWith(networkName: 'other'),
      enabledEasyTier.copyWith(networkSecret: 'new-secret'),
      enabledEasyTier.copyWith(peerUrls: ['tcp://other.example.com:11010']),
    ]) {
      expect(easyTierRouteConfigTag(props), isNot(tag));
    }
  });

  test('startup logs redact raw and JSON-escaped network secrets', () {
    const secret = 'test"key\\value\n密钥';
    final encoded = jsonEncode(secret);
    final escaped = encoded.substring(1, encoded.length - 1);
    final result = redactEasyTierSecret(
      'raw=$secret; json=$escaped; again=$secret',
      secret,
    );
    expect(result, 'raw=[已隐藏]; json=[已隐藏]; again=[已隐藏]');
    expect(redactEasyTierSecret('unchanged', ''), 'unchanged');
  });

  test('EasyTier defaults to disabled and survives config persistence', () {
    expect(AppSettingProps.fromJson({}).easyTier.enable, false);
    const config = Config(
      themeProps: ThemeProps(),
      appSettingProps: AppSettingProps(easyTier: enabledEasyTier),
    );
    final restored = Config.fromJson(
      jsonDecode(jsonEncode(config.toJson())) as Map<String, Object?>,
    );
    expect(restored.appSettingProps.easyTier, enabledEasyTier);
  });

  test('peer URLs and private IPv4 CIDRs are validated', () {
    for (final peer in [
      'tcp://vpn.example.com:11010',
      'udp://192.168.1.1:11010',
      'wss://vpn.example.com/easytier',
    ]) {
      expect(isEasyTierPeerUrl(peer), true, reason: peer);
    }
    for (final peer in [
      'https://host:11010',
      'tcp://host',
      'udp://host:0',
      'not a URL',
    ]) {
      expect(isEasyTierPeerUrl(peer), false, reason: peer);
    }
    for (final cidr in [
      '10.144.144.0/24',
      '172.20.0.0/16',
      '192.168.50.1/32',
      '100.64.0.0/10',
    ]) {
      expect(isEasyTierCidr(cidr), true, reason: cidr);
    }
    for (final cidr in [
      '0.0.0.0/0',
      '8.8.8.0/24',
      '127.0.0.0/8',
      '172.19.0.0/30',
      '172.16.0.0/12',
      '192.168.1.1/24',
      '192.168.1.0/33',
      '192.168.1.0/+24',
      '192.168.1.0/024',
      '192.168.1.256/32',
      '192.168.001.0/24',
      'fd00::/64',
    ]) {
      expect(isEasyTierCidr(cidr), false, reason: cidr);
    }
    expect(isEasyTierConfigValid(enabledEasyTier), true);
    expect(
      isEasyTierConfigValid(enabledEasyTier.copyWith(networkSecret: '')),
      false,
    );
    expect(
      isEasyTierConfigValid(enabledEasyTier.copyWith(peerUrls: [])),
      false,
    );
    expect(splitEasyTierLines('10.0.0.0/24\n10.0.0.0/24; 192.168.1.0/24'), [
      '10.0.0.0/24',
      '192.168.1.0/24',
    ]);
  });

  test('disabled integration leaves the original config unchanged', () {
    final config = <String, dynamic>{
      'mode': 'global',
      'rules': ['MATCH,subscription'],
      'proxies': [
        {'name': 'subscription', 'type': 'ss'},
      ],
    };
    final before = jsonEncode(config);
    applyEasyTierConfig(config, const EasyTierProps());
    expect(jsonEncode(config), before);
  });

  test('automatic host CIDRs normalize without accepting unsafe routes', () {
    expect(normalizeEasyTierCidr('10.126.126.10/24'), '10.126.126.0/24');
    expect(normalizeEasyTierCidr('192.168.6.183/24'), '192.168.6.0/24');
    expect(normalizeEasyTierCidr('100.64.12.34/10'), '100.64.0.0/10');
    expect(normalizeEasyTierCidr('172.19.0.4/30'), '172.19.0.4/30');
    for (final cidr in [
      '0.0.0.0/0',
      '8.8.8.8/24',
      '127.0.0.1/8',
      '172.16.2.1/12',
      '172.19.0.3/30',
      '192.168.1.1/15',
      '192.168.001.1/24',
      '192.168.1.1/024',
      '192.168.1.1',
      'fd00::1/64',
    ]) {
      expect(normalizeEasyTierCidr(cidr), isNull, reason: cidr);
    }
  });

  test('manual CIDRs may be empty but invalid manual entries still fail', () {
    final automatic = enabledEasyTier.copyWith(cidrs: []);
    expect(isEasyTierConfigValid(automatic), true);
    expect(
      isEasyTierConfigValid(automatic.copyWith(cidrs: ['192.168.6.183/24'])),
      false,
    );
    final config = <String, dynamic>{'rules': ['MATCH,DIRECT']};
    applyEasyTierConfig(config, automatic);
    expect(config['rules'], ['MATCH,DIRECT']);
    expect((config['proxies'] as List).single['udp'], true);
  });

  test('learned routes merge with manual routes before withdrawn guards', () {
    final config = <String, dynamic>{'rules': ['MATCH,subscription']};
    applyEasyTierConfig(
      config,
      enabledEasyTier,
      learnedCidrs: [
        '192.168.6.183/24',
        '10.144.144.10/24',
        '192.168.6.0/24',
        '0.0.0.0/0',
        '172.19.0.1/30',
        '8.8.8.8/32',
      ],
      blockedCidrs: [
        '192.168.6.1/24',
        '192.168.50.0/24',
        '10.144.0.0/16',
        '172.20.0.0/16',
        '172.20.0.1/16',
        '0.0.0.0/0',
      ],
    );
    expect(config['rules'], [
      'IP-CIDR,10.144.144.0/24,$easyTierProxyName,no-resolve',
      'IP-CIDR,192.168.50.0/24,$easyTierProxyName,no-resolve',
      'IP-CIDR,192.168.6.0/24,$easyTierProxyName,no-resolve',
      'IP-CIDR,10.144.0.0/16,REJECT,no-resolve',
      'IP-CIDR,172.20.0.0/16,REJECT,no-resolve',
      'MATCH,subscription',
    ]);
  });

  test('active and manual nested routes precede overlapping REJECT guards', () {
    for (final manual in [false, true]) {
      final config = <String, dynamic>{'rules': ['MATCH,subscription']};
      final props = enabledEasyTier.copyWith(
        cidrs: manual ? ['192.168.0.0/16'] : [],
      );
      applyEasyTierConfig(
        config,
        props,
        learnedCidrs: manual ? [] : ['192.168.6.183/24'],
        blockedCidrs: manual ? ['192.168.6.0/24'] : ['192.168.0.0/16'],
      );
      expect(config['rules'], [
        'IP-CIDR,${manual ? '192.168.0.0/16' : '192.168.6.0/24'},$easyTierProxyName,no-resolve',
        'IP-CIDR,${manual ? '192.168.6.0/24' : '192.168.0.0/16'},REJECT,no-resolve',
        'MATCH,subscription',
      ]);
    }
  });

  test(
    'enabled integration preserves manual CIDRs and existing proxies',
    () {
      final config = <String, dynamic>{
        'mode': 'direct',
        'rules': ['MATCH,subscription'],
        'proxies': [
          {'name': 'subscription', 'type': 'ss'},
        ],
      };
      applyEasyTierConfig(config, enabledEasyTier);
      expect(config['mode'], 'rule');
      expect(config['rules'], [
        'IP-CIDR,10.144.144.0/24,$easyTierProxyName,no-resolve',
        'IP-CIDR,192.168.50.0/24,$easyTierProxyName,no-resolve',
        'MATCH,subscription',
      ]);
      final proxies = config['proxies'] as List;
      expect(proxies.first, {'name': 'subscription', 'type': 'ss'});
      expect(proxies.last, {
        'name': easyTierProxyName,
        'type': 'socks5',
        'server': '127.0.0.1',
        'port': easyTierSocksPort,
        'udp': true,
      });
    },
  );

  test('subscription name collisions preserve the existing proxy', () {
    final config = <String, dynamic>{
      'proxies': [
        {'name': easyTierProxyName, 'type': 'ss'},
      ],
      'proxy-groups': [
        {'name': '${easyTierProxyName}_', 'type': 'select'},
      ],
    };
    applyEasyTierConfig(config, enabledEasyTier);
    final proxies = config['proxies'] as List;
    expect(proxies.first['type'], 'ss');
    expect(proxies.last['name'], '${easyTierProxyName}__');
    expect(
      (config['rules'] as List).first,
      contains('${easyTierProxyName}__,no-resolve'),
    );
  });

  test(
    'port conflicts and invalid restored settings fail before modifying config',
    () {
      final config = <String, dynamic>{'mixed-port': easyTierSocksPort};
      final before = jsonEncode(config);
      expect(
        () => applyEasyTierConfig(config, enabledEasyTier),
        throwsFormatException,
      );
      expect(jsonEncode(config), before);
      expect(
        () => applyEasyTierConfig(
          {},
          enabledEasyTier.copyWith(cidrs: ['0.0.0.0/0']),
        ),
        throwsFormatException,
      );
    },
  );

  for (final custom in [false, true]) {
    test(
      'EasyTier rules survive ${custom ? 'custom' : 'subscription and added'} rule merging',
      () async {
        final result = await makeRealProfileTask(
          MakeRealProfileState(
            profilesPath: '/tmp/flclash-test',
            profileId: 1,
            rawConfig: {
              'proxies': [
                {'name': 'subscription', 'type': 'ss'},
              ],
              'rules': ['MATCH,subscription'],
            },
            realPatchConfig: const PatchClashConfig(mode: Mode.global),
            overrideDns: false,
            appendSystemDns: false,
            proxyGroups: [],
            rules: custom ? [Rule.parse('MATCH,DIRECT')] : [],
            addedRules: [Rule.parse('DOMAIN,example.com,DIRECT')],
            defaultUA: 'test',
            easyTier: enabledEasyTier,
            easyTierLearnedCidrs: ['10.126.126.10/24', '192.168.6.0/24'],
            easyTierBlockedCidrs: ['172.20.0.0/16'],
          ),
        );
        final expectedLastRule = custom ? 'MATCH,DIRECT' : 'MATCH,subscription';
        expect(
          result.a,
          contains('IP-CIDR,10.144.144.0/24,$easyTierProxyName,no-resolve'),
        );
        expect(result.a, contains(expectedLastRule));
        expect(
          result.a,
          contains('IP-CIDR,192.168.6.0/24,$easyTierProxyName,no-resolve'),
        );
        expect(result.a, contains('IP-CIDR,172.20.0.0/16,REJECT,no-resolve'));
        expect(
          result.a.indexOf('IP-CIDR,192.168.6.0/24'),
          lessThan(result.a.indexOf('IP-CIDR,172.20.0.0/16,REJECT')),
        );
        expect(
          result.a.indexOf('IP-CIDR,172.20.0.0/16,REJECT'),
          lessThan(result.a.indexOf(expectedLastRule)),
        );
        expect(
          result.a.indexOf('IP-CIDR,10.144.144.0/24'),
          lessThan(result.a.indexOf(expectedLastRule)),
        );
        expect(result.a, contains('127.0.0.1'));
        expect(result.a, contains('17890'));
        if (!custom) expect(result.a, contains('DOMAIN,example.com,DIRECT'));
      },
    );
  }
}
