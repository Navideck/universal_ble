import 'dart:async';

/// Auto disposable StreamController
class UniversalBleStreamController<T> {
  Future<T> Function()? initialEvent;
  UniversalBleStreamController({this.initialEvent});

  StreamController<T>? _streamController;

  Stream<T> get stream {
    _setupStreamIfRequired();
    return _streamController!.stream;
  }

  bool get isClosed => _streamController?.isClosed ?? true;

  void add(T data) => _streamController?.add(data);

  void close() {
    _streamController?.close();
    _streamController = null;
  }

  void _setupStreamIfRequired() {
    if (_streamController != null) return;

    _streamController = StreamController.broadcast(
      onListen: () async {
        try {
          T? event = await initialEvent?.call();
          if (event != null) add(event);
        } catch (_) {}
      },
      onCancel: close,
    );
  }
}
