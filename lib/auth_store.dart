import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal resident profile persisted on-device after registration.
/// Only the fields the barangay system requires are stored.
class ResidentProfile {
  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String address;
  final String createdAtIso;

  const ResidentProfile({
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.address,
    required this.createdAtIso,
  });

  String get displayName => '$firstName $lastName'.trim();

  Map<String, dynamic> toJson() => {
        'phoneNumber': phoneNumber,
        'firstName': firstName,
        'lastName': lastName,
        'address': address,
        'createdAtIso': createdAtIso,
      };

  factory ResidentProfile.fromJson(Map<String, dynamic> json) {
    return ResidentProfile(
      phoneNumber: '${json['phoneNumber'] ?? ''}',
      firstName: '${json['firstName'] ?? ''}',
      lastName: '${json['lastName'] ?? ''}',
      address: '${json['address'] ?? ''}',
      createdAtIso: '${json['createdAtIso'] ?? ''}',
    );
  }
}

/// Outcome of a PIN verification attempt.
enum PinStatus {
  /// Correct PIN — attempt counters are reset.
  ok,

  /// Wrong PIN — [PinVerification.attemptsLeft] counts down to lockout.
  wrong,

  /// Temporarily locked — try again after [PinVerification.lockoutSeconds].
  locked,
}

class PinVerification {
  final PinStatus status;
  final int attemptsLeft;
  final int lockoutSeconds;

  const PinVerification._(
    this.status, {
    this.attemptsLeft = 0,
    this.lockoutSeconds = 0,
  });

  const PinVerification.ok() : this._(PinStatus.ok);

  const PinVerification.wrong(int attemptsLeft)
      : this._(PinStatus.wrong, attemptsLeft: attemptsLeft);

  const PinVerification.locked(int lockoutSeconds)
      : this._(PinStatus.locked, lockoutSeconds: lockoutSeconds);
}

/// On-device credential store backing the resident authentication flow.
///
/// Design notes:
/// - The PIN is NEVER stored as plain text — only a salted SHA-256 hash.
/// - "Returning resident = PIN first": [isReturningUser] is true when an
///   account exists, a PIN is set, and this device is trusted.
/// - "Device verification": an existing account on an untrusted device must
///   pass OTP + the Register-This-Device step before PIN login is allowed.
/// - Failed PIN attempts trigger an escalating temporary lockout.
class AuthStore {
  static const String _kAccount = 'cpss.account.v1';
  static const String _kDeviceId = 'cpss.device_id.v1';
  static const String _kTrusted = 'cpss.device_trusted.v1';
  static const String _kTrustedPhone = 'cpss.device_trusted_phone.v1';
  static const String _kPinHash = 'cpss.pin_hash.v1';
  static const String _kPinSalt = 'cpss.pin_salt.v1';
  static const String _kFailedAttempts = 'cpss.pin_failed_attempts.v1';
  static const String _kLockoutUntilMs = 'cpss.pin_lockout_until_ms.v1';
  static const String _kLockoutCount = 'cpss.pin_lockout_count.v1';

  /// Wrong PINs before a temporary lockout kicks in.
  static const int maxAttempts = 5;

  /// First lockout duration; doubles every subsequent cycle (cap 15 min).
  static const int baseLockoutSeconds = 30;
  static const int maxLockoutSeconds = 900;

  final SharedPreferences _prefs;

  AuthStore._(this._prefs);

