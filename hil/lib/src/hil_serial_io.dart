import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// The helper owns the COM port for one case. It reads the port continuously so
// fixture output is drained even while no command is in flight: the fixture
// logs on the same UART, and an undrained buffer would otherwise overflow and
// discard a reply. Every complete line is forwarded whole, so a failed exchange
// still leaves the log intact.
//
// A private loopback connection carries command lines and closes automatically
// if the test app exits.
const _bridge = r'''
$ErrorActionPreference = 'Stop'
$port = [IO.Ports.SerialPort]::new($env:HIL_SERIAL_PORT, 115200)
$port.DtrEnable = $true
$port.WriteTimeout = 2000
# A short read timeout lets one thread do both jobs: drain the fixture and
# accept host commands, without a blocking ReadLine that a timeout would abort.
$port.ReadTimeout = 100
$port.ReadBufferSize = 65536
$client = [Net.Sockets.TcpClient]::new()
try {
  $client.Connect('127.0.0.1', [int]$env:HIL_UART_BRIDGE_PORT)
  $client.NoDelay = $true
  $stream = $client.GetStream()
  $writer = [IO.StreamWriter]::new($stream)
  $writer.AutoFlush = $true
  $port.Open()
  $port.DiscardInBuffer()
  $port.WriteLine('')
  $buffer = [byte[]]::new(4096)
  $fromPort = [Text.StringBuilder]::new()
  $fromHost = [Text.StringBuilder]::new()
  $open = $true
  while ($open) {
    try {
      $count = $port.Read($buffer, 0, $buffer.Length)
      if ($count -gt 0) {
        [void]$fromPort.Append([Text.Encoding]::ASCII.GetString($buffer, 0, $count))
        $text = $fromPort.ToString()
        $newline = $text.IndexOf("`n")
        while ($newline -ge 0) {
          $writer.WriteLine($text.Substring(0, $newline).TrimEnd([char]13))
          [void]$fromPort.Remove(0, $newline + 1)
          $text = $fromPort.ToString()
          $newline = $text.IndexOf("`n")
        }
        # An unterminated run must still reach the log instead of growing
        # without bound.
        if ($fromPort.Length -ge 8192) {
          $writer.WriteLine($fromPort.ToString())
          [void]$fromPort.Clear()
        }
      }
    } catch {
      # A read timeout means only that no fixture output arrived in this
      # window: keep draining, and leave the missed reply to the host budget.
      # Anything else means the port is gone; the test app owns teardown.
      $problem = $_.Exception
      if (-not ($problem -is [TimeoutException] -or
                $problem.InnerException -is [TimeoutException])) {
        [Console]::Error.WriteLine("HIL bridge serial error: $($problem.Message)")
        $open = $false
      }
    }
    if (-not $open) { break }
    # Accept a command only when the host sent one, so this never blocks the
    # port reader.
    try {
      $socket = $client.Client
      if ($socket.Poll(0, [Net.Sockets.SelectMode]::SelectRead) -and
          $client.Available -eq 0) {
        # The test process closed the loopback connection; stop and release the
        # COM port.
        $open = $false
        break
      }
      while ($client.Available -gt 0) {
        $read = [Math]::Min($client.Available, $buffer.Length)
        $count = $stream.Read($buffer, 0, $read)
        if ($count -le 0) { $open = $false; break }
        [void]$fromHost.Append([Text.Encoding]::ASCII.GetString($buffer, 0, $count))
        $text = $fromHost.ToString()
        $newline = $text.IndexOf("`n")
        while ($newline -ge 0) {
          $line = $text.Substring(0, $newline).TrimEnd([char]13)
          if ($line.Length -gt 0) { $port.WriteLine($line) }
          [void]$fromHost.Remove(0, $newline + 1)
          $text = $fromHost.ToString()
          $newline = $text.IndexOf("`n")
        }
      }
    } catch {
      # Any socket failure means the test app is gone; stop owning the port.
      [Console]::Error.WriteLine("HIL bridge socket error: $($_.Exception.Message)")
      $open = $false
    }
  }
} finally {
  $port.Dispose()
  $client.Dispose()
}
''';

