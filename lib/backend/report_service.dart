import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_service.dart';

/// Represents a single photo or video attachment for a report.
///
/// Photos are stored in the `report-photos` bucket / `report_photos` table,
/// videos in the `report-videos` bucket / `report_videos` table.
class ReportMediaRecord {
  final String id;
  final String fileName;
  final String storagePath;
  final String mediaType;

  const ReportMediaRecord({
    required this.id,
    required this.fileName,
    required this.storagePath,
    this.mediaType = 'image',
  });

  factory ReportMediaRecord.fromJson(Map<String, dynamic> json) {
    return ReportMediaRecord(
      id: '${json['id'] ?? ''}',
      fileName: '${json['file_name'] ?? ''}',
      storagePath: '${json['storage_path'] ?? ''}',
      mediaType: '${json['media_type'] ?? 'image'}',
    );
  }
}

/// Represents a status update in the timeline of a report.
class ReportStatusUpdate {
  final String title;
  final String date;
  final String description;

  const ReportStatusUpdate({
    required this.title,
    required this.date,
    required this.description,
  });

  factory ReportStatusUpdate.fromJson(Map<String, dynamic> json) {
    return ReportStatusUpdate(
      title: '${json['title'] ?? ''}',
      date: '${json['date'] ?? ''}',
      description: '${json['description'] ?? ''}',
    );
  }
}

/// A full report record fetched from the `reports` table.
class ReportRecord {
  final String id;
  final String trackingId;
  final String userEmail;
  final String category;
  final String subtype;
  final bool isEmergency;
  final String priority;
  final double? latitude;
  final double? longitude;
  final String place;
  final String landmark;
  final String narrative;
  final String actionTaken;
  final String reportDateTime;
  final String incidentDateTime;
  final String status;
  final String requestedAction;
  final String actionOther;
  final bool anonymous;
  final String respondentName;
  final String respondentAddress;
  final String respondentContact;
  final String respondentRelation;
  final String callbackPhone;
  final String peopleAffected;
  final String additionalDescription;
  final Map<String, dynamic> specificInfo;
  final Map<String, dynamic> emergencyAnswers;
  final List<Map<String, dynamic>> witnesses;
  final List<ReportMediaRecord> photos;
  final List<ReportMediaRecord> videos;
  final List<ReportStatusUpdate> statusUpdates;
  final String createdAt;

  const ReportRecord({
    required this.id,
    required this.trackingId,
    required this.userEmail,
    required this.category,
    required this.subtype,
    this.isEmergency = false,
    this.priority = 'Normal',
    this.latitude,
    this.longitude,
    this.place = '',
    this.landmark = '',
    this.narrative = '',
    this.actionTaken = '',
    this.reportDateTime = '',
    this.incidentDateTime = '',
    this.status = 'pending',
    this.requestedAction = '',
    this.actionOther = '',
    this.anonymous = false,
    this.respondentName = '',
    this.respondentAddress = '',
    this.respondentContact = '',
    this.respondentRelation = '',
    this.callbackPhone = '',
    this.peopleAffected = '',
    this.additionalDescription = '',
    this.specificInfo = const {},
    this.emergencyAnswers = const {},
    this.witnesses = const [],
    this.photos = const [],
    this.videos = const [],
    this.statusUpdates = const [],
    this.createdAt = '',
  });

