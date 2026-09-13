import 'package:flutter/material.dart';
import 'login.dart' show AppColors;
import 'bottom_nav.dart';
import 'my_report.dart';
import 'notification.dart';
import 'report.dart';
import 'settings.dart';
import '../backend/auth_store.dart';
import '../backend/home_service.dart';
import '../backend/report_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  /// Dashboard data loaded from SQL (via [HomeService]).
  HomeDashboard? _dashboard;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final auth = await AuthStore.load();
      final profile = auth.account;
      final dashboard = await HomeService.loadDashboard(
        residentName: profile?.firstName ?? '',
        userEmail: profile?.email ?? '',
      );
      if (!mounted) return;
      setState(() => _dashboard = dashboard);
    } catch (_) {
      // Keep previous data (or empty placeholders) on failure.
    }
  }

  /// Greeting label — the resident's first name, 'Resident' as fallback.
  String get _greetingName {
    final name = (_dashboard?.residentName ?? '').trim();
    return name.isEmpty ? 'Resident' : name;
  }

  /// Hotlines from the DB, or the reference list when SQL is unreachable.
  List<Hotline> get _hotlines {
    final list = _dashboard?.hotlines ?? const <Hotline>[];
    return list.isEmpty ? _defaultHotlines : list;
  }

  /// "Track My Reports" summary line.
  String get _reportSummaryText {
    final summary = _dashboard?.reports;
    if (summary == null || summary.total == 0) return 'No reports yet';
    final total =
        summary.total == 1 ? '1 report' : '${summary.total} reports';
    final progress = summary.inProgress == 1
        ? '1 in progress'
        : '${summary.inProgress} in progress';
    return '$total · $progress';
  }

  /// The most recent report rows shown under "RECENT REPORTS".
  List<ReportRecord> get _recentReports =>
      _dashboard?.reports.recent ?? const <ReportRecord>[];

  /// Fallback hotlines used when the `hotlines` table is empty/unreachable.
  static final List<Hotline> _defaultHotlines = const [
    Hotline(id: 'bfp', label: 'BFP', number: '911', sortOrder: 1),
    Hotline(id: 'pnp', label: 'PNP', number: '911', sortOrder: 2),
    Hotline(id: 'tsemsd', label: 'TSEMSD', number: '8922-7000', sortOrder: 3),
    Hotline(id: 'ndrrmo', label: 'NDRRMO', number: '911', sortOrder: 4),
  ];

  void _onNavTap(int index) {
    if (index == 1) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ReportsScreen(),
        ),
      );
    } else if (index == 2) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          pageBuilder: (context, animation, secondaryAnimation) =>
              const AlertsScreen(),
        ),
      );
    } else if (index == 3) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          pageBuilder: (context, animation, secondaryAnimation) =>
              const SettingsScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _navIndex,
        onTap: _onNavTap,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Header ----
            Container(
              color: AppColors.primaryDark,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Good morning',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _greetingName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AlertsScreen(),
                            ),
                          );
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_none,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            Positioned(
                              right: -2,
                              top: -2,
                              child: (_dashboard?.unreadAlerts ?? 0) > 0
                                  ? Container(
                                      width: 18,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: AppColors.badgeRed,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${_dashboard?.unreadAlerts ?? 0}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMERGENCY HOTLINES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (var i = 0; i < _hotlines.length; i++) ...[
                              Expanded(
                                child: _HotlinePill(
                                  label: _hotlines[i].label,
                                  number: _hotlines[i].number,
                                ),
                              ),
                              if (i < _hotlines.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---- Body ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: [
                  // ── Prominent Emergency / SOS button ──
                  _EmergencyCard(
                    onTap: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                          pageBuilder: (_, __, ___) =>
                              const EmergencyReportFlow(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _ActionCard(
                    color: AppColors.reportCardGreen,
                    iconBg: Colors.white.withOpacity(0.15),
                    icon: Icons.local_fire_department,
                    iconColor: Colors.white,
                    title: 'report an incident',
                    titleColor: Colors.white,
                    subtitle: 'property · community · noise · road · animal · environment',
                    subtitleColor: Colors.white70,
                    chevronColor: Colors.white70,
                    onTap: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                          pageBuilder: (_, __, ___) =>
                              const ReportIncidentFlow(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _ActionCard(
                    color: Colors.white,
                    iconBg: AppColors.iconCircleDoc,
                    icon: Icons.description_outlined,
                    iconColor: AppColors.primary,
                    title: 'Track My Reports',
                    titleColor: AppColors.textDark,
                    subtitle: _reportSummaryText,
                    subtitleColor: AppColors.textGray,
                    chevronColor: AppColors.textGray,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'RECENT REPORTS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textGray.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_recentReports.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No reports submitted yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textGray.withOpacity(0.9),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final record in _recentReports) ...[
                      _RecentReportTile(record: record),
                      const SizedBox(height: 12),
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

class _HotlinePill extends StatelessWidget {
  final String label;
  final String number;
  const _HotlinePill({required this.label, required this.number});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calling $label ($number)...'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                number,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EmergencyCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFDC2626),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    'SOS',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'emergency',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'fire · flood · medical · crime',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white70,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final Color color;
  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color titleColor;
  final String subtitle;
  final Color subtitleColor;
  final Color chevronColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.color,
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleColor,
    required this.subtitle,
    required this.subtitleColor,
    required this.chevronColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: subtitleColor),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: chevronColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentReportTile extends StatelessWidget {
  final ReportRecord record;

  const _RecentReportTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final visual = _categoryVisual(record.category);
    final status = _statusStyle(record.status);
    final title = record.category.trim().isNotEmpty
        ? record.category.trim()
        : (record.isEmergency ? 'Emergency' : (record.subtype.trim().isNotEmpty
            ? record.subtype.trim()
            : 'Report'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: visual.bg,
              shape: BoxShape.circle,
            ),
            child: Icon(visual.icon, color: visual.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  record.trackingId,
                  style: TextStyle(fontSize: 12, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: status.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: status.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

({IconData icon, Color bg, Color color}) _categoryVisual(String category) {
  switch (category.toLowerCase()) {
    case 'fire & emergency':
    case 'fire':
    case 'emergency':
      return (
        icon: Icons.local_fire_department,
        bg: AppColors.iconCircleFire,
        color: AppColors.hotlineRed,
      );
    case 'noise':
    case 'noise disturbance':
    case 'community disputes':
      return (
        icon: Icons.volume_up_outlined,
        bg: AppColors.iconCircleNoise,
        color: AppColors.statusResolvedText,
      );
    case 'traffic & road':
    case 'traffic':
    case 'road':
      return (
        icon: Icons.directions_car_outlined,
        bg: AppColors.iconCircleRoad,
        color: AppColors.ratingStar,
      );
    case 'crime & property':
    case 'crime':
      return (
        icon: Icons.lock_outline,
        bg: AppColors.iconCircleDoc,
        color: AppColors.primary,
      );
    case 'environmental & sanitation':
    case 'environmental':
      return (
        icon: Icons.eco_outlined,
        bg: AppColors.iconCircleDoc,
        color: AppColors.primary,
      );
    case 'animal-related':
      return (
        icon: Icons.pets_outlined,
        bg: AppColors.iconCircleDoc,
        color: AppColors.primary,
      );
    default:
      return (
        icon: Icons.description_outlined,
        bg: AppColors.iconCircleDoc,
        color: AppColors.primary,
      );
  }
}

({String label, Color bg, Color text}) _statusStyle(String status) {
  switch (status.trim().toLowerCase()) {
    case 'resolved':
      return (
        label: 'Resolved',
        bg: AppColors.statusResolvedBg,
        text: AppColors.statusResolvedText,
      );
    case 'closed':
      return (
        label: 'Closed',
        bg: AppColors.statusClosedBg,
        text: AppColors.statusClosedText,
      );
    default:
      return (
        label: 'In Progress',
        bg: AppColors.statusInProgressBg,
        text: AppColors.statusInProgressText,
      );
  }
}
