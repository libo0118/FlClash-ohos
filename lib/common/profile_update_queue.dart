import 'dart:async';

/// Serializes profile writes and defers learned routes until startup completes.
class ProfileUpdateQueue {
  final bool Function() canRefresh;
  final Future<void> Function() refresh;
  final void Function(Object, StackTrace) onError;
  Future<void> _tail = Future.value();
  Timer? _timer;
  bool _pending = false;
  bool _disposed = false;

  ProfileUpdateQueue({
    required this.canRefresh,
    required this.refresh,
    required this.onError,
  });

  Future<T> run<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    // A failed profile must not prevent a later correction from running.
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void requestRefresh() {
    _pending = true;
    resumeRefresh();
  }

  void resumeRefresh() {
    if (_disposed || !_pending || !canRefresh()) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      _timer = null;
      unawaited(
        run(() async {
          if (_disposed || !_pending || !canRefresh()) return;
          _pending = false;
          await refresh();
        }).catchError(onError),
      );
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
