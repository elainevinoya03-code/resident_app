import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'app_colors.dart';
import '../backend/auth_store.dart';
import '../backend/api_service.dart';

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
  double? _locationAccuracy;
  bool _isLocating = false;
  bool _isGeoDecoding = false;
  Timer? _reverseDebounce;

  static final LatLng _defaultCenter = LatLng(14.6760, 121.0437);

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

      if (fix.accuracy > 30) {
        _showSnack(
          'Rough fix (\u00B1${fix.accuracy.toStringAsFixed(0)}m) — '
          'waiting for GPS to refine\u2026',
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
              ? 'Location found (\u00B1${acc.toStringAsFixed(0)}m). '
                  'Fine-tune the pin if needed.'
              : 'Still rough (\u00B1${acc.toStringAsFixed(0)}m) — '
                  'please move the map to fine-tune the pin.',
        );
      }
    } catch (e) {
      _showSnack('Could not determine your location.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

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

  void _onMapCenterChanged(LatLng center) {
    if (_selectedLocation == center) return;
    setState(() {
      _selectedLocation = center;
      _locationAccuracy = null;
    });
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _reverseGeocode(center);
    });
  }

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
    } catch (_) {}
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
              stepLabel: 'Create Account \u00B7 Step 2 of 3',
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
                                      _age?.toString() ?? '\u2014',
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
                                    ? 'Looking up address for the pin\u2026'
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
                                  '${_locationAccuracy != null ? ' \u00B7 GPS \u00B1${_locationAccuracy!.toStringAsFixed(0)}m' : ''}',
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

/// Success confirmation shown after a new account is created.
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
                decoration: const BoxDecoration(
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

/// Interactive Leaflet (OpenStreetMap) widget with a fixed center pin.
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
                    '\u2022 ',
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
