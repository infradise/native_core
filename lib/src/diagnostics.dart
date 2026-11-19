/// Signature for reporting non-fatal native FFI or lifecycle exceptions caught
/// inside `native_core`.
typedef NativeCoreErrorReporter =
    void Function(String operation, Object error, StackTrace stackTrace);

/// Optional diagnostic hook for observing non-fatal native OS FFI exceptions.
///
/// Production code isolates native lookup and windowing errors so host
/// applications never crash in headless test runners or stripped containers.
/// Assigning [onError] during development or integration testing surfaces every
/// caught exception with its operation context and stack trace.
abstract final class NativeCoreDiagnostics {
  /// Optional callback invoked whenever a non-fatal FFI error is caught.
  ///
  /// Defaults to `null` (zero overhead in production).
  static NativeCoreErrorReporter? onError;

  /// Forwards [error] and [stackTrace] for [operation] to [onError] when set.
  static void report(String operation, Object error, StackTrace stackTrace) {
    final reporter = onError;
    if (reporter == null) return;
    try {
      reporter(operation, error, stackTrace);
    } catch (_) {
      // Never allow a diagnostic observer failure to destabilize FFI callers.
    }
  }
}
