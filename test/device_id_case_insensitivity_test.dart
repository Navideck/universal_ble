import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble.g.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_peripheral_pigeon.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble_pigeon_channel.dart';
import 'package:universal_ble/src/utils/ble_command_queue.dart';
import 'package:universal_ble/src/utils/cache_handler.dart';
import 'package:universal_ble/src/utils/device_id.dart';
import 'package:universal_ble/src/utils/scan_deduplicator.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

/// A BLE device id is a case-insensitive identifier, but platforms report it in different cases (Android
/// upper-cases MACs, Windows/WinRT lower-cases them). These tests guard that universal_ble treats the two
/// cases as ONE device — event-stream matching, connect() completion, and the service cache — so a caller
/// holding the id in a different case than the platform reports doesn't miss events, doesn't hang connect(),
/// and doesn't split across entries. (Pairing-state and connection-parameters de-dup each have their own
/// file.)
class _MockPlatform extends UniversalBlePlatformMock {
  final List<String> readCalls = [];
  Completer<void>? readCompleter;

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    readCalls.add(deviceId);
    if (readCompleter != null) await readCompleter!.future;
    return Uint8List(0);
  }

  @override
  Future<int> readRssi(String deviceId) => throw UnimplementedError();

  @override
  Future<void> connect(
    String deviceId, {
    bool autoConnect = false,
    Duration? connectionTimeout,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    // Report the connection back with a DIFFERENT case than the caller passed — the original hang scenario.
    updateConnection(deviceId.toLowerCase(), true);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async =>
      [BleService('180d', [])];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const upper = 'AA:BB:CC:DD:EE:FF';
  const lower = 'aa:bb:cc:dd:ee:ff';
  const charId = '0000fff1-0000-1000-8000-00805f9b34fb';

  test('connectionStream matches a device id reported in a different case',
      () async {
    final platform = _MockPlatform();
    final event = platform.connectionStream(upper).first;
    platform.updateConnection(lower, true);
    expect(await event, isTrue);
  });

  test(
      'characteristicValueStream matches a device id reported in a different case',
      () async {
    final platform = _MockPlatform();
    final event = platform.characteristicValueStream(upper, charId).first;
    platform.updateCharacteristicValue(
        lower, charId, Uint8List.fromList([1, 2, 3]), null);
    expect(await event, Uint8List.fromList([1, 2, 3]));
  });

  test(
    'characteristic values exclude unrelated platform-message buffer bytes',
    () async {
      final platform = _MockPlatform();
      final backingBuffer = Uint8List.fromList([
        100,
        58,
        51,
        97,
        1,
        2,
        3,
        4,
        5,
      ]);
      final decodedView = Uint8List.sublistView(backingBuffer, 4, 8);
      final streamValue =
          platform.characteristicValueStream(upper, charId).first;
      Uint8List? callbackValue;
      platform.onValueChange = (update) => callbackValue = update.value;

      platform.updateCharacteristicValue(lower, charId, decodedView, null);

      final received = await streamValue;
      expect(received, [1, 2, 3, 4]);
      expect(received.offsetInBytes, 0);
      expect(received.buffer.lengthInBytes, received.lengthInBytes);
      expect(callbackValue, same(received));
      expect(received.buffer.asByteData().getUint8(0), 1);
    },
  );

  test(
    'standalone characteristic values are forwarded without copying',
    () async {
      final platform = _MockPlatform();
      final original = Uint8List.fromList([1, 2, 3]);
      final streamValue =
          platform.characteristicValueStream(upper, charId).first;

      platform.updateCharacteristicValue(lower, charId, original, null);

      expect(await streamValue, same(original));
    },
  );

  test('pairingStateStream matches a device id reported in a different case',
      () async {
    final platform = _MockPlatform();
    final event = platform.pairingStateStream(upper).first;
    platform.updatePairingState(lower, true);
    expect(await event, isTrue);
  });

  test(
      'connect() completes when the platform reports the id in a different case',
      () async {
    UniversalBle.setInstance(_MockPlatform());
    // Must not throw / time out: connect(upper) awaits a lower-case connection update (the original hang).
    await UniversalBle.connect(upper, timeout: const Duration(seconds: 2));
  });

  test('pairing-state dedup treats the two cases as one device', () async {
    final platform = _MockPlatform();
    final events = <bool>[];
    final sub = platform.pairingStateStream(upper).listen(events.add);
    platform.updatePairingState(lower, true); // first -> emits
    platform.updatePairingState(upper,
        true); // same device+value, other case -> deduped, no second emit
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(events, [true]);
  });

  test('connection-parameters dedup treats the two cases as one device',
      () async {
    final platform = _MockPlatform();
    final events = <String>[];
    platform.onConnectionParametersChange = (u) => events.add(u.deviceId);
    BleConnectionParametersChange params(String id) =>
        BleConnectionParametersChange(
            deviceId: id,
            interval: 12,
            latency: 0,
            supervisionTimeout: 500,
            status: 0);
    platform.updateConnectionParameters(params(lower)); // first -> fires
    platform.updateConnectionParameters(
        params(upper)); // identical params, other case -> deduped
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, [lower]);
  });

  test(
      'service cache is keyed case-insensitively (save one case, get/clear another)',
      () {
    // Caller-supplied ids are canonicalised at the API boundary, so the cache itself sees canonical
    // keys only — an address reaching it in either case lands on the same entry.
    UniversalBle.setInstance(_MockPlatform());
    final cache = CacheHandler.instance;
    final upperKey = UniversalBle.canonicalDeviceId(upper);
    final lowerKey = UniversalBle.canonicalDeviceId(lower);
    cache.resetDeviceCache(upperKey); // clean slate
    cache.saveServices(upperKey, const []); // non-null -> cached
    expect(cache.getServices(lowerKey), isNotNull); // found via the other case
    cache.resetDeviceCache(lowerKey); // cleared via the other case
    expect(cache.getServices(upperKey), isNull);
  });

  test('isSubscribed and getSubscribedCharacteristics match across cases',
      () async {
    UniversalBle.setInstance(_MockPlatform());
    expect(UniversalBle.isSubscribed(lower, charId), isFalse);
    await UniversalBle.subscribeNotifications(upper, '180d', charId);
    expect(UniversalBle.isSubscribed(lower, charId), isTrue);
    expect(UniversalBle.isSubscribed(upper, charId), isTrue);
    expect(UniversalBle.getSubscribedCharacteristics(lower), contains(charId));
    expect(UniversalBle.getSubscribedCharacteristics(upper), contains(charId));
    await UniversalBle.unsubscribe(lower, '180d', charId);
    expect(UniversalBle.isSubscribed(upper, charId), isFalse);
  });

  test(
      'BleDeviceExtension discoverServices and getServices share cache across cases',
      () async {
    UniversalBle.setInstance(_MockPlatform());
    final upperDevice = BleDevice(deviceId: upper, name: null);
    final lowerDevice = BleDevice(deviceId: lower, name: null);
    await upperDevice.discoverServices();
    final cachedService =
        await lowerDevice.getService('180d', preferCached: true);
    expect(cachedService, isNotNull);
  });

  test('an opaque id is NOT folded into the cache key', () {
    // Web's ids are case-sensitive, so two that differ only in case are two devices, not one.
    UniversalBle.setInstance(_OpaqueIdPlatform());
    const opaque = 'mHZbW+PZqBpUlZlVQrPzOQ==';
    final cache = CacheHandler.instance;
    final key = UniversalBle.canonicalDeviceId(opaque);
    final foldedKey = UniversalBle.canonicalDeviceId(opaque.toLowerCase());
    cache.resetDeviceCache(key);
    cache.resetDeviceCache(foldedKey);
    cache.saveServices(key, const []);
    expect(cache.getServices(foldedKey), isNull);
    cache.resetDeviceCache(key);
  });

  // Device ids are canonicalised to lower-case on the way OUT too: every callback/stream now emits the
  // lower-case form regardless of the case the platform reported. (Breaking, for the next major — the native
  // side converts back to upper-case at its boundary; see `_nativeId` in the pigeon channel / Linux instance.)

  test(
      'updateConnection emits a lower-case id even when the platform reports upper-case',
      () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onConnectionChange = (update) => emitted = update.deviceId;
    platform.updateConnection(upper, true);
    expect(emitted, lower);
  });

  test('updateCharacteristicValue emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onValueChange = (update) => emitted = update.deviceId;
    platform.updateCharacteristicValue(
        upper, charId, Uint8List.fromList([1]), null);
    expect(emitted, lower);
  });

  test('updatePairingState emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onPairingStateChange = (id, isPaired) => emitted = id;
    platform.updatePairingState(upper, true);
    expect(emitted, lower);
  });

  test('updateConnectionParameters emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onConnectionParametersChange = (u) => emitted = u.deviceId;
    platform.updateConnectionParameters(BleConnectionParametersChange(
        deviceId: upper,
        interval: 12,
        latency: 0,
        supervisionTimeout: 500,
        status: 0));
    expect(emitted, lower);
  });

  test('updateScanResult emits a lower-case id', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onScanResultUpdate = (d) => emitted = d.deviceId;
    platform.updateScanResult(BleDevice(deviceId: upper, name: null));
    expect(emitted, lower);
  });

  test('updateScanResult does not mutate the caller-supplied device', () {
    final platform = _MockPlatform();
    String? emitted;
    platform.onScanResultUpdate = (d) => emitted = d.deviceId;
    final device = BleDevice(deviceId: upper, name: null);

    platform.updateScanResult(device);

    // The caller's instance keeps the id it passed in; only the emitted copy is canonical.
    expect(device.deviceId, upper);
    expect(emitted, lower);
  });

  test('BleDevice.copyWith keeps the sanitised name and the raw name', () {
    final device = BleDevice(deviceId: upper, name: 'Sensor\u0001 ');
    expect(device.name, 'Sensor');

    final copy = device.copyWith(deviceId: lower);

    expect(copy.deviceId, lower);
    expect(copy.name, 'Sensor');
    expect(copy.rawName, 'Sensor\u0001 ');
  });

  test(
      'Pigeon scan result and picker result extensions emit lower-case deviceId',
      () {
    final scanResult = UniversalBleScanResult(deviceId: upper);
    expect(scanResult.toBleDevice().deviceId, lower);

    final pickerResult = UniversalDevicePickerResult(deviceId: upper);
    expect(pickerResult.toBleDevice().deviceId, lower);
  });

  test(
      'per-device command queue serializes commands across different cases',
      () async {
    final platform = _MockPlatform();
    UniversalBle.setInstance(platform);
    UniversalBle.queueType = QueueType.perDevice;

    platform.readCompleter = Completer<void>();
    final order = <int>[];

    final f1 = UniversalBle.readValue(upper, '180d', '2a37')
        .then((_) => order.add(1));
    final f2 = UniversalBle.readValue(lower, '180d', '2a37')
        .then((_) => order.add(2));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(order, isEmpty);
    expect(platform.readCalls, [upper]);

    platform.readCompleter!.complete();
    await Future.wait([f1, f2]);
    expect(order, [1, 2]);
    expect(platform.readCalls, [upper, lower]);
  });

  test('clearQueue clears per-device queue regardless of casing passed to it',
      () async {
    final platform = _MockPlatform();
    UniversalBle.setInstance(platform);
    UniversalBle.queueType = QueueType.perDevice;

    platform.readCompleter = Completer<void>();

    final f1 = UniversalBle.readValue(upper, '180d', '2a37');
    final f2Expectation = expectLater(
      UniversalBle.readValue(upper, '180d', '2a37'),
      throwsException,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    UniversalBle.clearQueue(lower);

    platform.readCompleter!.complete();
    await f1;
    await f2Expectation;
  });

  test('clearQueue with custom queueId does not touch other case variations',
      () async {
    final queue = BleCommandQueue(
      queueType: QueueType.perDevice,
      isAddress: true,
    );

    final syncQueueStarted = Completer<void>();
    final syncQueueRelease = Completer<void>();

    // Enqueue in-flight and pending commands on 'sync'
    final syncInFlight = queue.queueCommand(() async {
      syncQueueStarted.complete();
      await syncQueueRelease.future;
    }, queueId: 'sync');
    final syncPending = queue.queueCommand(
      () async => 'sync-pending-ok',
      queueId: 'sync',
    );

    await syncQueueStarted.future;

    // Enqueue in-flight and pending commands on 'Sync'
    final uppercaseQueueStarted = Completer<void>();
    unawaited(queue.queueCommand(() async {
      uppercaseQueueStarted.complete();
      await Future<void>.delayed(const Duration(seconds: 5));
    }, queueId: 'Sync'));
    final uppercasePending = queue.queueCommand(
      () async => 'uppercase-pending',
      queueId: 'Sync',
    );

    await uppercaseQueueStarted.future;

    // Clear 'Sync' only
    queue.clearQueue('Sync');

    // 'Sync' pending command is disposed
    await expectLater(uppercasePending, throwsException);

    // 'sync' queue was untouched: pending command completes normally once in-flight finishes
    syncQueueRelease.complete();
    await syncInFlight;
    expect(await syncPending, 'sync-pending-ok');
  });

  test(
      'clearQueue clears an id that is not address-shaped on an isAddress queue',
      () async {
    // Keying and clearing use the same rule (`DeviceId.looksLikeAddress`), so a queue must
    // always be clearable by the exact id that produced its key — including a non-address id.
    final queue = BleCommandQueue(
      queueType: QueueType.perDevice,
      isAddress: true,
    );

    final started = Completer<void>();
    final release = Completer<void>();

    final inFlight = queue.queueCommand(() async {
      started.complete();
      await release.future;
    }, deviceId: 'DeviceA');
    final pending = queue.queueCommand(
      () async => 'pending-ok',
      deviceId: 'DeviceA',
    );

    await started.future;

    final pendingExpectation = expectLater(pending, throwsException);
    queue.clearQueue('DeviceA');

    release.complete();
    await inFlight;
    await pendingExpectation;
  });

  test(
      'per-device command queue serializes commands when queueId is passed in different casing for device address',
      () async {
    final queue = BleCommandQueue(
      queueType: QueueType.perDevice,
      isAddress: true,
    );

    final order = <int>[];
    final completer1 = Completer<void>();

    final f1 = queue.queueCommand(() async {
      await completer1.future;
      order.add(1);
    }, deviceId: upper, queueId: upper);

    final f2 = queue.queueCommand(() async {
      order.add(2);
    }, deviceId: lower, queueId: lower);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(order, isEmpty);

    completer1.complete();
    await Future.wait([f1, f2]);
    expect(order, [1, 2]);
  });

  // A platform whose ids are NOT addresses (Web Bluetooth: opaque, case-sensitive browser tokens)
  // reports hasAddressDeviceIds == false, so its ids pass through verbatim. Emission and matching
  // both go through DeviceId, so a scanned id round-trips byte-for-byte and still matches.

  group('UniversalBle.canonicalDeviceId', () {
    test('lower-cases ids on address platforms', () {
      UniversalBle.setInstance(_MockPlatform());
      expect(UniversalBle.canonicalDeviceId(upper), lower);
      expect(UniversalBle.canonicalDeviceId(lower), lower);
      expect(UniversalBle.canonicalDeviceId('Aa:Bb:Cc:Dd:Ee:Ff'), lower);
    });

    test('returns opaque Web tokens verbatim (case preserved)', () {
      UniversalBle.setInstance(_OpaqueIdPlatform());
      const opaque = 'mHZbW+PZqBpUlZlVQrPzOQ==';
      expect(UniversalBle.canonicalDeviceId(opaque), opaque);
      expect(
        UniversalBle.canonicalDeviceId(opaque.toLowerCase()),
        opaque.toLowerCase(),
      );
    });
  });

  group('opaque (Web-style) device ids', () {
    const opaque = 'mHZbW+PZqBpUlZlVQrPzOQ==';

    test('updateScanResult emits an opaque id unchanged', () {
      final platform = _OpaqueIdPlatform();
      String? emitted;
      platform.onScanResultUpdate = (d) => emitted = d.deviceId;
      platform.updateScanResult(BleDevice(deviceId: opaque, name: null));
      expect(emitted, opaque);
    });

    test('updateConnection emits an opaque id unchanged', () {
      final platform = _OpaqueIdPlatform();
      String? emitted;
      platform.onConnectionChange = (update) => emitted = update.deviceId;
      platform.updateConnection(opaque, true);
      expect(emitted, opaque);
    });

    test('connectionStream matches the id exactly as scanned', () async {
      final platform = _OpaqueIdPlatform();
      final event = platform.connectionStream(opaque).first;
      platform.updateConnection(opaque, true);
      expect(await event, isTrue);
    });

    test('characteristicValueStream matches the id exactly as scanned',
        () async {
      final platform = _OpaqueIdPlatform();
      final event = platform.characteristicValueStream(opaque, charId).first;
      platform.updateCharacteristicValue(
          opaque, charId, Uint8List.fromList([1, 2, 3]), null);
      expect(await event, Uint8List.fromList([1, 2, 3]));
    });

    test('a lower-cased id does NOT match, so lookups keep their own case',
        () async {
      final platform = _OpaqueIdPlatform();
      final events = <bool>[];
      final sub =
          platform.connectionStream(opaque.toLowerCase()).listen(events.add);
      platform.updateConnection(opaque, true);
      await Future.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });

    test('ScanDeduplicator does not fold opaque Web tokens', () {
      final deduplicator = ScanDeduplicator(isAddress: false)..setEnabled(true);
      const id1 = 'mHZbW+PZqBpUlZlVQrPzOQ==';
      final id2 = id1.toLowerCase();
      expect(deduplicator.shouldEmit(BleDevice(deviceId: id1, name: null)),
          isTrue);
      expect(deduplicator.shouldEmit(BleDevice(deviceId: id2, name: null)),
          isTrue);
    });

    test('BleCommandQueue with isAddress: false does not fold opaque tokens',
        () async {
      final queue = BleCommandQueue(
        isAddress: false,
        queueType: QueueType.perDevice,
      );
      final order = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final f1 = queue.queueCommand(() async {
        await completer1.future;
        order.add(1);
      }, deviceId: opaque);

      final f2 = queue.queueCommand(() async {
        await completer2.future;
        order.add(2);
      }, deviceId: opaque.toLowerCase());

      completer2.complete();
      await f2;
      expect(order, [2]);

      completer1.complete();
      await f1;
      expect(order, [2, 1]);
    });
  });

  // The pigeon channel is the native boundary: ids leave Dart in the native (upper-case)
  // form, so a platform that requires upper case (e.g. Android's `getRemoteDevice`) keeps
  // working now that the ids the Dart layer emits are lower-case.

  group('pigeon channel boundary sends the native id', () {
    const connectChannel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.connect',
      UniversalBlePlatformChannel.pigeonChannelCodec,
    );
    const readValueChannel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.universal_ble.UniversalBlePlatformChannel.readValue',
      UniversalBlePlatformChannel.pigeonChannelCodec,
    );

    List<Object?> connectArgs = const [];
    List<Object?> readValueArgs = const [];

    setUp(() {
      connectArgs = const [];
      readValueArgs = const [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler<Object?>(connectChannel,
          (message) async {
        connectArgs = message! as List<Object?>;
        return <Object?>[null];
      });
      messenger.setMockDecodedMessageHandler<Object?>(readValueChannel,
          (message) async {
        readValueArgs = message! as List<Object?>;
        return <Object?>[Uint8List(0)];
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler<Object?>(connectChannel, null);
      messenger.setMockDecodedMessageHandler<Object?>(readValueChannel, null);
    });

    test('connect forwards the upper-case id', () async {
      await UniversalBlePigeonChannel.instance.connect(lower);
      expect(connectArgs.first, upper);
    });

    test('readValue forwards the upper-case id', () async {
      await UniversalBlePigeonChannel.instance.readValue(lower, '180d', '2a37');
      expect(readValueArgs.first, upper);
    });
  });

  // Peripheral mode canonicalises the same way: central ids in its streams are lower-case
  // regardless of the case the platform reports.

  group('peripheral', () {
    test('connectionStateStream emits a lower-case id', () async {
      final platform = _MockPeripheralPlatform();
      final event = platform.connectionStateStream.first;
      platform.updateConnectionState(
        BlePeripheralConnectionStateChanged(upper, true),
      );
      expect((await event).deviceId, lower);
    });

    test('characteristicSubscriptionStream emits a lower-case id', () async {
      final platform = _MockPeripheralPlatform();
      final event = platform.characteristicSubscriptionStream.first;
      platform.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: upper,
          characteristicId: charId,
          isSubscribed: true,
          name: null,
        ),
      );
      expect((await event).deviceId, lower);
    });

    test('mtuChangedStream emits a lower-case id', () async {
      final platform = _MockPeripheralPlatform();
      final event = platform.mtuChangedStream.first;
      platform.updateMtu(BlePeripheralMtuChanged(upper, 247));
      expect((await event).deviceId, lower);
    });

    test('peripheral request handlers receive lower-case deviceId', () {
      final pigeon = UniversalBlePeripheralPigeon.instance;
      String? receivedDeviceId;
      pigeon.setReadRequestHandler((deviceId, characteristicId, offset, value) {
        receivedDeviceId = deviceId;
        return PeripheralReadRequestResult(value: Uint8List(0));
      });
      pigeon.onReadRequest(upper, charId, 0, null);
      expect(receivedDeviceId, lower);
    });

    test('toDeviceId().native converts lower-case central id to upper-case', () {
      expect(lower.toDeviceId().native, upper);
    });
  });
}

class _MockPeripheralPlatform extends UniversalBlePeripheralUnsupported {}

/// Stands in for `UniversalBleWeb`, whose ids are opaque, case-sensitive browser tokens.
class _OpaqueIdPlatform extends UniversalBlePlatformMock {
  @override
  bool get hasAddressDeviceIds => false;
}
