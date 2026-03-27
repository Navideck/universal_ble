import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

class PeripheralHome extends StatefulWidget {
  const PeripheralHome({super.key});

  @override
  State<PeripheralHome> createState() => _PeripheralHomeState();
}

class _PeripheralHomeState extends State<PeripheralHome> {
  final List<String> _logs = <String>[];
  bool _initialized = false;
  bool _advertising = false;

  static const String _serviceBattery = '0000180F-0000-1000-8000-00805F9B34FB';
  static const String _charBattery = '00002A19-0000-1000-8000-00805F9B34FB';
  static const String _serviceTest = '0000180D-0000-1000-8000-00805F9B34FB';
  static const String _charTest = '00002A18-0000-1000-8000-00805F9B34FB';

  @override
  void initState() {
    super.initState();
    UniversalBlePeripheral.onAdvertisingStatusUpdate = (advertising, error) {
      setState(() {
        _advertising = advertising;
      });
      _log('Advertising: $advertising ${error ?? ''}'.trim());
    };
    UniversalBlePeripheral.onServiceAdded = (serviceId, error) {
      _log('Service added: $serviceId ${error ?? ''}'.trim());
    };
    UniversalBlePeripheral.onSubscriptionChange = (
      deviceId,
      characteristicId,
      isSubscribed,
      name,
    ) {
      _log(
        'Subscription ${isSubscribed ? 'on' : 'off'}: '
        '${name ?? deviceId} -> $characteristicId',
      );
    };
    UniversalBlePeripheral.onReadRequest = (deviceId, characteristicId, _, __) {
      _log('Read request: $deviceId $characteristicId');
      return BleReadRequestResult(value: utf8.encode('Hello World'));
    };
    UniversalBlePeripheral.onWriteRequest = (
      deviceId,
      characteristicId,
      _,
      value,
    ) {
      _log('Write request: $deviceId $characteristicId $value');
      return const BleWriteRequestResult();
    };
  }

  void _log(String text) {
    setState(() {
      _logs.insert(0, text);
    });
  }

  Future<void> _initialize() async {
    await UniversalBlePeripheral.initialize();
    final supported = await UniversalBlePeripheral.isSupported();
    setState(() {
      _initialized = true;
    });
    _log('Peripheral initialized. supported=$supported');
  }

  Future<void> _addServices() async {
    await UniversalBlePeripheral.addService(
      BleService(_serviceBattery, [
        BleCharacteristic(
          _charBattery,
          [CharacteristicProperty.read, CharacteristicProperty.notify],
          [],
        ),
      ]),
    );
    await UniversalBlePeripheral.addService(
      BleService(_serviceTest, [
        BleCharacteristic(
          _charTest,
          [
            CharacteristicProperty.read,
            CharacteristicProperty.notify,
            CharacteristicProperty.write,
          ],
          [BleDescriptor('00002908-0000-1000-8000-00805F9B34FB')],
        ),
      ]),
    );
    _log('Services queued');
  }

  Future<void> _startAdvertising() async {
    await UniversalBlePeripheral.startAdvertising(
      services: [_serviceBattery, _serviceTest],
      localName: 'UniversalBlePeripheral',
      manufacturerData: ManufacturerData(
        0x012D,
        Uint8List.fromList([0x03, 0x00, 0x64, 0x00]),
      ),
      addManufacturerDataInScanResponse: true,
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
                          _advertising = false;
                        });
                        _log('Stop advertising requested');
                      }
                    : null,
                child: const Text('Stop Advertising'),
              ),
              ElevatedButton(
                onPressed: _initialized
                    ? () async {
                        await UniversalBlePeripheral.updateCharacteristic(
                          characteristicId: _charTest,
                          value: utf8.encode('Test Data'),
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
              Text('Advertising: $_advertising'),
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
}
