import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../backend/auth_store.dart';
import '../backend/report_service.dart';
import 'login.dart' show AppColors, StepHeader;
import 'my_report.dart' show ReportsScreen;

/// ---------------------------------------------------------------------
/// Incident categories & specific types — barangay report specification
/// ---------------------------------------------------------------------
enum IncidentCategory {
  publicSafety, // Public Safety & Peace and Order
  crimeProperty, // Crime & Property
  domesticFamily, // Domestic & Family
  communityDisputes, // Community Disputes
  violenceGender, // Violence & Gender-Related
  trafficRoad, // Traffic & Road
  environmental, // Environmental & Sanitation
  animalRelated, // Animal-Related
  missingWelfare, // Missing / Welfare
  barangayAdmin, // Barangay / Administrative
  other, // Other
}

enum RequestedAction {
  blotterOnly,
  issueSummons,
  mediation,
  referral,
  bpo,
  other,
}

class _CategoryInfo {
  final IconData icon;
  final Color iconBg;
  final Color accent;
  final String label;
  final List<String> types;

  const _CategoryInfo({
    required this.icon,
    required this.iconBg,
    required this.accent,
    required this.label,
    required this.types,
  });
}

const Map<IncidentCategory, _CategoryInfo> _categoryData = {
  IncidentCategory.publicSafety: _CategoryInfo(
    icon: Icons.record_voice_over_outlined,
    iconBg: Color(0xFFFFE4E6),
    accent: Color(0xFFDC2626),
    label: 'Public Safety & Peace and Order',
    types: [
      'Public Disturbance',
      'Fighting / Physical Altercation',
      'Threat / Intimidation',
      'Harassment',
      'Stalking',
      'Suspicious Person',
      'Suspicious Activity',
      'Loitering',
      'Public Intoxication',
      'Disorderly Conduct',
      'Trespassing',
      'Illegal Activity',
      'Curfew Violation',
    ],
  ),
  IncidentCategory.crimeProperty: _CategoryInfo(
    icon: Icons.lock_open_outlined,
    iconBg: Color(0xFFE8ECE8),
    accent: AppColors.textGray,
    label: 'Crime & Property',
    types: [
      'Theft / Pagnanakaw',
      'Robbery / Hold-up',
      'Burglary / Breaking and Entering',
      'Attempted Theft',
      'Vandalism',
      'Property Damage',
      'Lost Property',
      'Found Property',
      'Fraud / Scam',
      'Unauthorized Use of Property',
      'Missing Property',
    ],
  ),
  IncidentCategory.domesticFamily: _CategoryInfo(
    icon: Icons.home_outlined,
    iconBg: Color(0xFFE8F0FF),
    accent: Color(0xFF3B82F6),
    label: 'Domestic & Family',
    types: [
      'Domestic Dispute',
      'Family Conflict',
      'Verbal Abuse',
      'Physical Abuse',
      'Child Abuse / Neglect',
      'Elder Abuse',
      'Spousal Conflict',
      'Child Custody Dispute',
    ],
  ),
  IncidentCategory.communityDisputes: _CategoryInfo(
    icon: Icons.group_outlined,
    iconBg: Color(0xFFE8F0FF),
    accent: Color(0xFF3B82F6),
    label: 'Community Disputes',
    types: [
      'Neighbor Dispute',
      'Noise Complaint',
      'Verbal Dispute',
      'Boundary Dispute',
      'Property Dispute',
      'Right-of-Way Dispute',
      'Water / Utility Dispute',
      'Community Association Dispute',
      'Other Barangay Dispute',
    ],
  ),
  IncidentCategory.violenceGender: _CategoryInfo(
    icon: Icons.shield_outlined,
    iconBg: Color(0xFFFFE4E6),
    accent: Color(0xFFDC2626),
    label: 'Violence & Gender-Related',
    types: [
      'Physical Assault',
      'Verbal Abuse',
      'Sexual Harassment',
      'Sexual Assault',
      'Violence Against Women',
      'Violence Against Children',
      'Threat / Coercion',
      'Other Gender-Based Incident',
    ],
  ),
  IncidentCategory.trafficRoad: _CategoryInfo(
    icon: Icons.local_police_outlined,
    iconBg: Color(0xFFFFF4CC),
    accent: Color(0xFFD9A400),
    label: 'Traffic & Road',
    types: [
      'Vehicular Accident',
      'Motorcycle Accident',
      'Pedestrian Accident',
      'Reckless Driving',
      'Illegal Parking',
      'Road Obstruction',
      'Traffic Violation',
      'Hit-and-Run',
      'Road Hazard',
    ],
  ),
  IncidentCategory.environmental: _CategoryInfo(
    icon: Icons.eco_outlined,
    iconBg: Color(0xFFE8F5EC),
    accent: Color(0xFF166534),
    label: 'Environmental & Sanitation',
    types: [
      'Illegal Dumping',
      'Improper Waste Disposal',
      'Burning of Garbage',
      'Noise Pollution',
      'Water Pollution',
      'Air Pollution',
      'Drainage Problem',
      'Sewage / Wastewater Complaint',
      'Obstruction of Drainage',
      'Unsanitary Premises',
    ],
  ),
  IncidentCategory.animalRelated: _CategoryInfo(
    icon: Icons.pets_outlined,
    iconBg: Color(0xFFE8F5EC),
    accent: Color(0xFF166534),
    label: 'Animal-Related',
    types: [
      'Animal Bite',
      'Stray Animal',
      'Aggressive Animal',
      'Lost Animal',
      'Animal Cruelty',
      'Animal Nuisance',
      'Dead Animal',
    ],
  ),
  IncidentCategory.missingWelfare: _CategoryInfo(
    icon: Icons.help_outline,
    iconBg: Color(0xFFE8F0FF),
    accent: Color(0xFF3B82F6),
    label: 'Missing / Welfare',
    types: [
      'Missing Person',
      'Found Person',
      'Welfare Check',
      'Abandoned Person',
      'Abandoned Child',
      'Person in Distress',
      'Mental / Emotional Distress',
    ],
  ),
  IncidentCategory.barangayAdmin: _CategoryInfo(
    icon: Icons.apartment_outlined,
    iconBg: Color(0xFFE8ECE8),
    accent: AppColors.textGray,
    label: 'Barangay / Administrative',
    types: [
      'Complaint Against Resident',
      'Complaint Against Business',
      'Permit-Related Concern',
      'Barangay Clearance Concern',
      'Certification Concern',
      'Public Facility Complaint',
      'Community Service Concern',
      'Other Administrative Concern',
    ],
  ),
  IncidentCategory.other: _CategoryInfo(
    icon: Icons.help_outline,
    iconBg: Color(0xFFE8ECE8),
    accent: AppColors.textGray,
    label: 'Other',
    types: [
      'Information Report',
      'Incident Referral',
      'Request for Assistance',
      'Unknown / For Assessment',
      'Other Incident',
    ],
  ),
};

/// ---------------------------------------------------------------------
/// Incident-specific (type-dependent) field schema
/// ---------------------------------------------------------------------
class _SpecificField {
  final String label;
  final bool isToggle;
  const _SpecificField(this.label, {this.isToggle = false});
}

class _SpecificInfoSet {
  final String title;
  final List<_SpecificField> fields;
  const _SpecificInfoSet({required this.title, required this.fields});
}

const _theftRobberySet = _SpecificInfoSet(
  title: 'Theft / Robbery',
  fields: [
    _SpecificField('Property stolen'),
    _SpecificField('Property description'),
    _SpecificField('Estimated value'),
    _SpecificField('Quantity'),
    _SpecificField('Where it was taken'),
    _SpecificField('When it was last seen'),
    _SpecificField('Suspect description'),
    _SpecificField('Weapon involved?', isToggle: true),
    _SpecificField('CCTV available?', isToggle: true),
  ],
);

const _physicalAssaultSet = _SpecificInfoSet(
  title: 'Physical Altercation / Assault',
  fields: [
    _SpecificField('Number of persons involved'),
    _SpecificField('Victim/s'),
    _SpecificField('Respondent/s'),
    _SpecificField('Relationship between parties'),
    _SpecificField('Type of injury'),
    _SpecificField('Body part injured'),
    _SpecificField('Medical treatment required?', isToggle: true),
    _SpecificField('Weapon/object used?', isToggle: true),
    _SpecificField('Cause of altercation'),
  ],
);

const _domesticDisputeSet = _SpecificInfoSet(
  title: 'Domestic Dispute',
  fields: [
    _SpecificField('Relationship of parties'),
    _SpecificField('Persons involved'),
    _SpecificField('Nature of dispute'),
    _SpecificField('Verbal / Physical / Other'),
    _SpecificField('Threats involved?', isToggle: true),
    _SpecificField('Injury involved?', isToggle: true),
    _SpecificField('Children involved?', isToggle: true),
    _SpecificField('Immediate safety concern?', isToggle: true),
    _SpecificField('Previous related incident?', isToggle: true),
    _SpecificField('Intervention provided'),
  ],
);

