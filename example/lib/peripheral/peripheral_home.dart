import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class PeripheralHome extends StatefulWidget {
  const PeripheralHome({super.key});

  @override
  State<PeripheralHome> createState() => _PeripheralHomeState();
}

class _PeripheralHomeState extends State<PeripheralHome> {
  final List<String> _logs = <String>[];

  StreamSubscription<BlePeripheralEvent>? _advertisingStateStreamSub;
  StreamSubscription<BlePeripheralEvent>? _characteristicSubscriptionStreamSub;
  StreamSubscription<BlePeripheralEvent>? _connectionStateStreamSub;
  StreamSubscription<BlePeripheralEvent>? _serviceAddedStreamSub;
  StreamSubscription<BlePeripheralEvent>? _mtuChangedStreamSub;

  bool _initialized = false;
  PeripheralAdvertisingState _advertisingState =
      PeripheralAdvertisingState.idle;

  static const String _serviceBattery = '0000180F-0000-1000-8000-00805F9B34FB';
  static const String _charBattery = '00002A19-0000-1000-8000-00805F9B34FB';
  static const String _serviceTest = '00004432-0000-1000-8000-00805F9B34FB';
  static const String _charTest = '00002A18-0000-1000-8000-00805F9B34FB';

  @override
  void initState() {
    super.initState();

    _initialize();

    _advertisingStateStreamSub = UniversalBlePeripheral.advertisingStateStream
        .listen((BlePeripheralAdvertisingStateChanged event) {
      setState(() {
        _advertisingState = event.state;
      });
      _log(
        'Advertising state: ${event.state.name} ${event.error ?? ''}'.trim(),
      );
    });

    _characteristicSubscriptionStreamSub = UniversalBlePeripheral
        .characteristicSubscriptionStream
        .listen((BlePeripheralCharacteristicSubscriptionChanged event) {
      _log(
        'Characteristic subscription: ${event.deviceId} ${event.characteristicId} ${event.isSubscribed} ${event.name ?? ''}',
      );
    });

    _connectionStateStreamSub = UniversalBlePeripheral.connectionStateStream
        .listen((BlePeripheralConnectionStateChanged event) {
      _log(
        'Connection state: ${event.deviceId} ${event.connected}',
      );
    });

    _serviceAddedStreamSub = UniversalBlePeripheral.serviceAddedStream
        .listen((BlePeripheralServiceAdded event) {
      _log('Service added: ${event.serviceId} ${event.error ?? ''}'.trim());
    });

    _mtuChangedStreamSub = UniversalBlePeripheral.mtuChangedStream
        .listen((BlePeripheralMtuChanged event) {
      _log('MTU: ${event.deviceId} mtu=${event.mtu}');
    });

    UniversalBlePeripheral.setReadRequestHandlers(
      (deviceId, characteristicId, _, __) {
        _log('Read request: $deviceId $characteristicId');
        return PeripheralReadRequestResult(
          value: Uint8List.fromList(utf8.encode('Hello World')),
        );
      },
    );

    UniversalBlePeripheral.setWriteRequestHandlers(
      (deviceId, characteristicId, _, value) {
        _log('Write request: $deviceId $characteristicId $value');
        return PeripheralWriteRequestResult();
      },
    );

    // UniversalBlePeripheral.setDescriptorReadRequestHandlers(
    //   (deviceId, characteristicId, descriptorId, _, __) {
    //     _log(
    //         'Descriptor read request: $deviceId $characteristicId $descriptorId');
    //     return PeripheralReadRequestResult(
    //       value: Uint8List.fromList(utf8.encode('Hello World')),
    //     );
    //   },
    // );

    // UniversalBlePeripheral.setDescriptorWriteRequestHandlers(
    //   (deviceId, characteristicId, descriptorId, _, value) {
    //     _log(
    //         'Descriptor write request: $deviceId $characteristicId $descriptorId $value');
    //     return PeripheralWriteRequestResult();
    //   },
    // );
  }

  void _log(String text) {
    setState(() {
      _logs.insert(0, text);
    });
  }

  Future<void> _initialize() async {
    final supported =
        (await UniversalBlePeripheral.getCapabilities()).supportsPeripheralMode;
    setState(() {
      _initialized = supported;
    });
    final readiness = await UniversalBlePeripheral.getAvailabilityState();
    _log(
      'Peripheral ready check. supported=$supported readiness=${readiness.name}',
    );
  }

  Future<void> _addServices() async {
    await UniversalBlePeripheral.addService(
      BlePeripheralService(
          uuid: _serviceBattery,
          primary: true,
          characteristics: [
            BlePeripheralCharacteristic(
              uuid: _charBattery,
              properties: [
                CharacteristicProperty.read,
                CharacteristicProperty.notify
              ],
              permissions: [
                PeripheralAttributePermission.readable,
                PeripheralAttributePermission.writeable,
              ],
            ),
          ]),
    );
    await UniversalBlePeripheral.addService(
      BlePeripheralService(
          uuid: _serviceTest,
          primary: false,
          characteristics: [
            BlePeripheralCharacteristic(
              uuid: _charTest,
              properties: [
                CharacteristicProperty.read,
                CharacteristicProperty.notify,
                CharacteristicProperty.write
              ],
              permissions: [
                PeripheralAttributePermission.readable,
                PeripheralAttributePermission.writeable,
              ],
            ),
          ]),
    );
    _log('Services queued');
  }

  Future<void> _startAdvertising() async {
    await UniversalBlePeripheral.startAdvertising(
      services: [
        _serviceBattery,
        _serviceTest,
      ],
      localName: 'UniBle',
      manufacturerData: ManufacturerData(
        0x012D,
        Uint8List.fromList([0x03, 0x00, 0x64, 0x00]),
      ),
      platformConfig: PeripheralPlatformConfig(
        android: PeripheralAndroidOptions(
          addManufacturerDataInScanResponse: false,
        ),
      ),
    );
    _log('Start advertising requested');
  }

  @override
  Widget build(BuildContext context) {
    var initializedButton = ElevatedButton(
      onPressed: _initialize,
      child: Text(_initialized ? 'Reinitialize' : 'Initialize'),
    );
    if (!_initialized) {
      return Center(child: initializedButton);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              initializedButton,
              ElevatedButton(
                onPressed: _addServices,
                child: const Text('Add Services'),
              ),
              ElevatedButton(
                onPressed: _startAdvertising,
                child: const Text('Start Advertising'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await UniversalBlePeripheral.stopAdvertising();
                  setState(() {
                    _advertisingState = PeripheralAdvertisingState.idle;
                  });
                  _log('Stop advertising requested');
                },
                child: const Text('Stop Advertising'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await UniversalBlePeripheral.updateCharacteristicValue(
                    characteristicId: _charBattery,
                    value: Uint8List.fromList([0x04]),
                  );
                  _log('Characteristic updated');
                },
                child: const Text('Update Characteristic'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text('Initialized: $_initialized'),
              const SizedBox(width: 16),
              Text('Advertising: ${_advertisingState.name}'),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _logs.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              title: Text(_logs[index]),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _advertisingStateStreamSub?.cancel();
    _characteristicSubscriptionStreamSub?.cancel();
    _connectionStateStreamSub?.cancel();
    _serviceAddedStreamSub?.cancel();
    _mtuChangedStreamSub?.cancel();
    super.dispose();
  }
}
