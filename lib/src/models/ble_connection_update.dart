class BleConnectionUpdate {
  final bool isConnected;
  final String? error;

  BleConnectionUpdate({
    required this.isConnected,
    this.error,
  });
}