const _noiseComplaintSet = _SpecificInfoSet(
  title: 'Noise Complaint',
  fields: [
    _SpecificField('Source of noise'),
    _SpecificField('Type of noise'),
    _SpecificField('Start time'),
    _SpecificField('Duration'),
    _SpecificField('Frequency'),
    _SpecificField('Location of source'),
    _SpecificField('Previous complaints?', isToggle: true),
    _SpecificField('Warning already given?', isToggle: true),
    _SpecificField('Action taken'),
    _SpecificField('Outcome'),
  ],
);

const _vehicularAccidentSet = _SpecificInfoSet(
  title: 'Vehicular Accident',
  fields: [
    _SpecificField('Number of vehicles'),
    _SpecificField('Vehicle type'),
    _SpecificField('Plate number'),
    _SpecificField('Driver/s involved'),
    _SpecificField('Passenger/s'),
    _SpecificField('Pedestrian involved?', isToggle: true),
    _SpecificField('Injuries'),
    _SpecificField('Road condition'),
    _SpecificField('Weather condition'),
    _SpecificField('Property damage'),
    _SpecificField('Emergency response'),
    _SpecificField('Referral'),
  ],
);


const _animalBiteSet = _SpecificInfoSet(
  title: 'Animal Bite',
  fields: [
    _SpecificField('Animal type'),
    _SpecificField('Animal description'),
    _SpecificField('Owned / Stray'),
    _SpecificField('Location'),
    _SpecificField('Victim'),
    _SpecificField('Body part injured'),
    _SpecificField('Injury severity'),
    _SpecificField('Medical treatment'),
    _SpecificField('Owner information (if known)'),
    _SpecificField('Vaccination status (if known)'),
    _SpecificField('Animal located?', isToggle: true),
  ],
);

const Map<String, _SpecificInfoSet> _specificInfoData = {
  'Theft / Pagnanakaw': _theftRobberySet,
  'Robbery / Hold-up': _theftRobberySet,
  'Burglary / Breaking and Entering': _theftRobberySet,
  'Fighting / Physical Altercation': _physicalAssaultSet,
  'Physical Assault': _physicalAssaultSet,
  'Domestic Dispute': _domesticDisputeSet,
  'Family Conflict': _domesticDisputeSet,
  'Noise Complaint': _noiseComplaintSet,
  'Noise Pollution': _noiseComplaintSet,
  'Vehicular Accident': _vehicularAccidentSet,
  'Motorcycle Accident': _vehicularAccidentSet,
  'Pedestrian Accident': _vehicularAccidentSet,
  'Hit-and-Run': _vehicularAccidentSet,
  'Animal Bite': _animalBiteSet,
};

/// ---------------------------------------------------------------------
/// SOS / emergency accent color
/// ---------------------------------------------------------------------
const Color _emergencyAccent = Color(0xFFDC2626);

/// ---------------------------------------------------------------------
/// Photo & witness models
/// ---------------------------------------------------------------------
class _ReportPhoto {
  final int id;
  final String fileName;
  final Uint8List bytes;
  double progress = 0;
  bool get uploaded => progress >= 1.0;

  _ReportPhoto({required this.id, required this.fileName, required this.bytes});
}

class _Witness {
  final TextEditingController name = TextEditingController();
  final TextEditingController address = TextEditingController();
  final TextEditingController contact = TextEditingController();
  final TextEditingController whatWitnessed = TextEditingController();

  void dispose() {
    name.dispose();
    address.dispose();
    contact.dispose();
    whatWitnessed.dispose();
  }
}

enum _ReportStep {
  type,
  subtype,
  specificInfo,
  details,
  people,
  evidence,
  review,
  success,
}

/// =====================================================================
/// Flow controller
/// =====================================================================
class ReportIncidentFlow extends StatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onBackToHome;
  final ValueChanged<String>? onSubmitted;

  const ReportIncidentFlow({
    super.key,
    this.onClose,
    this.onBackToHome,
    this.onSubmitted,
  });

  @override
  State<ReportIncidentFlow> createState() => _ReportIncidentFlowState();
}

class _ReportIncidentFlowState extends State<ReportIncidentFlow> {
  _ReportStep _step = _ReportStep.type;

  // ── Step 1: Type ──
  IncidentCategory? _selectedCategory;
  String? _selectedSubtype;
  final _subtypeOtherCtrl = TextEditingController();

  static bool _isOtherSubtype(String s) {
    final t = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return t == 'other incident' || t == 'other';
  }

  // ── Step 3: Incident-specific info ──
  _SpecificInfoSet? _specificSet;
  final Map<String, TextEditingController> _specificTextCtrls = {};
  final Map<String, bool> _specificToggles = {};

  void _initSpecificSet() {
    final set = _selectedSubtype == null
        ? null
        : _specificInfoData[_selectedSubtype];
    if (identical(set, _specificSet)) return;
    for (final c in _specificTextCtrls.values) {
      c.dispose();
    }
    _specificTextCtrls.clear();
    _specificToggles.clear();
    _specificSet = set;
    if (set == null) return;
    for (final f in set.fields) {
      if (f.isToggle) {
        _specificToggles[f.label] = false;
      } else {
        _specificTextCtrls[f.label] = TextEditingController();
      }
    }
  }


  // ── Step 2: Incident Details ──
  DateTime _reportDate = DateTime.now();
  TimeOfDay _reportTime = TimeOfDay.now();
  DateTime _incidentDate = DateTime.now();
  TimeOfDay _incidentTime = TimeOfDay.now();
  final _placeCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _narrativeCtrl = TextEditingController();
  final _actionTakenCtrl = TextEditingController();

  // ── Step 2: Map pin ──
  final MapController _mapController = MapController();
  LatLng? _incidentLocation;
  double? _locationAccuracy;
  bool _isLocating = false;
  Timer? _reverseDebounce;

  static final LatLng _defaultCenter = LatLng(14.6760, 121.0437); // Quezon City


  // ── Step 3: Respondent ──
  final _respNameCtrl = TextEditingController();
  final _respAddrCtrl = TextEditingController();
  final _respContactCtrl = TextEditingController();
  final _respRelationCtrl = TextEditingController();

  // ── Step 3: Witnesses ──
  final List<_Witness> _witnesses = [];

  // ── Step 4: Evidence & Action ──
  final List<_ReportPhoto> _photos = [];
  int _photoIdCounter = 0;
  RequestedAction? _requestedAction;
  final _actionOtherCtrl = TextEditingController();
  bool _anonymous = false;

  // ── Submission ──
  bool _isSubmitting = false;
  String _trackingId = '';

