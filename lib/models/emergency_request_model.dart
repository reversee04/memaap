import 'dart:convert';

// ── Emergency Severity ────────────────────────────────────────────────────────

/// Severity levels for triaging emergency requests.
enum EmergencySeverity { critical, urgent, nonUrgent }

extension EmergencySeverityExtension on EmergencySeverity {
  String get displayName {
    switch (this) {
      case EmergencySeverity.critical:
        return 'Critical';
      case EmergencySeverity.urgent:
        return 'Urgent';
      case EmergencySeverity.nonUrgent:
        return 'Non-Urgent';
    }
  }

  /// API / DB wire value.
  String get apiValue {
    switch (this) {
      case EmergencySeverity.critical:
        return 'critical';
      case EmergencySeverity.urgent:
        return 'urgent';
      case EmergencySeverity.nonUrgent:
        return 'non_urgent';
    }
  }

  /// 0 = highest priority.
  int get priorityOrder {
    switch (this) {
      case EmergencySeverity.critical:
        return 0;
      case EmergencySeverity.urgent:
        return 1;
      case EmergencySeverity.nonUrgent:
        return 2;
    }
  }

  static EmergencySeverity fromString(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'critical':
        return EmergencySeverity.critical;
      case 'urgent':
        return EmergencySeverity.urgent;
      case 'non_urgent':
      case 'nonurgent':
        return EmergencySeverity.nonUrgent;
      default:
        return EmergencySeverity.urgent; // safe default
    }
  }
}

// ── Emergency Type ────────────────────────────────────────────────────────────

/// Enum for emergency types — includes both legacy values and new quick-action
/// types added during the emergency request process improvement.
enum EmergencyType {
  medical,
  accident,
  cardiac,
  stroke,
  trauma,
  other,
  // Quick-action types
  heartAttack,
  severeBleed,
  breathingDifficulty,
  unconscious,
  choking,
  allergicReaction,
  seizure,
  maternal,
}

extension EmergencyTypeExtension on EmergencyType {
  String get typeDisplayName {
    switch (this) {
      case EmergencyType.medical:
        return 'Medical Emergency';
      case EmergencyType.accident:
        return 'Accident';
      case EmergencyType.cardiac:
        return 'Cardiac Emergency';
      case EmergencyType.stroke:
        return 'Stroke';
      case EmergencyType.trauma:
        return 'Trauma';
      case EmergencyType.heartAttack:
        return 'Heart Attack';
      case EmergencyType.severeBleed:
        return 'Severe Bleeding';
      case EmergencyType.breathingDifficulty:
        return 'Difficulty Breathing';
      case EmergencyType.unconscious:
        return 'Unconscious Person';
      case EmergencyType.choking:
        return 'Choking';
      case EmergencyType.allergicReaction:
        return 'Allergic Reaction';
      case EmergencyType.seizure:
        return 'Seizure';
      case EmergencyType.maternal:
        return 'Maternal Emergency';
      case EmergencyType.other:
        return 'Other Emergency';
    }
  }

  String get apiValue => name; // matches DB wire values directly
}

// ── Quick Emergency Preset ────────────────────────────────────────────────────

/// Pre-configured data for one-tap emergency reporting.
class QuickEmergencyPreset {
  final EmergencyType type;
  final EmergencySeverity severity;
  final String description;
  final String symptoms;
  final String iconAsset; // Lucide icon name string (used in UI for lookup)

  const QuickEmergencyPreset({
    required this.type,
    required this.severity,
    required this.description,
    required this.symptoms,
    required this.iconAsset,
  });
}

