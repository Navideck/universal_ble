// Apple and Web have no native bond-state API, so `pair()` drives pairing by running
// an encrypted-characteristic probe and reports the outcome through `pairingStateStream` /
// `onPairingStateChange`. `isPaired()` runs the same probe as a query and must not emit.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

import 'universal_ble_test_mock.dart';

class _EncryptedProbePlatform extends UniversalBlePlatformMock {
  _EncryptedProbePlatform({this.readError});

  final Object? readError;

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      BleConnectionState.connected;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async =>
      [
        BleService('180a', [
          BleCharacteristic('2a00', [CharacteristicProperty.read], const []),
        ]),
      ];

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    if (readError != null) throw readError!;
    return Uint8List.fromList([1]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceId = 'AA:BB:CC:DD:EE:FF';
  final encryptedCharacteristic = BleCommand(
    service: '180a',
    characteristic: '2a00',
  );
  final originalHasSystemPairingApi = BleCapabilities.hasSystemPairingApi;

  setUp(() {
    // Simulate Apple/Web: no system pairing API, so UniversalBle.pair() takes the
    // encrypted-characteristic path instead of calling _platform.pair().
    BleCapabilities.hasSystemPairingApi = false;
  });

  tearDown(() {
    BleCapabilities.hasSystemPairingApi = originalHasSystemPairingApi;
    UniversalBle.clearQueue();
  });

  test('pair() reports isPaired=true when the encrypted probe succeeds',
      () async {
    UniversalBle.setInstance(_EncryptedProbePlatform());
    final events = <bool>[];
    final sub = UniversalBle.pairingStateStream(deviceId).listen(events.add);

    await UniversalBle.pair(deviceId, pairingCommand: encryptedCharacteristic);
    await pumpEventQueue();
    await sub.cancel();

    expect(events, [true]);
  });

  test('pair() without a pairingCommand reports success via the read-all probe',
      () async {
    UniversalBle.setInstance(_EncryptedProbePlatform());
    final events = <bool>[];
    final sub = UniversalBle.pairingStateStream(deviceId).listen(events.add);

    await UniversalBle.pair(deviceId);
    await pumpEventQueue();
    await sub.cancel();

    expect(events, [true]);
  });

  test('pair() reports a failure event when the probe throws', () async {
    UniversalBle.setInstance(
      _EncryptedProbePlatform(readError: Exception('encrypted read failed')),
    );
    final events = <bool>[];
    final sub = UniversalBle.pairingStateStream(deviceId).listen(events.add);

    await expectLater(
      UniversalBle.pair(deviceId, pairingCommand: encryptedCharacteristic),
      throwsA(isA<PairingException>()),
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(events, [false]);
  });

  test('isPaired() runs the probe but does not emit a pairing state change',
      () async {
    UniversalBle.setInstance(_EncryptedProbePlatform());
    final events = <bool>[];
    final sub = UniversalBle.pairingStateStream(deviceId).listen(events.add);

    expect(
      await UniversalBle.isPaired(deviceId,
          pairingCommand: encryptedCharacteristic),
      isTrue,
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(events, isEmpty);
  });
}
