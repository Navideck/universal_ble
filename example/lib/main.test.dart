import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Universal BLE',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UniversalBle universalBle = UniversalBle();
  bool isScanning = false;

  // String readService = "00001800-0000-1000-8000-00805f9b34fb";
  // String readCharacteristic = "00002a00-0000-1000-8000-00805f9b34fb";
  String readService = "8000dd00-dd00-ffff-ffff-ffffffffffff";
  String readCharacteristic = "0000dd21-0000-1000-8000-00805f9b34fb";

  String writeService = "8000dd00-dd00-ffff-ffff-ffffffffffff";
  String writeCharacteristic = "0000dd11-0000-1000-8000-00805f9b34fb";

  ScanFilter scanFilter = ScanFilter(
    withManufacturerData: [
      ManufacturerDataFilter(
        companyIdentifier: 0x012D,
      ),
      ManufacturerDataFilter(
        companyIdentifier: 0x013D,
      )
    ],
  );

  @override
  void initState() {
    UniversalBle.queuesCommands = false;
    setupHandlers();
    super.initState();
  }

  Map<String, bool> connectionState = {};
  Map<String, BleCommandQueue> commandQueues = {};
  List<BleScanResult> scanResults = [];

  List<String> get connectedDevices =>
      connectionState.keys.where((e) => connectionState[e] == true).toList();

  @override
  void dispose() {
    UniversalBle.stopScan();
    super.dispose();
  }

  void setupHandlers() {
    UniversalBle.onScanResult = (BleScanResult scanResult) {
      if (!scanResults.any((e) => e.deviceId == scanResult.deviceId)) {
        log("${scanResult.name} ${scanResult.deviceId}");
        setState(() {
          scanResults.add(scanResult);
        });
        onNewDeviceFound(scanResult);
      }
    };

    UniversalBle.onConnectionChanged = (String deviceId, state) async {
      log("$deviceId ${state.name}");
      setState(() {
        connectionState[deviceId] = state == BleConnectionState.connected;
      });
      if (state == BleConnectionState.connected) {
        discoverService(deviceId);
      }
    };
  }

  void onNewDeviceFound(BleScanResult scanResult) {
    log("Connecting to ${scanResult.name}");
    UniversalBle.connect(scanResult.deviceId);
    commandQueues[scanResult.deviceId] = BleCommandQueue();
  }

  void discoverService(String deviceId) async {
    List<BleService> services = await UniversalBle.discoverServices(deviceId);
    log(
      "$deviceId: ${services.map((e) => "${e.uuid} ${e.characteristics.map((c) => c.uuid)}")}",
    );
  }

  void onScanResultTap(String deviceId) async {
    for (int i = 0; i < 10; i++) {
      readWithQueue(deviceId, false);
      writeWithQueue(deviceId, false);
    }
  }

  void readWithQueue(String deviceId, bool withQueue) async {
    _executeCommand(
      deviceId,
      () => UniversalBle.readValue(
        deviceId,
        readService,
        readCharacteristic,
      ),
      withQueue: withQueue,
    ).then((value) {
      log("ReadSuccess: $deviceId : ${utf8.decode(value)}");
    }).catchError((e) {
      log("ReadError: $deviceId : ${e.toString()}");
    });
  }

  void writeWithQueue(String deviceId, bool withQueue) async {
    _executeCommand(
      deviceId,
      () => UniversalBle.writeValue(
        deviceId,
        writeService,
        writeCharacteristic,
        utf8.encode("Hello World"),
        BleOutputProperty.withResponse,
      ),
      withQueue: withQueue,
    ).then((_) {
      log("WriteSuccess: $deviceId");
    }).catchError((e) {
      log("WriteError: $deviceId : ${e.toString()}");
    });
  }

  Future<T> _executeCommand<T>(
    String deviceId,
    Future<T> Function() command, {
    bool withQueue = true,
  }) {
    return withQueue
        ? commandQueues[deviceId]?.add(command) ?? command()
        : command();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Universal BLE'),
          elevation: 4,
          actions: [
            if (isScanning)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator.adaptive(),
              )
          ],
        ),
        body: Column(
          children: [
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await UniversalBle.startScan(scanFilter: scanFilter);
                    setState(() {
                      isScanning = true;
                    });
                  },
                  child: const Text('Start Scan'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await UniversalBle.stopScan();
                    setState(() {
                      isScanning = false;
                    });
                  },
                  child: const Text('Stop Scan'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () {
                    for (BleScanResult scanResult in scanResults) {
                      UniversalBle.connect(scanResult.deviceId);
                    }
                  },
                  child: const Text('Connect All'),
                ),
                ElevatedButton(
                  onPressed: () {
                    for (BleScanResult scanResult in scanResults) {
                      UniversalBle.disconnect(scanResult.deviceId);
                    }
                  },
                  child: const Text('Disconnect All'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    for (BleScanResult scanResult in scanResults) {
                      discoverService(scanResult.deviceId);
                    }
                  },
                  child: const Text('Discover Services'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    for (String deviceId in connectedDevices) {
                      onScanResultTap(deviceId);
                    }
                  },
                  child: const Text('Tap All'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: scanResults.length,
                itemBuilder: (BuildContext context, int index) {
                  BleScanResult scanResult = scanResults[index];
                  ManufacturerData manufacturerData = ManufacturerData.fromData(
                      scanResult.manufacturerData ?? Uint8List(0));
                  return Card(
                    child: ListTile(
                        title: Text(
                          "${scanResult.name} ( ${manufacturerData.companyIdRadix16} )",
                        ),
                        onTap: () {
                          onScanResultTap(scanResult.deviceId);
                        },
                        subtitle: Text(scanResult.deviceId),
                        trailing: Icon(
                          Icons.circle,
                          color: connectionState[scanResult.deviceId] == true
                              ? Colors.green
                              : Colors.red,
                        )),
                  );
                },
              ),
            ),
          ],
        ));
  }
}
