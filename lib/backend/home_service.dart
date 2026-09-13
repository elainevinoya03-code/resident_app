import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_service.dart';

/// An emergency hotline entry from the `hotlines` table, rendered as a pill
/// on the home screen.
class Hotline {
  final String id;
  final String label;
  final String number;
  final int sortOrder;

  const Hotline({
    required this.id,
    required this.label,
    required this.number,
    this.sortOrder = 0,
  });

  factory Hotline.fromJson(Map<String, dynamic> json) => Hotline(
        id: '${json['id'] ?? ''}',
        label: '${json['label'] ?? ''}',
        number: '${json['number'] ?? ''}',
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

/// A broadcast alert stored in the `notifications` table. Severity is one of
/// `critical`, `high`, `medium`, `low`.
class AlertNotification {
  final String id;
  final String severity;
  final bool acknowledged;
  final DateTime publishedAt;
  final String title;
  final String body;

  const AlertNotification({
    required this.id,
    required this.title,
    required this.body,
    this.severity = 'medium',
    this.acknowledged = false,
    required this.publishedAt,
  });

  bool get isUnread => !acknowledged;

  factory AlertNotification.fromJson(Map<String, dynamic> json) {
    return AlertNotification(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      severity: '${json['severity'] ?? 'medium'}',
      acknowledged: json['acknowledged'] as bool? ?? false,
      publishedAt:
          DateTime.tryParse('${json['published_at'] ?? ''}') ?? DateTime.now(),
    );
  }
}

/// Aggregated report counts plus the most recent reports for the resident,
/// used by the home dashboard ("Track My Reports" + "Recent Reports").
class ReportSummary {
  final int total;
  final int inProgress;
  final int resolved;
  final List<ReportRecord> recent;

  const ReportSummary({
    this.total = 0,
    this.inProgress = 0,
    this.resolved = 0,
    this.recent = const [],
  });
}

/// Everything the home screen needs in a single object.
class HomeDashboard {
  final String residentName;
  final List<Hotline> hotlines;
  final int unreadAlerts;
  final ReportSummary reports;

  const HomeDashboard({
    this.residentName = '',
    this.hotlines = const [],
    this.unreadAlerts = 0,
    required this.reports,
  });
}

/// Dart backend for the home dashboard. Reads directly from the same
/// PostgreSQL schema used by the rest of the app (Supabase / PostgREST):
///   - `hotlines`       -> emergency hotline pills
///   - `notifications`  -> alert badge count + Alerts tab data
///   - `reports`        -> report counts + recent report rows
///
/// Every method degrades gracefully: on a network/DB failure an empty value
/// is returned so the UI still renders (hotlines fall back to defaults).
class HomeService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const String _hotlinesTable = 'hotlines';
  static const String _alertsTable = 'notifications';
  static const String _reportsTable = 'reports';

  // ───────────────────── Dashboard ─────────────────────

  /// Load everything the home screen needs in one call.
  static Future<HomeDashboard> loadDashboard({
    String residentName = '',
    String userEmail = '',
  }) async {
    final results = await Future.wait<Object?>([
      fetchHotlines(),
      fetchUnreadAlerts(),
      fetchReportSummary(userEmail),
    ]);

    return HomeDashboard(
      residentName: residentName,
      hotlines: (results[0] as List<Hotline>?) ?? const [],
      unreadAlerts: (results[1] as int?) ?? 0,
      reports: (results[2] as ReportSummary?) ?? const ReportSummary(),
    );
  }

  // ───────────────────── Hotlines ─────────────────────

  /// Fetch the active emergency hotlines, ordered by [Hotline.sortOrder].
  /// Returns an empty list when the table is missing or unreachable.
  static Future<List<Hotline>> fetchHotlines() async {
    try {
      final data = await _client
          .from(_hotlinesTable)
          .select('id,label,number,sort_order')
          .eq('is_active', true)
          .order('sort_order');
      return (data as List<dynamic>)
          .map((row) => Hotline.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  // ───────────────────── Alerts ─────────────────────

  /// Count of broadcast alerts a resident still has to acknowledge — this is
  /// the red badge number on the home header bell icon.
  static Future<int> fetchUnreadAlerts() async {
    try {
      return await _client
          .from(_alertsTable)
          .select('id')
          .eq('acknowledged', false)
          .count(CountOption.exact);
    } on PostgrestException {
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Recent broadcast alerts (newest first).
  static Future<List<AlertNotification>> fetchRecentAlerts({
    int limit = 20,
  }) async {
    try {
      final data = await _client
          .from(_alertsTable)
          .select('id,title,body,severity,acknowledged,published_at')
          .order('published_at', ascending: false)
          .limit(limit);
      return (data as List<dynamic>)
          .map((row) => AlertNotification.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Mark a broadcast alert as acknowledged.
  static Future<void> acknowledgeAlert(String alertId) async {
    await _client
        .from(_alertsTable)
        .update({'acknowledged': true})
        .eq('id', alertId);
  }

  // ───────────────────── Report summary ─────────────────────

  /// Aggregate the resident's reports: total count, how many are still in
  /// progress, how many are resolved/closed, and the 3 most recent rows.
  static Future<ReportSummary> fetchReportSummary(String userEmail) async {
    final email = userEmail.trim().toLowerCase();
    if (email.isEmpty) return const ReportSummary();

    try {
      final recent = await _client
          .from(_reportsTable)
          .select(
            '*, report_photos(*), report_videos(*), report_status_updates(*)',
          )
          .eq('user_email', email)
          .order('created_at', ascending: false)
          .limit(3);

      final records = (recent as List<dynamic>)
          .map((row) => ReportRecord.fromJson(row as Map<String, dynamic>))
          .toList();

      final total = await _client
          .from(_reportsTable)
          .select('id')
          .eq('user_email', email)
          .count(CountOption.exact);

      final resolved = await _client
          .from(_reportsTable)
          .select('id')
          .eq('user_email', email)
          .inFilter('status', ['resolved', 'closed'])
          .count(CountOption.exact);

      return ReportSummary(
        total: total,
        inProgress: total - resolved,
        resolved: resolved,
        recent: records,
      );
    } on PostgrestException {
      return const ReportSummary();
    } catch (_) {
      return const ReportSummary();
    }
  }
}