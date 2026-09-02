import 'dart:convert';

/// [vsOkErgFail] is the mirror of [ergOkVsFail]: the trainer honours the gear
/// ratio but not the ERG target. Several "Zwift Ready" trainers implement only
/// the virtual-shifting subset of the Zwift Sync command set and expect ERG
/// over FTMS, which used to score as [noControl] and send the rider off to
/// change a protocol that was already driving their shifting.
enum SelfTestVerdict { pass, ergOkVsFail, vsOkErgFail, noControl, noData, aborted }

class SelfTestResult {
  final DateTime at;
  final SelfTestVerdict verdict;
  final int ergStepsPassed;
  final int ergStepsTotal;
  final int shiftStepsPassed;
  final int shiftStepsTotal;
  final String vsMode;
  final String protocol;

  /// True when the trainer reported no cadence, so the shift sweep was scored
  /// on power alone without the "did the rider hold cadence" cross-check. A
  /// caveat on the verdict, and shown to the rider as one.
  final bool cadenceless;

  /// The engine's per-step diagnostic lines: the same short English lines it
  /// mirrors into the harness log. Kept on the result so the support bundle can
  /// show the per-gear plateau numbers long after the volatile app log that
  /// used to be their only home has rolled over.
  final List<String> stepLog;

  const SelfTestResult({
    required this.at,
    required this.verdict,
    required this.ergStepsPassed,
    required this.ergStepsTotal,
    required this.shiftStepsPassed,
    required this.shiftStepsTotal,
    required this.vsMode,
    required this.protocol,
    this.cadenceless = false,
    this.stepLog = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'at': at.toIso8601String(),
      'verdict': verdict.name,
      'ergStepsPassed': ergStepsPassed,
      'ergStepsTotal': ergStepsTotal,
      'shiftStepsPassed': shiftStepsPassed,
      'shiftStepsTotal': shiftStepsTotal,
      'vsMode': vsMode,
      'protocol': protocol,
      'cadenceless': cadenceless,
      // Cap to the tail: a pathological run could log a great many lines, and
      // the newest ones (the last plateaus) are the ones worth keeping.
      'stepLog': stepLog.length > 200 ? stepLog.sublist(stepLog.length - 200) : stepLog,
    };
  }

  factory SelfTestResult.fromJson(Map<String, dynamic> json) {
    return SelfTestResult(
      at: DateTime.parse(json['at'] as String),
      verdict: SelfTestVerdict.values.byName(json['verdict'] as String),
      ergStepsPassed: json['ergStepsPassed'] as int,
      ergStepsTotal: json['ergStepsTotal'] as int,
      shiftStepsPassed: json['shiftStepsPassed'] as int,
      shiftStepsTotal: json['shiftStepsTotal'] as int,
      vsMode: json['vsMode'] as String,
      protocol: json['protocol'] as String,
      // Absent from every result stored before the flag existed.
      cadenceless: json['cadenceless'] as bool? ?? false,
      // Absent from every result stored before the step log existed.
      stepLog: (json['stepLog'] as List?)?.cast<String>() ?? const [],
    );
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  static SelfTestResult? tryParse(String? s) {
    if (s == null) {
      return null;
    }
    try {
      final json = jsonDecode(s) as Map<String, dynamic>;
      return SelfTestResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  String toBundleString() {
    final verdictLabel = _verdictToLabel(verdict);
    final dateStr = _formatDate(at);
    final ergStr = ergStepsTotal == 0 ? 'n/a' : '$ergStepsPassed/$ergStepsTotal';
    final shiftStr = '$shiftStepsPassed/$shiftStepsTotal';
    // Suffix, not a column: every bundle string written before this stays
    // byte-identical, and `no-cadence` only shows where it actually applies.
    return '$verdictLabel,$dateStr,a:$ergStr,b:$shiftStr,$vsMode${cadenceless ? ',no-cadence' : ''}';
  }

  static String _verdictToLabel(SelfTestVerdict verdict) {
    return switch (verdict) {
      SelfTestVerdict.pass => 'PASS',
      SelfTestVerdict.ergOkVsFail => 'ERG_OK_VS_FAIL',
      SelfTestVerdict.vsOkErgFail => 'VS_OK_ERG_FAIL',
      SelfTestVerdict.noControl => 'NO_CONTROL',
      SelfTestVerdict.noData => 'NO_DATA',
      SelfTestVerdict.aborted => 'ABORTED',
    };
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
