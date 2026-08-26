/// Wraps [compute] so the work only starts the first time the returned
/// function is called, and every call after that returns the exact same
/// in-flight/completed [Future] instead of repeating it.
///
/// Used for support-diagnostics gathers (`debugText()`, which runs a real
/// mDNS discovery scan) that are only worth paying for once a rider actually
/// commits to a support chat, not the moment a caller merely *might* route
/// them there — and, once paid, should be shared by both the composer's
/// diagnostic preview and whatever telemetry gets attached at send time
/// rather than gathered twice.
Future<T> Function() memoizeAsync<T>(Future<T> Function() compute) {
  Future<T>? cached;
  return () => cached ??= compute();
}
