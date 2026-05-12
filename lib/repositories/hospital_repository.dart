import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/hospital_model.dart';

/// Custom exceptions for hospital operations
class HospitalException implements Exception {
  final String message;
  final int? statusCode;
  
  HospitalException(this.message, [this.statusCode]);
  
  @override
  String toString() => 'HospitalException: $message';
}

class NetworkException extends HospitalException {
  NetworkException(String message) : super(message);
}

/// Repository class that handles hospital-related API calls
/// 
/// Provides methods for fetching hospital data from internal API and Google Places API
/// for the Mobile Emergency Medical Assistance App.
class HospitalRepository {
  static const String _baseUrlKey = 'BASE_API_URL';
  static const String _googleMapsKeyKey = 'GOOGLE_MAPS_KEY';
  static const Duration _timeout = Duration(seconds: 15);
  
  /// Gets the base API URL from environment configuration
  static String get _baseUrl => dotenv.env[_baseUrlKey] ?? 'https://api.memaap.com';
  
  /// Gets the Google Maps API key from environment configuration
  static String get _googleMapsKey => dotenv.env[_googleMapsKeyKey] ?? '';

  /// Fetches nearby hospitals from internal API
  /// 
  /// [lat] - Latitude of search center
  /// [lng] - Longitude of search center
  /// [radiusKm] - Search radius in kilometers
  /// 
  /// Returns a list of HospitalModel objects
  /// 
  /// Throws [HospitalException] if API call fails
  static Future<List<HospitalModel>> getNearbyHospitalsFromAPI(
    double lat,
    double lng, {
    double radiusKm = 10.0,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/hospitals/nearby'
                '?lat=$lat'
                '&lng=$lng'
                '&radius=$radiusKm'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          final hospitalsData = responseData['hospitals'] as List? ?? [];
          return hospitalsData
              .map((hospital) => HospitalModel.fromJson(hospital))
              .toList();
        case 404:
          return []; // No hospitals found
        default:
          throw HospitalException(
            responseData['message'] ?? 'Failed to fetch hospitals',
            response.statusCode,
          );
      }
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is HospitalException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Fetches nearby hospitals from Google Places API
  /// 
  /// [lat] - Latitude of search center
  /// [lng] - Longitude of search center
  /// [radiusKm] - Search radius in kilometers
  /// 
  /// Returns a list of HospitalModel objects
  /// 
  /// Throws [HospitalException] if API call fails
  static Future<List<HospitalModel>> getNearbyHospitalsFromGooglePlaces(
    double lat,
    double lng, {
    double radiusKm = 10.0,
  }) async {
    if (_googleMapsKey.isEmpty) {
      throw HospitalException('Google Maps API key not configured');
    }

    try {
      final radiusMeters = (radiusKm * 1000).round();
      final response = await http
          .get(
            Uri.parse('https://maps.googleapis.com/maps/api/place/nearbysearch/json'
                '?location=$lat,$lng'
                '&radius=$radiusMeters'
                '&type=hospital'
                '&key=$_googleMapsKey'),
            headers: {
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (responseData['status'] != 'OK') {
        throw HospitalException(
          'Google Places API error: ${responseData['status']}',
        );
      }

      final places = responseData['results'] as List? ?? [];
      
      return places
          .map((place) => HospitalModel.fromGooglePlaces(place, lat, lng))
          .where((hospital) => hospital.isWithinRadius(radiusKm))
          .toList();
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is HospitalException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Searches hospitals by name or address
  /// 
  /// [query] - Search query
  /// [lat] - Optional latitude for location-based search
  /// [lng] - Optional longitude for location-based search
  /// 
  /// Returns a list of HospitalModel objects
  static Future<List<HospitalModel>> searchHospitals(
    String query, {
    double? lat,
    double? lng,
  }) async {
    try {
      String url = '$_baseUrl/hospitals/search?q=${Uri.encodeComponent(query)}';
      if (lat != null && lng != null) {
        url += '&lat=$lat&lng=$lng';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          final hospitalsData = responseData['hospitals'] as List? ?? [];
          return hospitalsData
              .map((hospital) => HospitalModel.fromJson(hospital))
              .toList();
        case 404:
          return [];
        default:
          throw HospitalException(
            responseData['message'] ?? 'Failed to search hospitals',
            response.statusCode,
          );
      }
    } catch (e) {
      if (e is HospitalException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Gets detailed information about a specific hospital
  /// 
  /// [hospitalId] - ID of the hospital
  /// 
  /// Returns a HospitalModel object
  static Future<HospitalModel> getHospitalDetails(String hospitalId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/hospitals/$hospitalId'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          return HospitalModel.fromJson(responseData['hospital']);
        case 404:
          throw HospitalException('Hospital not found', 404);
        default:
          throw HospitalException(
            responseData['message'] ?? 'Failed to fetch hospital details',
            response.statusCode,
          );
      }
    } catch (e) {
      if (e is HospitalException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Reports hospital availability status
  /// 
  /// [hospitalId] - ID of the hospital
  /// [isAvailable] - Current availability status
  /// [token] - Authentication token
  static Future<void> reportHospitalAvailability(
    String hospitalId,
    bool isAvailable,
    String token,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/hospitals/$hospitalId/availability'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'isAvailable': isAvailable,
              'reportedAt': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final responseData = jsonDecode(response.body);
        throw HospitalException(
          responseData['message'] ?? 'Failed to report availability',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is HospitalException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Gets hospital availability history
  /// 
  /// [hospitalId] - ID of the hospital
  /// [days] - Number of days to look back (default: 7)
  static Future<List<Map<String, dynamic>>> getHospitalAvailabilityHistory(
    String hospitalId, {
    int days = 7,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/hospitals/$hospitalId/availability?days=$days'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          return List<Map<String, dynamic>>.from(responseData['history'] ?? []);
        default:
          throw HospitalException(
            responseData['message'] ?? 'Failed to fetch availability history',
            response.statusCode,
          );
      }
    } catch (e) {
      if (e is HospitalException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }
}
