import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

abstract final class HilUuid {
  static const service = '7e570001-7e57-4e57-8e57-7e5700000001';
  static const control = '7e570002-7e57-4e57-8e57-7e5700000001';
  static const state = '7e570003-7e57-4e57-8e57-7e5700000001';
  static const read = '7e570004-7e57-4e57-8e57-7e5700000001';
  static const write = '7e570005-7e57-4e57-8e57-7e5700000001';
  static const writeWithoutResponse = '7e570006-7e57-4e57-8e57-7e5700000001';
  static const writeMirror = '7e570007-7e57-4e57-8e57-7e5700000001';
  static const writeWithoutResponseMirror =
      '7e570008-7e57-4e57-8e57-7e5700000001';
  static const notify = '7e570009-7e57-4e57-8e57-7e5700000001';
  static const indicate = '7e57000a-7e57-4e57-8e57-7e5700000001';
  static const multi = '7e57000b-7e57-4e57-8e57-7e5700000001';
  static const auxiliaryService = '7e57000c-7e57-4e57-8e57-7e5700000001';
  static const auxiliaryRead = '7e57000d-7e57-4e57-8e57-7e5700000001';
  static const descriptor = '7e57000e-7e57-4e57-8e57-7e5700000001';
  static const telemetry = '7e57000f-7e57-4e57-8e57-7e5700000001';
}

abstract final class HilCommand {
  static const reset = 0x01;
  static const setReadValue = 0x02;
  static const notify = 0x03;
  static const indicate = 0x04;
  static const disconnect = 0x05;
  static const notifyBurst = 0x06;
  static const armReadFault = 0x07;
  static const armWriteFault = 0x08;
  static const notifyScript = 0x09;
  static const notifyOnSubscribe = 0x0a;
  static const setAuxiliaryService = 0x0b;
  static const scheduleAuxiliaryService = 0x0c;
  static const armCccDelay = 0x0d;
  static const armDescriptorReadFault = 0x0e;
  static const armDescriptorWriteFault = 0x0f;
  static const indicateOnSubscribe = 0x10;
  static const indicationScenario = 0x11;
  static const armCccFault = 0x12;
  static const setLongValue = 0x13;
  static const notifyPressure = 0x14;
  static const armConnectFault = 0x15;
  static const armDiscoveryFault = 0x16;
}

final class HilTelemetry {
  HilTelemetry(Uint8List value) {
    if (value.length != 36) throw StateError('Expected 36 telemetry bytes');
    final data = ByteData.sublistView(value);
    indicationPending = data.getUint16(0, Endian.little) != 0;
    indicationsCompleted = data.getUint16(2, Endian.little);
    indicationsRejected = data.getUint16(4, Endian.little);
    indicationFaultsTriggered = data.getUint16(6, Endian.little);
    cccFaultsTriggered = data.getUint16(8, Endian.little);
    bootCount = data.getUint32(10, Endian.little);
    oversizedWritesRejected = data.getUint16(14, Endian.little);
    pressureAccepted = data.getUint16(16, Endian.little);
    pressureRejected = data.getUint16(18, Endian.little);
    pressureCompleted = data.getUint16(20, Endian.little);
    pressureErrors = data.getUint16(22, Endian.little);
    connectFaultsTriggered = data.getUint16(24, Endian.little);
    discoveryFaultsTriggered = data.getUint16(26, Endian.little);
    physicalDisconnects = data.getUint16(28, Endian.little);
    disconnectTimersArmed = data.getUint16(30, Endian.little);
    disconnectTimersAttempted = data.getUint16(32, Endian.little);
    disconnectTimersCancelled = data.getUint16(34, Endian.little);
  }
  late final bool indicationPending;
  late final int indicationsCompleted;
  late final int indicationsRejected;
  late final int indicationFaultsTriggered;
  late final int cccFaultsTriggered;
  late final int bootCount;
  late final int oversizedWritesRejected;
  late final int pressureAccepted;
  late final int pressureRejected;
  late final int pressureCompleted;
  late final int pressureErrors;
  late final int connectFaultsTriggered;
  late final int discoveryFaultsTriggered;
  late final int physicalDisconnects;
  late final int disconnectTimersArmed;
  late final int disconnectTimersAttempted;
  late final int disconnectTimersCancelled;
}

