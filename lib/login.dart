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
import 'api_service.dart';

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

/// ---------------------------------------------------------------------
/// Login flow controller — swaps between the 3 steps
/// ---------------------------------------------------------------------
/// Resident authentication flow.
///
/// Routing principle (two separate paths):
/// - Log In (existing user): landing → email → OTP → home (dashboard). A
///   missing account is redirected to registration with a message.
/// - Create Account (new user): landing → email → OTP → create account
///   form → home. An email that already exists is redirected to the Log In
///   path (OTP already verified) with a message.
/// The OTP is the single verification step for logging in.
class LoginFlow extends StatefulWidget {
  /// Called once the resident is fully authenticated. Kept optional and
  /// generic (no import of home.dart here) so login.dart stays decoupled
  /// from what comes next — main.dart wires it up to actual navigation.
  final VoidCallback? onLoginSuccess;

  /// Where the flow starts.
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

  /// Email entry.
  email,

  /// OTP verification for the entered email.
  otp,

  /// New account: barangay registration form.
  createAccount,

  /// Success confirmation shown after an account is created.
  accountCreated,
}

class _LoginFlowState extends State<LoginFlow> {
  late LoginStep _step;
  String _email = '';
  ResidentProfile? _draftProfile;
  AuthStore? _auth;

  /// Raw email the resident typed, kept in the flow controller so it
  /// survives navigation between steps (spec: "Preserve the entered email
  /// when moving between authentication screens").
  String _emailDraft = '';

  /// Distinguishes the two landing choices even though both verify the
  /// email over OTP: false = "Log In" (existing account),
  /// true = "Create Account" (new registration).
  bool _isRegistering = false;

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

  /// Reserved for a future OTP step. For now registration proceeds
  /// straight from the email screen to the profile form.
  void _handleOtpVerified() {
    if (_isRegistering) {
      _goTo(LoginStep.createAccount);
    } else {
      widget.onLoginSuccess?.call();
    }
  }

  /// Persists a fresh registration: profile cache + trusted device.
  /// The account itself was already inserted into `users` in
  /// [CreateAccountScreen].
  Future<void> _finishRegistration() async {
    final auth = _auth;
    final profile = _draftProfile;
    if (auth == null || profile == null) return;
    await auth.saveRegistration(profile);
    await auth.trustDevice();
  }

