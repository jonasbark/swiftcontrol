import 'dart:convert';

enum SelfTestVerdict { pass, ergOkVsFail, noControl, noData, aborted }

class SelfTestResult {
  final DateTime at;
  final SelfTestVerdict verdict;
  final int ergStepsPassed;
  final int ergStepsTotal;
  final int shiftStepsPassed;
  final int shiftStepsTotal;
  final String vsMode;
  final String protocol;

  const SelfTestResult({
    required this.at,
    required this.verdict,
    required this.ergStepsPassed,
    required this.ergStepsTotal,
    required this.shiftStepsPassed,
    required this.shiftStepsTotal,
    required this.vsMode,
    required this.protocol,
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
    return '$verdictLabel,$dateStr,a:$ergStr,b:$shiftStr,$vsMode';
  }

  static String _verdictToLabel(SelfTestVerdict verdict) {
    return switch (verdict) {
      SelfTestVerdict.pass => 'PASS',
      SelfTestVerdict.ergOkVsFail => 'ERG_OK_VS_FAIL',
      SelfTestVerdict.noControl => 'NO_CONTROL',
      SelfTestVerdict.noData => 'NO_DATA',
      SelfTestVerdict.aborted => 'ABORTED',
    };
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
