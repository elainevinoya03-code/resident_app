import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'auth_store.dart';
import 'login.dart';
import 'home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  runApp(const SCSSApp());
}

class SCSSApp extends StatelessWidget {
  const SCSSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CPSS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
      ),
      builder: (context, child) => PhoneFrame(child: child!),
      home: const AuthGate(),
    );
  }
}

/// App-launch router: the landing page (Log In / Create Account) is always
/// the entry point. Returning residents on a trusted device can log back in
/// from here by verifying their email.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthStore? _auth;

  @override
  void initState() {
    super.initState();
    AuthStore.load().then((auth) {
      if (mounted) setState(() => _auth = auth);
    });
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOut,
                    ),
                  ),
              child: child,
            ),
          );
        },
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    if (auth == null) {
      // Splash while reading the trusted-device state — keeps launch fast.
      return const Scaffold(
        backgroundColor: AppColors.primaryDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CPSS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Smart Community Safety System',
                style: TextStyle(color: AppColors.primaryLight, fontSize: 13),
              ),
              SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LoginFlow(
      initialStep: LoginStep.landing,
      onLoginSuccess: _goHome,
    );
  }
}
