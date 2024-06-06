// ignore_for_file: avoid_print

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

  String readService = "00001800-0000-1000-8000-00805f9b34fb";
  String readCharacteristic = "00002a00-0000-1000-8000-00805f9b34fb";

  String writeService = "8000ff00-ff00-ffff-ffff-ffffffffffff";
  String writeCharacteristic = "0000ff01-0000-1000-8000-00805f9b34fb";

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

  void onScanResultTap(BleScanResult scanResult) async {
    for (int i = 0; i < 10; i++) {
      readWithQueue(scanResult, true);
      writeWithQueue(scanResult, true);
    }
  }

  void readWithQueue(BleScanResult scanResult, bool withQueue) async {
    _executeCommand(
      scanResult,
      () => UniversalBle.readValue(
        scanResult.deviceId,
        readService,
        readCharacteristic,
      ),
      withQueue: withQueue,
    ).then((value) {
      log("ReadSuccess: ${scanResult.name} : ${utf8.decode(value)}");
    }).catchError((e) {
      log("ReadError: ${scanResult.name} : ${e.toString()}");
    });
  }

  void writeWithQueue(BleScanResult scanResult, bool withQueue) async {
    _executeCommand(
      scanResult,
      () => UniversalBle.writeValue(
        scanResult.deviceId,
        writeService,
        writeCharacteristic,
        utf8.encode("Hello World"),
        BleOutputProperty.withResponse,
      ),
      withQueue: withQueue,
    ).then((_) {
      log("WriteSuccess: ${scanResult.name}");
    }).catchError((e) {
      log("WriteError: ${scanResult.name} : ${e.toString()}");
    });
  }

  Future<T> _executeCommand<T>(
    BleScanResult scanResult,
    Future<T> Function() command, {
    bool withQueue = true,
  }) {
    return withQueue
        ? commandQueues[scanResult.deviceId]?.add(command) ?? command()
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
                    for (BleScanResult scanResult in scanResults) {
                      onScanResultTap(scanResult);
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
                          onScanResultTap(scanResult);
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
