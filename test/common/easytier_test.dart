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

  test(
    'enabled integration prepends only explicit CIDRs and keeps existing proxies',
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
          ),
        );
        final expectedLastRule = custom ? 'MATCH,DIRECT' : 'MATCH,subscription';
        expect(
          result.a,
          contains('IP-CIDR,10.144.144.0/24,$easyTierProxyName,no-resolve'),
        );
        expect(result.a, contains(expectedLastRule));
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
