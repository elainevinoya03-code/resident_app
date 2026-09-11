import 'package:flutter/material.dart';
import 'login.dart' show AppColors;
import 'bottom_nav.dart';
import 'home.dart';
import 'notification.dart';
import 'report.dart';
import 'settings.dart';

enum ReportStatus { inProgress, resolved, closed }

/// One entry in a report's status timeline (New, Acknowledged, In Progress,
/// Resolved, Closed...). The last entry in the list is treated as the
/// "current" step and gets highlighted with the report's status color.
class StatusUpdate {
  final String title;
  final String date;
  final String description;

  const StatusUpdate({
    required this.title,
    required this.date,
    required this.description,
  });
}

class ReportItem {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String category; // e.g. 'Fire & Emergency'
  final String subtype; // e.g. 'Smoke / Burning Complaint'
  final String location;
  final String refId;
  final ReportStatus status;
  final bool showRating; // "Rate this" row shown under resolved reports

  // ---- Detail-screen fields ----
  final String dateTime;
  final String description;
  final String responderName;
  final String responderPhone;
  final List<StatusUpdate> updates;

  ReportItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.category,
    required this.subtype,
    required this.location,
    required this.refId,
    required this.status,
    this.showRating = false,
    String? dateTime,
    String? description,
    String? responderName,
    String? responderPhone,
    this.updates = const [],
  }) : dateTime = dateTime ?? '',
       description = description ?? '',
       responderName = responderName ?? '',
       responderPhone = responderPhone ?? '';
}

