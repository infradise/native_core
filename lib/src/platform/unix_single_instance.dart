import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics.dart';
import '../single_instance.dart';

const int _maxIpcPayloadBytes = 65536;
const Duration _clientInactivityTimeout = Duration(seconds: 2);

String _stripTrailingSlashes(String path) {
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2F) {
    end--;
  }
  return end == path.length ? path : path.substring(0, end);
}

/// Resolves a short, user-scoped Unix domain socket path guaranteed to fit
/// within the 104-byte BSD/macOS and 108-byte Linux `sockaddr_un.sun_path`
/// limit.
String resolveUnixSingleInstanceSocketPath(
  String appId, {
  Map<String, String>? environment,
  String? tempDirectoryPath,
  bool? isLinuxOverride,
}) {
  final env = environment ?? Platform.environment;
  final isLinuxHost = isLinuxOverride ?? Platform.isLinux;
  final hash = computeSingleInstanceHash(appId);

  if (isLinuxHost) {
    final xdgRuntime = _stripTrailingSlashes(
      (env['XDG_RUNTIME_DIR'] ?? '').trim(),
    );
    if (xdgRuntime.isNotEmpty && xdgRuntime.length <= 72) {
      return '$xdgRuntime/nc_si_$hash.sock';
    }
  }

  final rawUser = (env['USER'] ?? env['LOGNAME'] ?? 'u').trim();
  final userHash = computeSingleInstanceHash(rawUser);
  final baseTemp = _stripTrailingSlashes(
    tempDirectoryPath ?? Directory.systemTemp.path,
  );
  final candidate = '$baseTemp/nc_si_${userHash}_$hash.sock';
  if (candidate.length <= 100) {
    return candidate;
  }
  return '/tmp/nc_si_${userHash}_$hash.sock';
}

/// Pure-Dart Unix Domain Socket ([InternetAddressType.unix]) single-instance
/// coordinator for Linux and macOS, with automatic `SIGKILL` stale-socket
/// recovery.
class UnixSingleInstanceCoordinator implements SingleInstanceCoordinator {
  /// Creates a [UnixSingleInstanceCoordinator].
  UnixSingleInstanceCoordinator({this.socketPathOverride});

  /// Optional explicit socket path used in unit tests.
  final String? socketPathOverride;

  ServerSocket? _server;
  String? _boundSocketPath;
  bool _activateExistingWindow = true;
  void Function()? _onActivatePrimaryWindow;
  void Function(SecondInstancePayload payload)? _onSecondInstance;

  @override
  Future<bool> acquireOrForward({
    required String token,
    required SecondInstancePayload payload,
    required bool activateExistingWindow,
    required void Function() onActivatePrimaryWindow,
    required void Function(SecondInstancePayload payload)? onSecondInstance,
  }) async {
    _activateExistingWindow = activateExistingWindow;
    _onActivatePrimaryWindow = onActivatePrimaryWindow;
    _onSecondInstance = onSecondInstance;

    if (_server != null) {
      return true;
    }

    final socketPath =
        socketPathOverride ?? resolveUnixSingleInstanceSocketPath(token);
    final address = InternetAddress(socketPath, type: InternetAddressType.unix);

    // 1. Fast path: bind directly as the Primary Instance.
    if (await _tryBindServer(address, socketPath)) {
      return true;
    }

    // 2. Socket path already exists: attempt to forward payload to live Primary.
    final forwardedToLivePrimary = await _tryForwardToPrimary(address, payload);
    if (forwardedToLivePrimary) {
      return false;
    }

    // 3. Stale socket left behind by an unclean exit (e.g. SIGKILL): clean up
    // and promote this process to Primary.
    try {
      final stale = File(socketPath);
      if (stale.existsSync()) {
        stale.deleteSync();
      }
    } catch (_) {
      // Best-effort stale socket removal; rebind below handles any race.
    }

    if (await _tryBindServer(address, socketPath)) {
      return true;
    }

    // Fail-open so a broken / read-only temp directory never bricks startup.
    return true;
  }

  Future<bool> _tryBindServer(
    InternetAddress address,
    String socketPath,
  ) async {
    try {
      final parent = File(socketPath).parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      final server = await ServerSocket.bind(address, 0);
      _server = server;
      _boundSocketPath = socketPath;
      server.listen(
        _handleClientConnection,
        onError: (Object error, StackTrace stackTrace) {
          NativeCoreDiagnostics.report(
            'UnixSingleInstanceCoordinator.server',
            error,
            stackTrace,
          );
        },
      );
      return true;
    } on SocketException {
      return false;
    } catch (error, stackTrace) {
      NativeCoreDiagnostics.report(
        'UnixSingleInstanceCoordinator.bind',
        error,
        stackTrace,
      );
      return false;
    }
  }

  void _handleClientConnection(Socket client) {
    final bytes = <int>[];
    var handled = false;
    Timer? inactivityTimer;

    void processPayload() {
      if (handled) return;
      handled = true;
      inactivityTimer?.cancel();
      try {
        final raw = utf8.decode(bytes, allowMalformed: true).trim();
        final decoded =
            SecondInstancePayload.tryDecodeJson(raw) ??
            const SecondInstancePayload(
              arguments: <String>[],
              workingDirectory: '',
            );
        if (_activateExistingWindow) {
          _onActivatePrimaryWindow?.call();
        }
        _onSecondInstance?.call(decoded);
        client.add(const <int>[0x4F, 0x4B, 0x0A]); // "OK\n"
      } catch (error, stackTrace) {
        NativeCoreDiagnostics.report(
          'UnixSingleInstanceCoordinator.handleClient',
          error,
          stackTrace,
        );
      } finally {
        unawaited(
          client.flush().catchError((_) {}).whenComplete(client.destroy),
        );
      }
    }

    inactivityTimer = Timer(_clientInactivityTimeout, () {
      if (handled) return;
      handled = true;
      client.destroy();
    });

    client.listen(
      (chunk) {
        if (bytes.length + chunk.length <= _maxIpcPayloadBytes) {
          bytes.addAll(chunk);
        }
        if (chunk.contains(0x0A)) {
          processPayload();
        }
      },
      onDone: processPayload,
      onError: (_) {
        inactivityTimer?.cancel();
        client.destroy();
      },
      cancelOnError: true,
    );
  }

  Future<bool> _tryForwardToPrimary(
    InternetAddress address,
    SecondInstancePayload payload,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        0,
        timeout: const Duration(milliseconds: 800),
      );
      final encoded = utf8.encode('${payload.encodeJson()}\n');
      socket.add(encoded);
      await socket.flush().timeout(const Duration(milliseconds: 800));
      await socket.first
          .timeout(const Duration(milliseconds: 800))
          .catchError((_) => Uint8List(0));
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      // Connected to a live listener that was slow to ack; treat as delivered.
      return socket != null;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<void> release() async {
    final server = _server;
    _server = null;
    await server?.close();

    final path = _boundSocketPath;
    _boundSocketPath = null;
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // Best-effort cleanup of our domain socket file on shutdown.
      }
    }
  }
}
