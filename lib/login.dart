import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'auth_store.dart';

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

  static const Color primaryButtonDisabled = Color(0xFFA7D7B5);
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

/// ---------------------------------------------------------------------
/// Login flow controller — swaps between the 3 steps
/// ---------------------------------------------------------------------
/// Resident authentication flow.
///
/// Routing principle (two separate paths):
/// - Log In (existing user): landing → mobile number → OTP → enter code →
///   enter PIN → home. A number with no account is redirected to
///   registration with a message.
/// - Create Account (new user): landing → mobile number → OTP → create
///   account form → create PIN → confirm PIN → home. A number that already
///   exists is redirected to the Log In path with a message.
/// No step can be skipped: PIN login requires a verified OTP + code in the
/// same session ([_codeVerified]).
class LoginFlow extends StatefulWidget {
  /// Called once the resident is fully authenticated. Kept optional and
  /// generic (no import of home.dart here) so login.dart stays decoupled
  /// from what comes next — main.dart wires it up to actual navigation.
  final VoidCallback? onLoginSuccess;

  /// Where the flow starts. `main.dart` picks PIN vs mobile number based on
  /// [AuthStore.isReturningUser].
  final LoginStep initialStep;

  const LoginFlow({
    super.key,
    this.onLoginSuccess,
    this.initialStep = LoginStep.landing,
  });

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

enum LoginStep {
  /// Landing page: "Log In or Create Account" entry point.
  landing,

  /// First-time / logged-out entry: "Enter your mobile number to get started."
  mobileNumber,

  /// OTP verification for the entered number.
  otp,

  /// Existing account, new device: "Register this device?" gate.
  trustDevice,

  /// Log In flow, Step 3 of 4: verification/access code after OTP.
  enterCode,

  /// Returning-user fast path: masked number + PIN.
  pinLogin,

  /// New account: barangay registration form.
  createAccount,

  /// New account: choose a PIN (then confirm).
  createPin,
  confirmPin,

  /// Forgot PIN recovery: OTP on the stored number…
  forgotOtp,

  /// …then set a replacement PIN (then confirm).
  resetPin,
  resetConfirm,
}

class _LoginFlowState extends State<LoginFlow> {
  late LoginStep _step;
  String _phoneNumber = '';
  String _pin = '';
  String _resetPin = '';
  ResidentProfile? _draftProfile;
  AuthStore? _auth;

  /// Raw 10-digit number the resident typed, kept in the flow controller so
  /// it survives navigation between steps (spec: "Preserve the entered
  /// mobile number when moving between authentication screens").
  String _phoneDigits = '';

  /// Distinguishes the two landing choices even though both verify the
  /// mobile number over OTP: false = "Log In" (existing account),
  /// true = "Create Account" (new registration).
  bool _isRegistering = false;

  /// Guards the Log In path so the PIN screen (and home) can't be reached
  /// without passing OTP + access-code verification in the same session.
  bool _codeVerified = false;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final auth = await AuthStore.load();
    if (!mounted) return;
    setState(() {
      _auth = auth;
      // Never strand the user on PIN login without a usable credential:
      // fall back to the mobile-number entry instead.
      if (_step == LoginStep.pinLogin && !auth.isReturningUser) {
        _step = LoginStep.mobileNumber;
      }
    });
  }

  void _goTo(LoginStep step) {
  // Release keyboard focus before swapping steps on web so the engine
  // doesn't process a pending focus/geometry event against a torn-down
  // input element (avoids the text_editing.dart assertion, flutter#178619).
  FocusManager.instance.primaryFocus?.unfocus();
  setState(() => _step = step);
}

  void _showFlowMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// After OTP succeeds, route based on the landing choice:
  /// - Log In expects an existing account and continues to the access-code
  ///   step; a new number is redirected to registration with a message.
  /// - Create Account expects a new number; an existing number is redirected
  ///   to the Log In path instead of creating a duplicate.
  void _handleOtpVerified() {
    final auth = _auth;
    if (auth == null) {
      _goTo(LoginStep.createAccount);
      return;
    }
    final exists = auth.accountMatches(_phoneNumber);
    if (_isRegistering) {
      if (exists) {
        setState(() {
          _isRegistering = false;
          _codeVerified = false;
        });
        _showFlowMessage(
          'This number is already registered. Logging you in instead.',
        );
        if (auth.isDeviceTrusted) {
          _goTo(LoginStep.enterCode);
        } else {
          _goTo(LoginStep.trustDevice);
        }
      } else {
        _goTo(LoginStep.createAccount);
      }
    } else {
      // In demo mode, any well-formed number is treated as an existing
      // account so the Log In path always runs (no "account not found"),
      // and the device-trust gate is skipped for the demo account.
      if (exists || (AuthStore.demoMode && !_isRegistering)) {
        setState(() => _codeVerified = false);
        final demoLogin = AuthStore.demoMode && !auth.hasAccount;
        if (auth.isDeviceTrusted || demoLogin) {
          _goTo(LoginStep.enterCode);
        } else {
          _goTo(LoginStep.trustDevice);
        }
      } else {
        setState(() => _isRegistering = true);
        _showFlowMessage(
          'No account found for this number. Let’s create one.',
        );
        _goTo(LoginStep.createAccount);
      }
    }
  }

  /// After the access code is accepted, allow the PIN step.
  void _handleCodeVerified() {
    setState(() => _codeVerified = true);
    _goTo(LoginStep.pinLogin);
  }