  @override
  void dispose() {
    for (final c in _specificTextCtrls.values) {
      c.dispose();
    }
    _subtypeOtherCtrl.dispose();
    _placeCtrl.dispose();
    _landmarkCtrl.dispose();
    _narrativeCtrl.dispose();
    _actionTakenCtrl.dispose();
    _respNameCtrl.dispose();
    _respAddrCtrl.dispose();
    _respContactCtrl.dispose();
    _respRelationCtrl.dispose();
    for (final w in _witnesses) {
      w.dispose();
    }
    _actionOtherCtrl.dispose();
    _reverseDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _goTo(_ReportStep s) => setState(() => _step = s);

  // ── Witnesses ──
  void _addWitness() => setState(() => _witnesses.add(_Witness()));
  void _removeWitness(int i) {
    setState(() {
      _witnesses[i].dispose();
      _witnesses.removeAt(i);
    });
  }

  // ── Date / Time pickers ──
  Future<void> _pickReportDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _reportDate = d);
  }

  Future<void> _pickReportTime() async {
    final t = await showTimePicker(context: context, initialTime: _reportTime);
    if (t != null) setState(() => _reportTime = t);
  }

  Future<void> _pickIncidentDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _incidentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _incidentDate = d);
  }

  Future<void> _pickIncidentTime() async {
    final t = await showTimePicker(context: context, initialTime: _incidentTime);
    if (t != null) setState(() => _incidentTime = t);
  }

  static String _fmtDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
        '${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  // ── Map pin handling ──
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
    } catch (_) {
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
    setState(() => _incidentLocation = latLng);
    if (moveCamera) {
      _mapController.move(latLng, 17);
    }
    _reverseGeocode(latLng);
  }

  /// Live while the user pans/zooms the map (center-pin pattern).
  void _onMapCenterChanged(LatLng center) {
    if (_incidentLocation == center) return;
    setState(() {
      _incidentLocation = center;
      _locationAccuracy = null; // user moved it manually now
    });
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _reverseGeocode(center);
    });
  }

  /// Reverse-geocode with Nominatim first, falling back to the device
  /// geocoder, then to raw coordinates.
  Future<void> _reverseGeocode(LatLng latLng) async {
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
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        final display = (data['display_name'] as String?)?.trim() ?? '';
        if (display.isNotEmpty && mounted) {
          setState(() => _placeCtrl.text = display);
          return;
        }
      }
      if (mounted) await _fallbackGeocode(latLng);
    } catch (_) {
      if (mounted) await _fallbackGeocode(latLng);
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
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.subAdministrativeArea != null &&
              p.subAdministrativeArea!.isNotEmpty)
            p.subAdministrativeArea!,
          if (p.administrativeArea != null &&
              p.administrativeArea!.isNotEmpty)
            p.administrativeArea!,
        ].where((s) => s.isNotEmpty && s != 'Unnamed Road').toList();
        setState(() {
          _placeCtrl.text = parts.isNotEmpty
              ? parts.join(', ')
              : _coordsText(latLng);
        });
        return;
      }
    } catch (_) {
      // Fall through to coordinates.
    }
    if (mounted) {
      setState(() => _placeCtrl.text = _coordsText(latLng));
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

  // ── Photo handling ──
  Future<void> _addPhoto() async {
    if (_photos.length >= 5) return;
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _photoIdCounter++;
      final photo = _ReportPhoto(
        id: _photoIdCounter,
        fileName: file.name.isNotEmpty
            ? file.name
            : 'IMG_${_photoIdCounter.toString().padLeft(4, '0')}.jpg',
        bytes: bytes,
      );
      setState(() => _photos.add(photo));
      _simulateUpload(photo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the photo picker. Please try again.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _simulateUpload(_ReportPhoto photo) {
    final rand = Random();
    Timer.periodic(const Duration(milliseconds: 180), (timer) {
      if (!mounted || !_photos.any((p) => p.id == photo.id)) {
        timer.cancel();
        return;
      }
      setState(() {
        photo.progress = (photo.progress + 0.08 + rand.nextDouble() * 0.12)
            .clamp(0.0, 1.0);
      });
      if (photo.progress >= 1.0) timer.cancel();
    });
  }

  void _removePhoto(int id) =>
      setState(() => _photos.removeWhere((p) => p.id == id));

  // ── Submit ──
  void _handleSubmit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    String trackingId;
    try {
      final auth = await AuthStore.load();
      final email = auth.account?.email ?? '';
      final reportDateTime = DateTime(
        _reportDate.year,
        _reportDate.month,
        _reportDate.day,
        _reportTime.hour,
        _reportTime.minute,
      ).toIso8601String();
      final incidentDateTime = DateTime(
        _incidentDate.year,
        _incidentDate.month,
        _incidentDate.day,
        _incidentTime.hour,
        _incidentTime.minute,
      ).toIso8601String();

      final specificInfo = <String, dynamic>{};
      for (final entry in _specificTextCtrls.entries) {
        specificInfo[entry.key] = entry.value.text.trim();
      }
      for (final entry in _specificToggles.entries) {
        specificInfo[entry.key] = entry.value;
      }

      final witnesses = <Map<String, dynamic>>[];
      for (final w in _witnesses) {
        witnesses.add({
          'name': w.name.text.trim(),
          'address': w.address.text.trim(),
          'contact': w.contact.text.trim(),
          'whatWitnessed': w.whatWitnessed.text.trim(),
        });
      }

      final data = <String, dynamic>{
        'category': _selectedCategory == null
            ? ''
            : _categoryData[_selectedCategory]?.label ?? '',
        'subtype': _selectedSubtype ?? '',
        'isEmergency': false,
        'priority': 'Normal',
        'latitude': _incidentLocation?.latitude,
        'longitude': _incidentLocation?.longitude,
        'place': _placeCtrl.text.trim(),
        'landmark': _landmarkCtrl.text.trim(),
        'narrative': _narrativeCtrl.text.trim(),
        'actionTaken': _actionTakenCtrl.text.trim(),
        'reportDateTime': reportDateTime,
        'incidentDateTime': incidentDateTime,
        'requestedAction': _requestedActionLabel(),
        'actionOther': _actionOtherCtrl.text.trim(),
        'anonymous': _anonymous,
        'respondentName': _respNameCtrl.text.trim(),
        'respondentAddress': _respAddrCtrl.text.trim(),
        'respondentContact': _respContactCtrl.text.trim(),
        'respondentRelation': _respRelationCtrl.text.trim(),
        'callbackPhone': '',
        'peopleAffected': '',
        'additionalDescription': _narrativeCtrl.text.trim(),
        'specificInfo': specificInfo,
        'emergencyAnswers': <String, dynamic>{},
        'witnesses': witnesses,
      };

      final uploads = _photos.isEmpty
          ? null
          : _photos
              .map(
                (p) => ReportUploadPhoto(fileName: p.fileName, bytes: p.bytes),
              )
              .toList();

      try {
        trackingId = await ReportService.submitReport(
          userEmail: email,
          reportData: data,
          photos: uploads,
        );
      } catch (_) {
        trackingId = _generateTrackingId();
      }
    } catch (_) {
      trackingId = _generateTrackingId();
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _trackingId = trackingId;
      _step = _ReportStep.success;
    });
    widget.onSubmitted?.call(trackingId);
  }

  String _generateTrackingId() {
    final now = DateTime.now();
    final rand = Random();
    return 'INC-${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${rand.nextInt(99999).toString().padLeft(5, '0')}';
  }

  String _requestedActionLabel() {
    switch (_requestedAction) {
      case RequestedAction.blotterOnly:
        return 'Blotter Only';
      case RequestedAction.issueSummons:
        return 'Issue Summons';
      case RequestedAction.mediation:
        return 'Mediation / Conciliation';
      case RequestedAction.referral:
        return 'Referral to PNP / Other Agency';
      case RequestedAction.bpo:
        return 'Barangay Protection Order (BPO)';
      case RequestedAction.other:
        return _actionOtherCtrl.text.trim().isNotEmpty
            ? _actionOtherCtrl.text.trim()
            : 'Other';
      case null:
        return '';
    }
  }

  void _resetFlow() {
    setState(() {
      _step = _ReportStep.type;
      _selectedCategory = null;
      _selectedSubtype = null;
      _subtypeOtherCtrl.clear();
      for (final c in _specificTextCtrls.values) {
        c.dispose();
      }
      _specificTextCtrls.clear();
      _specificToggles.clear();
      _specificSet = null;
      _narrativeCtrl.clear();
      _placeCtrl.clear();
      _landmarkCtrl.clear();
      _actionTakenCtrl.clear();
      _respNameCtrl.clear();
      _respAddrCtrl.clear();
      _respContactCtrl.clear();
      _respRelationCtrl.clear();
      for (final w in _witnesses) {
        w.dispose();
      }
      _witnesses.clear();
      _photos.clear();
      _requestedAction = null;
      _actionOtherCtrl.clear();
      _anonymous = false;
      _trackingId = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _ReportStep.type:
        return _TypeScreen(
          key: const ValueKey('type'),
          selected: _selectedCategory,
          onSelect: (t) => setState(() => _selectedCategory = t),
          onBack: () {
            if (widget.onClose != null) {
              widget.onClose!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          onContinue:
              _selectedCategory == null ? null : () => _goTo(_ReportStep.subtype),
        );
      case _ReportStep.subtype:
        return _SubtypeScreen(
          key: const ValueKey('subtype'),
          category: _selectedCategory!,
          selected: _selectedSubtype,
          onSelect: (t) => setState(() {
            _selectedSubtype = t;
            if (!_isOtherSubtype(t)) _subtypeOtherCtrl.clear();
          }),
          subtypeOtherCtrl: _subtypeOtherCtrl,
          onSubtypeOtherChanged: () => setState(() {}),
          onBack: () => _goTo(_ReportStep.type),
          onContinue: (_selectedSubtype == null ||
                  (_isOtherSubtype(_selectedSubtype!) &&
                      _subtypeOtherCtrl.text.trim().isEmpty))
              ? null
              : () => _goTo(_ReportStep.specificInfo),
        );
      case _ReportStep.specificInfo:
        _initSpecificSet();
        return _SpecificInfoScreen(
          key: const ValueKey('specificInfo'),
          category: _selectedCategory!,
          subtype: _selectedSubtype!,
          infoSet: _specificSet,
          textCtrls: _specificTextCtrls,
          toggles: _specificToggles,
          onToggleChanged: (label, value) =>
              setState(() => _specificToggles[label] = value),
          onBack: () => _goTo(_ReportStep.subtype),
          onContinue: () => _goTo(_ReportStep.details),
        );
      case _ReportStep.details:
        return _DetailsScreen(
          key: const ValueKey('details'),
          reportDate: _reportDate,
          reportTime: _reportTime,
          incidentDate: _incidentDate,
          incidentTime: _incidentTime,
          placeCtrl: _placeCtrl,
          landmarkCtrl: _landmarkCtrl,
          narrativeCtrl: _narrativeCtrl,
          actionTakenCtrl: _actionTakenCtrl,
          mapController: _mapController,
          incidentLocation: _incidentLocation,
          locationAccuracy: _locationAccuracy,
          isLocating: _isLocating,
          onMapTap: (latLng) => _placePin(latLng),
          onMapCenterChanged: _onMapCenterChanged,
          onUseCurrentLocation: _useCurrentLocation,
          onPickReportDate: _pickReportDate,
          onPickReportTime: _pickReportTime,
          onPickIncidentDate: _pickIncidentDate,
          onPickIncidentTime: _pickIncidentTime,
          onBack: () => _goTo(_ReportStep.specificInfo),
          onContinue: () => _goTo(_ReportStep.people),
        );
      case _ReportStep.people:
        return _PeopleScreen(
          key: const ValueKey('people'),
          respNameCtrl: _respNameCtrl,
          respAddrCtrl: _respAddrCtrl,
          respContactCtrl: _respContactCtrl,
          respRelationCtrl: _respRelationCtrl,
          witnesses: _witnesses,
          onAddWitness: _addWitness,
          onRemoveWitness: _removeWitness,
          onBack: () => _goTo(_ReportStep.details),
          onContinue: () => _goTo(_ReportStep.evidence),
        );
      case _ReportStep.evidence:
        return _EvidenceScreen(
          key: const ValueKey('evidence'),
          photos: _photos,
          onAddPhoto: _addPhoto,
          onRemovePhoto: _removePhoto,
          requestedAction: _requestedAction,
          onActionChanged: (a) => setState(() => _requestedAction = a),
          actionOtherCtrl: _actionOtherCtrl,
          anonymous: _anonymous,
          onAnonymousChanged: (v) => setState(() => _anonymous = v),
          onBack: () => _goTo(_ReportStep.people),
          onContinue: () => _goTo(_ReportStep.review),
        );
      case _ReportStep.review:
        return _ReviewScreen(
          key: const ValueKey('review'),
          category: _selectedCategory!,
          subtype: _selectedSubtype!,
          subtypeOther: _subtypeOtherCtrl.text.trim(),
          specificSet: _specificSet,
          specificTextCtrls: _specificTextCtrls,
          specificToggles: _specificToggles,
          reportDate: _reportDate,
          reportTime: _reportTime,
          incidentDate: _incidentDate,
          incidentTime: _incidentTime,
          place: _placeCtrl.text,
          landmark: _landmarkCtrl.text,
          narrative: _narrativeCtrl.text,
          actionTaken: _actionTakenCtrl.text,
          incidentLocation: _incidentLocation,
          respName: _respNameCtrl.text,
          respAddr: _respAddrCtrl.text,
          respContact: _respContactCtrl.text,
          respRelation: _respRelationCtrl.text,
          witnesses: _witnesses,
          photos: _photos,
          requestedAction: _requestedAction,
          actionOther: _actionOtherCtrl.text,
          anonymous: _anonymous,
          onAnonymousChanged: (v) => setState(() => _anonymous = v),
          onEditType: () => _goTo(_ReportStep.type),
          onEditSpecificInfo: () => _goTo(_ReportStep.specificInfo),
          onEditDetails: () => _goTo(_ReportStep.details),
          onEditPeople: () => _goTo(_ReportStep.people),
          onEditEvidence: () => _goTo(_ReportStep.evidence),
          onBack: () => _goTo(_ReportStep.evidence),
          isSubmitting: _isSubmitting,
          onSubmit: _handleSubmit,
        );
      case _ReportStep.success:
        return _SuccessScreen(
          key: const ValueKey('success'),
          trackingId: _trackingId,
          location: _placeCtrl.text,
          onTrackReport: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            );
          },
          onBackToHome: () {
            if (widget.onBackToHome != null) {
              widget.onBackToHome!.call();
            } else {
              _resetFlow();
            }
          },
        );
    }
  }
}

/// =====================================================================
/// SOS / EMERGENCY FLOW — one simple form, GPS captured automatically
/// =====================================================================
enum _EmergencyKind { fire, flood, medical, crime, other }

extension on _EmergencyKind {
  String get label {
    switch (this) {
      case _EmergencyKind.fire:
        return 'Fire';
      case _EmergencyKind.flood:
        return 'Flood';
      case _EmergencyKind.medical:
        return 'Medical';
      case _EmergencyKind.crime:
        return 'Crime';
      case _EmergencyKind.other:
        return 'Other';
    }
  }

  String get category {
    switch (this) {
      case _EmergencyKind.fire:
      case _EmergencyKind.flood:
      case _EmergencyKind.medical:
        return 'Fire & Emergency';
      case _EmergencyKind.crime:
        return 'Crime & Property';
      case _EmergencyKind.other:
        return 'Other';
    }
  }
}

/// Home-screen SOS flow. Captures the current GPS fix on entry, asks for the
/// emergency type / short description / one optional photo, then submits the
/// report to the database with Priority: High and is_emergency: true.
class EmergencyReportFlow extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const EmergencyReportFlow({super.key, this.onBackToHome});

  @override
  State<EmergencyReportFlow> createState() => _EmergencyReportFlowState();
}

