import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryDark = Color(0xFF14532D);
  static const Color primary = Color(0xFF166534);
  static const Color primaryButton = Color(0xFF15803D);
  static const Color primaryLight = Color(0xFFE8F5EC);

  static const Color background = Color(0xFFF5FAF6);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFD9E8DE);

  static const Color textDark = Color(0xFF17251C);
  static const Color textGray = Color(0xFF647067);
  static const Color hint = Color(0xFF98A39B);

  static const Color hotlineBg = Color(0xFFFFF1F2);
  static const Color hotlineBorder = Color(0xFFFECACA);
  static const Color hotlineRed = Color(0xFFDC2626);

  static const Color errorText = Color(0xFFB42318);

  static const Color infoBg = Color(0xFFEFF8F1);
  static const Color infoBorder = Color(0xFFCDE6D3);

  static const Color badgeRed = Color(0xFFDC2626);

  static const Color reportCardGreen = Color(0xFF166534);

  static const Color iconCircleFire = Color(0xFFFFE4E6);
  static const Color iconCircleDoc = Color(0xFFE8F5EC);
  static const Color iconCircleNoise = Color(0xFFE5F5EC);
  static const Color iconCircleRoad = Color(0xFFFFF4CC);

  static const Color statusInProgressBg = Color(0xFFFFF4CC);
  static const Color statusInProgressText = Color(0xFF8A6500);

  static const Color statusResolvedBg = Color(0xFFE5F5EC);
  static const Color statusResolvedText = Color(0xFF287A4A);

  static const Color statusClosedBg = Color(0xFFE9EDF2);
  static const Color statusClosedText = Color(0xFF647067);

  static const Color ratingStar = Color(0xFFFFB800);

  static const Color success = Color(0xFF2E8B57);
  static const Color verified = Color(0xFF2E8B57);

  static const Color primaryButtonDisabled = Color(0xFF2E7D32);
}

/// A fixed-size frame so the login flow always looks like a phone screen,
/// regardless of the surrounding window (useful for desktop/web preview).
class PhoneFrame extends StatelessWidget {
  final Widget child;
  const PhoneFrame({super.key, required this.child});

  static const double phoneWidth = 390;
  static const double phoneHeight = 844;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: Container(
          width: phoneWidth,
          height: phoneHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.black, width: 8),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 30, spreadRadius: 2),
            ],
          ),
          child: MediaQuery(
            data: MediaQueryData(size: Size(phoneWidth, phoneHeight)),
            child: child,
          ),
        ),
      ),
    );
  }
}