  /// Persists a fresh registration: account + PIN hash + trusted device.
  Future<void> _finishRegistration() async {
    final auth = _auth;
    final profile = _draftProfile;
    if (auth == null || profile == null || _pin.isEmpty) return;
    await auth.saveRegistration(profile);
    await auth.setPin(_pin);
    await auth.trustDevice();
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    if (auth == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final Widget screen;
    switch (_step) {
      case LoginStep.landing:
        screen = LandingScreen(
          key: const ValueKey('landing'),
          auth: auth,
          onLogin: (digits) {
            // Log In goes straight to OTP using the number entered on the
            // landing page — the standalone mobile-number screen is skipped.
            setState(() {
              _isRegistering = false;
              _codeVerified = false;
              _phoneNumber = '+63 $digits';
              _phoneDigits = digits;
            });
            _goTo(LoginStep.otp);
          },
          onCreateAccount: () {
            setState(() {
              _phoneNumber = '';
              _isRegistering = true;
              _codeVerified = false;
              _phoneDigits = '';
            });
            _goTo(LoginStep.mobileNumber);
          },
        );
      case LoginStep.mobileNumber:
        screen = MobileNumberScreen(
          key: ValueKey('mobile_${_isRegistering ? 'register' : 'login'}'),
          initialNumber: _phoneDigits,
          isRegistering: _isRegistering,
          onBack: () => _goTo(LoginStep.landing),
          onSwitchMode: () =>
              setState(() => _isRegistering = !_isRegistering),
          onNumberChanged: (digits) => _phoneDigits = digits,
          onOtpSent: (digits) {
            setState(() {
              _phoneNumber = '+63 $digits';
            });
            _goTo(LoginStep.otp);
          },
        );
      case LoginStep.otp:
        screen = OtpScreen(
          key: ValueKey('otp_${_isRegistering ? 'register' : 'login'}'),
          phoneNumber: _phoneNumber,
          isRegistering: _isRegistering,
          onBack: () => _goTo(
            _isRegistering ? LoginStep.mobileNumber : LoginStep.landing,
          ),
          onChangeNumber: () => _goTo(
            _isRegistering ? LoginStep.mobileNumber : LoginStep.landing,
          ),
          onVerified: _handleOtpVerified,
        );
      case LoginStep.trustDevice:
        screen = TrustDeviceScreen(
          key: const ValueKey('trustDevice'),
          phoneNumber: _phoneNumber,
          onRegister: () async {
            await auth.trustDevice();
            _goTo(LoginStep.enterCode);
          },
          onUseDifferentNumber: () {
            setState(() {
              _isRegistering = false;
              _codeVerified = false;
            });
            _goTo(LoginStep.mobileNumber);
          },
        );
      case LoginStep.enterCode:
        screen = EnterAccessCodeScreen(
          key: const ValueKey('enterCode'),
          phoneNumber: _phoneNumber,
          onBack: () => _goTo(LoginStep.otp),
          onVerified: _handleCodeVerified,
        );
      case LoginStep.pinLogin:
        // Hard guard: PIN login requires a verified access code this
        // session, so the OTP → code → PIN sequence can't be skipped.
        if (!_codeVerified) {
          screen = EnterAccessCodeScreen(
            key: const ValueKey('enterCode_guard'),
            phoneNumber: _phoneNumber,
            onBack: () => _goTo(LoginStep.landing),
            onVerified: _handleCodeVerified,
          );
          break;
        }
        screen = EnterPinScreen(
          key: const ValueKey('pinLogin'),
          auth: auth,
          phoneNumber: _phoneNumber,
          onBack: () => _goTo(
            _codeVerified ? LoginStep.enterCode : LoginStep.landing,
          ),
          onForgotPin: () => _goTo(LoginStep.forgotOtp),
          onUseDifferentNumber: () {
            setState(() {
              _isRegistering = false;
              _codeVerified = false;
            });
            _goTo(LoginStep.mobileNumber);
          },
          onVerified: () {
            widget.onLoginSuccess?.call();
          },
        );
      case LoginStep.createAccount:
        screen = CreateAccountScreen(
          key: const ValueKey('createAccount'),
          phoneNumber: _phoneNumber,
          onBack: () => _goTo(LoginStep.otp),
          onAccountCreated: (profile) {
            setState(() => _draftProfile = profile);
            _goTo(LoginStep.createPin);
          },
        );
      case LoginStep.createPin:
        screen = CreatePinScreen(
          key: const ValueKey('createPin'),
          onBack: () => _goTo(LoginStep.createAccount),
          onPinCreated: (pin) {
            setState(() => _pin = pin);
            _goTo(LoginStep.confirmPin);
          },
        );
      case LoginStep.confirmPin:
        screen = ConfirmPinScreen(
          key: const ValueKey('confirmPin'),
          expectedPin: _pin,
          onBack: () => _goTo(LoginStep.createPin),
          onConfirmed: () async {
            await _finishRegistration();
            widget.onLoginSuccess?.call();
          },
        );
      case LoginStep.forgotOtp:
        final accountPhone = auth.account?.phoneNumber ?? _phoneNumber;
        screen = OtpScreen(
          key: const ValueKey('forgotOtp'),
          phoneNumber: accountPhone,
          onBack: () => _goTo(LoginStep.pinLogin),
          onChangeNumber: () => _goTo(LoginStep.pinLogin),
          onVerified: () {
            _goTo(LoginStep.resetPin);
          },
        );
      case LoginStep.resetPin:
        screen = CreatePinScreen(
          key: const ValueKey('resetPin'),
          onBack: () => _goTo(LoginStep.pinLogin),
          onPinCreated: (pin) {
            setState(() => _resetPin = pin);
            _goTo(LoginStep.resetConfirm);
          },
        );
      case LoginStep.resetConfirm:
        screen = ConfirmPinScreen(
          key: const ValueKey('resetConfirm'),
          expectedPin: _resetPin,
          onBack: () => _goTo(LoginStep.resetPin),
          onConfirmed: () async {
            await auth.setPin(_resetPin);
            widget.onLoginSuccess?.call();
          },
        );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: screen,
    );
  }
}

/// ---------------------------------------------------------------------
/// Shared header used by step 1 & step 2 (progress header)
/// ---------------------------------------------------------------------
class StepHeader extends StatelessWidget {
  /// Null hides the back arrow (used on root entry screens so returning
  /// users are never offered a dead back button).
  final VoidCallback? onBack;
  final String stepLabel; // "Step 1 of 2"
  final String title; // "Mobile Number"
  final double progress; // 0.0 - 1.0