  /// Maps a sign-in error to a user-friendly message.
  String _authErrorMessage(ApiException e) => e.message;

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
          onLogin: (emailValue, password) async {
            setState(() {
              _isRegistering = false;
              _email = emailValue.trim();
              _emailDraft = emailValue.trim();
            });
            try {
              // Authenticate against the existing `users` table via the
              // resident_login Postgres function.
              final profile = await ApiService.signIn(
                emailValue.trim(),
                password,
              );
              await auth.saveRegistration(profile);
              await auth.trustDevice();
              if (!mounted) return;
              widget.onLoginSuccess?.call();
            } on ApiException catch (e) {
              if (!mounted) return;
              _showFlowMessage(_authErrorMessage(e));
            } catch (_) {
              if (!mounted) return;
              _showFlowMessage(
                'Connection error. Please check your internet and try again.',
              );
            }
          },
          onCreateAccount: () {
            setState(() {
              _email = '';
              _isRegistering = true;
              _emailDraft = '';
            });
            // No OTP yet: registration goes straight to the profile form.
            _goTo(LoginStep.email);
          },
        );
      case LoginStep.email:
        screen = EmailInputScreen(
          key: ValueKey('email_${_isRegistering ? 'register' : 'login'}'),
          initialEmail: _emailDraft,
          isRegistering: _isRegistering,
          onBack: () => _goTo(LoginStep.landing),
          onSwitchMode: () =>
              setState(() => _isRegistering = !_isRegistering),
          onEmailChanged: (value) => _emailDraft = value,
          onOtpSent: (emailValue) {
            setState(() {
              _email = emailValue.trim();
              _emailDraft = emailValue.trim();
            });
            // OTP is not wired up yet — route by mode.
            // Register → profile form; Log In → landing (direct login).
            if (_isRegistering) {
              _goTo(LoginStep.createAccount);
            } else {
              _goTo(LoginStep.landing);
            }
          },
        );
      case LoginStep.otp:
        screen = OtpScreen(
          key: ValueKey('otp_${_isRegistering ? 'register' : 'login'}'),
          email: _email,
          isRegistering: _isRegistering,
          onBack: () => _goTo(
            _isRegistering ? LoginStep.email : LoginStep.landing,
          ),
          onChangeNumber: () => _goTo(
            _isRegistering ? LoginStep.email : LoginStep.landing,
          ),
          onVerified: _handleOtpVerified,
        );
      case LoginStep.createAccount:
        screen = CreateAccountScreen(
          key: const ValueKey('createAccount'),
          email: _email,
          onBack: () => _goTo(LoginStep.landing),
          onAccountCreated: (profile, password) async {
            setState(() {
              _draftProfile = profile;
            });
            await _finishRegistration();
            if (!mounted) return;
            setState(() {
              _isRegistering = false;
              _emailDraft = _email;
              _step = LoginStep.accountCreated;
            });
          },
        );
      case LoginStep.accountCreated:
        screen = AccountCreatedScreen(
          key: const ValueKey('accountCreated'),
          onContinue: () {
            // Account is created and the session is live — continue
            // straight into the dashboard.
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
/// residents and "Create Account" for new ones. Both paths start at
/// email verification.
class LandingScreen extends StatefulWidget {
  final void Function(String email, String password) onLogin;
  final VoidCallback onCreateAccount;

  const LandingScreen({
    super.key,
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
  bool _obscurePassword = true;

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
                    'EMAIL ADDRESS',
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
                    hint: 'yourname@email.com',
                    icon: Icons.mail_outline,
                    obscure: false,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'PASSWORD',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PasswordField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscure: _obscurePassword,
                    onToggleVisibility: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        final email = _emailController.text.trim();
                        final password = _passwordController.text;
                        final validEmail = RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(email);
                        if (!validEmail) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(const SnackBar(
                              content: Text('Enter a valid email address'),
                            ));
                          return;
                        }
                        if (password.isEmpty) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(const SnackBar(
                              content: Text('Enter your password'),
                            ));
                          return;
                        }
                        widget.onLogin(email, password);
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

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final VoidCallback onToggleVisibility;

  const _PasswordField({
    required this.controller,
    required this.focusNode,
    required this.obscure,
    required this.onToggleVisibility,
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
          hintText: 'Password',
          hintStyle: const TextStyle(color: AppColors.hint),
          prefixIcon: Icon(
            Icons.lock_outline,
            size: 20,
            color: focusNode.hasFocus
                ? AppColors.primary
                : AppColors.textGray,
          ),
          suffixIcon: IconButton(
            onPressed: onToggleVisibility,
            icon: Icon(
              obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20,
              color: AppColors.textGray,
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// STEP 1 — Enter Mobile Number
/// ---------------------------------------------------------------------
class EmailInputScreen extends StatefulWidget {
  /// Null hides the back arrow — the email screen is a root entry
  /// point for first-time users.
  final VoidCallback? onBack;
  final ValueChanged<String> onOtpSent;

  /// Raw email to restore if the screen is revisited (preservation).
  final String initialEmail;
  final ValueChanged<String> onEmailChanged;

  /// False = "Log In" flow, true = "Create Account" flow. Both verify the
  /// email over OTP, but headers, copy, and post-OTP routing differ.
  final bool isRegistering;
  final VoidCallback? onSwitchMode;

  const EmailInputScreen({
    super.key,
    required this.onBack,
    required this.onOtpSent,
    this.initialEmail = '',
    this.onEmailChanged = _noopChange,
    this.isRegistering = false,
    this.onSwitchMode,
  });

  static void _noopChange(String _) {}

  @override
  State<EmailInputScreen> createState() => _EmailInputScreenState();
}

class _EmailInputScreenState extends State<EmailInputScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  bool get _isValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_controller.text.trim());

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
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
    // OTP isn't wired up yet — continue straight to the profile form.
    if (mounted) {
      // Release focus before the screen is replaced so the web engine can't
      // race a pending geometry update against a torn-down input element.
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onOtpSent(_controller.text.trim());
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
                  ? 'Create Account · Step 1 of 3'
                  : 'Log In · Step 1 of 2',
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
                          ? 'Enter your email to register. It will be used '
                              'for your account and alert notifications.'
                          : 'Enter the email linked to your account to '
                              'continue.',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'EMAIL ADDRESS',
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
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textDark,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          hintText: 'yourname@email.com',
                          hintStyle: TextStyle(color: AppColors.hint),
                          prefixIcon: Icon(
                            Icons.mail_outline,
                            size: 20,
                            color: AppColors.textGray,
                          ),
                        ),
                        onChanged: (value) {
                          widget.onEmailChanged(value);
                          setState(() {});
                        },
                      ),
                    ),
                    if (showError) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Enter a valid email address',
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
                              'Your email is used only for account '
                              'verification and alert notifications. It is '
                              'never shared with third parties.',
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
  final String email;
  final VoidCallback onBack;
  final VoidCallback onChangeNumber;
  final VoidCallback onVerified;

  /// False = verifying to log in, true = verifying to register.
  final bool isRegistering;

  const OtpScreen({
    super.key,
    required this.email,
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
                  : 'Log In · Step 2 of 2',
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
                            text: widget.email.isEmpty
                                ? 'your email'
                                : AuthStore.maskEmail(widget.email),
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
                                    : AppColors.textGray.withValues(alpha: 0.5),
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
  final String email;
  final VoidCallback onBack;

  /// Returns the collected resident profile so the flow can persist the
  /// account once the form is submitted.
  final void Function(ResidentProfile profile, String password)
      onAccountCreated;

  const CreateAccountScreen({
    super.key,
    required this.email,
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
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

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
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  static final RegExp _phoneRegex = RegExp(r'^(09|\+639)\d{9}$');

  bool get _isPhoneValid {
    final phone = _phoneController.text.replaceAll(RegExp(r'[\s\-]'), '');
    return _phoneRegex.hasMatch(phone);
  }

  bool get _isValid =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _dateOfBirth != null &&
      _sex != null &&
      _civilStatus != null &&
      _addressController.text.trim().isNotEmpty &&
      _isPhoneValid &&
      AuthStore.isValidPassword(_passwordController.text) &&
      _confirmPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text == _passwordController.text;

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

  void _showMissingFieldsWarning() {
    final missing = <String>[];
    if (_firstNameController.text.trim().isEmpty) missing.add('First Name');
    if (_lastNameController.text.trim().isEmpty) missing.add('Last Name');
    if (_dateOfBirth == null) missing.add('Date of Birth');
    if (_sex == null) missing.add('Sex');
    if (_civilStatus == null) missing.add('Civil Status');
    if (_addressController.text.trim().isEmpty) missing.add('Home Address');
    if (!_isPhoneValid) missing.add('Phone Number');
    if (!AuthStore.isValidPassword(_passwordController.text)) {
      missing.add('Password');
    }
    if (_confirmPasswordController.text.isEmpty ||
        _confirmPasswordController.text != _passwordController.text) {
      missing.add('Confirm Password');
    }

    final String message;
    if (missing.length <= 2) {
      message = 'Please fill in the required fields: ${missing.join(" and ")}.';
    } else {
      message = 'Please fill in all required fields (${missing.length} missing).';
    }

    _showSnack(message);
  }

  void _handleCreateAccount() async {
    if (!_isValid || _isSubmitting) {
      if (!_isValid) _showMissingFieldsWarning();
      return;
    }
    setState(() => _isSubmitting = true);

    try {
      final profile = ResidentProfile(
        email: widget.email,
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        dateOfBirth: _dateOfBirth == null
            ? ''
            : _dateOfBirth!.toIso8601String().substring(0, 10),
        sex: _sex ?? '',
        civilStatus: _civilStatus ?? '',
        address: _addressController.text.trim(),
        phoneNumber: _phoneController.text.replaceAll(RegExp(r'[\s\-]'), ''),
        createdAtIso: DateTime.now().toIso8601String(),
      );

      // Create the Resident in the existing `users` table via the
      // resident_register Postgres function (bcrypt hash server-side).
      await ApiService.register(
        firstName: profile.firstName,
        middleName: profile.middleName,
        lastName: profile.lastName,
        email: profile.email,
        phone: profile.phoneNumber,
        password: _passwordController.text,
        dateOfBirth: profile.dateOfBirth,
        sex: profile.sex,
        civilStatus: profile.civilStatus,
        address: profile.address,
      );

      // Hand the completed registration back to the flow controller.
      if (mounted) {
        widget.onAccountCreated(profile, _passwordController.text);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack(
          'Connection error. Please check your internet and try again.',
        );
      }
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
              stepLabel: 'Create Account · Step 2 of 3',
              title: 'Create your account',
              segments: 3,
              filledSegments: 2,
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
                        _FieldLabel('PHONE NUMBER', required: true),
                        const SizedBox(height: 8),
                        _TextInputBox(
                          controller: _phoneController,
                          hintText: '09XX XXX XXXX or +639XX XXX XXXX',
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_phoneController.text.isNotEmpty &&
                            !_isPhoneValid) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Enter a valid Philippine mobile number '
                            '(e.g. 09171234567).',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.errorText,
                            ),
                          ),
                        ],
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
                                      'Email Address',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.email,
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
                                  color: AppColors.infoBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.infoBorder,
                                  ),
                                ),
                                child: const Text(
                                  'New account',
                                  style: TextStyle(
                                    fontSize: 11.5,
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
                    const SizedBox(height: 16),

                    // ---- Account password ----
                    _SectionCard(
                      title: 'ACCOUNT PASSWORD',
                      children: [
                        _FieldLabel('PASSWORD', required: true),
                        const SizedBox(height: 8),
                        _SecureInputBox(
                          controller: _passwordController,
                          hintText: 'At least ${AuthStore.minPasswordLength} characters',
                          obscure: _obscurePassword,
                          onToggleVisibility: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        _PasswordPolicyChecklist(password: _passwordController.text),
                        if (_passwordController.text.isNotEmpty &&
                            !AuthStore.isValidPassword(_passwordController.text)) ...[
                          const SizedBox(height: 10),
                          _PasswordPolicyErrors(
                            errors: AuthStore.passwordPolicyErrors(
                              _passwordController.text,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _FieldLabel('CONFIRM PASSWORD', required: true),
                        const SizedBox(height: 8),
                        _SecureInputBox(
                          controller: _confirmPasswordController,
                          hintText: 'Re-enter your password',
                          obscure: _obscureConfirmPassword,
                          onToggleVisibility: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_confirmPasswordController.text.isNotEmpty &&
                            _confirmPasswordController.text !=
                                _passwordController.text) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Passwords do not match.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.errorText,
                            ),
                          ),
                        ],
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

/// Success confirmation shown after a new account is created. Displays a
/// checkmark, a clear message, and a Continue button that returns the
/// user to the Login page.
class AccountCreatedScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const AccountCreatedScreen({
    super.key,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 80, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 56,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Account Created Successfully!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your account has been created successfully.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: AppColors.textGray,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryButton,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Continue',
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
                        ? AppColors.primary.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.25),
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

class _PasswordPolicyChecklist extends StatelessWidget {
  final String password;

  const _PasswordPolicyChecklist({required this.password});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password requirements',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
            ),
          ),
          const SizedBox(height: 8),
          _PolicyRow(
            label: 'At least ${AuthStore.minPasswordLength} characters',
            met: password.length >= AuthStore.minPasswordLength,
          ),
          _PolicyRow(
            label: 'At least one uppercase letter',
            met: RegExp(r'[A-Z]').hasMatch(password),
          ),
          _PolicyRow(
            label: 'At least one lowercase letter',
            met: RegExp(r'[a-z]').hasMatch(password),
          ),
          _PolicyRow(
            label: 'At least one number',
            met: RegExp(r'[0-9]').hasMatch(password),
          ),
          _PolicyRow(
            label: 'At least one special character (e.g. @, #, \$, !)',
            met: RegExp(r'[^A-Za-z0-9]').hasMatch(password),
          ),
        ],
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  final String label;
  final bool met;

  const _PolicyRow({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            met ? Icons.check_circle : Icons.cancel,
            size: 15,
            color: met ? AppColors.success : AppColors.hint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: met ? AppColors.textDark : AppColors.hint,
                fontWeight: met ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordPolicyErrors extends StatelessWidget {
  final List<String> errors;

  const _PasswordPolicyErrors({required this.errors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.hotlineBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hotlineBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password must:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.hotlineRed,
            ),
          ),
          const SizedBox(height: 4),
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.hotlineRed,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.hotlineRed,
                      ),
                    ),
                  ),
                ],
              ),
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

class _SecureInputBox extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final VoidCallback onToggleVisibility;

  const _SecureInputBox({
    required this.controller,
    required this.hintText,
    required this.obscure,
    required this.onToggleVisibility,
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
        obscureText: obscure,
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
          suffixIcon: IconButton(
            onPressed: onToggleVisibility,
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
              color: AppColors.textGray,
            ),
          ),
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

