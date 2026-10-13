import 'package:fl_clash/common/easytier.dart';
import 'package:riverpod/riverpod.dart';

class EasyTierRoutesState {
  final String? sessionId;
  final int revision;
  final String status;
  final List<String> activeCidrs;
  final List<String> blockedCidrs;

  EasyTierRoutesState({
    this.sessionId,
    this.revision = -1,
    this.status = 'stopped',
    Iterable<String> activeCidrs = const [],
    Iterable<String> blockedCidrs = const [],
  }) : activeCidrs = List.unmodifiable(activeCidrs),
       blockedCidrs = List.unmodifiable(blockedCidrs);
}

final easyTierRoutesProvider =
    NotifierProvider<EasyTierRoutes, EasyTierRoutesState>(EasyTierRoutes.new);

class EasyTierRoutes extends Notifier<EasyTierRoutesState> {
  static const _maxKnownRoutes = 512;
  final _knownCidrs = <String>{};
  final _retiredSessions = <String>{};

  @override
  EasyTierRoutesState build() => EasyTierRoutesState();

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
    return _setState(
      EasyTierRoutesState(
        sessionId: sessionId,
        revision: revision,
        status: status,
        activeCidrs: active.toList()..sort(),
        blockedCidrs: _knownCidrs.difference(active).toList()..sort(),
      ),
    );
  }

  bool markStopped() => _setState(
    EasyTierRoutesState(
      sessionId: state.sessionId,
      revision: state.revision,
      blockedCidrs: _knownCidrs.toList()..sort(),
    ),
  );

  bool reset() {
    if (state.sessionId != null) _retiredSessions.add(state.sessionId!);
    _knownCidrs.clear();
    return _setState(EasyTierRoutesState());
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
