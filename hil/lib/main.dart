import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_hil/src/hil_peripheral.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HilWebRunnerApp());
}

class HilWebRunnerApp extends StatelessWidget {
  const HilWebRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal BLE HIL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315ea8)),
        useMaterial3: true,
      ),
      home: const HilWebRunnerPage(),
    );
  }
}

class HilWebRunnerPage extends StatefulWidget {
  const HilWebRunnerPage({super.key});

  @override
  State<HilWebRunnerPage> createState() => _HilWebRunnerPageState();
}

class _HilWebRunnerPageState extends State<HilWebRunnerPage> {
  final List<_HilResult> _results = [];
  bool _running = false;
  String? _fatalError;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _fatalError = null;
      _results.clear();
    });

    HilPeripheral? peripheral;
    try {
      // This call must remain directly inside the button action. Chrome requires
      // requestDevice() to originate from a real user gesture.
      peripheral = await HilPeripheral.open();
      await _case('Scan and connect', () async {
        _check(
          peripheral!.device.name == HilPeripheral.deviceName,
          'Unexpected device name',
        );
        _check(
          peripheral.device.services.any(
            (uuid) => BleUuidParser.compareStrings(uuid, HilUuid.service),
          ),
          'HIL service was not advertised',
        );
      });
      await _case('Service discovery contract', () async {
        final services = await peripheral!.discover();
        final service = services.singleWhere(
          (service) =>
              BleUuidParser.compareStrings(service.uuid, HilUuid.service),
        );
        _check(
          service.characteristics.length >= 10,
          'Expected all HIL characteristics',
        );
      });
      await _case('Read and configured read', () async {
        await peripheral!.reset();
        _check(
          utf8.decode(await peripheral.read(HilUuid.read)) == 'HIL-READ-V1',
          'Default read value differs',
        );
        final expected = List<int>.generate(120, (index) => index);
        await peripheral.setReadValue(expected);
        _check(
          _equal(await peripheral.read(HilUuid.read), expected),
          'Configured read differs',
        );
      });
      await _case('Write with response', () async {
        await peripheral!.reset();
        final expected = List<int>.generate(120, (index) => 255 - index);
        await peripheral.write(HilUuid.write, expected);
        _check(
          _equal(await peripheral.read(HilUuid.writeMirror), expected),
          'Write mirror differs',
        );
        _check(
          (await peripheral.readState()).writesWithResponse == 1,
          'Write counter differs',
        );
      });
      await _case('Write without response', () async {
        await peripheral!.reset();
        final expected = List<int>.generate(80, (index) => index ^ 0x5a);
        await peripheral.write(
          HilUuid.writeWithoutResponse,
          expected,
          withoutResponse: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        _check(
          _equal(
            await peripheral.read(HilUuid.writeWithoutResponseMirror),
            expected,
          ),
          'Write-without-response mirror differs',
        );
      });
      await _case('Notification delivery', () async {
        await peripheral!.reset();
        await peripheral.subscribe(HilUuid.notify);
        final received = peripheral.values(HilUuid.notify).first;
        const expected = [0, 1, 127, 128, 254, 255];
        await peripheral.requestNotification(expected);
        _check(
          _equal(
            await received.timeout(HilPeripheral.operationTimeout),
            expected,
          ),
          'Notification payload differs',
        );
        await peripheral.unsubscribe(HilUuid.notify);
      });
      await _case('Indication delivery', () async {
        await peripheral!.reset();
        await peripheral.subscribe(HilUuid.indicate, indicate: true);
        final received = peripheral.values(HilUuid.indicate).first;
        final expected = utf8.encode('web-indication');
        await peripheral.requestIndication(expected);
        _check(
          _equal(
            await received.timeout(HilPeripheral.operationTimeout),
            expected,
          ),
          'Indication payload differs',
        );
        await peripheral.unsubscribe(HilUuid.indicate);
      });
      await _case('Notification burst ordering', () async {
        await peripheral!.reset();
        await peripheral.subscribe(HilUuid.notify);
        final received = peripheral.values(HilUuid.notify).take(20).toList();
        await peripheral.requestNotificationBurst(
          count: 20,
          size: 48,
          interval: const Duration(milliseconds: 30),
        );
        final values = await received.timeout(const Duration(seconds: 10));
        for (var index = 0; index < values.length; index++) {
          _check(
            values[index][0] | values[index][1] << 8 == index,
            'Sequence $index differs',
          );
          _check(values[index].length == 48, 'Burst payload size differs');
        }
        await peripheral.unsubscribe(HilUuid.notify);
      });
      await _case('Peripheral disconnect and reconnect', () async {
        final disconnected = peripheral!.connections.firstWhere(
          (connected) => !connected,
        );
        await peripheral.requestDisconnect(const Duration(milliseconds: 100));
        await disconnected.timeout(HilPeripheral.operationTimeout);
        await UniversalBle.connect(
          peripheral.deviceId,
          timeout: HilPeripheral.operationTimeout,
        );
        _check(
          (await peripheral.readState()).contractRevision ==
              HilPeripheral.contractRevision,
          'Reconnect read failed',
        );
      });
    } catch (error, stackTrace) {
      setState(() => _fatalError = '$error\n$stackTrace');
    } finally {
      if (peripheral != null) {
        await peripheral.close();
      }
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _case(String name, Future<void> Function() body) async {
    final stopwatch = Stopwatch()..start();
    try {
      await body();
      _addResult(_HilResult(name, true, stopwatch.elapsed, null));
    } catch (error) {
      _addResult(_HilResult(name, false, stopwatch.elapsed, error.toString()));
      rethrow;
    }
  }

  void _addResult(_HilResult result) {
    if (mounted) setState(() => _results.add(result));
  }

  @override
  Widget build(BuildContext context) {
    final passed = _results.where((result) => result.passed).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Universal BLE HIL')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Web Bluetooth regression suite',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Flash the nRF52 fixture, make sure UniversalBLE-HIL is advertising, '
                'then select it in Chrome. Keep this page visible until the run completes.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(
                  _running
                      ? 'Running $passed/${_results.length + 1}'
                      : 'Select device and run',
                ),
              ),
              const SizedBox(height: 24),
              if (_results.isEmpty && !_running)
                const Text(
                  'No results yet. The suite runs locally and does not upload BLE data.',
                ),
              for (final result in _results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    result.passed ? Icons.check_circle : Icons.cancel,
                    color: result.passed
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(result.name),
                  subtitle: result.error == null
                      ? null
                      : SelectableText(result.error!),
                  trailing: Text('${result.duration.inMilliseconds} ms'),
                ),
              if (_fatalError != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Run stopped',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _fatalError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool _equal(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

final class _HilResult {
  const _HilResult(this.name, this.passed, this.duration, this.error);

  final String name;
  final bool passed;
  final Duration duration;
  final String? error;
}
