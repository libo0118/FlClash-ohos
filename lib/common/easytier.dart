import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/models/models.dart';

const easyTierSocksPort = 17890;
const easyTierProxyName = '__FlClash_EasyTier__';

// Local IPC identity only; never include this credential-derived tag in logs.
String easyTierRouteConfigTag(EasyTierProps props) => sha256.convert(
  utf8.encode(jsonEncode([
    props.networkName,
    props.networkSecret,
    props.peerUrls,
    props.ipv6,
  ])),
).toString();

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

({int address, int prefix})? _parseEasyTierCidr(String value) {
  final parts = value.split('/');
  if (parts.length != 2) return null;
  if (!RegExp(r'^([1-9]|[12][0-9]|3[0-2])$').hasMatch(parts[1])) return null;
  final octets = parts[0].split('.');
  if (octets.length != 4) return null;
  var address = 0;
  for (final octet in octets) {
    if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(octet)) return null;
    final number = int.parse(octet);
    if (number > 255) return null;
    address = (address << 8) | number;
  }
  return (address: address, prefix: int.parse(parts[1]));
}

String? normalizeEasyTierCidr(String value) {
  final parsed = _parseEasyTierCidr(value.trim());
  if (parsed == null) return null;
  final mask = (0xffffffff << (32 - parsed.prefix)) & 0xffffffff;
  final address = parsed.address & mask;
  final cidr = '${(address >> 24) & 255}.${(address >> 16) & 255}.'
      '${(address >> 8) & 255}.${address & 255}/${parsed.prefix}';
  return isEasyTierCidr(cidr) ? cidr : null;
}

bool isEasyTierCidr(String value) {
  final parsed = _parseEasyTierCidr(value);
  if (parsed == null) return false;
  final address = parsed.address;
  final prefix = parsed.prefix;
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
    props.cidrs.every(isEasyTierCidr);

void applyEasyTierConfig(
  Map config,
  EasyTierProps props, {
  Iterable<String> learnedCidrs = const [],
  Iterable<String> blockedCidrs = const [],
}) {
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
  final learned = learnedCidrs
      .map(normalizeEasyTierCidr)
      .whereType<String>()
      .toSet()
      .toList()..sort();
  final active = {...props.cidrs, ...learned};
  final blocked = blockedCidrs
      .map(normalizeEasyTierCidr)
      .whereType<String>()
      .where((cidr) => !active.contains(cidr))
      .toSet()
      .toList()..sort();
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
    ...active.map((cidr) => 'IP-CIDR,$cidr,$name,no-resolve'),
    ...blocked.map((cidr) => 'IP-CIDR,$cidr,REJECT,no-resolve'),
    ...List<String>.from(config['rules'] ?? []),
  ];
}