  factory ReportRecord.fromJson(Map<String, dynamic> json) {
    return ReportRecord(
      id: '${json['id'] ?? ''}',
      trackingId: '${json['tracking_id'] ?? ''}',
      userEmail: '${json['user_email'] ?? ''}',
      category: '${json['category'] ?? ''}',
      subtype: '${json['subtype'] ?? ''}',
      isEmergency: json['is_emergency'] as bool? ?? false,
      priority: '${json['priority'] ?? 'Normal'}',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      place: '${json['place'] ?? ''}',
      landmark: '${json['landmark'] ?? ''}',
      narrative: '${json['narrative'] ?? ''}',
      actionTaken: '${json['action_taken'] ?? ''}',
      reportDateTime: '${json['report_date_time'] ?? ''}',
      incidentDateTime: '${json['incident_date_time'] ?? ''}',
      status: '${json['status'] ?? 'pending'}',
      requestedAction: '${json['requested_action'] ?? ''}',
      actionOther: '${json['action_other'] ?? ''}',
      anonymous: json['anonymous'] as bool? ?? false,
      respondentName: '${json['respondent_name'] ?? ''}',
      respondentAddress: '${json['respondent_address'] ?? ''}',
      respondentContact: '${json['respondent_contact'] ?? ''}',
      respondentRelation: '${json['respondent_relation'] ?? ''}',
      callbackPhone: '${json['callback_phone'] ?? ''}',
      peopleAffected: '${json['people_affected'] ?? ''}',
      additionalDescription: '${json['additional_description'] ?? ''}',
      specificInfo: _safeCastMap(json['specific_info']),
      emergencyAnswers: _safeCastMap(json['emergency_answers']),
      witnesses: _safeCastList(json['witnesses']),
      photos: (json['report_photos'] as List<dynamic>?)
              ?.map((p) =>
                  ReportMediaRecord.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      videos: (json['report_videos'] as List<dynamic>?)
              ?.map((v) =>
                  ReportMediaRecord.fromJson(v as Map<String, dynamic>))
              .toList() ??
          const [],
      statusUpdates: (json['report_status_updates'] as List<dynamic>?)
              ?.map((s) => ReportStatusUpdate.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: '${json['created_at'] ?? ''}',
    );
  }

  static Map<String, dynamic> _safeCastMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  static List<Map<String, dynamic>> _safeCastList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
          .toList();
    }
    return [];
  }
}

