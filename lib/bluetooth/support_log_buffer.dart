/// A bounded, newest-kept ring of timestamped log lines for the support bundle.
///
/// [Connection] keeps two of these: one for app-level events (shifts, ERG
/// targets, errors) and one for the verbose DirCon/trainer wire trace. Keeping
/// them separate means a high-rate trace can never evict the high-level events
/// a support bundle needs — the ThinkRider XX Pro beta bundle arrived as
/// 2000/2000 wire-trace frames with zero app entries because both shared one
/// buffer, which made every trainer-control issue undiagnosable.
class SupportLogBuffer {
  SupportLogBuffer(this.cap) : assert(cap > 0);

  /// Maximum number of entries retained; older entries are dropped first.
  final int cap;

  var _entries = <({DateTime date, String entry})>[];

  /// Oldest-to-newest view of the retained entries.
  List<({DateTime date, String entry})> get entries => _entries;

  void add(String entry, {DateTime? at}) {
    _entries.add((date: at ?? DateTime.now(), entry: entry));
    if (_entries.length > cap) {
      _entries = _entries.sublist(_entries.length - cap);
    }
  }

  void clear() => _entries = [];
}