/// Fixture replies are `HIL <8-hex request id> <payload>`. Zephyr logging shares
/// the console UART, so the marker is matched with [String.lastIndexOf] and the
/// payload is validated by an anchored pattern at each call site; text after a
/// validated payload is ignored.
final _readyPattern = RegExp(
  r'^READY 2 ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})(?![0-9A-Fa-f:])',
);
final _telemetryPattern =
    RegExp(r'^TELEMETRY ([0-9a-fA-F]{72})(?![0-9a-fA-F])');
final _whitespace = RegExp(r'\s+');

class HilSerial {
  HilSerial._(this._process, this._socket, this._port, this._nextId) {
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
        .listen((line) {
      _lastHelperError = line;
      debugPrintSynchronously('HIL UART helper: $line');
    });
    unawaited(_process.exitCode.then((code) {
      _fail(StateError('HIL UART helper exited ($code)'));
    }));
  }

  /// The only timeout authority for a single request. The bridge keeps draining
  /// the port after this expires, so a late reply cannot wedge the session.
  static const _replyBudget = Duration(seconds: 5);

  final Process _process;
  final Socket _socket;
  final String _port;
  late final StreamSubscription<String> _replies;
  late final StreamSubscription<String> _stderr;
  late String address;
  int _nextId;
  String? _pendingId;
  Completer<String>? _pending;
  Object? _failure;
  String? _lastHelperError;
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
    final serial = HilSerial._(
        process, socket, port, DateTime.now().microsecondsSinceEpoch);
    try {
      final reply = await serial._exchange([0xff]);
      final match = _readyPattern.firstMatch(reply);
      if (match == null) {
        throw StateError('Unexpected HIL UART handshake: ${_describe(reply)}');
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
      // The accept reply is the single token `0`; anything glued to it is not
      // an accept.
      if (reply.split(_whitespace).first != '0') {
        throw StateError(
            'Fixture rejected UART opcode ${bytes.first}: ${_describe(reply)}');
      }
    });
  }

  Future<Uint8List> readTelemetry() async {
    final reply = await _request([0xfe]);
    final match = _telemetryPattern.firstMatch(reply);
    if (match == null) {
      throw StateError(
          'Fixture must support UART telemetry; reflash the matching firmware. '
          'Reply: ${_describe(reply)}');
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
      return await reply.future.timeout(_replyBudget);
    } on TimeoutException {
      // This request failed; the bridge and the port stay usable, so only this
      // call is reported. A late reply arrives as ordinary fixture output.
      throw StateError(
        'HIL UART timed out after ${_replyBudget.inSeconds} s on $_port '
        '(request $id, opcode ${bytes.first}). '
        '${_lastHelperError == null ? '' : 'Helper error: $_lastHelperError. '}'
        'Check the "HIL UART helper" output for bridge errors and confirm '
        'nothing else holds the port.',
      );
    } finally {
      _pending = null;
      _pendingId = null;
    }
  }

  void _onLine(String line) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      debugPrintSynchronously('HIL fixture: $line');
      return;
    }
    final marker = 'HIL $_pendingId ';
    // The marker is the last thing a shared log line is guaranteed to contain,
    // and the payload follows it. Search from the end so log text before the
    // reply cannot hide it.
    final index = line.lastIndexOf(marker);
    if (index < 0) {
      debugPrintSynchronously('HIL fixture: $line');
      return;
    }
    pending.complete(line.substring(index + marker.length).trim());
  }

  void _fail(Object error) {
    _failure ??= error;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  Future<void> close() async {
    _socket.destroy();
    _process.kill();
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // A wedged helper must not stall teardown of the test app.
      _process.kill(ProcessSignal.sigkill);
    }
    await _replies.cancel();
    await _stderr.cancel();
  }
}

/// Keeps a diagnostic message readable when a reply carries a long log tail.
String _describe(String reply) =>
    reply.length <= 200 ? reply : '${reply.substring(0, 200)}...';
