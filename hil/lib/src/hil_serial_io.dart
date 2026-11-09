import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// The helper owns the COM port for one case. A private loopback connection
// carries serial lines and closes automatically if the test app exits.
const _bridge = r'''
$ErrorActionPreference = 'Stop'
$port = [IO.Ports.SerialPort]::new($env:HIL_SERIAL_PORT, 115200)
$port.DtrEnable = $true
$port.WriteTimeout = 2000
$port.ReadTimeout = 4000
$port.ReadBufferSize = 65536
$client = [Net.Sockets.TcpClient]::new()
try {
  $client.Connect('127.0.0.1', [int]$env:HIL_UART_BRIDGE_PORT)
  $client.NoDelay = $true
  $stream = $client.GetStream()
  $reader = [IO.StreamReader]::new($stream)
  $writer = [IO.StreamWriter]::new($stream)
  $writer.AutoFlush = $true
  $port.Open()
  $port.WriteLine('')
  while ($true) {
    $line = $reader.ReadLine()
    if ($null -eq $line) { break }
    $prefix = 'HIL ' + $line.Substring(0, 8) + ' '
    $port.WriteLine($line)
    do {
      $received = $port.ReadLine().TrimEnd([char]13)
      $writer.WriteLine($received)
    } until ($received.StartsWith($prefix, [StringComparison]::Ordinal))
  }
} finally {
  $port.Dispose()
  $client.Dispose()
}
''';

class HilSerial {
  HilSerial._(this._process, this._socket, this._nextId) {
    _replies = _socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_onLine, onError: _fail, onDone: () {
      _fail(StateError('HIL UART bridge disconnected'));
    });
    unawaited(_process.stdout.drain<void>());
    _stderr = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) => debugPrintSynchronously('HIL UART helper: $line'));
    unawaited(_process.exitCode.then((code) {
      _fail(StateError('HIL UART helper exited ($code)'));
    }));
  }

  final Process _process;
  final Socket _socket;
  late final StreamSubscription<String> _replies;
  late final StreamSubscription<String> _stderr;
  late String address;
  int _nextId;
  String? _pendingId;
  Completer<String>? _pending;
  Object? _failure;
  Future<void> _tail = Future<void>.value();

  static Future<HilSerial?> open() async {
    if (!Platform.isWindows) return null;
    final port = Platform.environment['HIL_SERIAL_PORT'] ?? '';
    if (!RegExp(r'^COM[1-9][0-9]*$', caseSensitive: false).hasMatch(port)) {
      throw StateError(
          'Set HIL_SERIAL_PORT to the fixture COM port (e.g. COM4).');
    }
    final script = base64.encode([
      for (final unit in _bridge.codeUnits) ...[unit & 255, unit >> 8],
    ]);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Process? process;
    final Socket socket;
    try {
      process = await Process.start('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-OutputFormat',
        'Text',
        '-EncodedCommand',
        script,
      ], environment: {
        'HIL_UART_BRIDGE_PORT': '${server.port}'
      });
      socket = await server.first.timeout(const Duration(seconds: 5));
    } catch (_) {
      process?.kill();
      rethrow;
    } finally {
      await server.close();
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final serial =
        HilSerial._(process, socket, DateTime.now().microsecondsSinceEpoch);
    try {
      final reply = await serial._exchange([0xff]);
      final match = RegExp(r'^READY 2 ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})$')
          .firstMatch(reply);
      if (match == null) {
        throw StateError('Unexpected HIL UART handshake: $reply');
      }
      serial.address = match[1]!;
      debugPrintSynchronously('HIL UART $port: fixture ${serial.address}');
      return serial;
    } catch (_) {
      await serial.close();
      rethrow;
    }
  }

  Future<void> command(List<int> bytes) {
    return _request(bytes).then((reply) {
      if (reply != '0') {
        throw StateError('Fixture rejected UART opcode ${bytes.first}: $reply');
      }
    });
  }

  Future<Uint8List> readTelemetry() async {
    final reply = await _request([0xfe]);
    final match = RegExp(r'^TELEMETRY ([0-9a-fA-F]{72})$').firstMatch(reply);
    if (match == null) {
      throw StateError(
          'Fixture must support UART telemetry; reflash the matching firmware. Reply: $reply');
    }
    final hex = match[1]!;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  Future<String> _request(List<int> bytes) {
    final result = _tail.then((_) => _exchange(bytes));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String> _exchange(List<int> bytes) async {
    if (_failure case final failure?) throw failure;
    final id = (_nextId++ & 0xffffffff).toRadixString(16).padLeft(8, '0');
    final reply = Completer<String>();
    _pendingId = id;
    _pending = reply;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    try {
      _socket.write('$id $hex\n');
      await _socket.flush();
      return await reply.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      final error =
          StateError('HIL UART timed out (request $id, opcode ${bytes.first})');
      _fail(error);
      throw error;
    } finally {
      _pending = null;
      _pendingId = null;
    }
  }

  void _onLine(String line) {
    final prefix = 'HIL $_pendingId ';
    final pending = _pending;
    if (pending != null && !pending.isCompleted && line.startsWith(prefix)) {
      pending.complete(line.substring(prefix.length));
    } else {
      debugPrintSynchronously('HIL fixture: $line');
    }
  }

  void _fail(Object error) {
    _failure ??= error;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  Future<void> close() async {
    _socket.destroy();
    _process.kill();
    await _process.exitCode;
    await _replies.cancel();
    await _stderr.cancel();
  }
}
