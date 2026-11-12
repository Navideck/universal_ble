import 'dart:typed_data';

class HilSerial {
  static Future<HilSerial?> open() async => null;

  String get address => throw UnsupportedError('UART is unavailable');
  Future<void> command(List<int> bytes) =>
      throw UnsupportedError('UART is unavailable');
  Future<Uint8List> readTelemetry() =>
      throw UnsupportedError('UART is unavailable');
  Future<void> close() async {}
}
