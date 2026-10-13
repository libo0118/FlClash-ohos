import 'dart:convert';

import 'package:fl_clash/models/models.dart';

const easyTierSocksPort = 17890;
const easyTierProxyName = '__FlClash_EasyTier__';

String redactEasyTierSecret(String message, String secret) {
  if (secret.isEmpty) return message;
  final encoded = jsonEncode(secret);
  return message
      .replaceAll(encoded.substring(1, encoded.length - 1), '[已隐藏]')
      .replaceAll(secret, '[已隐藏]');
}

List<String> splitEasyTierLines(String value) => value
    .split(RegExp(r'[\s,;]+'))
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();

bool isEasyTierPeerUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{
        'tcp',
        'udp',
        'quic',
        'ws',
        'wss',
        'wg',
        'faketcp',
      }.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  if (!uri.hasPort) return uri.scheme == 'ws' || uri.scheme == 'wss';
  return uri.port > 0 && uri.port <= 65535;
}

bool isEasyTierCidr(String value) {
  final parts = value.split('/');
  if (parts.length != 2) return false;
  if (!RegExp(r'^([1-9]|[12][0-9]|3[0-2])$').hasMatch(parts[1])) return false;
  final octets = parts[0].split('.');
  final prefix = int.tryParse(parts[1]);
  if (octets.length != 4 || prefix == null || prefix < 1 || prefix > 32) {
    return false;
  }
  var address = 0;
  for (final octet in octets) {
    if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(octet)) return false;
    final number = int.parse(octet);
    if (number > 255) return false;
    address = (address << 8) | number;
  }
  final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
  if ((address & mask) != address) return false;
  final end = address | (0xffffffff ^ mask);
  final privateRange =
      (address >= 0x0a000000 && end <= 0x0affffff) ||
      (address >= 0xac100000 && end <= 0xac1fffff) ||
      (address >= 0xc0a80000 && end <= 0xc0a8ffff) ||
      (address >= 0x64400000 && end <= 0x647fffff);
  // The system VPN owns 172.19.0.0/30, including its DNS endpoint.
  return privateRange && !(address <= 0xac130003 && end >= 0xac130000);
}

bool isEasyTierConfigValid(EasyTierProps props) =>
    props.networkName.trim().isNotEmpty &&
    props.networkSecret.trim().isNotEmpty &&
    props.peerUrls.isNotEmpty &&
    props.peerUrls.every(isEasyTierPeerUrl) &&
    props.cidrs.isNotEmpty &&
    props.cidrs.every(isEasyTierCidr);

void applyEasyTierConfig(Map config, EasyTierProps props) {
  if (!props.enable) return;
  if (!isEasyTierConfigValid(props)) {
    throw const FormatException('Invalid EasyTier configuration');
  }
  for (final key in [
    'mixed-port',
    'port',
    'socks-port',
    'redir-port',
    'tproxy-port',
  ]) {
    if (config[key] == easyTierSocksPort) {
      throw const FormatException(
        'EasyTier SOCKS port conflicts with a Clash port',
      );
    }
  }
  final proxies = List<Map>.from(config['proxies'] ?? []);
  final names = {
    ...proxies.map((proxy) => proxy['name']),
    ...List.from(
      config['proxy-groups'] ?? [],
    ).map((group) => group is Map ? group['name'] : (group as ProxyGroup).name),
    ...Map.from(config['proxy-providers'] ?? {}).keys,
  };
  var name = easyTierProxyName;
  while (names.contains(name)) {
    name = '${name}_';
  }
  config['mode'] = 'rule';
  config['proxies'] = [
    ...proxies,
    {
      'name': name,
      'type': 'socks5',
      'server': '127.0.0.1',
      'port': easyTierSocksPort,
      'udp': true,
    },
  ];
  config['rules'] = [
    ...props.cidrs.map((cidr) => 'IP-CIDR,$cidr,$name,no-resolve'),
    ...List<String>.from(config['rules'] ?? []),
  ];
}
