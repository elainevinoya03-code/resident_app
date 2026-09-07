import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'login.dart' show AppColors, StepHeader;
import 'my_report.dart' show ReportsScreen;

/// ---------------------------------------------------------------------
/// Incident category data
/// ---------------------------------------------------------------------
enum IncidentCategory { flood, crime, road, noise, vandalism, other }

class _CategoryInfo {
  final IconData icon;
  final Color iconBg;
  final Color accent;
  final String label;

  const _CategoryInfo({
    required this.icon,
    required this.iconBg,
    required this.accent,
    required this.label,
  });
}

const Map<IncidentCategory, _CategoryInfo> _categoryData = {
  IncidentCategory.flood: _CategoryInfo(
    icon: Icons.water_drop_outlined,
    iconBg: Color(0xFFE8F0FF),
    accent: Color(0xFF3B82F6),
    label: 'Flood',
  ),
  IncidentCategory.crime: _CategoryInfo(
    icon: Icons.shield_outlined,
    iconBg: Color(0xFFE8ECE8),
    accent: AppColors.textGray,
    label: 'Crime / Suspicious',
  ),
  IncidentCategory.road: _CategoryInfo(
    icon: Icons.directions_car_outlined,
    iconBg: AppColors.iconCircleRoad,
    accent: Color(0xFFD9A400),
    label: 'Road Obstruction',
  ),
  IncidentCategory.noise: _CategoryInfo(
    icon: Icons.volume_up_outlined,
    iconBg: AppColors.iconCircleNoise,
    accent: Color(0xFF2E8B57),
    label: 'Noise Disturbance',
  ),
  IncidentCategory.vandalism: _CategoryInfo(
    icon: Icons.brush,
    iconBg: Color(0xFFE8ECE8),
    accent: AppColors.textGray,
    label: 'Vandalism',
  ),
  IncidentCategory.other: _CategoryInfo(
    icon: Icons.help_outline,
    iconBg: Color(0xFFE8ECE8),
    accent: AppColors.textGray,
    label: 'Other',
  ),
};

/// A single attached photo, with a locally-simulated upload progress.
class _ReportPhoto {
  final int id;
  final String fileName;
  final Uint8List bytes;
  double progress = 0; // 0.0 - 1.0
  bool get uploaded => progress >= 1.0;

  _ReportPhoto({required this.id, required this.fileName, required this.bytes});
}

enum _ReportStep { type, details, photos, review, success }

/// ---------------------------------------------------------------------
/// Flow controller
/// ---------------------------------------------------------------------
class ReportIncidentFlow extends StatefulWidget {
  /// Called when the user taps back on step 1. Defaults to popping the
  /// current route if not provided.
  final VoidCallback? onClose;

  /// Called when the user taps "Back to Home" on the success screen.
  /// Defaults to resetting the flow back to step 1 if not provided.
  final VoidCallback? onBackToHome;

  /// Called once a report is (simulated) submitted, with the generated
  /// tracking ID.
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

  IncidentCategory? _selectedCategory;
  final TextEditingController _descController = TextEditingController();
  String _location = 'Brgy. Tandang Sora, Quezon City';
  final List<_ReportPhoto> _photos = [];
  int _photoIdCounter = 0;
  bool _anonymous = false;
  bool _isSubmitting = false;
  String _trackingId = '';

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  void _goTo(_ReportStep step) => setState(() => _step = step);

  /// Opens the device's native file/photo picker (works on mobile, web, and
  /// desktop) and adds the chosen image to the list with a simulated
  /// upload-progress overlay.
  Future<void> _addPhoto() async {
    if (_photos.length >= 5) return;
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null) return; // user cancelled the picker
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

  void _removePhoto(int id) {
    setState(() => _photos.removeWhere((p) => p.id == id));
  }

