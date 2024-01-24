enum BleInputProperty {
  disabled(0),
  notification(1),
  indication(2);

  final int value;
  const BleInputProperty(this.value);

  factory BleInputProperty.parse(int value) =>
      BleInputProperty.values.firstWhere((element) => element.value == value);
}

enum BleOutputProperty {
  withResponse(0),
  withoutResponse(1);

  final int value;
  const BleOutputProperty(this.value);

  factory BleOutputProperty.parse(int value) =>
      BleOutputProperty.values.firstWhere((element) => element.value == value);
}
