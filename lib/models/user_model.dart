import 'dart:convert';

enum ResponderAvailability {
  available,
  busy,
  offline,
  onBreak,
  inTransit,
}

extension ResponderAvailabilityExtension on ResponderAvailability {
  String get apiValue {
    switch (this) {
      case ResponderAvailability.available:
        return 'available';
      case ResponderAvailability.busy:
        return 'busy';
      case ResponderAvailability.offline:
        return 'offline';
      case ResponderAvailability.onBreak:
        return 'on_break';
      case ResponderAvailability.inTransit:
        return 'in_transit';
    }
  }

  static ResponderAvailability fromString(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'available':
        return ResponderAvailability.available;
      case 'busy':
        return ResponderAvailability.busy;
      case 'on_break':
        return ResponderAvailability.onBreak;
      case 'in_transit':
        return ResponderAvailability.inTransit;
      case 'offline':
      default:
        return ResponderAvailability.offline;
    }
  }
}

/// Contact entry stored in emergency contacts list.
class EmergencyContact {
  final String name;
  final String phone;

  const EmergencyContact({required this.name, required this.phone});

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  @override
  String toString() => 'EmergencyContact(name: $name, phone: $phone)';
}

/// Model class for user data
/// 
/// Represents a user in the Mobile Emergency Medical Assistance App
/// with their profile information, medical history, emergency contacts, and role.
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final ResponderAvailability availability;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Medical profile fields ─────────────────────────────────────────────────
  final String? bloodType;
  final List<String> medicalConditions;
  final List<String> allergies;
  final List<String> medications;

  // ── Emergency contacts ─────────────────────────────────────────────────────
  final List<EmergencyContact> emergencyContacts;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.availability = ResponderAvailability.offline,
    this.lastLatitude,
    this.lastLongitude,
    required this.createdAt,
    required this.updatedAt,
    this.bloodType,
    this.medicalConditions = const [],
    this.allergies = const [],
    this.medications = const [],
    this.emergencyContacts = const [],
  });

  /// Creates a copy of this model with updated values
  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    ResponderAvailability? availability,
    double? lastLatitude,
    double? lastLongitude,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? bloodType,
    List<String>? medicalConditions,
    List<String>? allergies,
    List<String>? medications,
    List<EmergencyContact>? emergencyContacts,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      availability: availability ?? this.availability,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      bloodType: bloodType ?? this.bloodType,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
    );
  }

  /// Creates a UserModel from a JSON map
  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String> _parseStringList(dynamic value) {
      if (value == null) return [];
      if (value is List) return value.cast<String>();
      if (value is String && value.isNotEmpty) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) return decoded.cast<String>();
        } catch (_) {}
      }
      return [];
    }

    List<EmergencyContact> _parseContacts(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value
            .whereType<Map<String, dynamic>>()
            .map(EmergencyContact.fromJson)
            .toList();
      }
      if (value is String && value.isNotEmpty) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) {
            return decoded
                .whereType<Map<String, dynamic>>()
                .map(EmergencyContact.fromJson)
                .toList();
          }
        } catch (_) {}
      }
      return [];
    }

    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      role: json['role'] ?? 'patient',
      availability: ResponderAvailabilityExtension.fromString(
        json['availability']?.toString(),
      ),
      lastLatitude: (json['last_latitude'] as num?)?.toDouble(),
      lastLongitude: (json['last_longitude'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      bloodType: json['blood_type'] ?? json['bloodType'],
      medicalConditions: _parseStringList(
        json['medical_conditions'] ?? json['medicalConditions'],
      ),
      allergies: _parseStringList(json['allergies']),
      medications: _parseStringList(json['medications']),
      emergencyContacts: _parseContacts(
        json['emergency_contacts'] ?? json['emergencyContacts'],
      ),
    );
  }

  /// Converts the model to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      if (email != null) 'email': email,
      'role': role,
      'availability': availability.apiValue,
      if (lastLatitude != null) 'last_latitude': lastLatitude,
      if (lastLongitude != null) 'last_longitude': lastLongitude,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (bloodType != null) 'blood_type': bloodType,
      if (medicalConditions.isNotEmpty)
        'medical_conditions': medicalConditions,
      if (allergies.isNotEmpty) 'allergies': allergies,
      if (medications.isNotEmpty) 'medications': medications,
      if (emergencyContacts.isNotEmpty)
        'emergency_contacts':
            emergencyContacts.map((c) => c.toJson()).toList(),
    };
  }

  /// Serialises medical history into a compact JSON string for storing in
  /// emergency request records (to be seen by responders).
  String? buildMedicalHistoryJson() {
    final hasMedical = bloodType != null ||
        medicalConditions.isNotEmpty ||
        allergies.isNotEmpty ||
        medications.isNotEmpty;
    if (!hasMedical) return null;

    return jsonEncode({
      if (bloodType != null) 'bloodType': bloodType,
      if (medicalConditions.isNotEmpty) 'conditions': medicalConditions,
      if (allergies.isNotEmpty) 'allergies': allergies,
      if (medications.isNotEmpty) 'medications': medications,
    });
  }

  /// Checks if the user is a patient
  bool get isPatient => role == 'patient';

  /// Checks if the user is a responder
  bool get isResponder => role == 'responder';

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, phone: $phone, role: $role)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel &&
        other.id == id &&
        other.name == name &&
        other.phone == phone &&
        other.email == email &&
        other.role == role;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        phone.hashCode ^
        email.hashCode ^
        role.hashCode;
  }
}
