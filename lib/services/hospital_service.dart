import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/hospital_model.dart';
import '../repositories/hospital_repository.dart';
import '../config/database_helper.dart';

/// Service class that provides hospital-related functionality with caching
/// 
/// Handles fetching nearby hospitals from backend API, falling back to Google Places API,
/// and caching results locally for 10 minutes for the Mobile Emergency Medical Assistance App.
class HospitalService {
  static const Duration _cacheDuration = Duration(minutes: 10);
  static const String _cacheKeyPrefix = 'nearby_hospitals_';
  
  static final Map<String, List<HospitalModel>> _memoryCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  /// Gets nearby hospitals within a configurable radius
  /// 
  /// [lat] - Latitude of search center
  /// [lng] - Longitude of search center
  /// [radiusKm] - Search radius in kilometers (default: 10)
  /// [forceRefresh] - Force refresh from API ignoring cache (default: false)
  /// 
  /// Returns a list of HospitalModel objects sorted by distance
  /// 
  /// Returns an empty list on total failure, never throws
  static Future<List<HospitalModel>> getNearbyHospitals(
    double lat,
    double lng, {
    double radiusKm = 10.0,
    bool forceRefresh = false,
  }) async {
    try {
      // Generate cache key based on location and radius
      final cacheKey = _generateCacheKey(lat, lng, radiusKm);
      
      // Check memory cache first
      if (!forceRefresh && _isMemoryCacheValid(cacheKey)) {
        return _memoryCache[cacheKey]!;
      }

      // Check database cache
      final cachedHospitals = await _getCachedFromDatabase(cacheKey);
      if (!forceRefresh && cachedHospitals != null) {
        // Update memory cache
        _memoryCache[cacheKey] = cachedHospitals;
        _cacheTimestamps[cacheKey] = DateTime.now();
        return cachedHospitals;
      }

      // Try internal API first
      List<HospitalModel> hospitals = [];
      
      try {
        hospitals = await HospitalRepository.getNearbyHospitalsFromAPI(
          lat,
          lng,
          radiusKm: radiusKm,
        );
        
        if (hospitals.isNotEmpty) {
          // Sort by distance and cache results
          hospitals.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
          await _cacheResults(cacheKey, hospitals);
          return hospitals;
        }
      } catch (e) {
        // Log error but continue to fallback
        debugPrint('Internal API failed: $e');
      }

      // Fallback to Google Places API
      try {
        hospitals = await HospitalRepository.getNearbyHospitalsFromGooglePlaces(
          lat,
          lng,
          radiusKm: radiusKm,
        );
        
        if (hospitals.isNotEmpty) {
          // Sort by distance and cache results
          hospitals.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
          await _cacheResults(cacheKey, hospitals);
          return hospitals;
        }
      } catch (e) {
        // Log error but continue to fallback
        debugPrint('Google Places API failed: $e');
      }

      // If both APIs failed, return empty list (never throw)
      return [];
      
    } catch (e) {
      // Catch any unexpected errors and return empty list
      debugPrint('Unexpected error in getNearbyHospitals: $e');
      return [];
    }
  }

  /// Searches hospitals by name or query
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
      final hospitals = await HospitalRepository.searchHospitals(query, lat: lat, lng: lng);
      
      // Sort by relevance/distance if location is provided
      if (lat != null && lng != null) {
        for (final hospital in hospitals) {
          hospital.withDistanceFrom(lat, lng);
        }
        hospitals.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      }
      
