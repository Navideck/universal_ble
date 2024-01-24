enum BleConnectionState {
  connected(0),
  disconnected(1);

  final int value;
  const BleConnectionState(this.value);

  factory BleConnectionState.parse(int value) =>
      BleConnectionState.values.firstWhere((element) => element.value == value);
}