/// All predefined quick-action emergency presets.
const List<QuickEmergencyPreset> kQuickEmergencyPresets = [
  QuickEmergencyPreset(
    type: EmergencyType.heartAttack,
    severity: EmergencySeverity.critical,
    description: 'Suspected heart attack — chest pain, pressure, left arm pain.',
    symptoms: 'Chest pain/pressure, shortness of breath, left arm/jaw pain, cold sweat',
    iconAsset: 'heartPulse',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.stroke,
    severity: EmergencySeverity.critical,
    description: 'Suspected stroke — face drooping, arm weakness, speech difficulty.',
    symptoms: 'Face drooping, arm weakness, slurred speech, sudden severe headache',
    iconAsset: 'brain',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.severeBleed,
    severity: EmergencySeverity.critical,
    description: 'Severe bleeding that cannot be controlled.',
    symptoms: 'Heavy uncontrolled bleeding, wound, possible shock',
    iconAsset: 'droplets',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.breathingDifficulty,
    severity: EmergencySeverity.critical,
    description: 'Patient is having severe difficulty breathing.',
    symptoms: 'Shortness of breath, wheezing, blue lips/fingertips',
    iconAsset: 'wind',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.unconscious,
    severity: EmergencySeverity.critical,
    description: 'Person is unconscious and not responding.',
    symptoms: 'Unresponsive, not breathing normally or no pulse',
    iconAsset: 'userX',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.choking,
    severity: EmergencySeverity.urgent,
    description: 'Person is choking and unable to speak or breathe.',
    symptoms: 'Cannot speak/cough/breathe, hands at throat, turning blue',
    iconAsset: 'alertCircle',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.allergicReaction,
    severity: EmergencySeverity.urgent,
    description: 'Severe allergic reaction (anaphylaxis).',
    symptoms: 'Hives, swelling, breathing difficulty, dizziness, known allergen exposure',
    iconAsset: 'zap',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.seizure,
    severity: EmergencySeverity.urgent,
    description: 'Person is having a seizure.',
    symptoms: 'Convulsions, muscle spasms, loss of consciousness, confusion',
    iconAsset: 'activity',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.accident,
    severity: EmergencySeverity.urgent,
    description: 'Road or physical accident with injuries.',
    symptoms: 'Trauma, fractures, lacerations, possible spinal injury',
    iconAsset: 'car',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.maternal,
    severity: EmergencySeverity.urgent,
    description: 'Obstetric / maternal emergency.',
    symptoms: 'Labour complications, heavy bleeding, pre-eclampsia symptoms',
    iconAsset: 'user',
  ),
  QuickEmergencyPreset(
    type: EmergencyType.other,
    severity: EmergencySeverity.nonUrgent,
    description: 'Other medical emergency.',
    symptoms: '',
    iconAsset: 'moreHorizontal',
  ),
];

// ── Emergency Status ──────────────────────────────────────────────────────────

/// Enum for emergency request status
enum EmergencyStatus {
  pending,
  accepted,
  inProgress,
  completed,
  cancelled,
  expired,
}

// ── Emergency Request Model ───────────────────────────────────────────────────

/// Model class for emergency request data
///
/// Represents an emergency request in the Mobile Emergency Medical Assistance App
/// with location information, patient details, severity, and status tracking.
class EmergencyRequest {
  final String id;
  final String userId;
  final EmergencyType type;
  final EmergencySeverity severity;
  final String description;
  final double latitude;
  final double longitude;
  final String? address;
  final EmergencyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? patientName;
  final String? patientPhone;
  final String? responderId;
  final String? responderName;
  final String? responderPhone;
  final int? estimatedArrivalMinutes;
  final bool isOfflineQueued;
  final DateTime? syncedAt;

  /// Serialised JSON string of patient medical history (optional)
  final String? medicalHistory;

  /// Live responder GPS coordinates — updated by ResponderService as they move
  final double? responderLat;
  final double? responderLng;

  EmergencyRequest({
    required this.id,
    required this.userId,
    required this.type,
    this.severity = EmergencySeverity.urgent,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.patientName,
    this.patientPhone,
    this.responderId,
    this.responderName,
    this.responderPhone,
    this.estimatedArrivalMinutes,
    this.isOfflineQueued = false,
    this.syncedAt,
    this.medicalHistory,
    this.responderLat,
    this.responderLng,
  });

