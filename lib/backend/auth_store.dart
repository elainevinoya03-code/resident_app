import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Resident profile stored in the existing Supabase `users` table and
/// cached locally in SharedPreferences for instant access.
class ResidentProfile {
  final String email;
  final String firstName;
  final String middleName;
  final String lastName;
  final String dateOfBirth;
  final String sex;
  final String civilStatus;
  final String address;
  final String phoneNumber;
  final String createdAtIso;

  const ResidentProfile({
    required this.email,
    required this.firstName,
    this.middleName = '',
    required this.lastName,
    this.dateOfBirth = '',
    this.sex = '',
    this.civilStatus = '',
    this.address = '',
    this.phoneNumber = '',
    this.createdAtIso = '',
  });

  String get displayName => '$firstName $lastName'.trim();

  Map<String, dynamic> toJson() => {
    'email': email,
    'firstName': firstName,
    'middleName': middleName,
    'lastName': lastName,
    'dateOfBirth': dateOfBirth,
    'sex': sex,
    'civilStatus': civilStatus,
    'address': address,
    'phoneNumber': phoneNumber,
    'createdAtIso': createdAtIso,
  };

  factory ResidentProfile.fromJson(Map<String, dynamic> json) {
    return ResidentProfile(
      email: '${json['email'] ?? ''}',
      firstName: '${json['firstName'] ?? ''}',
      middleName: '${json['middleName'] ?? ''}',
      lastName: '${json['lastName'] ?? ''}',
      dateOfBirth: '${json['dateOfBirth'] ?? ''}',
      sex: '${json['sex'] ?? ''}',
      civilStatus: '${json['civilStatus'] ?? ''}',
      address: '${json['address'] ?? ''}',
      phoneNumber: '${json['phoneNumber'] ?? ''}',
      createdAtIso: '${json['createdAtIso'] ?? ''}',
    );
  }
}

/// Authentication and profile store backed by Supabase.
///
/// Login/registration run against the existing `users` table through
/// [ApiService] (no Supabase Auth sessions). The profile is cached in
/// [SharedPreferences] so the UI can read it synchronously on every
/// launch while a fresh copy is fetched from the database in the
/// background.
class AuthStore {
  static const String _kProfile = 'cpss.profile.v2';
  static const String _kDeviceId = 'cpss.device_id.v1';
  static const String _kTrusted = 'cpss.device_trusted.v1';
  static const String _kTrustedEmail = 'cpss.device_trusted_email.v1';

  // ── Password policy (client-side validation only) ────────────

  static const int minPasswordLength = 8;
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasNumber = RegExp(r'[0-9]');
  static final RegExp _hasSpecial = RegExp(r'[^A-Za-z0-9]');

  static List<String> passwordPolicyErrors(String password) {
    final errors = <String>[];
    if (password.length < minPasswordLength) {
      errors.add('be at least $minPasswordLength characters');
    }
    if (!_hasUppercase.hasMatch(password)) {
      errors.add('contain at least one uppercase letter');
    }
    if (!_hasLowercase.hasMatch(password)) {
      errors.add('contain at least one lowercase letter');
    }
    if (!_hasNumber.hasMatch(password)) {
      errors.add('contain at least one number');
    }
    if (!_hasSpecial.hasMatch(password)) {
      errors.add('contain at least one special character (e.g. @, #, \$, !)');
    }
    return errors;
  }

  static bool isValidPassword(String password) =>
      passwordPolicyErrors(password).isEmpty;

  // ── Email helpers ────────────────────────────────────────────

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static String maskEmail(String email) {
    final e = email.trim();
    final at = e.indexOf('@');
    if (at <= 1) return e;
    final local = e.substring(0, at);
    final first = local[0];
    final masked = '$first${'*' * (local.length - 1)}';
    return '$masked${e.substring(at)}';
  }

  // ── Instance ─────────────────────────────────────────────────

  final SharedPreferences _prefs;
  ResidentProfile? _profile;

  AuthStore._(this._prefs);

  /// Load the cached profile and kick off a background refresh from
  /// Supabase. Returns immediately so the UI is never blocked.
  static Future<AuthStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = AuthStore._(prefs);

    // Restore the cached profile so the first frame has data.
    store._profile = store._readCache();

    // Fire-and-forget: fetch the fresh profile from Supabase and
    // update the cache. Callers that need the fresh data right away
    // should await [refreshProfile] instead.
    store._refreshProfileInBackground();

    return store;
  }

  // ── Account ──────────────────────────────────────────────────

  /// The cached resident profile. Returns `null` when no profile has
  /// been stored yet (first launch, or after clearing app data).
  ResidentProfile? get account => _profile;

  bool get hasAccount => _profile != null;

  /// True when the currently cached profile matches [email].
  bool accountMatches(String email) {
    final acc = _profile;
    if (acc == null) return false;
    return normalizeEmail(acc.email) == normalizeEmail(email);
  }

  String get maskedEmail {
    final acc = _profile;
    if (acc == null || acc.email.isEmpty) return 'name@email.com';
    return maskEmail(acc.email);
  }

  /// Persist a profile in the local cache. The account itself is already
  /// stored in the `users` table server-side during registration/login.
  Future<void> saveRegistration(ResidentProfile profile) async {
    _profile = profile;
    await _writeCache(profile);
  }

  /// Fetch the latest profile from Supabase by the cached email and
  /// update the cache.
  Future<void> refreshProfile() async {
    try {
      final email = _profile?.email;
      if (email == null || email.isEmpty) return;
      final profile = await ApiService.fetchProfileByEmail(email);
      if (profile != null) {
        _profile = profile;
        await _writeCache(profile);
      }
    } catch (_) {
      // Keep the stale cache; don't crash.
    }
  }

  // ── Trusted device (local-only) ──────────────────────────────

  Future<String> deviceId() async {
    var id = _prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await _prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  bool get isDeviceTrusted {
    if (!(_prefs.getBool(_kTrusted) ?? false)) return false;
    final acc = _profile;
    if (acc == null) return false;
    return normalizeEmail(_prefs.getString(_kTrustedEmail) ?? '') ==
        normalizeEmail(acc.email);
  }

  Future<void> trustDevice() async {
    final acc = _profile;
    if (acc == null) return;
    await deviceId();
    await _prefs.setBool(_kTrusted, true);
    await _prefs.setString(_kTrustedEmail, acc.email);
  }

  Future<void> untrustDevice() async {
    await _prefs.setBool(_kTrusted, false);
    await _prefs.remove(_kTrustedEmail);
  }

  bool get isReturningUser => hasAccount && isDeviceTrusted;

  /// Full reset — clears cached profile and device trust.
  Future<void> eraseAll() async {
    _profile = null;
    await _prefs.remove(_kProfile);
    await _prefs.remove(_kTrusted);
    await _prefs.remove(_kTrustedEmail);
  }

  // ── Private helpers ──────────────────────────────────────────

  void _refreshProfileInBackground() async {
    try {
      final email = _profile?.email;
      if (email == null || email.isEmpty) return;
      final profile = await ApiService.fetchProfileByEmail(email);
      if (profile != null) {
        _profile = profile;
        await _writeCache(profile);
      }
    } catch (_) {
      // Best-effort; the stale cache (or null) is fine.
    }
  }

  ResidentProfile? _readCache() {
    final raw = _prefs.getString(_kProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final profile = ResidentProfile.fromJson(map);
      if (profile.email.isEmpty) return null;
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(ResidentProfile profile) async {
    await _prefs.setString(_kProfile, jsonEncode(profile.toJson()));
  }
}