// Sample front-end data matching the reference design.
final List<ReportItem> _sampleReports = [
  ReportItem(
    icon: Icons.local_fire_department,
    iconBg: AppColors.iconCircleFire,
    iconColor: AppColors.hotlineRed,
    category: 'Fire & Emergency',
    subtype: 'Smoke / Burning Complaint',
    location: 'Brgy. Tandang Sora, Quezon City',
    refId: 'INC-2025-06-00123',
    status: ReportStatus.inProgress,
    dateTime: 'Jun 12, 2025 · 8:14 AM',
    description:
        'Smoke visible from an abandoned building near the basketball court on Tandang Sora Avenue.',
    responderName: 'SPO1 Juan dela Cruz',
    responderPhone: '0917-555-1234',
    updates: const [
      StatusUpdate(
        title: 'New',
        date: 'Jun 12 · 8:14 AM',
        description: 'Report received and logged by the system.',
      ),
      StatusUpdate(
        title: 'Acknowledged',
        date: 'Jun 12 · 8:22 AM',
        description: 'BFP Tandang Sora Station assigned to respond.',
      ),
      StatusUpdate(
        title: 'In Progress',
        date: 'Jun 12 · 8:45 AM',
        description:
            'Fire truck dispatched. Smoke contained — no structural damage.',
      ),
    ],
  ),
  ReportItem(
    icon: Icons.volume_up_outlined,
    iconBg: AppColors.iconCircleNoise,
    iconColor: AppColors.statusResolvedText,
    category: 'Community Disputes',
    subtype: 'Noise Complaint',
    location: 'Brgy. Tandang Sora, Quezon City',
    refId: 'INC-2025-05-00087',
    status: ReportStatus.resolved,
    showRating: true,
    dateTime: 'May 28, 2025 · 11:03 PM',
    description:
        'Loud videoke and music until 2 AM every Friday night near Visayas Avenue. Multiple households affected for three weeks.',
    responderName: 'Bgy. Tanod Jose Santos',
    responderPhone: '0912-888-5678',
    updates: const [
      StatusUpdate(
        title: 'New',
        date: 'May 28 · 11:03 PM',
        description: 'Report received.',
      ),
      StatusUpdate(
        title: 'Acknowledged',
        date: 'May 28 · 11:15 PM',
        description: 'Barangay tanod notified and dispatched.',
      ),
      StatusUpdate(
        title: 'In Progress',
        date: 'May 28 · 11:40 PM',
        description: 'Tanod visited site. Spoken to property owner.',
      ),
      StatusUpdate(
        title: 'Resolved',
        date: 'May 29 · 12:05 AM',
        description: 'Noise stopped. Owner complied with ordinance.',
      ),
    ],
  ),
  ReportItem(
    icon: Icons.directions_car_outlined,
    iconBg: AppColors.iconCircleRoad,
    iconColor: AppColors.ratingStar,
    category: 'Traffic & Road',
    subtype: 'Road Obstruction',
    location: 'Brgy. Tandang Sora, Quezon City',
    refId: 'INC-2025-05-00044',
    status: ReportStatus.closed,
    dateTime: 'May 15, 2025 · 6:32 AM',
    description:
        'Fallen tree blocking the northbound lane of Tandang Sora Ave. near Congressional Avenue.',
    responderName: 'DPWH-NCR Crew 3',
    responderPhone: '',
    updates: const [
      StatusUpdate(
        title: 'New',
        date: 'May 15 · 6:32 AM',
        description: 'Report received.',
      ),
      StatusUpdate(
        title: 'Acknowledged',
        date: 'May 15 · 7:00 AM',
        description: 'DPWH notified and cleared for dispatch.',
      ),
      StatusUpdate(
        title: 'In Progress',
        date: 'May 15 · 9:15 AM',
        description: 'Clearing crew on site with chainsaw equipment.',
      ),
      StatusUpdate(
        title: 'Resolved',
        date: 'May 15 · 11:30 AM',
        description: 'Tree fully removed. Road clear in both directions.',
      ),
      StatusUpdate(
        title: 'Closed',
        date: 'May 15 · 2:00 PM',
        description: 'Case officially closed.',
      ),
    ],
  ),
];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _navIndex = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<ReportItem> get _all => _sampleReports;
  List<ReportItem> get _active =>
      _sampleReports.where((r) => r.status == ReportStatus.inProgress).toList();
  List<ReportItem> get _resolved => _sampleReports
      .where(
        (r) =>
            r.status == ReportStatus.resolved ||
            r.status == ReportStatus.closed,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          setState(() => _navIndex = i);
          if (i == 0) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 200),
                reverseTransitionDuration: const Duration(milliseconds: 200),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const HomeScreen(),
              ),
            );
          } else if (i == 2) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 200),
                reverseTransitionDuration: const Duration(milliseconds: 200),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const AlertsScreen(),
              ),
            );
          } else if (i == 3) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 200),
                reverseTransitionDuration: const Duration(milliseconds: 200),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const SettingsScreen(),
              ),
            );
          }
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Header ----
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Reports',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textGray,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Active'),
                      Tab(text: 'Resolved'),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            // ---- Tab content ----
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ReportList(reports: _all),
                  _ReportList(reports: _active),
                  _ReportList(reports: _resolved),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final List<ReportItem> reports;
  const _ReportList({required this.reports});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        for (final report in reports) ...[
          _ReportCard(report: report),
          const SizedBox(height: 12),
        ],
        const _ReportIncidentButton(),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportItem report;
  const _ReportCard({required this.report});

  String get _statusLabel {
    switch (report.status) {
      case ReportStatus.inProgress:
        return 'In Progress';
      case ReportStatus.resolved:
        return 'Resolved';
      case ReportStatus.closed:
        return 'Closed';
    }
  }

  Color get _statusBg {
    switch (report.status) {
      case ReportStatus.inProgress:
        return AppColors.statusInProgressBg;
      case ReportStatus.resolved:
        return AppColors.statusResolvedBg;
      case ReportStatus.closed:
        return AppColors.statusClosedBg;
    }
  }

  Color get _statusText {
    switch (report.status) {
      case ReportStatus.inProgress:
        return AppColors.statusInProgressText;
      case ReportStatus.resolved:
        return AppColors.statusResolvedText;
      case ReportStatus.closed:
        return AppColors.statusClosedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReportDetailsScreen(report: report),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: report.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(report.icon, color: report.iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.subtype,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                report.category,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _statusBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _statusText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.location,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.refId,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                    ),
                    if (report.showRating) ...[
                      const SizedBox(height: 14),
                      const Center(child: _RateThisRow()),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.textGray,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateThisRow extends StatefulWidget {
  const _RateThisRow();

  @override
  State<_RateThisRow> createState() => _RateThisRowState();
}

class _RateThisRowState extends State<_RateThisRow> {
  int _selectedRating = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...List.generate(
          5,
          (i) => GestureDetector(
            onTap: () {
              setState(() => _selectedRating = i + 1);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Rated ${i + 1} star${i == 0 ? '' : 's'} — Thank you!',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                i < _selectedRating ? Icons.star : Icons.star_border,
                size: 15,
                color: AppColors.ratingStar,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _selectedRating > 0
              ? '$_selectedRating star${_selectedRating == 1 ? '' : 's'}'
              : 'Rate this',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ratingStar,
          ),
        ),
      ],
    );
  }
}

class _ReportIncidentButton extends StatelessWidget {
  const _ReportIncidentButton();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => const ReportIncidentFlow(),
          ),
        );
      },
      child: CustomPaint(
        painter: _DashedRRectPainter(
          color: AppColors.textGray.withValues(alpha: 0.4),
          radius: 16,
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 17,
                  color: AppColors.textGray,
                ),
                SizedBox(width: 8),
                Text(
                  'Report an Incident',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple dashed rounded-rectangle border painter — avoids pulling in an
/// external package just for one dashed outline.
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.4;
    const dashWidth = 5.0;
    const dashGap = 4.0;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) => false;
}

