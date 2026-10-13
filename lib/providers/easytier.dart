import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/easytier.dart';
import 'package:riverpod/riverpod.dart';

class EasyTierPeer {
  final String peerId;
  final String hostname;
  final String? ipv4;
  final String connectionType;
  final double? latencyMs;
  final List<String> protocols;

  const EasyTierPeer({
    required this.peerId,
    required this.hostname,
    required this.ipv4,
    required this.connectionType,
    required this.latencyMs,
    this.protocols = const [],
  });
}

class EasyTierRoutesState {
  final String? sessionId;
  final int revision;
  final String status;
  final List<String> activeCidrs;
  final List<String> blockedCidrs;
  final String peerStatus;
  final String? virtualIpv4;
  final List<EasyTierPeer> peers;

  EasyTierRoutesState({
    this.sessionId,
    this.revision = -1,
    this.status = 'stopped',
    Iterable<String> activeCidrs = const [],
    Iterable<String> blockedCidrs = const [],
    this.peerStatus = 'stopped',
    this.virtualIpv4,
    Iterable<EasyTierPeer> peers = const [],
  }) : activeCidrs = List.unmodifiable(activeCidrs),
       blockedCidrs = List.unmodifiable(blockedCidrs),
       peers = List.unmodifiable(peers);
}

final easyTierRoutesProvider =
    NotifierProvider<EasyTierRoutes, EasyTierRoutesState>(EasyTierRoutes.new);

class EasyTierRoutes extends Notifier<EasyTierRoutesState> {
  static const _maxKnownRoutes = 512;
  final _knownCidrs = <String>{};
  final _retiredSessions = <String>{};
  Timer? _peerExpiry;

  @override
  EasyTierRoutesState build() {
    ref.onDispose(() => _peerExpiry?.cancel());
    return EasyTierRoutesState();
  }

  bool applySnapshot(Map snapshot, {String expectedConfigTag = ''}) {
    if ((snapshot['configTag'] ?? '') != expectedConfigTag) return false;
    final sessionId = snapshot['sessionId'];
    final revision = snapshot['revision'];
    final status = snapshot['status'];
    final rawCidrs = snapshot['cidrs'];
    if (sessionId is! String ||
        sessionId.isEmpty ||
        sessionId.length > 128 ||
        sessionId.trim() != sessionId ||
        revision is! int ||
        revision < 0 ||
        revision > 0x1fffffffffffff ||
        status is! String ||
        !{'starting', 'ready', 'stopped'}.contains(status) ||
        rawCidrs is! List ||
        rawCidrs.length > 4096 ||
        rawCidrs.any((cidr) => cidr is! String || cidr.length > 256)) {
      return false;
    }
    if (_retiredSessions.contains(sessionId) ||
        (sessionId == state.sessionId &&
            (revision <= state.revision ||
                (state.status == 'stopped' && status != 'stopped')))) {
      return false;
    }
    final cidrs = rawCidrs
        .cast<String>()
        .map(normalizeEasyTierCidr)
        .whereType<String>()
        .toSet();
    final known = {
      ..._knownCidrs,
      if (status == 'ready') ...cidrs,
    };
    if (cidrs.length > _maxKnownRoutes || known.length > _maxKnownRoutes) {
      return false;
    }
    if (state.sessionId != null && sessionId != state.sessionId) {
      _retiredSessions.add(state.sessionId!);
    }
    _knownCidrs.addAll(known);
    final active = status == 'ready' ? cidrs : <String>{};
    final telemetry = _readTelemetry(snapshot, status);
    return _setState(
      EasyTierRoutesState(
        sessionId: sessionId,
        revision: revision,
        status: status,
        activeCidrs: active.toList()..sort(),
        blockedCidrs: _knownCidrs.difference(active).toList()..sort(),
        peerStatus: telemetry.peerStatus,
        virtualIpv4: telemetry.virtualIpv4,
        peers: telemetry.peers,
      ),
    );
  }

  bool markStopped() {
    _peerExpiry?.cancel();
    return _setState(
    EasyTierRoutesState(
      sessionId: state.sessionId,
      revision: state.revision,
      blockedCidrs: _knownCidrs.toList()..sort(),
    ),
    );
  }

