import 'package:flutter/material.dart';
import '../backend/auth_store.dart';
import 'login.dart' show AppColors, LoginFlow, LoginStep;
import 'bottom_nav.dart';
import 'home.dart';
import 'my_report.dart';
import 'notification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _navIndex = 3; // "Settings" tab active in the bottom nav

  // ---- Local (front-end only) state ----
  bool _isEnglish = true;
  bool _highSeverityAlerts = true;
  bool _mediumSeverityAlerts = true;
  bool _lowSeverityAlerts = false;

  String _fullName = 'Kababayan';
  String _accountEmail = '';
  String _maskedEmail = '';
  String _accountPhone = '';

  @override
  void initState() {
    super.initState();
    AuthStore.load().then((auth) {
      if (!mounted) return;
      final account = auth.account;
      setState(() {
        if (account != null && account.displayName.isNotEmpty) {
          _fullName = account.displayName;
        }
        if (account != null && account.email.isNotEmpty) {
          _accountEmail = account.email;
        }
        if (account != null && account.phoneNumber.isNotEmpty) {
          _accountPhone = account.phoneNumber;
        }
        _maskedEmail = auth.maskedEmail;
      });
    });
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label coming soon!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == _navIndex) return;
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
    }
  }

  Future<void> _confirmLogOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to verify your email code to log back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.hotlineRed),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      // Clear the cached profile and trusted-device state.
      final auth = await AuthStore.load();
      await auth.eraseAll();
      if (!mounted) return;
      // Trust is kept, so the returning resident logs back in through the
      // landing page — the same path as a fresh app launch.
      // NOTE: onLoginSuccess is required — without it the login flow
      // never leaves (stuck on the loading spinner).
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (loginCtx) => LoginFlow(
            initialStep: LoginStep.landing,
            onLoginSuccess: () {
              Navigator.of(loginCtx).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
          ),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _confirmRemoveDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this device?'),
        content: const Text(
          'This device will be unregistered. You will need to '
          'log back in with your email and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.hotlineRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final auth = await AuthStore.load();
      await auth.untrustDevice();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (loginCtx) => LoginFlow(
              initialStep: LoginStep.landing,
              onLoginSuccess: () {
                Navigator.of(loginCtx).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              },
            ),
          ),
          (route) => false,
        );
      }
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.badgeRed,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            'KK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fullName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      color: AppColors.verified,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _maskedEmail,
                                    style: const TextStyle(
                                      color: AppColors.primaryLight,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _showComingSoon('Edit profile'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.10),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  const _SectionLabel('Personal Information'),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.person_outline,
                    title: 'Full Name',
                    subtitle: _fullName,
                    onTap: () => _showComingSoon('Edit name'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.cake_outlined,
                    title: 'Date of Birth',
                    subtitle: 'Not set',
                    onTap: () => _showComingSoon('Date of birth'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.location_on_outlined,
                    title: 'Home Address',
                    subtitle: 'Not set',
                    onTap: () => _showComingSoon('Home address'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'Email',
                    subtitle: _accountEmail.isEmpty
                        ? 'Not provided'
                        : _accountEmail,
                    onTap: () => _showComingSoon('Email'),
                  ),

                  const SizedBox(height: 22),
                  const _SectionLabel('Language'),
                  const SizedBox(height: 10),
                  _LanguageToggle(
                    isEnglish: _isEnglish,
                    onChanged: (v) => setState(() => _isEnglish = v),
                  ),

                  const SizedBox(height: 22),
                  const _SectionLabel('Notifications'),
                  const SizedBox(height: 10),
                  _SettingsGroupCard(
                    children: [
                      _ToggleRow(
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.hotlineRed,
                        iconBg: AppColors.iconCircleFire,
                        title: 'Critical & Emergency Alerts',
                        subtitle:
                            'Cannot be disabled — required for your safety.',
                        subtitleColor: AppColors.hotlineRed,
                        value: true,
                        onChanged: null,
                      ),
                      const _RowDivider(),
                      _ToggleRow(
                        icon: Icons.notifications_none,
                        title: 'High Severity Alerts',
                        subtitle: 'Fires, crimes, medical',
                        value: _highSeverityAlerts,
                        onChanged: (v) =>
                            setState(() => _highSeverityAlerts = v),
                      ),
                      const _RowDivider(),
                      _ToggleRow(
                        icon: Icons.notifications_none,
                        title: 'Medium Severity Alerts',
                        subtitle: 'Floods, road issues',
                        value: _mediumSeverityAlerts,
                        onChanged: (v) =>
                            setState(() => _mediumSeverityAlerts = v),
                      ),
                      const _RowDivider(),
                      _ToggleRow(
                        icon: Icons.notifications_none,
                        title: 'Low Severity / Informational',
                        subtitle: 'Advisories, maintenance',
                        value: _lowSeverityAlerts,
                        onChanged: (v) =>
                            setState(() => _lowSeverityAlerts = v),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),
                  const _SectionLabel('Data & Sync'),
                  const SizedBox(height: 10),
                  _SettingsGroupCard(
                    children: [
                      if (_accountPhone.isNotEmpty)
                        _InfoRow(
                          icon: Icons.phone_outlined,
                          title: 'Registered number',
                          subtitle: _accountPhone,
                          trailing: const Icon(
                            Icons.verified_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                      if (_accountPhone.isNotEmpty) const _RowDivider(),
                      _InfoRow(
                        icon: Icons.wifi,
                        title: 'All data synced',
                        subtitle: 'Last synced: Today, 9:41 AM',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.statusResolvedBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.statusResolvedText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),
                  const _SectionLabel('Privacy & Security'),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.visibility_off_outlined,
                    title: 'Data Privacy Policy',
                    subtitle: 'RA 10173 — Data Privacy Act',
                    onTap: () => _showComingSoon('Data Privacy Policy'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.shield_outlined,
                    title: 'Security & Verification',
                    subtitle: 'Email verified · Code enabled',
                    onTap: () => _showComingSoon('Security & Verification'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.phonelink_erase_outlined,
                    title: 'Remove this device',
                    subtitle: 'Unregister this device from your account',
                    onTap: _confirmRemoveDevice,
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    onTap: () => _showComingSoon('Terms of Service'),
                  ),

                  const SizedBox(height: 22),
                  const _SectionLabel('About'),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.info_outline,
                    title: 'About CPSS',
                    subtitle: 'Smart Community Safety System',
                    onTap: () => _showComingSoon('About CPSS'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    subtitle: 'FAQs, contact, report a bug',
                    onTap: () => _showComingSoon('Help & Support'),
                  ),
                  const SizedBox(height: 10),
                  _SettingsRowCard(
                    icon: Icons.star_border,
                    title: 'App Version',
                    subtitle: 'Version 2.4.1 · Lungsod ng Quezon',
                  ),

                  const SizedBox(height: 22),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _confirmLogOut,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout,
                                size: 18,
                                color: AppColors.hotlineRed,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Log Out',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.hotlineRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Center(
                    child: Text(
                      'CPSS 2026',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small all-caps section label (e.g. "PERSONAL INFORMATION").
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textGray.withOpacity(0.9),
      ),
    );
  }
}

/// A single tappable white rounded card row, used for Personal Information,
/// Privacy & Security, and About entries.
class _SettingsRowCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsRowCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.iconCircleDoc,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
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
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textGray,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white rounded container that groups multiple rows together, separated
/// by thin dividers (used for Notifications and Data & Sync).
class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: AppColors.border,
      indent: 14,
      endIndent: 14,
    );
  }
}

/// A row with an icon, title/subtitle, and a toggle switch. Pass
/// `onChanged: null` to render a locked/disabled switch (used for the
/// mandatory Critical & Emergency Alerts row).
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Color? iconBg;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleRow({
    required this.icon,
    this.iconColor,
    this.iconBg,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: iconBg ?? AppColors.iconCircleDoc,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: subtitleColor ?? AppColors.textGray,
                    fontWeight: subtitleColor != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// A non-interactive info row with a trailing widget (used for "All data
/// synced" under Data & Sync).
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.statusResolvedBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: AppColors.statusResolvedText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// Two-segment English / Filipino language switcher.
class _LanguageToggle extends StatelessWidget {
  final bool isEnglish;
  final ValueChanged<bool> onChanged;

  const _LanguageToggle({required this.isEnglish, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LanguageOption(
              flagLabel: 'US',
              label: 'English',
              selected: isEnglish,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _LanguageOption(
              flagLabel: 'PH',
              label: 'Filipino',
              selected: !isEnglish,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String flagLabel;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.flagLabel,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              flagLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white70 : AppColors.textGray,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textDark,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 14, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}