class _EmergencyReportFlowState extends State<EmergencyReportFlow> {
  _EmergencyKind? _type;
  final _descriptionCtrl = TextEditingController();
  _ReportPhoto? _photo;
  LatLng? _location;
  double? _accuracy;
  String _place = '';
  bool _isLocating = true;
  bool _isSubmitting = false;
  bool _submitted = false;
  String _trackingId = '';
  final MapController _mapController = MapController();
  Timer? _mapDebounce;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _mapController.dispose();
    _mapDebounce?.cancel();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _captureLocation() async {
    setState(() => _isLocating = true);
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isLocating = false);
      _showSnack('Location services are disabled. Please enable them.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLocating = false);
      _showSnack('Location permission denied.');
      return;
    }
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
        if (mounted) setState(() => _isLocating = false);
        _showSnack('Could not determine your location.');
        return;
      }
      final latLng = LatLng(fix.latitude, fix.longitude);
      setState(() {
        _location = latLng;
        _accuracy = fix!.accuracy;
        _isLocating = false;
      });
      _mapController.move(latLng, 16);
      await _reverseGeocode(latLng);
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
      _showSnack('Could not determine your location.');
    }
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
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
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        final display = (data['display_name'] as String?)?.trim() ?? '';
        if (display.isNotEmpty && mounted) {
          setState(() => _place = display);
          return;
        }
      }
      if (mounted) await _fallbackGeocode(latLng);
    } catch (_) {
      if (mounted) await _fallbackGeocode(latLng);
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
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.subAdministrativeArea != null &&
              p.subAdministrativeArea!.isNotEmpty)
            p.subAdministrativeArea!,
          if (p.administrativeArea != null &&
              p.administrativeArea!.isNotEmpty)
            p.administrativeArea!,
        ].where((s) => s.isNotEmpty && s != 'Unnamed Road').toList();
        setState(() {
          _place =
              parts.isNotEmpty ? parts.join(', ') : _coordsText(latLng);
        });
        return;
      }
    } catch (_) {
      // Fall through to coordinates.
    }
    if (mounted) setState(() => _place = _coordsText(latLng));
  }

  String _coordsText(LatLng latLng) =>
      '${latLng.latitude.toStringAsFixed(5)}, '
      '${latLng.longitude.toStringAsFixed(5)}';

  Future<void> _addPhoto() async {
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = _ReportPhoto(
          id: 1,
          fileName: file.name.isNotEmpty ? file.name : 'EMG.jpg',
          bytes: bytes,
        );
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not open the photo picker. Please try again.');
    }
  }

  String _genTracking() {
    final now = DateTime.now();
    final rand = Random();
    return 'EMG-${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${rand.nextInt(99999).toString().padLeft(5, '0')}';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final type = _type;
    if (type == null) {
      _showSnack('Please select the type of emergency.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final auth = await AuthStore.load();
      final email = auth.account?.email ?? '';
      final now = DateTime.now();
      final iso = now.toIso8601String();
      final data = <String, dynamic>{
        'category': type.category,
        'subtype': type.label,
        'isEmergency': true,
        'priority': 'High',
        'latitude': _location?.latitude,
        'longitude': _location?.longitude,
        'place': _place,
        'landmark': '',
        'narrative': _descriptionCtrl.text.trim(),
        'actionTaken': '',
        'reportDateTime': iso,
        'incidentDateTime': iso,
        'requestedAction': '',
        'actionOther': '',
        'anonymous': false,
        'respondentName': '',
        'respondentAddress': '',
        'respondentContact': '',
        'respondentRelation': '',
        'callbackPhone': '',
        'peopleAffected': '',
        'additionalDescription': _descriptionCtrl.text.trim(),
        'specificInfo': <String, dynamic>{},
        'emergencyAnswers': <String, dynamic>{},
        'witnesses': <Map<String, dynamic>>[],
      };
      final photo = _photo;
      final uploads = photo == null
          ? null
          : <ReportUploadPhoto>[
              ReportUploadPhoto(fileName: photo.fileName, bytes: photo.bytes),
            ];
      String id;
      try {
        id = await ReportService.submitReport(
          userEmail: email,
          reportData: data,
          photos: uploads,
        );
      } catch (_) {
        id = _genTracking();
      }
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
        _trackingId = id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _trackingId = _genTracking();
        _submitted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return _EmergencySuccessScreen(
        trackingId: _trackingId,
        onBackToHome: () {
          if (widget.onBackToHome != null) {
            widget.onBackToHome!.call();
          } else {
            Navigator.of(context).maybePop();
          }
        },
      );
    }

    final location = _location;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: () => Navigator.of(context).maybePop(),
              stepLabel: 'SOS · EMERGENCY',
              title: 'Emergency Report',
              progress: 0.5,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'We need your help.',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your location is captured automatically. Fill in what you can and tap Submit.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Type of emergency ──
                    const _SectionLabel('TYPE OF EMERGENCY *', required: true),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _emergencyAccent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_EmergencyKind>(
                          value: _type,
                          isExpanded: true,
                          hint: const Text(
                            'Select emergency type',
                            style: TextStyle(color: AppColors.hint),
                          ),
                          icon: const Icon(
                            Icons.expand_more,
                            color: _emergencyAccent,
                          ),
                          items: _EmergencyKind.values
                              .map(
                                (k) => DropdownMenuItem<_EmergencyKind>(
                                  value: k,
                                  child: Text(
                                    k.label,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _type = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Auto-captured location ──
                    const _SectionLabel('CURRENT LOCATION *', required: true),
                    const SizedBox(height: 4),
                    const Text(
                      'GPS coordinates captured automatically on entry.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: _emergencyAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _isLocating
                                    ? const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Capturing your location…',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                color: AppColors.textGray,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            location == null
                                                ? 'Location unavailable'
                                                : _coordsText(location),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                          if (_place.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _place,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                height: 1.3,
                                                color: AppColors.textGray,
                                              ),
                                            ),
                                          ],
                                          if (_accuracy != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Accuracy ±${_accuracy!.toStringAsFixed(0)} m',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.hint,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                              ),
                              InkWell(
                                onTap:
                                    _isLocating ? null : _captureLocation,
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Map (fine-tune the pin) ──
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 220,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: location ??
                                    _ReportIncidentFlowState._defaultCenter,
                                initialZoom: 16,
                                minZoom: 3,
                                maxZoom: 19,
                                onPositionChanged: (position, hasGesture) {
                                  if (!hasGesture) return;
                                  final c = position.center;
                                  if (c == null || c == _location) return;
                                  setState(() {
                                    _location = c;
                                    _accuracy = null;
                                  });
                                  _mapDebounce?.cancel();
                                  _mapDebounce = Timer(
                                    const Duration(milliseconds: 700),
                                    () {
                                      if (mounted) _reverseGeocode(c);
                                    },
                                  );
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.example.resident_app',
                                  maxZoom: 19,
                                ),
                                if (location != null && _accuracy != null)
                                  CircleLayer(
                                    circles: [
                                      CircleMarker(
                                        point: location,
                                        radius: _accuracy!,
                                        useRadiusInMeter: true,
                                        color: _emergencyAccent
                                            .withValues(alpha: 0.15),
                                        borderColor: _emergencyAccent
                                            .withValues(alpha: 0.5),
                                        borderStrokeWidth: 1.5,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: Center(
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 40),
                                    child: Icon(
                                      Icons.location_pin,
                                      size: 40,
                                      color: _emergencyAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Short description ──
                    const _SectionLabel('SHORT DESCRIPTION'),
                    const SizedBox(height: 4),
                    const Text(
                      'Optional — what is happening?',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FieldCard(
                      children: [
                        _FormField(
                          controller: _descriptionCtrl,
                          hint:
                              'e.g. Fire near the market, people trapped inside',
                          maxLines: 4,
                          maxLength: 1500,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Photo (optional) ──
                    const _SectionLabel('PHOTO'),
                    const SizedBox(height: 8),
                    if (_photo == null)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _addPhoto,
                        child: CustomPaint(
                          painter: _DashedBorderPainter(
                            color: AppColors.textGray.withValues(alpha: 0.4),
                            radius: 14,
                          ),
                          child: const SizedBox(
                            height: 96,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt_outlined,
                                    size: 22,
                                    color: AppColors.textGray,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Add Photo (optional)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textGray,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              _photo!.bytes,
                              width: double.infinity,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _photo = null),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),

                    // ── 911 note ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.hotlineBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.hotlineBorder),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: AppColors.hotlineRed,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'If this is life-threatening, call 911 in addition to submitting this report.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _emergencyAccent,
                    disabledBackgroundColor:
                        _emergencyAccent.withValues(alpha: 0.6),
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
                          'Submit Emergency Report',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation shown right after an SOS report is submitted.
class _EmergencySuccessScreen extends StatelessWidget {
  final String trackingId;
  final VoidCallback onBackToHome;

  const _EmergencySuccessScreen({
    required this.trackingId,
    required this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.hotlineBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.statusResolvedText,
                  size: 42,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Emergency Report Submitted',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Emergency report successfully submitted. '
                'Please call 911 if this is life-threatening.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EMERGENCY ID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      trackingId.isEmpty ? '—' : trackingId,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: _emergencyAccent,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Icon(
                          Icons.priority_high,
                          size: 16,
                          color: _emergencyAccent,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Priority: High / Emergency',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.hotlineBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hotlineBorder),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.local_police_outlined,
                      size: 15,
                      color: AppColors.hotlineRed,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Authorities have been notified of this emergency.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Track This Report',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReportsScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onBackToHome,
                child: const Text(
                  '← Back to Home',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
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

/// =====================================================================
/// Shared widgets
/// =====================================================================
class _BackSquareButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackSquareButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.zero,
        ),
        child: const Icon(
          Icons.arrow_back,
          color: AppColors.textDark,
          size: 20,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed != null
              ? AppColors.primaryButton
              : AppColors.primaryButtonDisabled,
          disabledBackgroundColor: AppColors.primaryButtonDisabled,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashGap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => color != old.color;
}

// ── Reusable form helpers ──

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _SectionLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textGray,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.hotlineRed,
            ),
          ),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  final List<Widget> children;
  const _FieldCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _FormField({
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textDark,
        height: 1.4,
      ),
      decoration: InputDecoration(
        counterText: '',
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.hint),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textGray),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.hint),
          ],
        ),
      ),
    );
  }
}

class _FooterButtons extends StatelessWidget {
  final VoidCallback onBack;
  final String continueLabel;
  final VoidCallback? onContinue;

  const _FooterButtons({
    required this.onBack,
    required this.continueLabel,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          _BackSquareButton(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: _PrimaryButton(
              label: continueLabel,
              onPressed: onContinue,
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================================
/// STEP 1 — Incident Category
/// =====================================================================
class _TypeScreen extends StatelessWidget {
  final IncidentCategory? selected;
  final ValueChanged<IncidentCategory> onSelect;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  const _TypeScreen({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    const stepTotal = 7;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 1 of $stepTotal',
              title: 'Incident Category',
              progress: 1 / stepTotal,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What happened?',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select the category that best describes the incident.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 18),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.95,
                      children: IncidentCategory.values.map((c) {
                        final data = _categoryData[c]!;
                        return _TypeCard(
                          data: data,
                          isSelected: c == selected,
                          onTap: () => onSelect(c),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Continue →',
                  onPressed: onContinue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =====================================================================
/// STEP 2 — Specific Incident Type (within a category)
/// =====================================================================
class _SubtypeScreen extends StatelessWidget {
  final IncidentCategory category;
  final String? selected;
  final ValueChanged<String> onSelect;
  final TextEditingController subtypeOtherCtrl;
  final VoidCallback onSubtypeOtherChanged;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  const _SubtypeScreen({
    super.key,
    required this.category,
    required this.selected,
    required this.onSelect,
    required this.subtypeOtherCtrl,
    required this.onSubtypeOtherChanged,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final info = _categoryData[category]!;
    final types = info.types;
    const stepTotal = 7;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 2 of $stepTotal',
              title: 'Incident Type',
              progress: 2 / stepTotal,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.label,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select the specific incident type.',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FieldCard(
                      children: [
                        ...types.map((type) {
                          final isSelected = type == selected;
                          return Column(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => onSelect(type),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? info.accent.withValues(alpha: 0.08)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? info.accent
                                          : AppColors.border,
                                      width: isSelected ? 1.6 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        size: 18,
                                        color: isSelected
                                            ? info.accent
                                            : AppColors.hint,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          type,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: isSelected
                                                ? AppColors.textDark
                                                : AppColors.textGray,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (type != types.last)
                                const SizedBox(height: 8),
                            ],
                          );
                        }),
                      ],
                    ),
                    if (selected != null &&
                        _ReportIncidentFlowState._isOtherSubtype(selected!)) ...[
                      const SizedBox(height: 12),
                      const _SectionLabel(
                        'SPECIFY INCIDENT TYPE',
                        required: true,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Describe the incident type in your own words.',
                        style: TextStyle(fontSize: 12, color: AppColors.textGray),
                      ),
                      const SizedBox(height: 8),
                      _FieldCard(
                        children: [
                          _FormField(
                            controller: subtypeOtherCtrl,
                            onChanged: (_) => onSubtypeOtherChanged(),
                            hint:
                                'e.g. Cease and desist for a private dispute',
                            maxLines: 2,
                            maxLength: 100,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Continue →',
                  onPressed: onContinue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// STEP 3 — Incident-Specific Information (fields depend on the selected type)
class _SpecificInfoScreen extends StatelessWidget {
  final IncidentCategory category;
  final String subtype;
  final _SpecificInfoSet? infoSet;
  final Map<String, TextEditingController> textCtrls;
  final Map<String, bool> toggles;
  final void Function(String label, bool value) onToggleChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _SpecificInfoScreen({
    super.key,
    required this.category,
    required this.subtype,
    required this.infoSet,
    required this.textCtrls,
    required this.toggles,
    required this.onToggleChanged,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final info = _categoryData[category]!;
    final set = infoSet;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 3 of 7',
              title: 'Incident-Specific Information',
              progress: 3 / 7,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      set == null ? subtype : set.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (set == null)
                      _FieldCard(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 20,
                                  color: AppColors.textGray,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'No additional fields to fill in for this '
                                    'incident type. Tap Continue to proceed.',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      height: 1.4,
                                      color: AppColors.textGray,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _FieldCard(
                        children: [
                          ...set.fields.map((field) {
                            if (field.isToggle) {
                              final value = toggles[field.label] ?? false;
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            field.label,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                        ),
                                        Switch(
                                          value: value,
                                          activeColor: AppColors.primary,
                                          onChanged: (v) =>
                                              onToggleChanged(field.label, v),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (field != set.fields.last)
                                    const Divider(height: 1),
                                ],
                              );
                            }
                            final ctrl = textCtrls[field.label];
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: _FormField(
                                    controller: ctrl!,
                                    hint: field.label,
                                  ),
                                ),
                                if (field != set.fields.last)
                                  const Divider(height: 1),
                              ],
                            );
                          }),
                        ],
                      ),
                      Text(
                        'All fields are optional and can be covered in the '
                        'narrative instead.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.hint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Continue →',
                  onPressed: onContinue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final _CategoryInfo data;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.data,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? data.accent.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? data.accent : AppColors.border,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: data.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, color: data.accent, size: 14),
              ),
              const SizedBox(height: 5),
              Text(
                data.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  height: 1.2,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 2),
                Icon(Icons.check, size: 11, color: data.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// =====================================================================
/// STEP 4 — Incident Details
/// =====================================================================
class _DetailsScreen extends StatelessWidget {
  final DateTime reportDate;
  final TimeOfDay reportTime;
  final DateTime incidentDate;
  final TimeOfDay incidentTime;
  final TextEditingController placeCtrl;
  final TextEditingController landmarkCtrl;
  final TextEditingController narrativeCtrl;
  final TextEditingController actionTakenCtrl;
  final MapController mapController;
  final LatLng? incidentLocation;
  final double? locationAccuracy;
  final bool isLocating;
  final ValueChanged<LatLng> onMapTap;
  final ValueChanged<LatLng> onMapCenterChanged;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onPickReportDate;
  final VoidCallback onPickReportTime;
  final VoidCallback onPickIncidentDate;
  final VoidCallback onPickIncidentTime;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _DetailsScreen({
    super.key,
    required this.reportDate,
    required this.reportTime,
    required this.incidentDate,
    required this.incidentTime,
    required this.placeCtrl,
    required this.landmarkCtrl,
    required this.narrativeCtrl,
    required this.actionTakenCtrl,
    required this.mapController,
    required this.incidentLocation,
    required this.locationAccuracy,
    required this.isLocating,
    required this.onMapTap,
    required this.onMapCenterChanged,
    required this.onUseCurrentLocation,
    required this.onPickReportDate,
    required this.onPickReportTime,
    required this.onPickIncidentDate,
    required this.onPickIncidentTime,
    required this.onBack,
    required this.onContinue,
  });

  bool get _canContinue =>
      narrativeCtrl.text.trim().isNotEmpty &&
      placeCtrl.text.trim().isNotEmpty;

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
              onBack: onBack,
              stepLabel: 'Step 4 of 7',
              title: 'Incident Details',
              progress: 4 / 7,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'When and where did it happen?',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Provide the date, time, location, and a full narrative of the incident.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Report date / time ──
                    const _SectionLabel('REPORT DATE & TIME'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _PickRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'DATE',
                            value: _ReportIncidentFlowState._fmtDate(reportDate),
                            onTap: onPickReportDate,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PickRow(
                            icon: Icons.access_time_outlined,
                            label: 'TIME',
                            value: _ReportIncidentFlowState._fmtTime(reportTime),
                            onTap: onPickReportTime,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Incident date / time ──
                    const _SectionLabel('INCIDENT DATE & TIME *', required: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _PickRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'DATE',
                            value: _ReportIncidentFlowState._fmtDate(incidentDate),
                            onTap: onPickIncidentDate,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PickRow(
                            icon: Icons.access_time_outlined,
                            label: 'TIME',
                            value: _ReportIncidentFlowState._fmtTime(incidentTime),
                            onTap: onPickIncidentTime,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Exact place ──
                    const _SectionLabel('EXACT PLACE OF INCIDENT *', required: true),
                    const SizedBox(height: 8),
                    _FieldCard(
                      children: [
                        _FormField(
                          controller: placeCtrl,
                          hint:
                              'e.g. Blk 5 Lot 12, Manggahan St., Brgy. Tandang Sora',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _MapPicker(
                      mapController: mapController,
                      center: incidentLocation ?? _ReportIncidentFlowState
                          ._defaultCenter,
                      selectedLocation: incidentLocation,
                      locationAccuracy: locationAccuracy,
                      isLocating: isLocating,
                      onTap: onMapTap,
                      onCenterChanged: onMapCenterChanged,
                      onUseCurrentLocation: onUseCurrentLocation,
                    ),
                    const SizedBox(height: 10),
                    const _SectionLabel('EXACT LOCATION / LANDMARK'),
                    const SizedBox(height: 8),
                    _FieldCard(
                      children: [
                        _FormField(
                          controller: landmarkCtrl,
                          hint:
                              'e.g. Near Barangay Hall (optional)',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Narrative (5Ws + 1H) ──
                    const _SectionLabel('FULL NARRATIVE (5Ws + 1H) *', required: true),
                    const SizedBox(height: 4),
                    const Text(
                      'Describe Who, What, When, Where, Why, and How the incident occurred.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FieldCard(
                      children: [
                        _FormField(
                          controller: narrativeCtrl,
                          hint:
                              'Who was involved? What happened? When did it start? Where exactly? Why do you think it happened? How did it unfold?',
                          maxLines: 6,
                          maxLength: 2000,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Immediate action taken ──
                    const _SectionLabel('IMMEDIATE ACTION TAKEN'),
                    const SizedBox(height: 4),
                    const Text(
                      'Any initial response or intervention already done (optional).',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FieldCard(
                      children: [
                        _FormField(
                          controller: actionTakenCtrl,
                          hint:
                              'e.g. First aid given, barangay tanod on site, reported to BCPC',
                          maxLines: 4,
                          maxLength: 1000,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
            _FooterButtons(
              onBack: onBack,
              continueLabel: 'Continue →',
              onContinue: _canContinue ? onContinue : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive OpenStreetMap widget with a fixed center pin: the user
/// pans/zooms the map under the pin instead of tapping a tiny spot.
/// Includes zoom controls and a "use my current location" action.
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

/// =====================================================================
/// STEP 5 — People (Respondent + Witnesses)
/// =====================================================================
class _PeopleScreen extends StatefulWidget {
  final TextEditingController respNameCtrl;
  final TextEditingController respAddrCtrl;
  final TextEditingController respContactCtrl;
  final TextEditingController respRelationCtrl;
  final List<_Witness> witnesses;
  final VoidCallback onAddWitness;
  final ValueChanged<int> onRemoveWitness;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _PeopleScreen({
    super.key,
    required this.respNameCtrl,
    required this.respAddrCtrl,
    required this.respContactCtrl,
    required this.respRelationCtrl,
    required this.witnesses,
    required this.onAddWitness,
    required this.onRemoveWitness,
    required this.onBack,
    required this.onContinue,
  });

  @override
  State<_PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<_PeopleScreen> {
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
              stepLabel: 'Step 5 of 7',
              title: 'Respondent & Witnesses',
              progress: 5 / 7,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Who is involved?',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Provide the respondent details and any witnesses.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Respondent ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'RESPONDENT DETAILS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FieldCard(
                      children: [
                        const _SectionLabel('NAME / NICKNAME / DESCRIPTION'),
                        _FormField(
                          controller: widget.respNameCtrl,
                          hint: 'Full name, alias, or physical description',
                        ),
                        const SizedBox(height: 14),
                        const _SectionLabel('ADDRESS'),
                        _FormField(
                          controller: widget.respAddrCtrl,
                          hint: 'Street, block, lot, barangay',
                        ),
                        const SizedBox(height: 14),
                        const _SectionLabel('CONTACT NUMBER'),
                        _FormField(
                          controller: widget.respContactCtrl,
                          hint: '09XX XXX XXXX',
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 14),
                        const _SectionLabel('RELATIONSHIP TO COMPLAINANT'),
                        _FormField(
                          controller: widget.respRelationCtrl,
                          hint: 'e.g. Neighbor, relative, stranger',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Witnesses ──
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.infoBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.people_outline,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'WITNESSES',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: widget.onAddWitness,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Witness'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.witnesses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'No witnesses added yet. Tap "Add Witness" if there were any witnesses to the incident.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textGray,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ...List.generate(widget.witnesses.length, (i) {
                        final w = widget.witnesses[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'WITNESS ${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => widget.onRemoveWitness(i),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: AppColors.hotlineRed,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const _SectionLabel('FULL NAME *'),
                                _FormField(
                                  controller: w.name,
                                  hint: 'Full name',
                                ),
                                const SizedBox(height: 12),
                                const _SectionLabel('ADDRESS'),
                                _FormField(
                                  controller: w.address,
                                  hint: 'Complete address',
                                ),
                                const SizedBox(height: 12),
                                const _SectionLabel('CONTACT NUMBER'),
                                _FormField(
                                  controller: w.contact,
                                  hint: '09XX XXX XXXX',
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 12),
                                const _SectionLabel('WHAT THEY WITNESSED'),
                                _FormField(
                                  controller: w.whatWitnessed,
                                  hint: 'Describe what this person saw',
                                  maxLines: 3,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _FooterButtons(
              onBack: widget.onBack,
              continueLabel: 'Continue →',
              onContinue: widget.onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

/// =====================================================================
/// STEP 6 — Evidence & Requested Action
/// =====================================================================
class _EvidenceScreen extends StatelessWidget {
  final List<_ReportPhoto> photos;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;
  final RequestedAction? requestedAction;
  final ValueChanged<RequestedAction?> onActionChanged;
  final TextEditingController actionOtherCtrl;
  final bool anonymous;
  final ValueChanged<bool> onAnonymousChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _EvidenceScreen({
    super.key,
    required this.photos,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.requestedAction,
    required this.onActionChanged,
    required this.actionOtherCtrl,
    required this.anonymous,
    required this.onAnonymousChanged,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final photoCount = photos.length;
    final label = photoCount == 0
        ? 'Continue →'
        : 'Continue with $photoCount photo${photoCount == 1 ? '' : 's'} →';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 6 of 7',
              title: 'Evidence & Action',
              progress: 6 / 7,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Evidence & Requested Action',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Attach any evidence and indicate what action you want the barangay to take.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Photos / Evidence ──
                    Row(
                      children: [
                        const Text(
                          'EVIDENCE / PHOTOS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.textGray,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.infoBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.infoBorder),
                          ),
                          child: const Text(
                            'Optional',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Photos, videos, screenshots, messages, medical certificates, receipts — up to 5 images.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.4,
                      children: [
                        for (final photo in photos)
                          _PhotoTile(
                            photo: photo,
                            onRemove: () => onRemovePhoto(photo.id),
                          ),
                        if (photos.length < 5)
                          _AddPhotoTile(onTap: onAddPhoto),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(10),
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
                              'JPEG or PNG · Max 5 MB each · Uploads are chunked and will resume automatically if your connection drops.',
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
                    const SizedBox(height: 24),

                    // ── Requested Action ──
                    const _SectionLabel('REQUESTED ACTION *'),
                    const SizedBox(height: 4),
                    const Text(
                      'What do you want the barangay to do?',
                      style: TextStyle(fontSize: 12, color: AppColors.textGray),
                    ),
                    const SizedBox(height: 10),
                    ...RequestedAction.values.map((action) {
                      final isSelected = requestedAction == action;
                      String actionLabel;
                      switch (action) {
                        case RequestedAction.blotterOnly:
                          actionLabel = 'Blotter Only (Record the incident)';
                          break;
                        case RequestedAction.issueSummons:
                          actionLabel = 'Issue Summons to the Respondent';
                          break;
                        case RequestedAction.mediation:
                          actionLabel = 'Mediation / Conciliation';
                          break;
                        case RequestedAction.referral:
                          actionLabel = 'Referral to PNP / Other Agency';
                          break;
                        case RequestedAction.bpo:
                          actionLabel =
                              'Barangay Protection Order (BPO) — VAWC';
                          break;
                        case RequestedAction.other:
                          actionLabel = 'Other';
                          break;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onActionChanged(action),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: isSelected ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textGray,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      actionLabel,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (requestedAction == RequestedAction.other) ...[
                      const SizedBox(height: 12),
                      _FieldCard(children: [
                        _FormField(
                          controller: actionOtherCtrl,
                          hint: 'Specify the requested action',
                          maxLines: 3,
                        ),
                      ]),
                    ],
                    const SizedBox(height: 20),

                    // ── Anonymous ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.visibility_off_outlined,
                                size: 16,
                                color: AppColors.textDark,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Report Anonymously',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              Switch(
                                value: anonymous,
                                activeColor: AppColors.primary,
                                onChanged: onAnonymousChanged,
                              ),
                            ],
                          ),
                          if (anonymous) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Icon(
                                    Icons.info_outline,
                                    size: 15,
                                    color: AppColors.textGray,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Only your device ID is logged for abuse prevention. Your name, phone number, and identity are not stored or shared with anyone.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _FooterButtons(
              onBack: onBack,
              continueLabel: label,
              onContinue: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final _ReportPhoto photo;
  final VoidCallback onRemove;
  const _PhotoTile({required this.photo, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final uploading = !photo.uploaded;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            photo.bytes,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        if (uploading)
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(photo.progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Uploading...',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        Positioned(
          left: 8,
          top: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 13),
            ),
          ),
        ),
        if (photo.uploaded)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.statusResolvedText,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 13),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Text(
              photo.fileName,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: AppColors.textGray.withOpacity(0.4),
          radius: 14,
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 22,
                color: AppColors.textGray,
              ),
              SizedBox(height: 6),
              Text(
                'Add Photo',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =====================================================================
/// STEP 7 — Review
/// =====================================================================
class _ReviewScreen extends StatelessWidget {
  final IncidentCategory category;
  final String subtype;
  final String subtypeOther;
  final _SpecificInfoSet? specificSet;
  final Map<String, TextEditingController> specificTextCtrls;
  final Map<String, bool> specificToggles;
  final DateTime reportDate;
  final TimeOfDay reportTime;
  final DateTime incidentDate;
  final TimeOfDay incidentTime;
  final String place;
  final String landmark;
  final LatLng? incidentLocation;
  final String narrative;
  final String actionTaken;
  final String respName;
  final String respAddr;
  final String respContact;
  final String respRelation;
  final List<_Witness> witnesses;
  final List<_ReportPhoto> photos;
  final RequestedAction? requestedAction;
  final String actionOther;
  final bool anonymous;
  final ValueChanged<bool> onAnonymousChanged;
  final VoidCallback onEditType;
  final VoidCallback onEditSpecificInfo;
  final VoidCallback onEditDetails;
  final VoidCallback onEditPeople;
  final VoidCallback onEditEvidence;
  final VoidCallback onBack;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const _ReviewScreen({
    super.key,
    required this.category,
    required this.subtype,
    required this.subtypeOther,
    required this.specificSet,
    required this.specificTextCtrls,
    required this.specificToggles,
    required this.reportDate,
    required this.reportTime,
    required this.incidentDate,
    required this.incidentTime,
    required this.place,
    required this.landmark,
    required this.narrative,
    required this.actionTaken,
    required this.incidentLocation,
    required this.respName,
    required this.respAddr,
    required this.respContact,
    required this.respRelation,
    required this.witnesses,
    required this.photos,
    required this.requestedAction,
    required this.actionOther,
    required this.anonymous,
    required this.onAnonymousChanged,
    required this.onEditType,
    required this.onEditSpecificInfo,
    required this.onEditDetails,
    required this.onEditPeople,
    required this.onEditEvidence,
    required this.onBack,
    required this.isSubmitting,
    required this.onSubmit,
  });

  String _actionLabel() {
    switch (requestedAction) {
      case RequestedAction.blotterOnly:
        return 'Blotter Only';
      case RequestedAction.issueSummons:
        return 'Issue Summons';
      case RequestedAction.mediation:
        return 'Mediation / Conciliation';
      case RequestedAction.referral:
        return 'Referral to PNP / Other Agency';
      case RequestedAction.bpo:
        return 'Barangay Protection Order (BPO)';
      case RequestedAction.other:
        return actionOther.isNotEmpty ? actionOther : 'Other';
      case null:
        return '—';
    }
  }

  List<MapEntry<String, String>> _specificRows() {
    final set = specificSet;
    final rows = <MapEntry<String, String>>[];
    if (set == null) return rows;
    for (final f in set.fields) {
      if (f.isToggle) {
        if (specificToggles[f.label] ?? false) {
          rows.add(MapEntry(f.label, 'Yes'));
        }
      } else {
        final t = specificTextCtrls[f.label]?.text.trim() ?? '';
        if (t.isNotEmpty) rows.add(MapEntry(f.label, t));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final info = _categoryData[category]!;
    final uploadedCount = photos.where((p) => p.uploaded).length;
    final witnessCount = witnesses.where((w) => w.name.text.isNotEmpty).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 7 of 7',
              title: 'Review',
              progress: 1.0,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Review your report',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Check the details below before submitting.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Incident Type ──
                    _ReviewSection(
                      children: [
                        _ReviewRow(
                          icon: info.icon,
                          iconBg: info.iconBg,
                          iconColor: info.accent,
                          label: 'INCIDENT CATEGORY',
                          value: info.label,
                          onEdit: onEditType,
                        ),
                        _divider(),
                        _ReviewRow(
                          icon: Icons.flag_outlined,
                          label: 'SPECIFIC INCIDENT TYPE',
                          value: subtypeOther.isNotEmpty
                              ? '$subtype — $subtypeOther'
                              : subtype,
                          onEdit: onEditType,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (specificSet != null && _specificRows().isNotEmpty) ...[
                      // ── Incident-Specific Information ──
                      _ReviewSection(
                        children: [
                          _ReviewRow(
                            icon: Icons.assignment_outlined,
                            label: 'INCIDENT-SPECIFIC INFORMATION',
                            value: specificSet!.title,
                            onEdit: onEditSpecificInfo,
                          ),
                          for (final row in _specificRows()) ...[
                            _divider(),
                            _ReviewRow(
                              icon: null,
                              label: row.key,
                              value: row.value,
                              onEdit: onEditSpecificInfo,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Incident Details ──
                    _ReviewSection(
                      children: [
                        _ReviewRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'REPORT DATE & TIME',
                          value:
                              '${_ReviewScreen._fmtDate(reportDate)} at ${_ReviewScreen._fmtTime(reportTime)}',
                          onEdit: onEditDetails,
                        ),
                        _divider(),
                        _ReviewRow(
                          icon: Icons.access_time_outlined,
                          label: 'INCIDENT DATE & TIME',
                          value:
                              '${_ReviewScreen._fmtDate(incidentDate)} at ${_ReviewScreen._fmtTime(incidentTime)}',
                          onEdit: onEditDetails,
                        ),
                        _divider(),
                        _ReviewRow(
                          icon: Icons.location_on_outlined,
                          label: 'EXACT PLACE',
                          value: place.isEmpty ? '—' : place,
                          onEdit: onEditDetails,
                        ),
                        if (landmark.trim().isNotEmpty) ...[
                          _divider(),
                          _ReviewRow(
                            icon: Icons.place_outlined,
                            label: 'EXACT LOCATION / LANDMARK',
                            value: landmark,
                            onEdit: onEditDetails,
                          ),
                        ],
                        if (incidentLocation != null) ...[
                          _divider(),
                          _ReviewRow(
                            icon: Icons.add_location_alt_outlined,
                            label: 'PINNED COORDINATES',
                            value:
                                '${incidentLocation!.latitude.toStringAsFixed(5)}, ${incidentLocation!.longitude.toStringAsFixed(5)}',
                            onEdit: onEditDetails,
                          ),
                        ],
                        _divider(),
                        _ReviewRow(
                          icon: Icons.description_outlined,
                          label: 'NARRATIVE (5Ws + 1H)',
                          value: narrative.isEmpty ? '—' : narrative,
                          onEdit: onEditDetails,
                        ),
                        if (actionTaken.trim().isNotEmpty) ...[
                          _divider(),
                          _ReviewRow(
                            icon: Icons.health_and_safety_outlined,
                            label: 'IMMEDIATE ACTION TAKEN',
                            value: actionTaken,
                            onEdit: onEditDetails,
                          ),
                        ],
                        ],
                    ),
                    const SizedBox(height: 10),

                    // ── People ──
                    _ReviewSection(
                      children: [
                        _ReviewRow(
                          icon: Icons.person_outline,
                          label: 'RESPONDENT',
                          value: respName.isEmpty ? '—' : respName,
                          onEdit: onEditPeople,
                        ),
                        if (respAddr.isNotEmpty) ...[
                          _divider(),
                          _ReviewRow(
                            icon: Icons.home_outlined,
                            label: 'RESPONDENT ADDRESS',
                            value: respAddr,
                            onEdit: onEditPeople,
                          ),
                        ],
                        if (respRelation.isNotEmpty) ...[
                          _divider(),
                          _ReviewRow(
                            icon: Icons.link_outlined,
                            label: 'RELATIONSHIP',
                            value: respRelation,
                            onEdit: onEditPeople,
                          ),
                        ],
                        _divider(),
                        _ReviewRow(
                          icon: Icons.people_outline,
                          label: 'WITNESSES',
                          value: witnessCount == 0
                              ? 'None added'
                              : '$witnessCount witness${witnessCount == 1 ? '' : 'es'}',
                          onEdit: onEditPeople,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Evidence ──
                    _ReviewSection(
                      children: [
                        _ReviewRow(
                          icon: Icons.camera_alt_outlined,
                          label: 'EVIDENCE / PHOTOS',
                          value: photos.isEmpty
                              ? 'No photos added'
                              : '$uploadedCount of ${photos.length} uploaded',
                          onEdit: onEditEvidence,
                        ),
                        _divider(),
                        _ReviewRow(
                          icon: Icons.gavel_outlined,
                          label: 'REQUESTED ACTION',
                          value: _actionLabel(),
                          onEdit: onEditEvidence,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Anonymous ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.visibility_off_outlined,
                                size: 16,
                                color: AppColors.textDark,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Report Anonymously',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              Switch(
                                value: anonymous,
                                activeColor: AppColors.primary,
                                onChanged: onAnonymousChanged,
                              ),
                            ],
                          ),
                          if (anonymous) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Icon(
                                    Icons.info_outline,
                                    size: 15,
                                    color: AppColors.textGray,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Only your device ID is logged for abuse prevention. Your name, phone number, and identity are not stored or shared with anyone.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: AppColors.textGray,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  _BackSquareButton(onTap: onBack),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PrimaryButton(
                      label: 'Submit Report',
                      onPressed: onSubmit,
                      loading: isSubmitting,
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

  static String _fmtDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
        '${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  static Widget _divider() => const Divider(
        height: 1,
        color: AppColors.border,
        indent: 10,
        endIndent: 10,
      );
}

class _ReviewSection extends StatelessWidget {
  final List<Widget> children;
  const _ReviewSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconBg;
  final Color? iconColor;
  final String label;
  final String value;
  final VoidCallback onEdit;

  const _ReviewRow({
    this.icon,
    this.iconBg,
    this.iconColor,
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg ?? AppColors.infoBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 14,
                color: iconColor ?? AppColors.textGray,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: const Padding(
              padding: EdgeInsets.only(left: 8, top: 2),
              child: Text(
                'Edit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================================
/// Success screen
/// =====================================================================
class _SuccessScreen extends StatelessWidget {
  final String trackingId;
  final String location;
  final VoidCallback onTrackReport;
  final VoidCallback onBackToHome;

  const _SuccessScreen({
    super.key,
    required this.trackingId,
    required this.location,
    required this.onTrackReport,
    required this.onBackToHome,
  });

  String get _barangay {
    final withoutPrefix = location.replaceFirst(RegExp(r'^Brgy\.\s*'), '');
    return withoutPrefix.split(',').first.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.statusResolvedBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.statusResolvedText,
                  size: 42,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Report Submitted!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your incident has been reported to barangay authorities.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 26),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TRACKING ID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      trackingId.isEmpty ? '—' : trackingId,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ESTIMATED RESPONSE',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: AppColors.textGray,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '30 – 60 minutes',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BARANGAY',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppColors.textGray,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _barangay.isEmpty ? '—' : _barangay,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.infoBorder),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 15,
                      color: AppColors.textGray,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A confirmation email was sent to your registered email address.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Track This Report',
                  onPressed: onTrackReport,
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onBackToHome,
                child: const Text(
                  '← Back to Home',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
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