  bool reset() {
    _peerExpiry?.cancel();
    if (state.sessionId != null) _retiredSessions.add(state.sessionId!);
    _knownCidrs.clear();
    return _setState(EasyTierRoutesState());
  }

  EasyTierRoutesState _readTelemetry(Map snapshot, String routeStatus) {
    _peerExpiry?.cancel();
    if (routeStatus == 'stopped') return EasyTierRoutesState();
    final status = snapshot['peerStatus'];
    final capturedAt = snapshot['capturedAt'];
    final rawPeers = snapshot['peers'];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!{'starting', 'ready', 'unavailable'}.contains(status) ||
        capturedAt is! int || capturedAt < 0 || capturedAt > now + 5000 ||
        rawPeers is! List || rawPeers.length > 512) {
      return EasyTierRoutesState(peerStatus: 'unavailable');
    }
    final peers = <EasyTierPeer>[];
    final ids = <String>{};
    for (final raw in rawPeers) {
      if (raw is! Map) return EasyTierRoutesState(peerStatus: 'unavailable');
      final id = raw['peerId'];
      final name = raw['hostname'];
      final type = raw['connectionType'];
      final protocols = raw['protocols'];
      final latency = raw['latencyMs'];
      if (id is! String || !RegExp(r'^\d{1,10}$').hasMatch(id) ||
          int.parse(id) > 0xffffffff || !ids.add(id) ||
          name is! String || name.length > 256 ||
          !{'direct', 'relay'}.contains(type) ||
          protocols is! List || protocols.length > 16 ||
          protocols.any((value) => value is! String || value.length > 16) ||
          (raw['ipv4'] != null && _ipv4(raw['ipv4']) == null)) {
        return EasyTierRoutesState(peerStatus: 'unavailable');
      }
      peers.add(EasyTierPeer(
        peerId: id,
        hostname: name.replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), ''),
        ipv4: _ipv4(raw['ipv4']),
        connectionType: type as String,
        latencyMs: type == 'direct' && latency is num && latency.isFinite && latency > 0
            ? latency.toDouble() : null,
        protocols: List.unmodifiable(protocols.cast<String>().where(
          (value) => {'tcp', 'udp', 'ws', 'wss', 'quic', 'wg', 'faketcp', 'ring', 'unix'}
              .contains(value.toLowerCase()),
        ).map((value) => value.toUpperCase())),
      ));
    }
    if (snapshot['virtualIpv4'] != null && _ipv4(snapshot['virtualIpv4']) == null) {
      return EasyTierRoutesState(peerStatus: 'unavailable');
    }
    final expiresIn = (status == 'starting' ? 35000 : 10000) - (now - capturedAt);
    final effective = status != 'unavailable' && expiresIn <= 0 ? 'stale' : status as String;
    if (effective == 'ready' || effective == 'starting') {
      _peerExpiry = Timer(Duration(milliseconds: expiresIn), () {
        // Stale display data must never withdraw routes or reload the proxy.
        state = EasyTierRoutesState(
          sessionId: state.sessionId, revision: state.revision, status: state.status,
          activeCidrs: state.activeCidrs, blockedCidrs: state.blockedCidrs,
          peerStatus: 'stale', virtualIpv4: state.virtualIpv4, peers: state.peers,
        );
      });
    }
    return EasyTierRoutesState(
      peerStatus: effective,
      virtualIpv4: _ipv4(snapshot['virtualIpv4']),
      peers: peers,
    );
  }

  String? _ipv4(Object? value) {
    if (value is! String || !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value)) return null;
    final address = InternetAddress.tryParse(value);
    return address?.type == InternetAddressType.IPv4 ? address!.address : null;
  }

  bool _setState(EasyTierRoutesState next) {
    final changed = !_sameRoutes(state.activeCidrs, next.activeCidrs) ||
        !_sameRoutes(state.blockedCidrs, next.blockedCidrs);
    state = next;
    return changed;
  }

  bool _sameRoutes(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
