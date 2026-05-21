/// Enum for emergency types
enum EmergencyType {
  medical,
  accident,
  cardiac,
  stroke,
  trauma,
  other,
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
      case EmergencyType.other:
        return 'Other Emergency';
    }
  }
}

/// Enum for emergency request status
enum EmergencyStatus {
  pending,
  accepted,
  inProgress,
  completed,
  cancelled,
  expired,
}

/// Model class for emergency request data
/// 
/// Represents an emergency request in the Mobile Emergency Medical Assistance App
/// with location information, patient details, and status tracking.
class EmergencyRequest {
  final String id;
  final String userId;
  final EmergencyType type;
  final String description;
  final double latitude;
  final double longitude;
  final String? address;
  final EmergencyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? responderId;
  final String? responderName;
  final int? estimatedArrivalMinutes;
  final bool isOfflineQueued;
  final DateTime? syncedAt;
  /// Live responder GPS coordinates — updated by ResponderService as they move
  final double? responderLat;
  final double? responderLng;

  EmergencyRequest({
    required this.id,
    required this.userId,
    required this.type,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.responderId,
    this.responderName,
    this.estimatedArrivalMinutes,
    this.isOfflineQueued = false,
    this.syncedAt,
    this.responderLat,
    this.responderLng,
  });

  /// Creates a copy of this model with updated values
  EmergencyRequest copyWith({
    String? id,
    String? userId,
    EmergencyType? type,
    String? description,
    double? latitude,
    double? longitude,
    String? address,
    EmergencyStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? responderId,
    String? responderName,
    int? estimatedArrivalMinutes,
    bool? isOfflineQueued,
    DateTime? syncedAt,
    double? responderLat,
    double? responderLng,
  }) {
    return EmergencyRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      responderId: responderId ?? this.responderId,
      responderName: responderName ?? this.responderName,
      estimatedArrivalMinutes: estimatedArrivalMinutes ?? this.estimatedArrivalMinutes,
      isOfflineQueued: isOfflineQueued ?? this.isOfflineQueued,
      syncedAt: syncedAt ?? this.syncedAt,
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
      description: json['description'] ?? '',
      latitude: (json['latitude'] ?? json['lat'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? json['lng'] ?? 0.0).toDouble(),
      address: json['address'],
      status: _parseEmergencyStatus(json['status'] ?? json['request_status']),
      createdAt: DateTime.tryParse(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
      responderId: json['responderId']?.toString() ?? json['responder_id'],
      responderName: json['responderName'] ?? json['responder_name'],
      estimatedArrivalMinutes: json['estimatedArrivalMinutes']?.toInt() ?? json['estimated_arrival_minutes']?.toInt(),
      isOfflineQueued: json['isOfflineQueued'] ?? json['is_offline_queued'] ?? false,
      syncedAt: json['syncedAt'] != null 
          ? DateTime.tryParse(json['syncedAt']) 
          : null,
      responderLat: (json['responderLat'] ?? json['responder_lat'])?.toDouble(),
      responderLng: (json['responderLng'] ?? json['responder_lng'])?.toDouble(),
    );
  }

  /// Converts the model to a JSON map for API requests
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type.name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (responderId != null) 'responderId': responderId,
      if (responderName != null) 'responderName': responderName,
      if (estimatedArrivalMinutes != null) 'estimatedArrivalMinutes': estimatedArrivalMinutes,
      'isOfflineQueued': isOfflineQueued,
      if (syncedAt != null) 'syncedAt': syncedAt!.toIso8601String(),
      if (responderLat != null) 'responderLat': responderLat,
      if (responderLng != null) 'responderLng': responderLng,
    };
  }

  /// Converts the model to a database map for SQLite storage
  Map<String, dynamic> toDatabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (responderId != null) 'responder_id': responderId,
      if (responderName != null) 'responder_name': responderName,
      if (estimatedArrivalMinutes != null) 'estimated_arrival_minutes': estimatedArrivalMinutes,
      'is_offline_queued': isOfflineQueued ? 1 : 0,
      if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
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
      description: map['description'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      address: map['address'],
      status: _parseEmergencyStatus(map['status'] ?? ''),
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
      responderId: map['responder_id']?.toString(),
      responderName: map['responder_name'],
      estimatedArrivalMinutes: map['estimated_arrival_minutes']?.toInt(),
      isOfflineQueued: (map['is_offline_queued'] ?? 0) == 1,
      syncedAt: map['synced_at'] != null
          ? DateTime.tryParse(map['synced_at'])
          : null,
      responderLat: (map['responder_lat'] as num?)?.toDouble(),
      responderLng: (map['responder_lng'] as num?)?.toDouble(),
    );
  }

  /// Parses emergency type from string
  static EmergencyType _parseEmergencyType(String typeString) {
    switch (typeString.toLowerCase()) {
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
      case 'other':
      default:
        return EmergencyType.other;
    }
  }

  /// Parses emergency status from string
  static EmergencyStatus _parseEmergencyStatus(String statusString) {
    switch (statusString.toLowerCase()) {
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

  /// Gets the display name for emergency type
  String get typeDisplayName {
    switch (type) {
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
      case EmergencyType.other:
        return 'Other Emergency';
    }
  }

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
    return 'EmergencyRequest(id: $id, type: $typeDisplayName, status: $statusDisplayName)';
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
    return id.hashCode ^
        userId.hashCode ^
        type.hashCode ^
        status.hashCode;
  }
}
