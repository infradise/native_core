import 'dart:convert';

/// Execution policy controlling whether multiple OS processes of the same
/// desktop application may run concurrently.
enum InstanceMode {
  /// Restricts the application to a single primary OS process per user session
  /// (default).
  ///
  /// Launching a second executable forwards its [SecondInstancePayload] to the
  /// primary process, brings the primary window to the foreground, and exits
  /// the secondary process before rendering any UI or tray icon.
  singleInstance,

  /// Allows unlimited independent OS processes to run concurrently.
  multiInstance,
}

/// Context forwarded from a secondary launch invocation to the primary running
/// process when [InstanceMode.singleInstance] is active.
final class SecondInstancePayload {
  /// Creates a [SecondInstancePayload].
  const SecondInstancePayload({
    required this.arguments,
    required this.workingDirectory,
  });

  /// Command-line arguments passed to the secondary process.
  final List<String> arguments;

  /// Working directory of the secondary process when launched.
  final String workingDirectory;

  /// Encodes this payload as a single-line UTF-8 JSON string.
  String encodeJson() =>
      jsonEncode(<String, Object>{'args': arguments, 'cwd': workingDirectory});

  /// Parses a JSON string produced by [encodeJson], returning `null` if
  /// malformed.
  static SecondInstancePayload? tryDecodeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final rawArgs = decoded['args'];
      final args =
          rawArgs is List
              ? rawArgs.whereType<String>().toList(growable: false)
              : const <String>[];
      final cwd = decoded['cwd'];
      return SecondInstancePayload(
        arguments: args,
        workingDirectory: cwd is String ? cwd : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Deterministic 32-bit FNV-1a hash formatted as an 8-character lowercase hex
/// string so distinct `appId` values never collide after character sanitization
/// and Unix domain socket paths stay well below the 104-byte BSD/macOS limit.
String computeSingleInstanceHash(String appId) {
  final bytes = utf8.encode(appId);
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Converts an arbitrary [appId] into a kernel-object-safe and filesystem-safe
/// token (`[A-Za-z0-9._-]` + 8-hex digest, max 49 chars).
String sanitizeSingleInstanceToken(String appId) {
  final trimmed = appId.trim().isEmpty ? 'native_core_app' : appId.trim();
  final buffer = StringBuffer();
  for (var i = 0; i < trimmed.length && buffer.length < 40; i++) {
    final unit = trimmed.codeUnitAt(i);
    final isAlphaNum =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A);
    if (isAlphaNum || unit == 0x2E || unit == 0x2D || unit == 0x5F) {
      buffer.writeCharCode(unit);
    } else {
      buffer.writeCharCode(0x5F);
    }
  }
  final prefix = buffer.isEmpty ? 'app' : buffer.toString();
  return '${prefix}_${computeSingleInstanceHash(trimmed)}';
}

/// Internal contract implemented by OS-specific single-instance coordinators.
abstract interface class SingleInstanceCoordinator {
  /// Acquires primary ownership for `token`, or forwards [payload] to the
  /// existing primary process and returns `false`.
  Future<bool> acquireOrForward({
    required String token,
    required SecondInstancePayload payload,
    required bool activateExistingWindow,
    required void Function() onActivatePrimaryWindow,
    required void Function(SecondInstancePayload payload)? onSecondInstance,
  });

  /// Releases the underlying OS mutex or domain socket owned by this primary
  /// coordinator.
  Future<void> release();
}
