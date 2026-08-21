import 'dart:convert';

import 'network_check.dart';

class NetworkSelfTestResult {
  final DateTime at;
  final String platform; // Platform.operatingSystem
  final String obcBackend; // ObpMdnsBackend.name
  final String? hostname;
  final List<NetworkCheck> checks;
  final bool completed; // false when cancelled mid-run

  NetworkVerdict get verdict => overallVerdict(checks);

  const NetworkSelfTestResult({
    required this.at,
    required this.platform,
    required this.obcBackend,
    this.hostname,
    required this.checks,
    required this.completed,
  });

  Map<String, dynamic> toJson() {
    return {
      'at': at.toIso8601String(),
      'platform': platform,
      'obcBackend': obcBackend,
      if (hostname != null) 'hostname': hostname,
      'checks': checks.map((c) => _checkToJson(c)).toList(),
      'completed': completed,
    };
  }

  static Map<String, dynamic> _checkToJson(NetworkCheck check) {
    return {
      'id': check.id.name,
      'verdict': check.verdict.name,
      'detail': check.detail,
      'fixes': check.fixes.map((f) => f.name).toList(),
    };
  }

  /// Tolerant: unknown check ids, verdicts, or fix ids are DROPPED silently,
  /// never thrown. Used to survive schema growth across app versions.
  factory NetworkSelfTestResult.fromJson(Map<String, dynamic> json) {
    final rawChecks = json['checks'] as List<dynamic>? ?? const [];
    final checks = <NetworkCheck>[];
    for (final rawCheck in rawChecks) {
      final check = _checkFromJson(rawCheck as Map<String, dynamic>);
      if (check != null) {
        checks.add(check);
      }
    }
    return NetworkSelfTestResult(
      at: DateTime.parse(json['at'] as String),
      platform: json['platform'] as String,
      obcBackend: json['obcBackend'] as String,
      hostname: json['hostname'] as String?,
      checks: checks,
      completed: json['completed'] as bool,
    );
  }

  static NetworkCheck? _checkFromJson(Map<String, dynamic> json) {
    final id = _parseEnum(NetworkCheckId.values, json['id'] as String?);
    if (id == null) {
      return null;
    }
    final verdict = _parseEnum(NetworkVerdict.values, json['verdict'] as String?);
    if (verdict == null) {
      return null;
    }
    final rawDetail = json['detail'] as Map<String, dynamic>? ?? const {};
    final detail = rawDetail.map((key, value) => MapEntry(key, value as String));
    final rawFixes = json['fixes'] as List<dynamic>? ?? const [];
    final fixes = <NetworkFixId>[];
    for (final rawFix in rawFixes) {
      final fix = _parseEnum(NetworkFixId.values, rawFix as String?);
      if (fix != null) {
        fixes.add(fix);
      }
    }
    return NetworkCheck(id: id, verdict: verdict, detail: detail, fixes: fixes);
  }

  static T? _parseEnum<T extends Enum>(List<T> values, String? name) {
    if (name == null) {
      return null;
    }
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// Pure parse, no side effects: returns null on garbage instead of
  /// recording an error (mirrors SelfTestResult.tryParse).
  static NetworkSelfTestResult? tryParse(String? s) {
    if (s == null) {
      return null;
    }
    try {
      final json = jsonDecode(s) as Map<String, dynamic>;
      return NetworkSelfTestResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// One line per non-skipped check: `id=verdict[ key=value ...]`, prefixed
  /// by a header line `NETWORK &lt;VERDICT&gt;,&lt;yyyy-mm-dd&gt;,&lt;platform&gt;,&lt;backend&gt;
  /// [,host=&lt;hostname&gt;]`.
  String toBundleString() {
    final lines = <String>[_headerLine()];
    for (final check in checks) {
      if (check.verdict == NetworkVerdict.skipped) {
        continue;
      }
      lines.add(_checkLine(check));
    }
    return lines.join('\n');
  }

  String _headerLine() {
    final buffer = StringBuffer('NETWORK ${verdict.name.toUpperCase()},${_formatDate(at)},$platform,$obcBackend');
    if (hostname != null) {
      buffer.write(',host=$hostname');
    }
    return buffer.toString();
  }

  static String _checkLine(NetworkCheck check) {
    final sortedKeys = check.detail.keys.toList()..sort();
    final detailStr = sortedKeys.map((key) => '$key=${check.detail[key]}').join(' ');
    final base = '${check.id.name}=${check.verdict.name}';
    return detailStr.isEmpty ? base : '$base $detailStr';
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
