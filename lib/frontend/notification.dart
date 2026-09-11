import 'package:flutter/material.dart';
import 'login.dart' show AppColors;
import 'bottom_nav.dart';
import 'home.dart';
import 'my_report.dart';
import 'settings.dart';

enum AlertSeverity { critical, high, medium, low }

class AlertItem {
  final String id;
  final AlertSeverity severity;
  final String timestamp;
  final String title;
  final String body;
  bool acknowledged;

  AlertItem({
    required this.id,
    required this.severity,
    required this.timestamp,
    required this.title,
    required this.body,
    this.acknowledged = false,
  });
}

// Sample front-end data matching the reference design.
List<AlertItem> _buildSampleAlerts() => [
  AlertItem(
    id: 'a1',
    severity: AlertSeverity.critical,
    timestamp: 'Today, 6:00 AM',
    title: 'Typhoon Aghon — Signal No. 2 Raised (Quezon City)',
    body:
        'PAGASA has raised Tropical Storm Warning Signal No. 2 over '
        'the entirety of Quezon City. Expect strong winds '
        '(75–100 kph) and heavy rainfall. Residents in low-lying '
        'and flood-prone areas are advised to evacuate immediately.\n\n'
        'Emergency shelters: Quezon City High School, Batasan Hills '
        'National High School, Commonwealth Elementary School, '
        'Novaliches High School, and other designated evacuation '
        'centers across all barangays.',
  ),
  AlertItem(
    id: 'a2',
    severity: AlertSeverity.high,
    timestamp: 'Today, 7:30 AM',
    title: 'Flood Warning — Tullahan River Level Rising',
    body:
        'Tullahan River is now at critical level and rising. Residents '
        'near riverbanks in Brgy. Tandang Sora, Culiat, and Sauyo '
        'are advised to pre-emptively evacuate.',
  ),
  AlertItem(
    id: 'a3',
    severity: AlertSeverity.medium,
    timestamp: 'Yesterday, 3:00 PM',
    title: 'Road Closure — Mindanao Ave. Northbound',
    body:
        'Mindanao Ave. northbound is closed from Tandang Sora Ave. '
        'to Sauyo Rd. due to flooding and emergency response '
        'operations. Use alternate routes via Quirino Highway or '
        'Congressional Ave.',
    acknowledged: true,
  ),
  AlertItem(
    id: 'a4',
    severity: AlertSeverity.low,
    timestamp: 'Jun 12, 10:00 AM',
    title: 'Scheduled Power Interruption — Brgy. Tandang Sora',
    body:
        'Meralco will conduct system maintenance on June 15, 2025 '
        'from 8:00 AM to 5:00 PM. Affected: selected streets within '
        'Tandang Sora including areas near Visayas Ave. and '
        'Congressional Ave.',
    acknowledged: true,
  ),
];

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final List<AlertItem> _alerts = _buildSampleAlerts();
  int _navIndex = 2; // "Alerts" tab active in the bottom nav

  int get _unreadCount => _alerts.where((a) => !a.acknowledged).length;

  void _acknowledge(AlertItem alert) {
    setState(() => alert.acknowledged = true);
  }

  void _onNavTap(int index) {
    setState(() => _navIndex = index);
    if (index == 0) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomeScreen(),
        ),
      );
    } else if (index == 1) {
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
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alerts & Notifications',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _unreadCount == 0
                        ? 'All caught up'
                        : '$_unreadCount unread',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),

            // ---- Body ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  for (final alert in _alerts) ...[
                    alert.severity == AlertSeverity.critical
                        ? _BroadcastCard(
                            alert: alert,
                            onAcknowledge: () => _acknowledge(alert),
                          )
                        : _AlertCard(
                            alert: alert,
                            onAcknowledge: () => _acknowledge(alert),
                          ),
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

/// Full-bleed green/red card for mass emergency broadcasts — the most
/// urgent alert type, always shown at the top regardless of timestamp.
class _BroadcastCard extends StatelessWidget {
  final AlertItem alert;
  final VoidCallback onAcknowledge;

  const _BroadcastCard({required this.alert, required this.onAcknowledge});

  static const Color _bandBg = AppColors.hotlineRed;
  static const Color _bodyBg = AppColors.hotlineBg;
  static const Color _borderColor = AppColors.hotlineRed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bodyBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Red "must read" band ----
          Container(
            color: _bandBg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MASS EMERGENCY BROADCAST — MUST READ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ---- Body ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.hotlineRed,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  alert.body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.hotlineRed.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        alert.timestamp,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.hotlineRed.withOpacity(0.55),
                        ),
                      ),
                    ),
                    if (alert.acknowledged)
                      Row(
                        children: const [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppColors.hotlineRed,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Acknowledged',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.hotlineRed,
                            ),
                          ),
                        ],
                      )
                    else
                      ElevatedButton(
                        onPressed: onAcknowledge,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.hotlineRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Acknowledge',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Regular severity-ranked alert card (High / Medium / Low).
class _AlertCard extends StatelessWidget {
  final AlertItem alert;
  final VoidCallback onAcknowledge;

  const _AlertCard({required this.alert, required this.onAcknowledge});

  ({Color dot, Color badgeBg, Color badgeText, String label})
  get _severityStyle {
    switch (alert.severity) {
      case AlertSeverity.high:
        return (
          dot: AppColors.hotlineRed,
          badgeBg: AppColors.iconCircleFire,
          badgeText: AppColors.hotlineRed,
          label: 'HIGH',
        );
      case AlertSeverity.medium:
        return (
          dot: const Color(0xFFD9A400),
          badgeBg: const Color(0xFFFFF4CC),
          badgeText: const Color(0xFF8A6500),
          label: 'MEDIUM',
        );
      case AlertSeverity.low:
        return (
          dot: AppColors.statusResolvedText,
          badgeBg: AppColors.statusResolvedBg,
          badgeText: AppColors.statusResolvedText,
          label: 'LOW',
        );
      case AlertSeverity.critical:
        return (
          dot: AppColors.hotlineRed,
          badgeBg: AppColors.iconCircleFire,
          badgeText: AppColors.hotlineRed,
          label: 'CRITICAL',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _severityStyle;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: style.dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: style.badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: style.badgeText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert.timestamp,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            alert.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            alert.body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textGray,
            ),
          ),
          const SizedBox(height: 12),
          if (alert.acknowledged)
            Row(
              children: const [
                Icon(Icons.check, size: 15, color: AppColors.textGray),
                SizedBox(width: 4),
                Text(
                  'Acknowledged',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            )
          else
            ElevatedButton(
              onPressed: onAcknowledge,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryButton,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Acknowledge',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
