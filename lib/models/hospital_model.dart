import 'dart:math' as math;

/// Model class for hospital data
/// 
/// Represents a hospital in the Mobile Emergency Medical Assistance App
/// with location information and availability status.
class HospitalModel {
  final String id;
  final String name;
  final String address;
  final String? phone;
  final double lat;
  final double lng;
  final double distanceKm;
  final bool isAvailable;
  final DateTime? cachedAt;

  HospitalModel({
    required this.id,
    required this.name,
    required this.address,
    this.phone,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.isAvailable,
    this.cachedAt,
  });

  /// Creates a copy of this model with updated values
  HospitalModel copyWith({
    String? id,
    String? name,
    String? address,
    String? phone,
    double? lat,
    double? lng,
    double? distanceKm,
    bool? isAvailable,
    DateTime? cachedAt,
  }) {
    return HospitalModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      distanceKm: distanceKm ?? this.distanceKm,
      isAvailable: isAvailable ?? this.isAvailable,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  /// Creates a HospitalModel from a JSON map
  factory HospitalModel.fromJson(Map<String, dynamic> json) {
    return HospitalModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      phone: json['phone'],
      lat: (json['lat'] ?? json['latitude'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? json['longitude'] ?? 0.0).toDouble(),
      distanceKm: (json['distanceKm'] ?? json['distance_km'] ?? 0.0).toDouble(),
      isAvailable: json['isAvailable'] ?? json['is_available'] ?? true,
      cachedAt: json['cachedAt'] != null 
          ? DateTime.tryParse(json['cachedAt']) 
          : null,
    );
  }

  /// Creates a HospitalModel from Google Places API response
  factory HospitalModel.fromGooglePlaces(Map<String, dynamic> place, double userLat, double userLng) {
    final location = place['geometry']['location'];
    final lat = location['lat']?.toDouble() ?? 0.0;
    final lng = location['lng']?.toDouble() ?? 0.0;
    final distance = _calculateDistance(userLat, userLng, lat, lng);

    return HospitalModel(
      id: place['place_id'] ?? '',
      name: place['name'] ?? '',
      address: place['vicinity'] ?? '',
      phone: place['formatted_phone_number'],
      lat: lat,
      lng: lng,
      distanceKm: distance,
      isAvailable: place['business_status'] == 'OPERATIONAL',
    );
  }

  /// Converts the model to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      if (phone != null) 'phone': phone,
      'lat': lat,
      'lng': lng,
      'distanceKm': distanceKm,
      'isAvailable': isAvailable,
      if (cachedAt != null) 'cachedAt': cachedAt!.toIso8601String(),
    };
  }

  /// Converts the model to a database map for SQLite storage
  Map<String, dynamic> toDatabaseMap() {
    return {
      'id': id,
      'name': name,
      'latitude': lat,
      'longitude': lng,
      'address': address,
      'phone': phone,
      'emergency_services': isAvailable ? 1 : 0,
      'cached_at': cachedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Creates a HospitalModel from database map
  factory HospitalModel.fromDatabaseMap(Map<String, dynamic> map) {
    return HospitalModel(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      phone: map['phone'],
      lat: (map['latitude'] ?? 0.0).toDouble(),
      lng: (map['longitude'] ?? 0.0).toDouble(),
      distanceKm: 0.0, // Distance calculated separately
      isAvailable: (map['emergency_services'] ?? 1) == 1,
      cachedAt: map['cached_at'] != null 
          ? DateTime.tryParse(map['cached_at']) 
          : null,
    );
  }

  /// Calculates distance between two coordinates using Haversine formula
  static double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);

    final double a = 
        (dLat / 2).sin() * (dLat / 2).sin() +
        lat1.toRadians().cos() * lat2.toRadians().cos() *
        (dLng / 2).sin() * (dLng / 2).sin();

    final double c = 2 * a.sqrt().asin();
    return earthRadius * c;
  }

  /// Converts degrees to radians
  static double _toRadians(double degrees) {
    return degrees * (3.14159265359 / 180);
  }

  /// Updates the distance from a user location
  HospitalModel withDistanceFrom(double userLat, double userLng) {
    return copyWith(
      distanceKm: _calculateDistance(userLat, userLng, lat, lng),
    );
  }

  /// Gets the distance as a formatted string
  String get distanceText {
    if (distanceKm < 1.0) {
      return '${(distanceKm * 1000).round()}m away';
    } else {
      return '${distanceKm.toStringAsFixed(1)}km away';
    }
  }

  /// Checks if the hospital is within a given radius
  bool isWithinRadius(double radiusKm) {
    return distanceKm <= radiusKm;
  }

  @override
  String toString() {
    return 'HospitalModel(id: $id, name: $name, address: $address, distance: ${distanceText})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HospitalModel &&
        other.id == id &&
        other.name == name &&
        other.address == address &&
        other.lat == lat &&
        other.lng == lng;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        address.hashCode ^
        lat.hashCode ^
        lng.hashCode;
  }
}

/// Extension on double for math operations
extension DoubleExtension on double {
  double toRadians() => this * (3.14159265359 / 180);
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double asin() => math.asin(this);
  double sqrt() => math.sqrt(this);
}

