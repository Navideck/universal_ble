enum BleConnectionState {
  connected,
  disconnected;

  const BleConnectionState();

  factory BleConnectionState.parse(int index) =>
      BleConnectionState.values[index];
}