  void _handleSubmit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 1400));
    final rand = Random();
    final now = DateTime.now();
    final id =
        'INC-${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${rand.nextInt(99999).toString().padLeft(5, '0')}';
    if (!mounted) return;
    setState(() {
      _trackingId = id;
      _isSubmitting = false;
      _step = _ReportStep.success;
    });
    widget.onSubmitted?.call(id);
  }

  void _resetFlow() {
    setState(() {
      _step = _ReportStep.type;
      _selectedCategory = null;
      _descController.clear();
      _photos.clear();
      _anonymous = false;
      _trackingId = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget screen;
    switch (_step) {
      case _ReportStep.type:
        screen = _TypeScreen(
          key: const ValueKey('type'),
          selected: _selectedCategory,
          onSelect: (c) => setState(() => _selectedCategory = c),
          onBack: () {
            if (widget.onClose != null) {
              widget.onClose!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          onContinue: _selectedCategory == null
              ? null
              : () => _goTo(_ReportStep.details),
        );
      case _ReportStep.details:
        screen = _DetailsScreen(
          key: const ValueKey('details'),
          controller: _descController,
          location: _location,
          onLocationChanged: (v) => setState(() => _location = v),
          onBack: () => _goTo(_ReportStep.type),
          onContinue: () => _goTo(_ReportStep.photos),
        );
      case _ReportStep.photos:
        screen = _PhotosScreen(
          key: const ValueKey('photos'),
          photos: _photos,
          onAddPhoto: _addPhoto,
          onRemovePhoto: _removePhoto,
          onBack: () => _goTo(_ReportStep.details),
          onContinue: () => _goTo(_ReportStep.review),
        );
      case _ReportStep.review:
        screen = _ReviewScreen(
          key: const ValueKey('review'),
          category: _selectedCategory ?? IncidentCategory.other,
          description: _descController.text,
          location: _location,
          photos: _photos,
          anonymous: _anonymous,
          onAnonymousChanged: (v) => setState(() => _anonymous = v),
          onEditType: () => _goTo(_ReportStep.type),
          onEditDescription: () => _goTo(_ReportStep.details),
          onEditLocation: () => _goTo(_ReportStep.details),
          onEditPhotos: () => _goTo(_ReportStep.photos),
          onBack: () => _goTo(_ReportStep.photos),
          isSubmitting: _isSubmitting,
          onSubmit: _handleSubmit,
        );
      case _ReportStep.success:
        screen = _SuccessScreen(
          key: const ValueKey('success'),
          trackingId: _trackingId,
          location: _location,
          onTrackReport: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
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
    return screen;
  }
}

/// ---------------------------------------------------------------------
/// Shared bits
/// ---------------------------------------------------------------------
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

/// A simple dashed rounded-rectangle border painter (no external package).
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
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// ---------------------------------------------------------------------
/// STEP 1 — Type
/// ---------------------------------------------------------------------
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 1 of 4',
              title: 'Type',
              progress: 0.25,
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
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.8,
                      children: IncidentCategory.values.map((c) {
                        final data = _categoryData[c]!;
                        return _CategoryCard(
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

class _CategoryCard extends StatelessWidget {
  final _CategoryInfo data;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.data,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? data.accent.withOpacity(0.08) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: data.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, color: data.accent, size: 16),
              ),
              const SizedBox(height: 6),
              Text(
                data.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  height: 1.2,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 2),
                Icon(Icons.check, size: 12, color: data.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsScreen extends StatefulWidget {
  final TextEditingController controller;
  final String location;
  final ValueChanged<String> onLocationChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _DetailsScreen({
    super.key,
    required this.controller,
    required this.location,
    required this.onLocationChanged,
    required this.onBack,
    required this.onContinue,
  });

  @override
  State<_DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<_DetailsScreen> {
  final FocusNode _focusNode = FocusNode();
  static const int _maxLength = 2000;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _editLocation() async {
    final controller = TextEditingController(text: widget.location);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Brgy. ..., Quezon City'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      widget.onLocationChanged(result);
    }
  }

  String _formatCount(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _maxLength - widget.controller.text.length;
    final canContinue = widget.controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: widget.onBack,
              stepLabel: 'Step 2 of 4',
              title: 'Details',
              progress: 0.5,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Describe the incident',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Provide as much detail as you can — it helps responders.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Text(
                          'DESCRIPTION',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.textGray,
                          ),
                        ),
                        Text(
                          ' *',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.hotlineRed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _focusNode.hasFocus
                              ? AppColors.primary
                              : AppColors.border,
                          width: _focusNode.hasFocus ? 1.6 : 1,
                        ),
                      ),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        maxLines: 5,
                        maxLength: _maxLength,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textDark,
                          height: 1.4,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                          hintText:
                              'Describe what you observed: what happened, when it started, and any other details...',
                          hintStyle: TextStyle(color: AppColors.hint),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Be specific: time, location, persons involved.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                        Text(
                          _formatCount(remaining),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'LOCATION',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _editLocation,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 15,
                                  color: AppColors.hotlineRed,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'GPS auto-detected · tap to edit',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.hotlineRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.location,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'GPS detected your barangay. Edit the address if it is not accurate.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  _BackSquareButton(onTap: widget.onBack),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PrimaryButton(
                      label: 'Continue →',
                      onPressed: canContinue ? widget.onContinue : null,
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

/// ---------------------------------------------------------------------
/// STEP 3 — Photos
/// ---------------------------------------------------------------------
class _PhotosScreen extends StatelessWidget {
  final List<_ReportPhoto> photos;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _PhotosScreen({
    super.key,
    required this.photos,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final count = photos.length;
    final label = count == 0
        ? 'Continue →'
        : 'Continue with $count photo${count == 1 ? '' : 's'} →';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 3 of 4',
              title: 'Photos',
              progress: 0.75,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Add photos',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
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
                      'Photos help responders assess the situation faster. Up to 5 images.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 18),
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
                        if (photos.length < 5) _AddPhotoTile(onTap: onAddPhoto),
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
                    child: _PrimaryButton(label: label, onPressed: onContinue),
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

/// ---------------------------------------------------------------------
/// STEP 4 — Review
/// ---------------------------------------------------------------------
class _ReviewScreen extends StatelessWidget {
  final IncidentCategory category;
  final String description;
  final String location;
  final List<_ReportPhoto> photos;
  final bool anonymous;
  final ValueChanged<bool> onAnonymousChanged;
  final VoidCallback onEditType;
  final VoidCallback onEditDescription;
  final VoidCallback onEditLocation;
  final VoidCallback onEditPhotos;
  final VoidCallback onBack;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const _ReviewScreen({
    super.key,
    required this.category,
    required this.description,
    required this.location,
    required this.photos,
    required this.anonymous,
    required this.onAnonymousChanged,
    required this.onEditType,
    required this.onEditDescription,
    required this.onEditLocation,
    required this.onEditPhotos,
    required this.onBack,
    required this.isSubmitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final info = _categoryData[category]!;
    final uploadedCount = photos.where((p) => p.uploaded).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepHeader(
              onBack: onBack,
              stepLabel: 'Step 4 of 4',
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
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _ReviewRow(
                            icon: info.icon,
                            iconBg: info.iconBg,
                            iconColor: info.accent,
                            label: 'INCIDENT TYPE',
                            value: info.label,
                            onEdit: onEditType,
                          ),
                          const Divider(
                            height: 1,
                            color: AppColors.border,
                            indent: 10,
                            endIndent: 10,
                          ),
                          _ReviewRow(
                            icon: Icons.description_outlined,
                            label: 'DESCRIPTION',
                            value: description.trim().isEmpty
                                ? '—'
                                : description,
                            onEdit: onEditDescription,
                          ),
                          const Divider(
                            height: 1,
                            color: AppColors.border,
                            indent: 10,
                            endIndent: 10,
                          ),
                          _ReviewRow(
                            icon: Icons.location_on_outlined,
                            label: 'LOCATION',
                            value: location,
                            onEdit: onEditLocation,
                          ),
                          const Divider(
                            height: 1,
                            color: AppColors.border,
                            indent: 10,
                            endIndent: 10,
                          ),
                          _ReviewRow(
                            icon: Icons.camera_alt_outlined,
                            label: 'PHOTOS',
                            value: photos.isEmpty
                                ? 'No photos added'
                                : '$uploadedCount of ${photos.length} uploaded',
                            onEdit: onEditPhotos,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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

/// ---------------------------------------------------------------------
/// Success screen
/// ---------------------------------------------------------------------
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
                              _barangay,
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
                      Icons.sms_outlined,
                      size: 15,
                      color: AppColors.textGray,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A confirmation SMS was sent to your registered number.',
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