  const StepHeader({
    super.key,
    required this.onBack,
    required this.stepLabel,
    required this.title,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.primaryDark,
          padding: const EdgeInsets.fromLTRB(12, 50, 20, 20),
          child: Row(
            children: [
              if (back != null) ...[
                InkWell(
                  onTap: back,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stepLabel,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // thin progress bar
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          builder: (context, value, _) {
            final filled = (value * 100).round();
            final remaining = 100 - filled;
            return SizedBox(
              height: 3,
              child: Row(
                children: [
                  if (filled > 0)
                    Expanded(
                      flex: filled,
                      child: Container(color: AppColors.primary),
                    ),
                  if (remaining > 0)
                    Expanded(
                      flex: remaining,
                      child: Container(color: AppColors.border),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}



/// ---------------------------------------------------------------------
/// LANDING — Log In or Create Account
/// ---------------------------------------------------------------------
/// App entry point: the landing page offers "Log In" for existing
/// residents and "Create Account" for new ones. Returning residents
/// (trusted device + PIN) see a "Welcome back" greeting with their
/// masked number; both paths start at mobile-number verification.
class LandingScreen extends StatefulWidget {
  final AuthStore auth;
  final ValueChanged<String> onLogin;
  final VoidCallback onCreateAccount;

  const LandingScreen({
    super.key,
    required this.auth,
    required this.onLogin,
    required this.onCreateAccount,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final isReturning = auth.isReturningUser;
    final name = auth.account?.displayName.trim() ?? '';

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Text(
                        'CPSS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Smart Community\nSafety System',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isReturning && name.isNotEmpty
                          ? 'Welcome back, $name!'
                          : 'Report incidents, track response,\nand stay safe.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (isReturning) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                              color: AppColors.primaryLight,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              auth.maskedPhone,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Resident Login',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PHONE NUMBER',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _CredentialField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    hint: 'Phone Number',
                    icon: Icons.phone_outlined,
                    obscure: false,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        final digits = _emailController.text.trim();
                        if (digits.length == 10) {
                          widget.onLogin(digits);
                        } else {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(const SnackBar(
                              content: Text(
                                'Enter all 10 digits (e.g. 9171234567)',
                              ),
                            ));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryButton,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Log In',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.hint,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: AppColors.border)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: widget.onCreateAccount,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Barangay-verified · Data Privacy Act (RA 10173) compliant',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textGray,
                      ),
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

/// A bordered credential input (email / password) used on the landing screen.
class _CredentialField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final bool obscure;

  const _CredentialField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    required this.obscure,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focusNode.hasFocus ? AppColors.primary : AppColors.border,
          width: focusNode.hasFocus ? 1.6 : 1,
        ),
        color: Colors.white,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        style: const TextStyle(fontSize: 15, color: AppColors.textDark),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.hint),
          prefixIcon: Icon(
            icon,
            size: 20,
            color: focusNode.hasFocus
                ? AppColors.primary
                : AppColors.textGray,
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// STEP 1 — Enter Mobile Number
/// ---------------------------------------------------------------------
class MobileNumberScreen extends StatefulWidget {
  /// Null hides the back arrow — the mobile-number screen is a root entry
  /// point for first-time users.
  final VoidCallback? onBack;
  final ValueChanged<String> onOtpSent;

  /// Raw digits to restore if the screen is revisited (number preservation).
  final String initialNumber;
  final ValueChanged<String> onNumberChanged;

  /// False = "Log In" flow, true = "Create Account" flow. Both verify the
  /// number over OTP, but headers, copy, and post-OTP routing differ.
  final bool isRegistering;
  final VoidCallback? onSwitchMode;

  const MobileNumberScreen({
    super.key,
    required this.onBack,
    required this.onOtpSent,
    this.initialNumber = '',
    this.onNumberChanged = _noopChange,
    this.isRegistering = false,
    this.onSwitchMode,
  });

  static void _noopChange(String _) {}

  @override
  State<MobileNumberScreen> createState() => _MobileNumberScreenState();
}

class _MobileNumberScreenState extends State<MobileNumberScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  bool get _isValid => _controller.text.length == 10;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNumber);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSendOtp() async {
    if (!_isValid || _isSending) return;
    setState(() => _isSending = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      // Release focus before the screen is replaced so the web engine can't
      // race a pending geometry update against a torn-down input element.
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onOtpSent(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live validation: as soon as the user has typed something but it's
    // not yet a full 10-digit number, show the inline error — matches
    // the reference design (e.g. typing "3" already shows the hint).
    final showError = _controller.text.isNotEmpty && !_isValid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: widget.onBack,
              stepLabel: widget.isRegistering
                  ? 'Create Account · Step 1 of 4'
                  : 'Log In · Step 1 of 4',
              title: widget.isRegistering ? 'Create Account' : 'Log In',
              progress: 0.25,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isRegistering
                          ? 'Let’s create your account'
                          : 'Welcome back! Log in',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isRegistering
                          ? 'Enter your mobile number to register. We will '
                              'send a one-time password (OTP) to verify it.'
                          : 'Enter the mobile number linked to your account. '
                              'We will send a one-time password (OTP) to '
                              'verify it’s you.',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'MOBILE NUMBER',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: showError
                              ? AppColors.errorText
                              : (_focusNode.hasFocus
                                    ? AppColors.primary
                                    : AppColors.border),
                          width: showError || _focusNode.hasFocus ? 1.6 : 1,
                        ),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                right: BorderSide(color: AppColors.border),
                              ),
                            ),
                            child: const Text(
                              'PH  +63',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              style: const TextStyle(
                                fontSize: 17,
                                letterSpacing: 1.5,
                                color: AppColors.textDark,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 16,
                                ),
                                hintText: '9XX XXX XXXX',
                                hintStyle: TextStyle(
                                  color: AppColors.hint,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              onChanged: (value) {
                                widget.onNumberChanged(value);
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showError) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Enter all 10 digits (e.g. 9171234567)',
                        style: TextStyle(
                          color: AppColors.errorText,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.infoBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.textGray,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your number is used only for account '
                              'verification and SMS alerts. It is never '
                              'shared with third parties.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (AuthStore.demoMode && !widget.isRegistering) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Demo: any valid number works (e.g. 9171234567)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSending ? null : _handleSendOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isValid && !_isSending
                              ? AppColors.primaryButton
                              : AppColors.primaryButtonDisabled,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    if (widget.onSwitchMode != null) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: GestureDetector(
                          onTap: widget.onSwitchMode,
                          child: Text(
                            widget.isRegistering
                                ? 'Already have an account? Log In'
                                : 'New here? Create Account',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// STEP 2 — Verify OTP
/// ---------------------------------------------------------------------
class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback onBack;
  final VoidCallback onChangeNumber;
  final VoidCallback onVerified;

  /// False = verifying to log in, true = verifying to register.
  final bool isRegistering;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.onBack,
    required this.onChangeNumber,
    required this.onVerified,
    this.isRegistering = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _otpLength = 6;
  static const int _resendSeconds = 60;

  final List<TextEditingController> _controllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _isVerifying = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _secondsLeft = _resendSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _code => _controllers.map((c) => c.text).join();
  bool get _isComplete => _code.length == _otpLength;

  String get _resendLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _errorText = null);
    if (_isComplete) {
      _handleVerify();
    }
  }

  void _resend() async {
    if (_secondsLeft != 0) return;
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() => _errorText = null);
    await Future.delayed(const Duration(milliseconds: 800));
    _startResendTimer();
    setState(() {});
  }

  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
  }

  /// Verifies the OTP. Demo backend: any 6-digit code is accepted except
  /// "000000", which surfaces the incorrect-code error path. Replace the
  /// simulated call below with the real SMS-OTP verification API.
  void _handleVerify() async {
    if (!_isComplete || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _errorText = null;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    if (_code == '000000') {
      setState(() {
        _isVerifying = false;
        _errorText = 'Incorrect code. Please check and try again.';
      });
      _clearCode();
      return;
    }
    setState(() => _isVerifying = false);
    // Release focus before the screen is replaced so the web engine can't
    // race a pending geometry update against a torn-down input element.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onVerified();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
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
            StepHeader(
              onBack: widget.onBack,
              stepLabel: widget.isRegistering
                  ? 'Create Account · Step 2 of 4'
                  : 'Log In · Step 2 of 4',
              title: widget.isRegistering ? 'Verify to Register' : 'Verify to Log In',
              progress: 0.5,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isRegistering
                          ? 'Verify to create your account'
                          : 'Enter verification code to log in',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textGray,
                        ),
                        children: [
                          const TextSpan(text: 'A 6-digit code was sent to '),
                          TextSpan(
                            text: widget.phoneNumber.isEmpty
                                ? '+63 9XX XXX XXXX'
                                : widget.phoneNumber,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_otpLength, (i) {
                        return _OtpBox(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          onChanged: (v) => _onDigitChanged(i, v),
                          onBackspaceEmpty: i > 0
                              ? () {
                                  _controllers[i - 1].clear();
                                  _focusNodes[i - 1].requestFocus();
                                  setState(() {});
                                }
                              : null,
                        );
                      }),
                    ),
                    if (AuthStore.demoMode) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'Demo: enter any 6-digit code (e.g. 111111)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'This code expires in 10 minutes.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _errorText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.errorText,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.textDark,
                              ),
                              children: [
                                const TextSpan(text: 'Resend in '),
                                TextSpan(
                                  text: _resendLabel,
                                  style: const TextStyle(
                                    color: AppColors.hotlineRed,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _resend,
                            child: Text(
                              'Resend OTP',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: _secondsLeft == 0
                                    ? AppColors.primary
                                    : AppColors.textGray.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isVerifying
                            ? null
                            : (_isComplete ? _handleVerify : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isComplete && !_isVerifying
                              ? AppColors.primaryButton
                              : AppColors.primaryButtonDisabled,
                          disabledBackgroundColor:
                              AppColors.primaryButtonDisabled,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Verify OTP',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: widget.onChangeNumber,
                        child: const Text(
                          'Wrong number?  ←  Change number',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBackspaceEmpty;
  final bool obscureText;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onBackspaceEmpty,
    this.obscureText = false,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  Timer? _hideTimer;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.isEmpty) {
      widget.onBackspaceEmpty?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onDigitChanged(String value) {
    widget.onChanged(value);
    if (value.isNotEmpty && widget.obscureText) {
      setState(() => _revealed = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _revealed = false);
      });
    }
    if (value.isNotEmpty) {
      _animController.forward().then((_) => _animController.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    final showObscure = widget.obscureText && !_revealed;

    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) {
        return Transform.scale(scale: _scaleAnim.value, child: child);
      },
      child: SizedBox(
        width: 44,
        height: 54,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode..onKeyEvent = _handleKeyEvent,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          obscureText: showObscure,
          obscuringCharacter: '●',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.8,
              ),
            ),
          ),
          onChanged: _onDigitChanged,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// FINAL STEP — Create Account (Resident Profile)
/// ---------------------------------------------------------------------
class CreateAccountScreen extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback onBack;

  /// Returns the collected resident profile so the flow can persist the
  /// account once the PIN is confirmed.
  final ValueChanged<ResidentProfile> onAccountCreated;

  const CreateAccountScreen({
    super.key,
    required this.phoneNumber,
    required this.onBack,
    required this.onAccountCreated,
  });

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  DateTime? _dateOfBirth;
  String? _sex;
  String? _civilStatus;
  bool _isSubmitting = false;

  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  double? _locationAccuracy; // meters, from the last GPS fix (null = manual)
  bool _isLocating = false;
  bool _isGeoDecoding = false;
  Timer? _reverseDebounce;

  static final LatLng _defaultCenter = LatLng(14.6760, 121.0437); // Quezon City

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _reverseDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Location services are disabled. Please enable them.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showSnack('Location permission denied.');
      return;
    }

    setState(() => _isLocating = true);
    try {
      // 1) Fast first fix. On Android this is often a coarse
      // network-based position, so never trust it blindly.
      Position? fix;
      try {
        fix = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } on TimeoutException {
        fix = await Geolocator.getLastKnownPosition();
      } catch (_) {
        fix = await Geolocator.getLastKnownPosition();
      }
      if (fix == null) {
        _showSnack('Could not determine your location.');
        return;
      }

      // 2) If the fix is coarse (>30 m), keep listening briefly for
      // the GPS to refine it before pinning.
      if (fix.accuracy > 30) {
        _showSnack(
          'Rough fix (±${fix.accuracy.toStringAsFixed(0)}m) — '
          'waiting for GPS to refine…',
        );
        fix = await _waitForBetterFix(fix);
      }

      final latLng = LatLng(fix.latitude, fix.longitude);
      setState(() => _locationAccuracy = fix!.accuracy);
      await _placePin(latLng, moveCamera: true);
      if (mounted) {
        final acc = fix.accuracy;
        _showSnack(
          acc <= 30
              ? 'Location found (±${acc.toStringAsFixed(0)}m). '
                  'Fine-tune the pin if needed.'
              : 'Still rough (±${acc.toStringAsFixed(0)}m) — '
                  'please move the map to fine-tune the pin.',
        );
      }
    } catch (e) {
      _showSnack('Could not determine your location.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Listens to the GPS stream for up to [maxWait], returning the most
  /// accurate fix seen (or early once [targetAccuracy] is reached).
  Future<Position> _waitForBetterFix(
    Position current, {
    double targetAccuracy = 30,
    Duration maxWait = const Duration(seconds: 10),
  }) async {
    final completer = Completer<Position>();
    StreamSubscription<Position>? sub;
    Timer? timer;

    void finish(Position p) {
      if (!completer.isCompleted) completer.complete(p);
    }

    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen(
      (pos) {
        if (pos.accuracy < current.accuracy) current = pos;
        if (pos.accuracy <= targetAccuracy) finish(pos);
      },
      onError: (_) => finish(current),
    );
    timer = Timer(maxWait, () => finish(current));

    final result = await completer.future;
    await sub.cancel();
    timer.cancel();
    return result;
  }

  Future<void> _placePin(LatLng latLng, {bool moveCamera = false}) async {
    setState(() => _selectedLocation = latLng);
    if (moveCamera) {
      _mapController.move(latLng, 17);
    }
    _reverseGeocode(latLng);
  }

  /// Called live while the user pans/zooms the map (center-pin pattern).
  /// Updates the pin immediately but debounces the address lookup.
  void _onMapCenterChanged(LatLng center) {
    if (_selectedLocation == center) return;
    setState(() {
      _selectedLocation = center;
      _locationAccuracy = null; // user moved it manually now
    });
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _reverseGeocode(center);
    });
  }

  /// Reverse-geocode with Nominatim first (detailed OSM address),
  /// falling back to the device geocoder, then to raw coordinates.
  Future<void> _reverseGeocode(LatLng latLng) async {
    setState(() => _isGeoDecoding = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': latLng.latitude.toString(),
        'lon': latLng.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '18',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': 'resident_app/1.0'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        final display = (data['display_name'] as String?)?.trim() ?? '';
        if (display.isNotEmpty) {
          _addressController.text = display;
          setState(() {});
          return;
        }
      }
      await _fallbackGeocode(latLng);
    } catch (_) {
      await _fallbackGeocode(latLng);
    } finally {
      if (mounted) setState(() => _isGeoDecoding = false);
    }
  }

  Future<void> _fallbackGeocode(LatLng latLng) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty)
            p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.subAdministrativeArea != null &&
              p.subAdministrativeArea!.isNotEmpty)
            p.subAdministrativeArea!,
          if (p.administrativeArea != null &&
              p.administrativeArea!.isNotEmpty)
            p.administrativeArea!,
        ].where((s) => s.isNotEmpty && s != 'Unnamed Road').toList();
        _addressController.text = parts.isNotEmpty
            ? parts.join(', ')
            : _coordsText(latLng);
        setState(() {});
        return;
      }
    } catch (_) {
      // Fall through to coordinates.
    }
    if (mounted) {
      _addressController.text = _coordsText(latLng);
      setState(() {});
    }
  }

  String _coordsText(LatLng latLng) =>
      '${latLng.latitude.toStringAsFixed(5)}, '
      '${latLng.longitude.toStringAsFixed(5)}';

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int? get _age {
    final dob = _dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  bool get _isValid =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _dateOfBirth != null &&
      _sex != null &&
      _civilStatus != null &&
      _addressController.text.trim().isNotEmpty;

  String get _maskedNumber {
    if (widget.phoneNumber.isEmpty) return '+63 XXX XXXX';
    // Mask the middle digits, keep country code + last few visible, e.g.
    // "+63 XXX XXXX" as shown in the reference design.
    final digits = widget.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return widget.phoneNumber;
    final last4 = digits.substring(digits.length - 4);
    return '+63 XXX $last4';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  void _handleCreateAccount() async {
    if (!_isValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      widget.onAccountCreated(
        ResidentProfile(
          phoneNumber: widget.phoneNumber,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          address: _addressController.text.trim(),
          createdAtIso: DateTime.now().toIso8601String(),
        ),
      );
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
            _SegmentedStepHeader(
              onBack: widget.onBack,
              stepLabel: 'Final Step',
              title: 'Create your account',
              segments: 3,
              filledSegments: 3,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This information is used for your resident profile. '
                      'All fields marked * are required.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ---- Full Name ----
                    _SectionCard(
                      title: 'FULL NAME',
                      children: [
                        _FieldLabel('FIRST NAME', required: true),
                        const SizedBox(height: 8),
                        _TextInputBox(
                          controller: _firstNameController,
                          hintText: 'e.g. Maria',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('MIDDLE NAME'),
                        const SizedBox(height: 8),
                        _TextInputBox(
                          controller: _middleNameController,
                          hintText: 'e.g. Santos (optional)',
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('LAST NAME', required: true),
                        const SizedBox(height: 8),
                        _TextInputBox(
                          controller: _lastNameController,
                          hintText: 'e.g. Dela Cruz',
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ---- Personal Details ----
                    _SectionCard(
                      title: 'PERSONAL DETAILS',
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _FieldLabel('DATE OF BIRTH', required: true),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: _pickDateOfBirth,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      height: 52,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _dateOfBirth == null
                                                  ? 'dd/mm/yyyy'
                                                  : '${_dateOfBirth!.day.toString().padLeft(2, '0')}/'
                                                        '${_dateOfBirth!.month.toString().padLeft(2, '0')}/'
                                                        '${_dateOfBirth!.year}',
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                color: _dateOfBirth == null
                                                    ? AppColors.hint
                                                    : AppColors.textDark,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.calendar_today_outlined,
                                            size: 16,
                                            color: AppColors.textGray,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _FieldLabel('AGE'),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 52,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.infoBg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.infoBorder,
                                      ),
                                    ),
                                    child: Text(
                                      _age?.toString() ?? '—',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('SEX', required: true),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _PillOption(
                                label: 'Male',
                                selected: _sex == 'Male',
                                onTap: () => setState(() => _sex = 'Male'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PillOption(
                                label: 'Female',
                                selected: _sex == 'Female',
                                onTap: () => setState(() => _sex = 'Female'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PillOption(
                                label: 'Prefer not to say',
                                selected: _sex == 'Prefer not to say',
                                onTap: () =>
                                    setState(() => _sex = 'Prefer not to say'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('CIVIL STATUS', required: true),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _PillOption(
                                label: 'Single',
                                selected: _civilStatus == 'Single',
                                onTap: () =>
                                    setState(() => _civilStatus = 'Single'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PillOption(
                                label: 'Married',
                                selected: _civilStatus == 'Married',
                                onTap: () =>
                                    setState(() => _civilStatus = 'Married'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _PillOption(
                                label: 'Widowed',
                                selected: _civilStatus == 'Widowed',
                                onTap: () =>
                                    setState(() => _civilStatus = 'Widowed'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PillOption(
                                label: 'Legally Separated',
                                selected: _civilStatus == 'Legally Separated',
                                onTap: () => setState(
                                  () => _civilStatus = 'Legally Separated',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ---- Address & Contact ----
                    _SectionCard(
                      title: 'ADDRESS & CONTACT',
                      children: [
                        _FieldLabel('HOME ADDRESS', required: true),
                        const SizedBox(height: 8),
                        _TextInputBox(
                          controller: _addressController,
                          hintText: 'Unit/House No., Street, Barangay, City',
                          maxLines: 2,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        _MapPicker(
                          mapController: _mapController,
                          center: _selectedLocation ?? _defaultCenter,
                          selectedLocation: _selectedLocation,
                          locationAccuracy: _locationAccuracy,
                          isLocating: _isLocating,
                          onTap: (latLng) {
                            setState(() => _locationAccuracy = null);
                            _placePin(latLng, moveCamera: true);
                          },
                          onCenterChanged: _onMapCenterChanged,
                          onUseCurrentLocation: _useCurrentLocation,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_isGeoDecoding)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            if (_isGeoDecoding) const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isGeoDecoding
                                    ? 'Looking up address for the pin…'
                                    : 'Move the map so the pin sits on your '
                                        'home. The address is filled in '
                                        'automatically.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: AppColors.textGray,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_selectedLocation != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_pin,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Pinned: '
                                  '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                                  '${_selectedLocation!.longitude.toStringAsFixed(5)}'
                                  '${_locationAccuracy != null ? ' · GPS ±${_locationAccuracy!.toStringAsFixed(0)}m' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        _FieldLabel('EMAIL ADDRESS (OPTIONAL)'),
                        const SizedBox(height: 8),
                        _TextInputBox(
                          controller: _emailController,
                          hintText: 'yourname@email.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.phone,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Linked Mobile Number',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _maskedNumber,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textDark,
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
                                  color: AppColors.statusResolvedBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.statusResolvedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ---- Privacy notice ----
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.infoBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.textGray,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your personal information is stored securely '
                              'and used only for identity verification and '
                              'emergency coordination in compliance with '
                              'RA 10173 (Data Privacy Act).',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _handleCreateAccount,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isValid && !_isSubmitting
                              ? AppColors.primaryButton
                              : AppColors.primaryButtonDisabled,
                          disabledBackgroundColor:
                              AppColors.primaryButtonDisabled,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive Leaflet (OpenStreetMap) widget with a fixed center pin:
/// the user pans/zooms the map under the pin instead of tapping a tiny
/// spot. Includes zoom controls and a "use my current location" action.
/// No API key required.
class _MapPicker extends StatelessWidget {
  final MapController mapController;
  final LatLng center;
  final LatLng? selectedLocation;
  final double? locationAccuracy;
  final bool isLocating;
  final ValueChanged<LatLng> onTap;
  final ValueChanged<LatLng> onCenterChanged;
  final VoidCallback onUseCurrentLocation;

  const _MapPicker({
    required this.mapController,
    required this.center,
    required this.selectedLocation,
    required this.locationAccuracy,
    required this.isLocating,
    required this.onTap,
    required this.onCenterChanged,
    required this.onUseCurrentLocation,
  });

  void _zoom(double delta) {
    final camera = mapController.camera;
    final next = (camera.zoom + delta).clamp(3.0, 19.0);
    mapController.move(camera.center, next);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          SizedBox(
            height: 280,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 19,
                onTap: (_, latLng) => onTap(latLng),
                onPositionChanged: (position, hasGesture) {
                  final c = position.center;
                  if (hasGesture && c != null) onCenterChanged(c);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.resident_app',
                  maxZoom: 19,
                ),
                // Blue GPS-accuracy circle around the fix, so the user
                // can see how much to trust it.
                if (selectedLocation != null && locationAccuracy != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: selectedLocation!,
                        radius: locationAccuracy!,
                        useRadiusInMeter: true,
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Fixed center pin (pointer-transparent so map gets gestures).
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(
                    Icons.location_pin,
                    size: 44,
                    color: AppColors.hotlineRed,
                  ),
                ),
              ),
            ),
          ),
          // Zoom controls.
          Positioned(
            right: 10,
            bottom: 10,
            child: Column(
              children: [
                _mapButton(
                  icon: Icons.add,
                  onTap: () => _zoom(1),
                ),
                const SizedBox(height: 8),
                _mapButton(
                  icon: Icons.remove,
                  onTap: () => _zoom(-1),
                ),
              ],
            ),
          ),
          // My-location button.
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: isLocating ? null : onUseCurrentLocation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: isLocating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'My location',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
      ),
    );
  }
}

/// Header variant used by the Create Account screen: shows a short label
/// ("Final Step"), a title, and a segmented progress bar (all segments
/// filled since this is the last step of the flow).
class _SegmentedStepHeader extends StatelessWidget {
  final VoidCallback onBack;
  final String stepLabel;
  final String title;
  final int segments;
  final int filledSegments;

  const _SegmentedStepHeader({
    required this.onBack,
    required this.stepLabel,
    required this.title,
    required this.segments,
    required this.filledSegments,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryDark,
      padding: const EdgeInsets.fromLTRB(12, 50, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stepLabel,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(segments, (i) {
              final filled = i < filledSegments;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == segments - 1 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: filled
                        ? AppColors.primary.withOpacity(0.9)
                        : Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// White rounded card used to group related fields, with an all-caps
/// section title (e.g. "FULL NAME", "PERSONAL DETAILS").
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Small all-caps field label, with an optional required-field asterisk.
class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;

  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textGray,
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.hotlineRed),
            ),
        ],
      ),
    );
  }
}

/// Plain bordered text input box shared by the form fields on this screen.
class _TextInputBox extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _TextInputBox({
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14.5, color: AppColors.textDark),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          hintText: hintText,
          hintStyle: const TextStyle(color: AppColors.hint),
        ),
      ),
    );
  }
}

/// A rounded, tappable "pill" option used for Sex and Civil Status
/// single-choice selections.
class _PillOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textDark,
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// STEP — Create PIN (Step 1 of 2 of the PIN setup mini-flow)
/// ---------------------------------------------------------------------
class CreatePinScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<String> onPinCreated;

  const CreatePinScreen({
    super.key,
    required this.onBack,
    required this.onPinCreated,
  });

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  static const int _pinLength = 6;
  static const int _minPinLength = 4;
  final List<TextEditingController> _controllers = List.generate(
    _pinLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _pinLength,
    (_) => FocusNode(),
  );
  bool _obscurePin = true;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _pin => _controllers.map((c) => c.text).join();
  bool get _isValid =>
      _pin.length >= _minPinLength && _pin.length <= _pinLength;

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < _pinLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _errorText = null);
  }

  void _handleContinue() async {
    if (!_isValid || _isSubmitting) return;
    if (_pin.length < _minPinLength) {
      setState(
        () => _errorText = 'PIN must be $_minPinLength–$_pinLength digits.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) widget.onPinCreated(_pin);
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
            StepHeader(
              onBack: widget.onBack,
              stepLabel: 'Step 1 of 2',
              title: 'Create your PIN',
              progress: 0.5,
            ),
            Expanded(
              child: _PinEntryBody(
                title: 'Create your PIN',
                subtitle:
                    'Create a secure $_minPinLength–$_pinLength digit PIN. '
                    'You will use this every time you log in.',
                controllers: _controllers,
                focusNodes: _focusNodes,
                errorText: _errorText,
                onChanged: _onDigitChanged,
                obscureText: _obscurePin,
                onToggleVisibility: () =>
                    setState(() => _obscurePin = !_obscurePin),
                actionLabel: 'Continue',
                actionEnabled: _isValid,
                isBusy: _isSubmitting,
                onAction: _handleContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// STEP — Confirm PIN (Step 2 of 2 of the PIN setup mini-flow)
/// ---------------------------------------------------------------------
class ConfirmPinScreen extends StatefulWidget {
  final String expectedPin;
  final VoidCallback onBack;
  final VoidCallback onConfirmed;

  const ConfirmPinScreen({
    super.key,
    required this.expectedPin,
    required this.onBack,
    required this.onConfirmed,
  });

  @override
  State<ConfirmPinScreen> createState() => _ConfirmPinScreenState();
}

class _ConfirmPinScreenState extends State<ConfirmPinScreen> {
  static const int _pinLength = 6;
  static const int _minPinLength = 4;
  final List<TextEditingController> _controllers = List.generate(
    _pinLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _pinLength,
    (_) => FocusNode(),
  );
  String? _errorText;
  bool _obscurePin = true;
  bool _isSubmitting = false;

  String get _pin => _controllers.map((c) => c.text).join();
  bool get _isValid =>
      _pin.length >= _minPinLength && _pin.length <= _pinLength;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    setState(() => _errorText = null);
    if (value.isNotEmpty && index < _pinLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  void _handleConfirm() async {
    if (!_isValid || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    if (_pin == widget.expectedPin) {
      setState(() => _isSubmitting = false);
      widget.onConfirmed();
    } else {
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
      setState(() {
        _isSubmitting = false;
        _errorText = 'PINs did not match. Please try again.';
      });
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
            StepHeader(
              onBack: widget.onBack,
              stepLabel: 'Step 2 of 2',
              title: 'Confirm your PIN',
              progress: 1.0,
            ),
            Expanded(
              child: _PinEntryBody(
                title: 'Confirm your PIN',
                subtitle:
                    'Re-enter the $_minPinLength–$_pinLength digit PIN you '
                    'just created to confirm it.',
                controllers: _controllers,
                focusNodes: _focusNodes,
                errorText: _errorText,
                onChanged: _onDigitChanged,
                obscureText: _obscurePin,
                onToggleVisibility: () =>
                    setState(() => _obscurePin = !_obscurePin),
                actionLabel: 'Confirm PIN',
                actionEnabled: _isValid,
                isBusy: _isSubmitting,
                onAction: _handleConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared body for the Create PIN / Confirm PIN screens: lock icon, title,
/// subtitle, up to 6 OTP-style digit boxes (PIN is 4–6 digits), a
/// show/hide toggle, an explicit action button, and an error line.
class _PinEntryBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final String? errorText;
  final void Function(int index, String value) onChanged;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final String actionLabel;
  final bool actionEnabled;
  final bool isBusy;
  final VoidCallback onAction;

  const _PinEntryBody({
    required this.title,
    required this.subtitle,
    required this.controllers,
    required this.focusNodes,
    required this.errorText,
    required this.onChanged,
    required this.obscureText,
    required this.onToggleVisibility,
    required this.actionLabel,
    required this.actionEnabled,
    required this.isBusy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.hotlineBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.hotlineBorder),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: AppColors.primary,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textGray,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              return _OtpBox(
                controller: controllers[i],
                focusNode: focusNodes[i],
                obscureText: obscureText,
                onChanged: (v) => onChanged(i, v),
                onBackspaceEmpty: i > 0
                    ? () {
                        controllers[i - 1].clear();
                        focusNodes[i - 1].requestFocus();
                      }
                    : null,
              );
            }),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: onToggleVisibility,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    obscureText
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    obscureText ? 'Show PIN' : 'Hide PIN',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.errorText,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: isBusy
                  ? null
                  : (actionEnabled ? onAction : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: actionEnabled && !isBusy
                    ? AppColors.primaryButton
                    : AppColors.primaryButtonDisabled,
                disabledBackgroundColor: AppColors.primaryButtonDisabled,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// RETURNING USER — Enter PIN (post-onboarding login)
/// ---------------------------------------------------------------------
/// Shown to a resident who already has an account: a "Welcome back" card
/// with their initials/name/masked number, 6 PIN boxes filled via the
/// device's own keyboard (no custom on-screen keypad), and a fallback
/// link to verify via OTP if the PIN is forgotten.
/// Returning-user fast path: shows the resident's masked mobile number and
/// asks for the PIN. Verification runs against the salted hash in [AuthStore]
/// (this screen never holds the real PIN) with failed-attempt lockout.
class EnterPinScreen extends StatefulWidget {
  final AuthStore auth;
  final VoidCallback? onBack;
  final VoidCallback onForgotPin;
  final VoidCallback onUseDifferentNumber;
  final VoidCallback onVerified;

  /// The full number (+63 …) the resident verified, used for the greeting /
  /// masked number in demo mode when no real account is stored yet.
  final String phoneNumber;

const EnterPinScreen({
      super.key,
      required this.auth,
      this.onBack,
      required this.onForgotPin,
      required this.onUseDifferentNumber,
      required this.onVerified,
      this.phoneNumber = '',
    });

  @override
  State<EnterPinScreen> createState() => _EnterPinScreenState();
}

class _EnterPinScreenState extends State<EnterPinScreen> {
  static const int _pinLength = 6;
  static const int _minPinLength = 4;
  final List<TextEditingController> _controllers = List.generate(
    _pinLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _pinLength,
    (_) => FocusNode(),
  );

  String? _errorText;
  bool _isVerifying = false;
  bool _obscurePin = true;
  int _lockedSeconds = 0;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _refreshLockout();
  }

  String get _pin => _controllers.map((c) => c.text).join();
  bool get _isComplete => _pin.length == _pinLength;
  bool get _isValid =>
      _pin.length >= _minPinLength && _pin.length <= _pinLength;
  bool get _isLocked => _lockedSeconds > 0;

  String get _userName {
    final name = widget.auth.account?.displayName.trim() ?? '';
    if (name.isNotEmpty) return name;
    // Demo login without a stored account — show the demo designation.
    if (AuthStore.demoMode) return AuthStore.demoName;
    return 'Kababayan';
  }

  String get _initials {
    final trimmed = _userName.trim();
    if (trimmed.isEmpty) return 'KK';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    final word = parts.first;
    return (word.length >= 2 ? word.substring(0, 2) : word * 2).toUpperCase();
  }

  String get _maskedNumber {
    if (widget.auth.hasAccount) return widget.auth.maskedPhone;
    // Demo: build a masked display from the number the resident entered.
    final digits = AuthStore.normalizePhone(widget.phoneNumber);
    if (digits.length < 4) return widget.phoneNumber;
    return '+63 XXX ${digits.substring(digits.length - 4)}';
  }

  String get _lockCountdown {
    final m = _lockedSeconds ~/ 60;
    final s = _lockedSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _refreshLockout() {
    final remaining = widget.auth.lockoutSecondsRemaining;
    if (remaining > 0) {
      setState(() {
        _lockedSeconds = remaining;
        _errorText = 'Too many incorrect attempts. Try again later.';
      });
      _startLockCountdown();
    }
  }

  void _startLockCountdown() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = widget.auth.lockoutSecondsRemaining;
      setState(() {
        _lockedSeconds = remaining;
        if (remaining <= 0) {
          _errorText = null;
        }
      });
      if (remaining <= 0) {
        _lockTimer?.cancel();
        _focusNodes.first.requestFocus();
      }
    });
  }

  void _clearPinBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
  }

  void _onDigitChanged(int index, String value) {
    if (_isLocked) return;
    setState(() => _errorText = null);
    if (value.isNotEmpty && index < _pinLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
    if (_isComplete) {
      _handleVerify();
    }
  }

  void _handleVerify() async {
    if (!_isValid || _isVerifying || _isLocked) return;
    setState(() {
      _isVerifying = true;
      _errorText = null;
    });
    final result = await widget.auth.verifyPin(_pin);
    if (!mounted) return;
    switch (result.status) {
      case PinStatus.ok:
        // Unfocus + settle so the web engine finishes its input connection
        // before this screen is torn down (avoids the text_editing.dart
        // "DOM element ... not currently active" assert, flutter#178619).
        FocusManager.instance.primaryFocus?.unfocus();
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        widget.onVerified();
        // Defensive: if the caller forgot onLoginSuccess / onVerified
        // navigation, don't leave the spinner stuck forever.
        if (mounted) setState(() => _isVerifying = false);
        break;
      case PinStatus.wrong:
        _clearPinBoxes();
        setState(() {
          _isVerifying = false;
          _errorText = 'Incorrect PIN. '
              '${result.attemptsLeft} attempt(s) left before lockout.';
        });
        break;
      case PinStatus.locked:
        _clearPinBoxes();
        setState(() {
          _isVerifying = false;
          _lockedSeconds = result.lockoutSeconds;
          _errorText = 'Too many incorrect attempts. Try again later.';
        });
        _startLockCountdown();
        break;
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
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
            // ---- Header + "Welcome back" card (green) ----
            Container(
              color: AppColors.primaryDark,
              padding: const EdgeInsets.fromLTRB(12, 50, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (widget.onBack != null)
                        InkWell(
                          onTap: widget.onBack,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      if (widget.onBack != null) const SizedBox(width: 4),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Log In · Step 4 of 4',
                              style: TextStyle(
                                color: AppColors.primaryLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Enter your PIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onBack == null)
                        const Text(
                          'Enter your PIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.badgeRed,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            _initials,
                            style: const TextStyle(
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
                                'Welcome back, $_userName!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _maskedNumber,
                                style: const TextStyle(
                                  color: AppColors.primaryLight,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---- Body: PIN entry ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  children: [
                    const Text(
                      'Welcome back! Enter your 4–6 digit PIN to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    if (widget.auth.isDemoAccount) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.infoBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Demo PIN: ${AuthStore.demoPin}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    IgnorePointer(
                      ignoring: _isLocked || _isVerifying,
                      child: Opacity(
                        opacity: _isLocked ? 0.45 : 1.0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(_pinLength, (i) {
                            return _OtpBox(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              obscureText: _obscurePin,
                              onChanged: (v) => _onDigitChanged(i, v),
                              onBackspaceEmpty: i > 0
                                  ? () {
                                      _controllers[i - 1].clear();
                                      _focusNodes[i - 1].requestFocus();
                                      setState(() {});
                                    }
                                  : null,
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _isLocked || _isVerifying
                          ? null
                          : () => setState(
                                () => _obscurePin = !_obscurePin,
                              ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _obscurePin
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _obscurePin ? 'Show PIN' : 'Hide PIN',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.errorText,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (_isLocked) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Try again in $_lockCountdown',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isVerifying || _isLocked
                            ? null
                            : (_isValid ? _handleVerify : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isValid && !_isVerifying
                              ? AppColors.primaryButton
                              : AppColors.primaryButtonDisabled,
                          disabledBackgroundColor:
                              AppColors.primaryButtonDisabled,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Log In',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: _isVerifying || _isLocked
                          ? null
                          : widget.onForgotPin,
                      child: Text(
                        'Forgot PIN? Verify via OTP',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _isLocked
                              ? AppColors.hint
                              : AppColors.hotlineRed,
                          decoration: TextDecoration.underline,
                          decorationColor: _isLocked
                              ? AppColors.hint
                              : AppColors.hotlineRed,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _isVerifying ? null : widget.onUseDifferentNumber,
                      child: const Text(
                        'Not you? Use a different number',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// Device Verification — existing account, new/unregistered device
/// ---------------------------------------------------------------------
/// Shown when OTP succeeds for a number that already has an account but
/// this device is not trusted yet. The resident explicitly registers the
/// device before PIN login is allowed (banking-app style).
class TrustDeviceScreen extends StatefulWidget {
  final String phoneNumber;
  final Future<void> Function() onRegister;
  final VoidCallback onUseDifferentNumber;

  const TrustDeviceScreen({
    super.key,
    required this.phoneNumber,
    required this.onRegister,
    required this.onUseDifferentNumber,
  });

  @override
  State<TrustDeviceScreen> createState() => _TrustDeviceScreenState();
}

class _TrustDeviceScreenState extends State<TrustDeviceScreen> {
  bool _isRegistering = false;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    AuthStore.load().then((auth) async {
      final id = await auth.deviceId();
      if (mounted) setState(() => _deviceId = id);
    });
  }

  String get _maskedNumber {
    final digits =
        AuthStore.normalizePhone(widget.phoneNumber);
    if (digits.length < 4) return widget.phoneNumber;
    return '+63 XXX ${digits.substring(digits.length - 4)}';
  }

  String get _shortDeviceId =>
      _deviceId.length <= 8 ? _deviceId : _deviceId.substring(0, 8);

  Future<void> _handleRegister() async {
    if (_isRegistering) return;
    setState(() => _isRegistering = true);
    await widget.onRegister();
    if (mounted) setState(() => _isRegistering = false);
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
            Container(
              color: AppColors.primaryDark,
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New device detected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This account is already registered. Verify this device '
                    'to continue.',
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.infoBg,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: AppColors.infoBorder),
                            ),
                            child: const Icon(
                              Icons.phonelink_lock_outlined,
                              color: AppColors.primary,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _maskedNumber,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _deviceId.isEmpty
                                ? 'Identifying this device…'
                                : 'Device ID: $_shortDeviceId',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Only register devices you own. If you did not request '
                      'this, choose a different number.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed:
                            _isRegistering ? null : _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryButton,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isRegistering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Register this device',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: _isRegistering
                            ? null
                            : widget.onUseDifferentNumber,
                        child: const Text(
                          'Use a different number',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// LOG IN — Step 3 of 4: Enter verification/access Code
/// ---------------------------------------------------------------------
/// Shown after OTP verification in the Log In flow. The resident enters
/// the barangay-issued verification code; only a valid code unlocks the
/// Enter PIN step. The number shown is preserved from the earlier screens.
class EnterAccessCodeScreen extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback onBack;
  final VoidCallback onVerified;

  const EnterAccessCodeScreen({
    super.key,
    required this.phoneNumber,
    required this.onBack,
    required this.onVerified,
  });

  @override
  State<EnterAccessCodeScreen> createState() => _EnterAccessCodeScreenState();
}

class _EnterAccessCodeScreenState extends State<EnterAccessCodeScreen> {
  static const int _codeLength = 6;

  final List<TextEditingController> _controllers = List.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _codeLength,
    (_) => FocusNode(),
  );

  bool _isVerifying = false;
  bool _obscureCode = true;
  String? _errorText;

  String get _code => _controllers.map((c) => c.text).join();
  bool get _isComplete => _code.length == _codeLength;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _errorText = null);
    if (_isComplete) {
      _handleVerify();
    }
  }

  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
  }

  /// Validates the access code. Demo backend: any 6-digit code is accepted
  /// except "000000", which surfaces the incorrect-code error path.
  /// Replace the simulated call below with the real verification API.
  void _handleVerify() async {
    if (!_isComplete || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _errorText = null;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    if (_code == '000000') {
      setState(() {
        _isVerifying = false;
        _errorText = 'Incorrect code. Please check and try again.';
      });
      _clearCode();
      return;
    }
    setState(() => _isVerifying = false);
    // Release focus before the screen is replaced so the web engine can't
    // race a pending geometry update against a torn-down input element.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onVerified();
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
            StepHeader(
              onBack: widget.onBack,
              stepLabel: 'Log In · Step 3 of 4',
              title: 'Enter Code',
              progress: 0.75,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter your verification code',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textGray,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Enter the access code issued for ',
                          ),
                          TextSpan(
                            text: widget.phoneNumber.isEmpty
                                ? '+63 9XX XXX XXXX'
                                : widget.phoneNumber,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_codeLength, (i) {
                        return _OtpBox(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          obscureText: _obscureCode,
                          onChanged: (v) => _onDigitChanged(i, v),
                          onBackspaceEmpty: i > 0
                              ? () {
                                  _controllers[i - 1].clear();
                                  _focusNodes[i - 1].requestFocus();
                                  setState(() {});
                                }
                              : null,
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _obscureCode = !_obscureCode),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _obscureCode
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _obscureCode ? 'Show code' : 'Hide code',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _errorText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.errorText,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                    if (AuthStore.demoMode) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          'Demo: enter any 6-digit code (e.g. 654321)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.infoBorder),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.textGray,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This code confirms your identity together '
                              'with the OTP. Contact your barangay hall if '
                              'you lost your code.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isVerifying
                            ? null
                            : (_isComplete ? _handleVerify : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isComplete && !_isVerifying
                              ? AppColors.primaryButton
                              : AppColors.primaryButtonDisabled,
                          disabledBackgroundColor:
                              AppColors.primaryButtonDisabled,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Verify Code',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