  /// Creates a copy of this model with updated values
  EmergencyRequest copyWith({
    String? id,
    String? userId,
    EmergencyType? type,
    EmergencySeverity? severity,
    String? description,
    double? latitude,
    double? longitude,
    String? address,
    EmergencyStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? patientName,
    String? patientPhone,
    String? responderId,
    String? responderName,
    String? responderPhone,
    int? estimatedArrivalMinutes,
    bool? isOfflineQueued,
    DateTime? syncedAt,
    String? medicalHistory,
    double? responderLat,
    double? responderLng,
  }) {
    return EmergencyRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patientName: patientName ?? this.patientName,
      patientPhone: patientPhone ?? this.patientPhone,
      responderId: responderId ?? this.responderId,
      responderName: responderName ?? this.responderName,
      responderPhone: responderPhone ?? this.responderPhone,
      estimatedArrivalMinutes:
          estimatedArrivalMinutes ?? this.estimatedArrivalMinutes,
      isOfflineQueued: isOfflineQueued ?? this.isOfflineQueued,
      syncedAt: syncedAt ?? this.syncedAt,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      responderLat: responderLat ?? this.responderLat,
      responderLng: responderLng ?? this.responderLng,
    );
  }

  /// Creates an EmergencyRequest from a JSON map
  factory EmergencyRequest.fromJson(Map<String, dynamic> json) {
    return EmergencyRequest(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      type: _parseEmergencyType(json['type'] ?? json['emergency_type']),
      severity: EmergencySeverityExtension.fromString(
        json['severity']?.toString(),
      ),
      description: json['description'] ?? '',
      latitude: (json['latitude'] ?? json['lat'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? json['lng'] ?? 0.0).toDouble(),
      address: json['address'],
      status: _parseEmergencyStatus(json['status'] ?? json['request_status']),
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? json['created_at']) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] ?? json['updated_at']) ??
          DateTime.now(),
      patientName: json['patientName'] ?? json['patient_name'],
      patientPhone: json['patientPhone'] ?? json['patient_phone'],
      responderId: json['responderId']?.toString() ?? json['responder_id'],
      responderName: json['responderName'] ?? json['responder_name'],
      responderPhone: json['responderPhone'] ?? json['responder_phone'],
      estimatedArrivalMinutes:
          json['estimatedArrivalMinutes']?.toInt() ??
          json['estimated_arrival_minutes']?.toInt(),
      isOfflineQueued:
          json['isOfflineQueued'] ?? json['is_offline_queued'] ?? false,
      syncedAt: json['syncedAt'] != null
          ? DateTime.tryParse(json['syncedAt'])
          : null,
      medicalHistory:
          json['medicalHistory'] ?? json['medical_history'],
      responderLat: (json['responderLat'] ?? json['responder_lat'])?.toDouble(),
      responderLng: (json['responderLng'] ?? json['responder_lng'])?.toDouble(),
    );
  }

  /// Converts the model to a JSON map for API requests
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type.apiValue,
      'severity': severity.apiValue,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (responderId != null) 'responderId': responderId,
      if (patientName != null) 'patientName': patientName,
      if (patientPhone != null) 'patientPhone': patientPhone,
      if (responderName != null) 'responderName': responderName,
      if (responderPhone != null) 'responderPhone': responderPhone,
      if (estimatedArrivalMinutes != null)
        'estimatedArrivalMinutes': estimatedArrivalMinutes,
      'is_offline_queued': isOfflineQueued ? 1 : 0,
      if (syncedAt != null) 'syncedAt': syncedAt!.toIso8601String(),
      if (medicalHistory != null) 'medicalHistory': medicalHistory,
      if (responderLat != null) 'responderLat': responderLat,
      if (responderLng != null) 'responderLng': responderLng,
    };
  }

  /// Converts the model to a database map for SQLite storage
  Map<String, dynamic> toDatabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.apiValue,
      'severity': severity.apiValue,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (responderId != null) 'responder_id': responderId,
      if (responderName != null) 'responder_name': responderName,
      if (responderPhone != null) 'responder_phone': responderPhone,
      if (estimatedArrivalMinutes != null)
        'estimated_arrival_minutes': estimatedArrivalMinutes,
      'is_offline_queued': isOfflineQueued ? 1 : 0,
      if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
      if (medicalHistory != null) 'medical_history': medicalHistory,
      if (responderLat != null) 'responder_lat': responderLat,
      if (responderLng != null) 'responder_lng': responderLng,
    };
  }

  /// Creates an EmergencyRequest from database map
  factory EmergencyRequest.fromDatabaseMap(Map<String, dynamic> map) {
    return EmergencyRequest(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      type: _parseEmergencyType(map['type'] ?? ''),
      severity: EmergencySeverityExtension.fromString(
        map['severity']?.toString(),
      ),
      description: map['description'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      address: map['address'],
      status: _parseEmergencyStatus(map['status'] ?? ''),
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
      patientName: map['patient_name'],
      patientPhone: map['patient_phone'],
      responderId: map['responder_id']?.toString(),
      responderName: map['responder_name'],
      responderPhone: map['responder_phone'],
      estimatedArrivalMinutes: map['estimated_arrival_minutes']?.toInt(),
      isOfflineQueued: (map['is_offline_queued'] ?? 0) == 1,
      syncedAt: map['synced_at'] != null
          ? DateTime.tryParse(map['synced_at'])
          : null,
      medicalHistory: map['medical_history'],
      responderLat: (map['responder_lat'] as num?)?.toDouble(),
      responderLng: (map['responder_lng'] as num?)?.toDouble(),
    );
  }

  // ── Parsers ────────────────────────────────────────────────────────────────

  static EmergencyType _parseEmergencyType(String? typeString) {
    switch ((typeString ?? '').toLowerCase()) {
      case 'medical':
        return EmergencyType.medical;
      case 'accident':
        return EmergencyType.accident;
      case 'cardiac':
        return EmergencyType.cardiac;
      case 'stroke':
        return EmergencyType.stroke;
      case 'trauma':
        return EmergencyType.trauma;
      case 'heartattack':
        return EmergencyType.heartAttack;
      case 'severebleed':
        return EmergencyType.severeBleed;
      case 'breathingdifficulty':
        return EmergencyType.breathingDifficulty;
      case 'unconscious':
        return EmergencyType.unconscious;
      case 'choking':
        return EmergencyType.choking;
      case 'allergicreaction':
        return EmergencyType.allergicReaction;
      case 'seizure':
        return EmergencyType.seizure;
      case 'maternal':
        return EmergencyType.maternal;
      case 'other':
      default:
        return EmergencyType.other;
    }
  }

  static EmergencyStatus _parseEmergencyStatus(String? statusString) {
    switch ((statusString ?? '').toLowerCase()) {
      case 'pending':
        return EmergencyStatus.pending;
      case 'accepted':
        return EmergencyStatus.accepted;
      case 'in_progress':
      case 'inprogress':
        return EmergencyStatus.inProgress;
      case 'completed':
        return EmergencyStatus.completed;
      case 'cancelled':
        return EmergencyStatus.cancelled;
      case 'expired':
        return EmergencyStatus.expired;
      default:
        return EmergencyStatus.pending;
    }
  }

  // ── Computed properties ────────────────────────────────────────────────────

  String get typeDisplayName => type.typeDisplayName;

  /// Gets the display name for emergency status
  String get statusDisplayName {
    switch (status) {
      case EmergencyStatus.pending:
        return 'Pending';
      case EmergencyStatus.accepted:
        return 'Accepted';
      case EmergencyStatus.inProgress:
        return 'In Progress';
      case EmergencyStatus.completed:
        return 'Completed';
      case EmergencyStatus.cancelled:
        return 'Cancelled';
      case EmergencyStatus.expired:
        return 'Expired';
    }
  }

  /// Checks if the request is active (not completed, cancelled, or expired)
  bool get isActive {
    return status == EmergencyStatus.pending ||
        status == EmergencyStatus.accepted ||
        status == EmergencyStatus.inProgress;
  }

  /// Checks if the request has been assigned to a responder
  bool get hasResponder {
    return responderId != null && responderId!.isNotEmpty;
  }

  bool get hasResponderPhone {
    return responderPhone != null && responderPhone!.trim().isNotEmpty;
  }

  /// Decoded medical history map (convenience getter).
  Map<String, dynamic>? get medicalHistoryMap {
    if (medicalHistory == null || medicalHistory!.isEmpty) return null;
    try {
      return jsonDecode(medicalHistory!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Gets the estimated arrival time as a formatted string
  String get estimatedArrivalText {
    if (estimatedArrivalMinutes == null) return 'Unknown';

    if (estimatedArrivalMinutes! <= 1) {
      return 'Arriving now';
    } else if (estimatedArrivalMinutes! <= 60) {
      return '$estimatedArrivalMinutes min';
    } else {
      final hours = estimatedArrivalMinutes! ~/ 60;
      final minutes = estimatedArrivalMinutes! % 60;
      return '${hours}h ${minutes}min';
    }
  }

  /// Gets the Google Maps URL for the location
  String get mapsUrl {
    return 'https://maps.google.com/?q=$latitude,$longitude';
  }

  /// Gets the time since creation as a formatted string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  String toString() {
    return 'EmergencyRequest(id: $id, type: $typeDisplayName, severity: ${severity.displayName}, status: $statusDisplayName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmergencyRequest &&
        other.id == id &&
        other.userId == userId &&
        other.type == type &&
        other.status == status;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ type.hashCode ^ status.hashCode;
  }
}