  static Future<AuthStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthStore._(prefs);
  }

  // ------------------------------------------------------------------
  // Demo mode
  // ------------------------------------------------------------------
  // The whole auth backend is simulated for the demo (no SMS, no server).
  // [demoMode] loosens the Log In path so any well-formed number and the
  // [demoPin] are accepted, letting reviewers reach Home without a real
  // registered account. Set this to false and wire the real backend to
  // restore strict behavior.

  /// When true, Log In accepts any valid mobile number and [demoPin].
  static const bool demoMode = true;

  /// The PIN accepted on the Log In screen when demo mode is on and no real
  /// account/PIN is stored on the device yet.
  static const String demoPin = '123456';

  /// Demo designation used for the masked number / greeting when no actual
  /// account is stored (so demo Log In doesn't show a blank name).
  static const String demoName = 'Demo Resident';

  /// In demo mode the [demoPin] always unlocks Log In, so the demo hint is
  /// always relevant on the PIN screen.
  bool get isDemoAccount => demoMode;

  // ------------------------------------------------------------------
  // Account
  // ------------------------------------------------------------------

  ResidentProfile? get account {
    final raw = _prefs.getString(_kAccount);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final profile = ResidentProfile.fromJson(map);
      if (profile.phoneNumber.isEmpty) return null;
      return profile;
    } catch (_) {
      return null;
    }
  }

  bool get hasAccount => account != null;

  /// Compares by last 10 digits so "+63 9XX…", "09XX…" and "9XX…" all match.
  static String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 10) return digits.substring(digits.length - 10);
    return digits;
  }

  bool accountMatches(String phone) {
    final acc = account;
    if (acc == null) return false;
    return normalizePhone(acc.phoneNumber) == normalizePhone(phone);
  }

  String get maskedPhone {
    final acc = account;
    if (acc == null) return '+63 XXX XXXX';
    final digits = normalizePhone(acc.phoneNumber);
    if (digits.length < 4) return acc.phoneNumber;
    return '+63 XXX ${digits.substring(digits.length - 4)}';
  }

  Future<void> saveRegistration(ResidentProfile profile) async {
    await _prefs.setString(_kAccount, jsonEncode(profile.toJson()));
  }

  // ------------------------------------------------------------------
  // Trusted device
  // ------------------------------------------------------------------

  /// Stable per-install device identifier (created lazily).
  Future<String> deviceId() async {
    var id = _prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      final bytes = List<int>.generate(12, (_) => r.nextInt(256));
      id = base64Url.encode(bytes).replaceAll('=', '');
      await _prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  bool get isDeviceTrusted {
    if (!(_prefs.getBool(_kTrusted) ?? false)) return false;
    final acc = account;
    if (acc == null) return false;
    return normalizePhone(_prefs.getString(_kTrustedPhone) ?? '') ==
        normalizePhone(acc.phoneNumber);
  }

  /// Marks this device as trusted for the currently stored account.
  Future<void> trustDevice() async {
    final acc = account;
    if (acc == null) return;
    await deviceId();
    await _prefs.setBool(_kTrusted, true);
    await _prefs.setString(_kTrustedPhone, acc.phoneNumber);
  }

  /// Unregisters this device (keeps the account record so the
  /// Device-Verification flow can run on next launch).
  Future<void> untrustDevice() async {
    await _prefs.setBool(_kTrusted, false);
    await _prefs.remove(_kTrustedPhone);
  }

  /// Full reset — as if app data was cleared. Next launch starts at the
  /// mobile-number screen with no remembered account.
  Future<void> eraseAll() async {
    await _prefs.remove(_kAccount);
    await _prefs.remove(_kTrusted);
    await _prefs.remove(_kTrustedPhone);
    await _prefs.remove(_kPinHash);
    await _prefs.remove(_kPinSalt);
    await _prefs.remove(_kFailedAttempts);
    await _prefs.remove(_kLockoutUntilMs);
    await _prefs.remove(_kLockoutCount);
  }

  // ------------------------------------------------------------------
  // PIN (salted SHA-256 hash — never plain text)
  // ------------------------------------------------------------------

  bool get hasPin => (_prefs.getString(_kPinHash) ?? '').isNotEmpty;

  /// True when app launch should go straight to PIN login.
  bool get isReturningUser => hasAccount && hasPin && isDeviceTrusted;

  static String hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt::$pin')).toString();
  }

  static String newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// PIN policy shared by the create/confirm/enter PIN screens: 4–6 digits.
  static bool isValidPin(String pin) {
    if (pin.length < 4 || pin.length > 6) return false;
    return RegExp(r'^[0-9]+$').hasMatch(pin);
  }

  /// Stores a new PIN (hash only) and clears any lockout state.
  Future<void> setPin(String pin) async {
    final salt = newSalt();
    await _prefs.setString(_kPinSalt, salt);
    await _prefs.setString(_kPinHash, hashPin(pin, salt));
    await _prefs.setInt(_kFailedAttempts, 0);
    await _prefs.setInt(_kLockoutUntilMs, 0);
    await _prefs.setInt(_kLockoutCount, 0);
  }

  int get failedAttempts => _prefs.getInt(_kFailedAttempts) ?? 0;

  int get lockoutSecondsRemaining {
    final until = _prefs.getInt(_kLockoutUntilMs) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (until <= now) return 0;
    return ((until - now) / 1000).ceil();
  }

  Future<PinVerification> verifyPin(String pin) async {
    // Demo mode: the demo PIN ALWAYS unlocks Log In and clears any lockout
    // left over from earlier testing or from entering a real PIN wrong, so
    // reviewers can never get stuck on the demo.
    if (demoMode && pin == demoPin) {
      await _prefs.setInt(_kFailedAttempts, 0);
      await _prefs.setInt(_kLockoutUntilMs, 0);
      await _prefs.setInt(_kLockoutCount, 0);
      return const PinVerification.ok();
    }

    final remaining = lockoutSecondsRemaining;
    if (remaining > 0) {
      return PinVerification.locked(remaining);
    }

    final salt = _prefs.getString(_kPinSalt) ?? '';
    final stored = _prefs.getString(_kPinHash) ?? '';
    if (stored.isNotEmpty && stored == hashPin(pin, salt)) {
      await _prefs.setInt(_kFailedAttempts, 0);
      await _prefs.setInt(_kLockoutUntilMs, 0);
      await _prefs.setInt(_kLockoutCount, 0);
      return const PinVerification.ok();
    }

    final attempts = failedAttempts + 1;
    if (attempts >= maxAttempts) {
      final count = (_prefs.getInt(_kLockoutCount) ?? 0) + 1;
      var seconds = baseLockoutSeconds * (1 << (count - 1));
      if (seconds > maxLockoutSeconds) seconds = maxLockoutSeconds;
      final until =
          DateTime.now().millisecondsSinceEpoch + seconds * 1000;
      await _prefs.setInt(_kFailedAttempts, 0);
      await _prefs.setInt(_kLockoutCount, count);
      await _prefs.setInt(_kLockoutUntilMs, until);
      return PinVerification.locked(seconds);
    }

    await _prefs.setInt(_kFailedAttempts, attempts);
    return PinVerification.wrong(maxAttempts - attempts);
  }
}
