enum AvailabilityState {
  unknown(0),
  resetting(1),
  unsupported(2),
  unauthorized(3),
  poweredOff(4),
  poweredOn(5);

  final int value;
  const AvailabilityState(this.value);

  factory AvailabilityState.parse(int value) =>
      AvailabilityState.values.firstWhere((element) => element.value == value);
}
