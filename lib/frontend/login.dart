import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'create_account.dart';
import '../backend/auth_store.dart';
import '../backend/api_service.dart';

export 'app_colors.dart' show AppColors, PhoneFrame;
export 'create_account.dart' show CreateAccountScreen, AccountCreatedScreen;

/// ---------------------------------------------------------------------
/// Login flow controller — swaps between the steps
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
  landing,
  email,
  createAccount,
  accountCreated,
}

class _LoginFlowState extends State<LoginFlow> {
  late LoginStep _step;
  String _email = '';
  ResidentProfile? _draftProfile;
  AuthStore? _auth;
  String _emailDraft = '';
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
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
  }

  void _showFlowMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finishRegistration() async {
    final auth = _auth;
    final profile = _draftProfile;
    if (auth == null || profile == null) return;
    await auth.saveRegistration(profile);
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
          onLogin: (emailValue, password) async {
            setState(() {
              _isRegistering = false;
              _email = emailValue.trim();
              _emailDraft = emailValue.trim();
            });
            try {
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
              _showFlowMessage(e.message);
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
            if (_isRegistering) {
              _goTo(LoginStep.createAccount);
            } else {
              _goTo(LoginStep.landing);
            }
          },
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
/// Shared header used by step screens (progress header)
/// ---------------------------------------------------------------------
class StepHeader extends StatelessWidget {
  final VoidCallback? onBack;
  final String stepLabel;
  final String title;
  final double progress;

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
                      'Barangay-verified \u00B7 Data Privacy Act (RA 10173) compliant',
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
/// STEP 1 — Enter Email
/// ---------------------------------------------------------------------
class EmailInputScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final ValueChanged<String> onOtpSent;
  final String initialEmail;
  final ValueChanged<String> onEmailChanged;
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
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onOtpSent(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  ? 'Create Account \u00B7 Step 1 of 3'
                  : 'Log In \u00B7 Step 1 of 2',
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
                          ? 'Let\u2019s create your account'
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