      return hospitals;
    } catch (e) {
      debugPrint('Error searching hospitals: $e');
      return [];
    }
  }

  /// Gets detailed information about a specific hospital
  /// 
  /// [hospitalId] - ID of the hospital
  /// 
  /// Returns a HospitalModel object or null if not found
  static Future<HospitalModel?> getHospitalDetails(String hospitalId) async {
    try {
      return await HospitalRepository.getHospitalDetails(hospitalId);
    } catch (e) {
      debugPrint('Error getting hospital details: $e');
      return null;
    }
  }

  /// Reports hospital availability status
  /// 
  /// [hospitalId] - ID of the hospital
  /// [isAvailable] - Current availability status
  /// [token] - Authentication token
  /// 
  /// Returns true if report was successful
  static Future<bool> reportHospitalAvailability(
    String hospitalId,
    bool isAvailable,
    String token,
  ) async {
    try {
      await HospitalRepository.reportHospitalAvailability(
        hospitalId,
        isAvailable,
        token,
      );
      return true;
    } catch (e) {
      debugPrint('Error reporting hospital availability: $e');
      return false;
    }
  }

  /// Gets hospital availability history
  /// 
  /// [hospitalId] - ID of the hospital
  /// [days] - Number of days to look back (default: 7)
  /// 
  /// Returns a list of availability history records
  static Future<List<Map<String, dynamic>>> getHospitalAvailabilityHistory(
    String hospitalId, {
    int days = 7,
  }) async {
    try {
      return await HospitalRepository.getHospitalAvailabilityHistory(hospitalId, days: days);
    } catch (e) {
      debugPrint('Error getting hospital availability history: $e');
      return [];
    }
  }

  /// Generates a unique cache key based on location and radius
  static String _generateCacheKey(double lat, double lng, double radiusKm) {
    // Round coordinates to 4 decimal places for cache key stability
    final roundedLat = (lat * 10000).round() / 10000;
    final roundedLng = (lng * 10000).round() / 10000;
    final roundedRadius = (radiusKm * 10).round() / 10;
    
    return '${_cacheKeyPrefix}${roundedLat}_${roundedLng}_${roundedRadius}';
  }

  /// Checks if memory cache is still valid
  static bool _isMemoryCacheValid(String cacheKey) {
    final timestamp = _cacheTimestamps[cacheKey];
    if (timestamp == null) return false;
    
    return DateTime.now().difference(timestamp) < _cacheDuration;
  }

  /// Gets cached hospitals from database
  static Future<List<HospitalModel>?> _getCachedFromDatabase(String cacheKey) async {
    try {
      final db = await DatabaseHelper().database;
      
      final results = await db.query(
        DatabaseHelper.tableCachedHospitals,
        where: 'id = ? AND cached_at > ?',
        whereArgs: [
          cacheKey,
          DateTime.now().subtract(_cacheDuration).toIso8601String(),
        ],
        orderBy: 'cached_at DESC',
      );

      if (results.isEmpty) return null;

      // Convert database results to HospitalModel objects
      final hospitals = results.map((row) {
        final hospital = HospitalModel.fromDatabaseMap(row);
        
        // Parse additional metadata from the cache key
        if (cacheKey.startsWith(_cacheKeyPrefix)) {
          final parts = cacheKey.substring(_cacheKeyPrefix.length).split('_');
          if (parts.length >= 3) {
            final centerLat = double.tryParse(parts[0]);
            final centerLng = double.tryParse(parts[1]);
            if (centerLat != null && centerLng != null) {
              return hospital.withDistanceFrom(centerLat, centerLng);
            }
          }
        }
        
        return hospital;
      }).toList();

      return hospitals;
    } catch (e) {
      debugPrint('Error getting cached hospitals from database: $e');
      return null;
    }
  }

  /// Caches hospital results in both memory and database
  static Future<void> _cacheResults(String cacheKey, List<HospitalModel> hospitals) async {
    try {
      // Update memory cache
      _memoryCache[cacheKey] = hospitals;
      _cacheTimestamps[cacheKey] = DateTime.now();

      // Update database cache
      final db = await DatabaseHelper().database;
      
      // Delete existing cache entry
      await db.delete(
        DatabaseHelper.tableCachedHospitals,
        where: 'id = ?',
        whereArgs: [cacheKey],
      );

      // Insert new cache entries
      final batch = db.batch();
      
      for (final hospital in hospitals) {
        final hospitalData = hospital.toDatabaseMap();
        hospitalData['id'] = cacheKey; // Use cache key as ID
        batch.insert(DatabaseHelper.tableCachedHospitals, hospitalData);
      }
      
      await batch.commit(noResult: true);
      
    } catch (e) {
      debugPrint('Error caching hospital results: $e');
    }
  }

  /// Clears all cached hospital data
  static Future<void> clearCache() async {
    try {
      // Clear memory cache
      _memoryCache.clear();
      _cacheTimestamps.clear();

      // Clear database cache
      final db = await DatabaseHelper().database;
      await db.delete(DatabaseHelper.tableCachedHospitals);
      
    } catch (e) {
      debugPrint('Error clearing hospital cache: $e');
    }
  }

  /// Clears expired cache entries
  static Future<void> clearExpiredCache() async {
    try {
      final now = DateTime.now();
      
      // Clear expired memory cache entries
      final expiredKeys = _cacheTimestamps.entries
          .where((entry) => now.difference(entry.value) >= _cacheDuration)
          .map((entry) => entry.key)
          .toList();
      
      for (final key in expiredKeys) {
        _memoryCache.remove(key);
        _cacheTimestamps.remove(key);
      }

      // Clear expired database cache entries
      final db = await DatabaseHelper().database;
      await db.delete(
        DatabaseHelper.tableCachedHospitals,
        where: 'cached_at < ?',
        whereArgs: [now.subtract(_cacheDuration).toIso8601String()],
      );
      
    } catch (e) {
      debugPrint('Error clearing expired hospital cache: $e');
    }
  }

  /// Gets cache statistics for debugging
  static Map<String, dynamic> getCacheStats() {
    return {
      'memoryCacheSize': _memoryCache.length,
      'validCacheEntries': _cacheTimestamps.entries
          .where((entry) => _isMemoryCacheValid(entry.key))
          .length,
      'cacheDurationMinutes': _cacheDuration.inMinutes,
    };
  }
}