final class HilState {
  const HilState({
    required this.contractRevision,
    required this.notificationsEnabled,
    required this.indicationsEnabled,
    required this.multiNotificationsEnabled,
    required this.writesWithResponse,
    required this.writesWithoutResponse,
    required this.mtu,
  });

  factory HilState.fromBytes(Uint8List value) {
    if (value.length != 16) {
      throw StateError(
        'Expected a 16-byte HIL state, received ${value.length}',
      );
    }
    final data = ByteData.sublistView(value);
    return HilState(
      contractRevision: value[0],
      notificationsEnabled: value[1] != 0,
      indicationsEnabled: value[2] != 0,
      multiNotificationsEnabled: value[3] != 0,
      writesWithResponse: data.getUint32(4, Endian.little),
      writesWithoutResponse: data.getUint32(8, Endian.little),
      mtu: data.getUint16(12, Endian.little),
    );
  }

  final int contractRevision;
  final bool notificationsEnabled;
  final bool indicationsEnabled;
  final bool multiNotificationsEnabled;
  final int writesWithResponse;
  final int writesWithoutResponse;
  final int mtu;
}

final class HilPeripheral {
  HilPeripheral._(this.device);

  static const deviceName = 'UniversalBLE-HIL';
  static const contractRevision = 2;
  static const maxWriteLength = 384;
  static const _configuredDeviceId = String.fromEnvironment('HIL_DEVICE_ID');
  static const operationTimeout = Duration(seconds: 10);
  static const scanTimeout = Duration(seconds: 30);
  static BleDevice? _discoveredDevice;

  final BleDevice device;

  String get deviceId => device.deviceId;

  static Future<HilPeripheral> open() async {
    UniversalBle.timeout = operationTimeout;
    UniversalBle.queueType = QueueType.global;
    await UniversalBle.setLogLevel(BleLogLevel.verbose);

    final device = _configuredDeviceId.isEmpty || kIsWeb
        ? _discoveredDevice ??= await _discover()
        : BleDevice(deviceId: _configuredDeviceId, name: deviceName);

    final peripheral = HilPeripheral._(device);
    await peripheral.reconnect(timeout: scanTimeout);
    await peripheral.reset();
    final actualContractRevision =
        (await peripheral.readState()).contractRevision;
    if (actualContractRevision != contractRevision) {
      throw StateError(
        'HIL fixture contract mismatch: expected revision $contractRevision, '
        'received $actualContractRevision. Build and flash the matching '
        'universal_ble_hil_firmware image.',
      );
    }
    return peripheral;
  }