// ============================================================================
// Report Details screen
// ============================================================================

class ReportDetailsScreen extends StatelessWidget {
  final ReportItem report;
  const ReportDetailsScreen({super.key, required this.report});

  String get _statusLabel {
    switch (report.status) {
      case ReportStatus.inProgress:
        return 'In Progress';
      case ReportStatus.resolved:
        return 'Resolved';
      case ReportStatus.closed:
        return 'Closed';
    }
  }

  Color get _statusBg {
    switch (report.status) {
      case ReportStatus.inProgress:
        return AppColors.statusInProgressBg;
      case ReportStatus.resolved:
        return AppColors.statusResolvedBg;
      case ReportStatus.closed:
        return AppColors.statusClosedBg;
    }
  }

  Color get _statusText {
    switch (report.status) {
      case ReportStatus.inProgress:
        return AppColors.statusInProgressText;
      case ReportStatus.resolved:
        return AppColors.statusResolvedText;
      case ReportStatus.closed:
        return AppColors.statusClosedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Header ----
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 14, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.textDark,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Report Details',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          report.refId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _statusText,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ---- Body ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  _InfoCard(report: report),
                  const SizedBox(height: 14),
                  _ResponderCard(report: report),
                  const SizedBox(height: 14),
                  _StatusUpdatesCard(report: report),
                  if (report.showRating) ...[
                    const SizedBox(height: 14),
                    const _RateResponseCard(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final ReportItem report;
  const _InfoCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: report.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(report.icon, color: report.iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      report.subtype,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.category,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _IconLine(
                      icon: Icons.location_on_outlined,
                      text: report.location,
                    ),
                    const SizedBox(height: 3),
                    _IconLine(icon: Icons.access_time, text: report.dateTime),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.description,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.textGray),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textGray),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textGray,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _ResponderCard extends StatelessWidget {
  final ReportItem report;
  const _ResponderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Assigned Responder'),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.statusClosedBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: AppColors.textGray,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.responderName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (report.responderPhone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        report.responderPhone,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (report.responderPhone.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Calling ${report.responderPhone}…'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.iconCircleFire,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone_outlined,
                      color: AppColors.hotlineRed,
                      size: 17,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusUpdatesCard extends StatelessWidget {
  final ReportItem report;
  const _StatusUpdatesCard({required this.report});

  Color get _currentColor {
    switch (report.status) {
      case ReportStatus.inProgress:
        return AppColors.statusInProgressText;
      case ReportStatus.resolved:
        return AppColors.statusResolvedText;
      case ReportStatus.closed:
        return AppColors.statusClosedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = report.updates;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Status Updates'),
          const SizedBox(height: 14),
          for (int i = 0; i < updates.length; i++)
            _TimelineStep(
              update: updates[i],
              isLast: i == updates.length - 1,
              isCurrent: i == updates.length - 1,
              highlightColor: _currentColor,
            ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final StatusUpdate update;
  final bool isLast;
  final bool isCurrent;
  final Color highlightColor;

  const _TimelineStep({
    required this.update,
    required this.isLast,
    required this.isCurrent,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = isCurrent
        ? highlightColor
        : AppColors.textGray.withValues(alpha: 0.35);
    final Color titleColor = isCurrent ? highlightColor : AppColors.textGray;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 1.5, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    update.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    update.date,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    update.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone "Rate the Response" card shown on the details screen for
/// resolved reports. Tracks its own selected star count and shows a
/// confirmation state once submitted.
class _RateResponseCard extends StatefulWidget {
  const _RateResponseCard();

  @override
  State<_RateResponseCard> createState() => _RateResponseCardState();
}

class _RateResponseCardState extends State<_RateResponseCard> {
  static const Color _cardBg = Color(0xFFFFF9E9);
  static const Color _cardBorder = Color(0xFFF0D98C);
  static const Color _submitBg = AppColors.primaryButtonDisabled;

  int _selectedRating = 0;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rate the Response',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Your feedback helps improve community services.',
            style: TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
          const SizedBox(height: 14),
          if (_submitted)
            const Row(
              children: [
                Icon(Icons.check_circle, size: 17, color: AppColors.success),
                SizedBox(width: 6),
                Text(
                  'Thank you for your feedback!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: List.generate(
                5,
                (i) => GestureDetector(
                  onTap: () => setState(() => _selectedRating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      i < _selectedRating ? Icons.star : Icons.star_border,
                      size: 26,
                      color: AppColors.ratingStar,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedRating == 0
                    ? null
                    : () => setState(() => _submitted = true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: _submitBg.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Submit Rating',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
