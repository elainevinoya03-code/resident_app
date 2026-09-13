import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_store.dart';

/// An error that can be shown directly in the UI.
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// Dart backend layer for login and registration.
///
/// Authentication runs directly against the existing `users` table through
/// the [resident_login] / [resident_register] Postgres functions, so the
/// resident app and the CPSS web dashboard (FastAPI) share the same account
/// data and bcrypt password hashes. No Supabase Auth sessions are used.
class ApiService {
  static SupabaseClient get _client => Supabase.instance.client;

  // ──────────────────────────── Auth ────────────────────────────

  /// Verify email + password against the `users` table.
  /// Returns the resident profile, or throws [ApiException] with a
  /// user-friendly message (e.g. wrong credentials, deactivated account).
  static Future<ResidentProfile> signIn(String email, String password) async {
    try {
      final data = await _client.rpc(
        'resident_login',
        params: {'p_email': email.trim(), 'p_password': password},
      );
      return profileFromApi(data as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ApiException(_authError(e.message));
    }
  }

  /// Register a new Resident in the `users` table.
  /// Returns the created resident profile, or throws [ApiException]
  /// (e.g. email already registered, weak password).
  static Future<ResidentProfile> register({
    required String firstName,
    required String middleName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String dateOfBirth,
    required String sex,
    required String civilStatus,
    required String address,
  }) async {
    final name = [
      firstName.trim(),
      if (middleName.trim().isNotEmpty) middleName.trim(),
      lastName.trim(),
    ].join(' ');

    try {
      final data = await _client.rpc(
        'resident_register',
        params: {
          'p_name': name,
          'p_email': email.trim(),
          'p_phone': phone,
          'p_password': password,
          'p_birthday': dateOfBirth.isEmpty ? null : dateOfBirth,
          'p_sex': sex,
          'p_civil_status': civilStatus,
          'p_address': address,
        },
      );
      return profileFromApi(data as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ApiException(_registerError(e.message));
    }
  }

  /// Fetch a user row from the `users` table by email.
  /// Returns `null` when no matching account exists.
  static Future<ResidentProfile?> fetchProfileByEmail(String email) async {
    try {
      final data = await _client
          .from('users')
          .select(
            'id,user_id,name,email,phone,role,purok,active,two_factor,'
            'last_login,birthday,sex,civil_status,address,created_at,'
            'updated_at',
          )
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();
      if (data == null) return null;
      return profileFromApi(data);
    } on PostgrestException {
      return null;
    }
  }

  // ────────────────────────── Mapping ───────────────────────────

  /// Convert a `users` table row into a [ResidentProfile].
  static ResidentProfile profileFromApi(Map<String, dynamic> row) {
    final fullName = '${row['name'] ?? ''}'.trim();
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.last : '';
    final middleName =
        parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';

    return ResidentProfile(
      email: '${row['email'] ?? ''}',
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      dateOfBirth: '${row['birthday'] ?? ''}',
      sex: '${row['sex'] ?? ''}',
      civilStatus: '${row['civil_status'] ?? ''}',
      address: '${row['address'] ?? ''}',
      phoneNumber: '${row['phone'] ?? ''}',
      createdAtIso: '${row['created_at'] ?? ''}',
    );
  }

  // ─────────────────────── Error messages ───────────────────────

  static String _authError(String? message) {
    final msg = (message ?? '').toUpperCase();
    if (msg.contains('ACCOUNT_DEACTIVATED')) {
      return 'This account has been deactivated.';
    }
    if (msg.contains('INVALID_CREDENTIALS')) {
      return 'Incorrect email or password.';
    }
    return 'Sign in failed. Please try again.';
  }

  static String _registerError(String? message) {
    final msg = (message ?? '').toUpperCase();
    if (msg.contains('EMAIL_EXISTS')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('WEAK_PASSWORD')) {
      return 'Password must be at least 8 characters.';
    }
    if (msg.contains('NAME_REQUIRED')) {
      return 'Please enter your full name.';
    }
    if (msg.contains('EMAIL_REQUIRED')) {
      return 'Please enter your email address.';
    }
    return 'Could not create your account. Please try again.';
  }
}