  static Future<BleDevice> _discover() async {
    final result = Completer<BleDevice>();
    final subscription = UniversalBle.scanStream.listen((device) {
      if (!result.isCompleted &&
          (device.name == deviceName || device.services.any(_isHilService))) {
        result.complete(device);
      }
    });

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withServices: const [HilUuid.service],
          withNamePrefix: const [deviceName],
        ),
      );
      return await result.future.timeout(scanTimeout);
    } finally {
      await UniversalBle.stopScan();
      await subscription.cancel();
    }
  }

  static bool _isHilService(String uuid) =>
      BleUuidParser.compareStrings(uuid, HilUuid.service);

  Future<void> close() =>
      UniversalBle.disconnect(deviceId, timeout: operationTimeout);

  Future<void> reconnect({Duration timeout = scanTimeout}) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    do {
      try {
        await UniversalBle.connect(
          deviceId,
          timeout: const Duration(seconds: 5),
        );
        try {
          await UniversalBle.requestMtu(deviceId, 247);
        } catch (_) {
          // MTU negotiation may fail after some disconnect sequences;
          // the connection is still usable with the default MTU.
        }
        await discover();
        return;
      } catch (error) {
        lastError = error;
        await UniversalBle.disconnect(
          deviceId,
          timeout: const Duration(seconds: 2),
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } while (DateTime.now().isBefore(deadline));
    throw StateError(
      'Could not reconnect to $deviceId within $timeout: $lastError',
    );
  }

  Future<List<BleService>> discover({bool withDescriptors = true}) =>
      UniversalBle.discoverServices(
        deviceId,
        withDescriptors: withDescriptors,
        timeout: operationTimeout,
      );

  Future<Uint8List> read(String characteristic) => UniversalBle.read(
        deviceId,
        HilUuid.service,
        characteristic,
        timeout: operationTimeout,
      );

  Future<void> write(
    String characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) =>
      UniversalBle.write(
        deviceId,
        HilUuid.service,
        characteristic,
        Uint8List.fromList(value),
        withoutResponse: withoutResponse,
        timeout: operationTimeout,
      );

  Future<void> command(int opcode, [List<int> payload = const []]) =>
      write(HilUuid.control, [opcode, ...payload]);

  Future<void> reset() => command(HilCommand.reset);

  Future<void> setReadValue(List<int> value) =>
      command(HilCommand.setReadValue, value);

  Future<HilState> readState() async =>
      HilState.fromBytes(await read(HilUuid.state));

  Future<void> requestNotification(List<int> value) =>
      command(HilCommand.notify, value);

  Future<void> requestIndication(List<int> value) =>
      command(HilCommand.indicate, value);

  Future<HilTelemetry> readTelemetry() async =>
      HilTelemetry(await read(HilUuid.telemetry));

  Future<void> armIndicationOnSubscribe() =>
      command(HilCommand.indicateOnSubscribe);

  Future<void> requestNotificationPressure() =>
      command(HilCommand.notifyPressure);

  Future<void> armConnectFault(Duration delay) => command(
      HilCommand.armConnectFault,
      _uint16(_durationMilliseconds(delay, 'delay')));

  // 1: disconnect while pending; 2: reboot while pending; 3: second send while busy.
  Future<void> requestIndicationScenario(int action) {
    RangeError.checkValueInInterval(action, 1, 3, 'action');
    return command(HilCommand.indicationScenario, [action]);
  }

  Future<void> setLongValue(int length) {
    RangeError.checkValueInInterval(length, 0, 512, 'length');
    return command(HilCommand.setLongValue, _uint16(length));
  }

  Future<void> armCccFault(
          {required Duration disconnectAfter,
          required Duration callbackDelay,
          bool reboot = false}) =>
      command(HilCommand.armCccFault, [
        reboot ? 2 : 1,
        ..._uint16(_durationMilliseconds(disconnectAfter, 'disconnectAfter')),
        ..._uint16(_durationMilliseconds(callbackDelay, 'callbackDelay'))
      ]);

  Future<void> requestDisconnect(Duration delay) {
    final milliseconds = delay.inMilliseconds;
    if (milliseconds < 0 || milliseconds > 0xffff) {
      throw RangeError.range(milliseconds, 0, 0xffff, 'delay');
    }
    return command(HilCommand.disconnect, _uint16(milliseconds));
  }

  Future<void> requestNotificationBurst({
    required int count,
    required int size,
    required Duration interval,
  }) =>
      command(HilCommand.notifyBurst, [
        ..._uint16(count),
        ..._uint16(size),
        ..._uint16(interval.inMilliseconds),
      ]);

  Future<void> requestNotificationScript({
    required List<int> sequenceNumbers,
    required int size,
    required Duration interval,
  }) {
    if (sequenceNumbers.isEmpty || sequenceNumbers.length > 64) {
      throw RangeError.range(sequenceNumbers.length, 1, 64, 'sequenceNumbers');
    }
    if (sequenceNumbers.any((sequence) => sequence < 0 || sequence > 0xffff)) {
      throw RangeError('Every sequence number must fit in a uint16');
    }
    if (size < 2 || size > 244) {
      throw RangeError.range(size, 2, 244, 'size');
    }
    final intervalMs = _durationMilliseconds(interval, 'interval');
    return command(HilCommand.notifyScript, [
      ..._uint16(size),
      ..._uint16(intervalMs),
      sequenceNumbers.length,
      ...sequenceNumbers.expand(_uint16),
    ]);
  }

  Future<void> armNotificationOnSubscribe() =>
      command(HilCommand.notifyOnSubscribe);

  Future<void> setAuxiliaryService({required bool enabled}) =>
      command(HilCommand.setAuxiliaryService, [enabled ? 1 : 0]);

  Future<void> scheduleAuxiliaryService({
    required bool enabled,
    required Duration delay,
  }) =>
      command(HilCommand.scheduleAuxiliaryService, [
        enabled ? 1 : 0,
        ..._uint16(_durationMilliseconds(delay, 'delay')),
      ]);

  Future<void> armCccDelay(Duration delay) => command(
        HilCommand.armCccDelay,
        _uint16(_durationMilliseconds(delay, 'delay')),
      );

  Future<Uint8List> readDescriptor() => UniversalBle.readDescriptor(
        deviceId,
        HilUuid.service,
        HilUuid.read,
        HilUuid.descriptor,
        timeout: operationTimeout,
      );

  Future<void> writeDescriptor(List<int> value) => UniversalBle.writeDescriptor(
        deviceId,
        HilUuid.service,
        HilUuid.read,
        HilUuid.descriptor,
        Uint8List.fromList(value),
        timeout: operationTimeout,
      );

  Future<void> armReadFault({
    int attError = 0,
    Duration delay = Duration.zero,
    Duration? disconnectAfter,
  }) =>
      _armOperationFault(
        HilCommand.armReadFault,
        attError: attError,
        delay: delay,
        disconnectAfter: disconnectAfter,
      );

  Future<void> armDiscoveryFault(
          {required Duration delay, required Duration disconnectAfter}) =>
      _armOperationFault(HilCommand.armDiscoveryFault,
          attError: 0, delay: delay, disconnectAfter: disconnectAfter);

  Future<void> armWriteFault({
    int attError = 0,
    Duration delay = Duration.zero,
    Duration? disconnectAfter,
  }) =>
      _armOperationFault(
        HilCommand.armWriteFault,
        attError: attError,
        delay: delay,
        disconnectAfter: disconnectAfter,
      );

  Future<void> armDescriptorReadFault({
    int attError = 0,
    Duration delay = Duration.zero,
    Duration? disconnectAfter,
  }) =>
      _armOperationFault(
        HilCommand.armDescriptorReadFault,
        attError: attError,
        delay: delay,
        disconnectAfter: disconnectAfter,
      );

  Future<void> armDescriptorWriteFault({
    int attError = 0,
    Duration delay = Duration.zero,
    Duration? disconnectAfter,
  }) =>
      _armOperationFault(
        HilCommand.armDescriptorWriteFault,
        attError: attError,
        delay: delay,
        disconnectAfter: disconnectAfter,
      );

  Future<void> _armOperationFault(
    int command, {
    required int attError,
    required Duration delay,
    required Duration? disconnectAfter,
  }) {
    if (attError < 0 || attError > 0xff) {
      throw RangeError.range(attError, 0, 0xff, 'attError');
    }
    final delayMs = _durationMilliseconds(delay, 'delay');
    final disconnectMs = disconnectAfter == null
        ? 0xffff
        : _durationMilliseconds(disconnectAfter, 'disconnectAfter');
    return this.command(command, [
      attError,
      ..._uint16(delayMs),
      ..._uint16(disconnectMs),
    ]);
  }

  Future<void> subscribe(String characteristic, {bool indicate = false}) =>
      indicate
          ? UniversalBle.subscribeIndications(
              deviceId,
              HilUuid.service,
              characteristic,
              timeout: operationTimeout,
            )
          : UniversalBle.subscribeNotifications(
              deviceId,
              HilUuid.service,
              characteristic,
              timeout: operationTimeout,
            );

  Future<void> unsubscribe(String characteristic) => UniversalBle.unsubscribe(
        deviceId,
        HilUuid.service,
        characteristic,
        timeout: operationTimeout,
      );

  Stream<Uint8List> values(String characteristic) =>
      UniversalBle.characteristicValueStream(deviceId, characteristic);

  Stream<bool> get connections => UniversalBle.connectionStream(deviceId);

  static List<int> _uint16(int value) => [value & 0xff, value >> 8 & 0xff];

  static int _durationMilliseconds(Duration value, String name) {
    final milliseconds = value.inMilliseconds;
    if (milliseconds < 0 || milliseconds >= 0xffff) {
      throw RangeError.range(milliseconds, 0, 0xfffe, name);
    }
    return milliseconds;
  }
}