/// Dart backend service for incident reports. Talks to Supabase
/// (PostgREST + Storage) directly — no separate API server required.
///
/// Photo and video attachments are fully separated:
///   images -> `report-photos` bucket / `report_photos` table
///   videos -> `report-videos` bucket / `report_videos` table
class ReportService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const String _reportsTable = 'reports';
  static const String _photosTable = 'report_photos';
  static const String _videosTable = 'report_videos';
  static const String _statusTable = 'report_status_updates';
  static const String _photoBucket = 'report-photos';
  static const String _videoBucket = 'report-videos';

  /// Upload caps: at most this many photos and videos per report. Anything
  /// past the cap is dropped during upload so callers can never flood a
  /// report with attachments.
  static const int maxPhotosPerReport = 5;
  static const int maxVideosPerReport = 2;

  static const List<String> _validStatuses = [
    'pending',
    'under_review',
    'assigned',
    'resolved',
    'closed',
  ];

  // ───────────────────────── Submit ─────────────────────────

  /// Submit a new incident report. Returns the tracking ID.
  ///
  /// [userEmail] is the resident's email (from AuthStore).
  /// [reportData] should contain all the fields from the report form:
  ///   - category, subtype, isEmergency
  ///   - place, landmark, narrative, actionTaken
  ///   - latitude, longitude
  ///   - reportDateTime, incidentDateTime
  ///   - respondentName/Address/Contact/Relation
  ///   - witnesses (List<Map>)
  ///   - specificInfo (Map)
  ///   - emergencyAnswers (Map)
  ///   - requestedAction, actionOther
  ///   - anonymous, callbackPhone, peopleAffected, additionalDescription
  static Future<String> submitReport({
    required String userEmail,
    required Map<String, dynamic> reportData,
    List<ReportUploadPhoto>? photos,
  }) async {
    if (userEmail.trim().isEmpty) {
      throw ApiException('You must be signed in to submit a report.');
    }

    final trackingId = _generateTrackingId(reportData['isEmergency'] == true);

    final row = <String, dynamic>{
      'tracking_id': trackingId,
      'user_email': userEmail.trim().toLowerCase(),
      'category': reportData['category'] ?? '',
      'subtype': reportData['subtype'] ?? '',
      'is_emergency': reportData['isEmergency'] ?? false,
      'priority': reportData['priority'] ??
          (reportData['isEmergency'] == true ? 'High' : 'Normal'),
      'latitude': reportData['latitude'],
      'longitude': reportData['longitude'],
      'place': reportData['place'] ?? '',
      'landmark': reportData['landmark'] ?? '',
      'narrative': reportData['narrative'] ?? '',
      'action_taken': reportData['actionTaken'] ?? '',
      'report_date_time': reportData['reportDateTime'] ?? '',
      'incident_date_time': reportData['incidentDateTime'] ?? '',
      'status': 'pending',
      'requested_action': reportData['requestedAction'] ?? '',
      'action_other': reportData['actionOther'] ?? '',
      'anonymous': reportData['anonymous'] ?? false,
      'respondent_name': reportData['respondentName'] ?? '',
      'respondent_address': reportData['respondentAddress'] ?? '',
      'respondent_contact': reportData['respondentContact'] ?? '',
      'respondent_relation': reportData['respondentRelation'] ?? '',
      'callback_phone': reportData['callbackPhone'] ?? '',
      'people_affected': reportData['peopleAffected'] ?? '',
      'additional_description': reportData['additionalDescription'] ?? '',
      'specific_info': reportData['specificInfo'] ?? {},
      'emergency_answers': reportData['emergencyAnswers'] ?? {},
      'witnesses': reportData['witnesses'] ?? [],
    };

    final response = await _client
        .from(_reportsTable)
        .insert(row)
        .select('id')
        .single();

    final reportId = '${response['id'] ?? ''}';

    // Upload photo/video attachments (each to its own bucket + table).
    if (photos != null && photos.isNotEmpty && reportId.isNotEmpty) {
      await _uploadPhotos(reportId, photos);
    }

    // Create initial status update.
    await _client.from(_statusTable).insert({
      'report_id': reportId,
      'title': 'New',
      'date': _formatNow(),
      'description': 'Report received and logged by the system.',
    });

    return trackingId;
  }

  // ───────────────────────── Fetch ─────────────────────────

  /// Fetch all reports for a user, most recent first.
  static Future<List<ReportRecord>> fetchMyReports(String userEmail) async {
    if (userEmail.trim().isEmpty) return [];

    try {
      final data = await _client
          .from(_reportsTable)
          .select(
            '*, report_photos(*), report_videos(*), report_status_updates(*)',
          )
          .eq('user_email', userEmail.trim().toLowerCase())
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map((row) => ReportRecord.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException {
      return [];
    }
  }

  /// Fetch a single report by its tracking ID.
  static Future<ReportRecord?> fetchReportByTrackingId(String trackingId) async {
    try {
      final data = await _client
          .from(_reportsTable)
          .select(
            '*, report_photos(*), report_videos(*), report_status_updates(*)',
          )
          .eq('tracking_id', trackingId)
          .maybeSingle();

      if (data == null) return null;
      return ReportRecord.fromJson(data);
    } on PostgrestException {
      return null;
    }
  }

  /// Fetch a single report by its UUID.
  static Future<ReportRecord?> fetchReportById(String reportId) async {
    try {
      final data = await _client
          .from(_reportsTable)
          .select(
            '*, report_photos(*), report_videos(*), report_status_updates(*)',
          )
          .eq('id', reportId)
          .maybeSingle();

      if (data == null) return null;
      return ReportRecord.fromJson(data);
    } on PostgrestException {
      return null;
    }
  }

  // ─────────────────── Status updates ─────────────────

  /// Valid statuses a report can move through.
  static List<String> get validStatuses => List.unmodifiable(_validStatuses);

  /// Change a report's status. Also appends a timeline entry so the
  /// change is visible in the report's "Status Updates" list.
  static Future<void> updateStatus(String reportId, String status) async {
    final normalized = status.trim().toLowerCase();
    if (!_validStatuses.contains(normalized)) {
      throw ApiException(
        'Invalid status. Choose one of: ${_validStatuses.join(', ')}',
      );
    }

    final report = await fetchReportById(reportId);
    if (report == null) {
      throw ApiException('Report not found.');
    }

    final label = _statusLabel(normalized);
    await _client
        .from(_reportsTable)
        .update({'status': normalized, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', reportId);

    await _client.from(_statusTable).insert({
      'report_id': reportId,
      'title': label,
      'date': _formatNow(),
      'description': 'Report status changed to $label.',
    });
  }

  /// Add a custom entry to the report's status timeline.
  static Future<void> addStatusUpdate(
    String reportId, {
    required String title,
    required String description,
    String date = '',
  }) async {
    final report = await fetchReportById(reportId);
    if (report == null) {
      throw ApiException('Report not found.');
    }

    await _client.from(_statusTable).insert({
      'report_id': reportId,
      'title': title.trim(),
      'date': date.trim().isEmpty ? _formatNow() : date.trim(),
      'description': description.trim(),
    });
  }

  // ─────────────────── Media (photos & videos) ─────────────────

  /// Upload one or more attachments to Supabase Storage and link them to a
  /// report. Storage and database records are fully separated:
  ///   images -> 'report-photos' bucket /  `report_photos` table
  ///   videos -> 'report-videos' bucket / `report_videos` table
  static Future<void> _uploadPhotos(
    String reportId,
    List<ReportUploadPhoto> photos,
  ) async {
    var photoCount = 0;
    var videoCount = 0;
    for (final photo in photos) {
      if (photo.isVideo) {
        if (videoCount >= maxVideosPerReport) continue;
        videoCount++;
      } else {
        if (photoCount >= maxPhotosPerReport) continue;
        photoCount++;
      }
      try {
        final bucket = photo.isVideo ? _videoBucket : _photoBucket;
        final table = photo.isVideo ? _videosTable : _photosTable;
        final path = '$reportId/${photo.fileName}';
        final contentType = photo.isVideo
            ? _videoContentType(photo.fileName)
            : 'image/jpeg';

        if (photo.isVideo) {
          final filePath = photo.filePath;
          if (filePath == null || !File(filePath).existsSync()) continue;
          await _client.storage.from(bucket).upload(
                path,
                File(filePath),
                fileOptions: FileOptions(
                  upsert: true,
                  contentType: contentType,
                ),
              );
        } else if (photo.bytes != null) {
          await _client.storage.from(bucket).uploadBinary(
                path,
                photo.bytes!,
                fileOptions: FileOptions(
                  upsert: true,
                  contentType: contentType,
                ),
              );
        } else {
          continue;
        }

        await _client.from(table).insert({
          'report_id': reportId,
          'file_name': photo.fileName,
          'storage_path': path,
          'media_type': photo.isVideo ? 'video' : 'image',
        });
      } catch (_) {
        // Non-fatal: a failed attachment should not block the report.
      }
    }
  }

  /// Attach an already-uploaded file's metadata to a report. Use when the
  /// file was uploaded directly (e.g. progressive upload with its own
  /// progress UI) and only the storage reference needs to be recorded.
  static Future<void> attachMedia(
    String reportId, {
    required String fileName,
    required String storagePath,
    bool isVideo = false,
  }) async {
    final report = await fetchReportById(reportId);
    if (report == null) {
      throw ApiException('Report not found.');
    }

    final table = isVideo ? _videosTable : _photosTable;
    await _client.from(table).insert({
      'report_id': reportId,
      'file_name': fileName,
      'storage_path': storagePath,
      'media_type': isVideo ? 'video' : 'image',
    });
  }

  /// Best-effort MIME type from the file extension (defaults to video/mp4).
  static String _videoContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return 'video/mp4';
    }
  }

  /// Get a signed URL for viewing a stored attachment.
  ///
  /// [mediaType] ('image' or 'video') selects which bucket the object lives
  /// in: images in 'report-photos', videos in 'report-videos'.
  static Future<String?> getPhotoUrl(
    String storagePath, {
    String mediaType = 'image',
  }) async {
    try {
      final bucket =
          mediaType == 'video' ? _videoBucket : _photoBucket;
      final url = await _client.storage
          .from(bucket)
          .createSignedUrl(storagePath, 3600);
      return url;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────── Helpers ─────────────────────

  static String _generateTrackingId(bool isEmergency) {
    final now = DateTime.now();
    final rand = DateTime.now().microsecondsSinceEpoch % 9973;
    final suffix =
        (rand.abs()).toString().padLeft(5, '0');
    final prefix = isEmergency ? 'EMG' : 'INC';
    return '$prefix-${now.year}-${now.month.toString().padLeft(2, '0')}-$suffix';
  }

  static String _statusLabel(String status) {
    return status
        .split('_')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1) : ''}')
        .join(' ');
  }

  static String _formatNow() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    return '${_month(now.month)} ${now.day} · '
        '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
  }

  static String _month(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[m];
  }
}

/// Data class for a photo or video ready to upload.
///
/// [isVideo] selects the content type, storage bucket and database table:
/// images are uploaded from [bytes] (memory) to the photo bucket; videos
/// are uploaded from [filePath] (disk, to avoid loading large files into
/// memory) to the video bucket.
class ReportUploadPhoto {
  final String fileName;
  final Uint8List? bytes;
  final String? filePath;
  final bool isVideo;

  const ReportUploadPhoto({
    required this.fileName,
    this.bytes,
    this.filePath,
    this.isVideo = false,
  });
}