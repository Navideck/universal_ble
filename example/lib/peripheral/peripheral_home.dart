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
  StreamSubscription<UniversalBlePeripheralEvent>? _eventSub;
  bool _initialized = false;
  PeripheralAdvertisingState _advertisingState =
      PeripheralAdvertisingState.idle;

  static const String _serviceBattery = '0000180F-0000-1000-8000-00805F9B34FB';
  static const String _charBattery = '00002A19-0000-1000-8000-00805F9B34FB';
  static const String _serviceTest = '0000180D-0000-1000-8000-00805F9B34FB';
  static const String _charTest = '00002A18-0000-1000-8000-00805F9B34FB';

  @override
  void initState() {
    super.initState();
    _eventSub = UniversalBlePeripheral.eventStream.listen((event) {
      switch (event) {
        case UniversalBlePeripheralAdvertisingStateChanged():
          setState(() {
            _advertisingState = event.state;
          });
          _log('Advertising state: ${event.state.name} ${event.error ?? ''}'
              .trim());
        case UniversalBlePeripheralServiceAdded():
          _log('Service added: ${event.serviceId} ${event.error ?? ''}'.trim());
        case UniversalBlePeripheralCharacteristicSubscriptionChanged():
          _log(
            'Subscription ${event.isSubscribed ? 'on' : 'off'}: '
            '${event.name ?? event.deviceId} -> ${event.characteristicId}',
          );
        case UniversalBlePeripheralConnectionStateChanged():
          _log(
            'Connection: ${event.deviceId} connected=${event.connected}',
          );
        case UniversalBlePeripheralMtuChanged():
          _log('MTU: ${event.deviceId} mtu=${event.mtu}');
      }
    });
    UniversalBlePeripheral.setRequestHandlers(
      PeripheralRequestHandlers(
        onReadRequest: (deviceId, characteristicId, _, __) {
          _log('Read request: $deviceId $characteristicId');
          return PeripheralReadRequestResult(
            value: Uint8List.fromList(utf8.encode('Hello World')),
          );
        },
        onWriteRequest: (deviceId, characteristicId, _, value) {
          _log('Write request: $deviceId $characteristicId $value');
          return PeripheralWriteRequestResult();
        },
      ),
    );
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
        'Peripheral ready check. supported=$supported readiness=${readiness.name}');
  }

  Future<void> _addServices() async {
    await UniversalBlePeripheral.addService(
      PeripheralService(uuid: _serviceBattery, primary: true, characteristics: [
        PeripheralCharacteristic(
          uuid: _charBattery,
          properties: [
            CharacteristicProperty.read,
            CharacteristicProperty.notify
          ],
          permissions: [],
          descriptors: [],
          value: null,
        ),
      ]),
    );
    await UniversalBlePeripheral.addService(
      PeripheralService(uuid: _serviceTest, primary: false, characteristics: [
        PeripheralCharacteristic(
          uuid: _charTest,
          properties: [
            CharacteristicProperty.read,
            CharacteristicProperty.notify,
            CharacteristicProperty.write
          ],
          permissions: [],
          descriptors: [],
          value: null,
        ),
      ]),
    );
    _log('Services queued');
  }

  Future<void> _startAdvertising() async {
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    await UniversalBlePeripheral.startAdvertising(
      services: [
        _serviceBattery,
        _serviceTest,
      ],
      localName: isWindows ? null : 'UniversalBlePeripheral',
      manufacturerData: isWindows
          ? null
          : ManufacturerData(
              0x012D,
              Uint8List.fromList([0x03, 0x00, 0x64, 0x00]),
            ),
      addManufacturerDataInScanResponse: !isWindows,
    );
    _log('Start advertising requested');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _initialize,
                child: Text(_initialized ? 'Reinitialize' : 'Initialize'),
              ),
              ElevatedButton(
                onPressed: _initialized ? _addServices : null,
                child: const Text('Add Services'),
              ),
              ElevatedButton(
                onPressed: _initialized ? _startAdvertising : null,
                child: const Text('Start Advertising'),
              ),
              ElevatedButton(
                onPressed: _initialized
                    ? () async {
                        await UniversalBlePeripheral.stopAdvertising();
                        setState(() {
                          _advertisingState = PeripheralAdvertisingState.idle;
                        });
                        _log('Stop advertising requested');
                      }
                    : null,
                child: const Text('Stop Advertising'),
              ),
              ElevatedButton(
                onPressed: _initialized
                    ? () async {
                        await UniversalBlePeripheral.updateCharacteristicValue(
                          characteristicId: _charTest,
                          value: Uint8List.fromList(utf8.encode('Test Data')),
                        );
                        _log('Characteristic updated');
                      }
                    : null,
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
    _eventSub?.cancel();
    super.dispose();
  }
}
