import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Custom exceptions for location services
class LocationException implements Exception {
  final String message;
  final LocationExceptionType type;
  
  LocationException(this.message, [this.type = LocationExceptionType.unknown]);
  
  @override
  String toString() => 'LocationException: $message';
}

enum LocationExceptionType {
  permissionDenied,
  permissionPermanentlyDenied,
  locationDisabled,
  timeout,
  unknown,
}

/// Service class that manages GPS permission requests, real-time location streaming,
/// geocoding, and background location updates with battery-aware frequency.
/// 
/// Provides comprehensive location management for the Mobile Emergency Medical Assistance App.
class LocationService {
  static const String _lastLocationKey = 'last_known_location';
  static const String _locationPermissionKey = 'location_permission_status';
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const int _defaultDistanceFilter = 10; // meters
  
  static StreamSubscription<Position>? _positionStreamSubscription;
  static Position? _lastKnownPosition;
  static bool _isUpdating = false;

  /// Requests location permission from the user
  /// 
  /// Returns true if permission is granted, false otherwise
  /// 
  /// Throws [LocationException] if permission is permanently denied
  static Future<bool> requestPermission() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw LocationException(
          'Location services are disabled. Please enable location services.',
          LocationExceptionType.locationDisabled,
        );
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();
        
        if (permission == LocationPermission.denied) {
          await _savePermissionStatus('denied');
          throw LocationException(
            'Location permission denied. Please enable location access.',
            LocationExceptionType.permissionDenied,
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _savePermissionStatus('permanently_denied');
        throw LocationException(
          'Location permission permanently denied. Please enable location access in app settings.',
          LocationExceptionType.permissionPermanentlyDenied,
        );
      }

      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        await _savePermissionStatus('granted');
        return true;
      }

      return false;
    } catch (e) {
      if (e is LocationException) rethrow;
      throw LocationException('Failed to request location permission: $e');
    }
  }

  /// Gets the current device location
  /// 
  /// [accuracy] - Desired accuracy level (default: high)
  /// [timeout] - Maximum time to wait for location (default: 30 seconds)
  /// 
  /// Returns => current Position
  /// 
  /// Throws [LocationException] if location cannot be determined
  static Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeout,
  }) async {
    try {
      // Ensure permission is granted
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        throw LocationException('Location permission not granted');
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout ?? _defaultTimeout,
      );

      // Cache last known location
      await _cacheLastKnownLocation(position);
      _lastKnownPosition = position;

      return position;
    } on LocationException {
      rethrow;
    } on TimeoutException {
      // Try to return cached location if available
      final cachedLocation = await getCachedLocation();
      if (cachedLocation != null) {
        return cachedLocation;
      }
      throw LocationException(
        'Location request timed out',
        LocationExceptionType.timeout,
      );
    } catch (e) {
      // Try to return cached location if available
      final cachedLocation = await getCachedLocation();
      if (cachedLocation != null) {
        return cachedLocation;
      }
      throw LocationException('Failed to get current location: $e');
    }
  }

  /// Gets a stream of location updates
  /// 
  /// [distanceFilter] - Minimum distance between updates in meters (default: 10)
  /// [accuracy] - Desired accuracy level (default: high)
  /// 
  /// Returns a Stream of Position objects
  /// 
  /// Throws [LocationException] if stream cannot be created
  static Stream<Position> getLocationStream({
    int distanceFilter = _defaultDistanceFilter,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    ).handleError((error) {
      throw LocationException('Location stream error: $error');
    });
  }

  /// Starts location updates in background
  /// 
  /// [distanceFilter] - Minimum distance between updates in meters
  /// [callback] - Callback function for location updates
  /// 
  /// Returns true if updates started successfully
  static Future<bool> startLocationUpdates({
    int distanceFilter = _defaultDistanceFilter,
    required Function(Position) callback,
  }) async {
    try {
      if (_isUpdating) {
        return true; // Already updating
      }

      // Ensure permission is granted
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        throw LocationException('Location permission not granted');
      }

      // Cancel existing subscription
      await stopLocationUpdates();

      // Start new subscription
      _positionStreamSubscription = getLocationStream(
        distanceFilter: distanceFilter,
      ).listen(
        (position) {
          _lastKnownPosition = position;
          _cacheLastKnownLocation(position);
          callback(position);
        },
        onError: (error) {
          throw LocationException('Location update error: $error');
        },
      );

      _isUpdating = true;
      return true;
    } catch (e) {
      throw LocationException('Failed to start location updates: $e');
    }
  }

  /// Stops location updates
  static Future<void> stopLocationUpdates() async {
    try {
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _isUpdating = false;
    } catch (e) {
      throw LocationException('Failed to stop location updates: $e');
    }
  }

  /// Converts coordinates to a human-readable address
  /// 
  /// [lat] - Latitude
  /// [lng] - Longitude
  /// 
  /// Returns a list of Placemark objects
  /// 
  /// Throws [LocationException] if geocoding fails
  static Future<List<Placemark>> getAddressFromCoords(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      return placemarks;
    } catch (e) {
      throw LocationException('Failed to get address from coordinates: $e');
    }
  }

  /// Converts an address to coordinates
  /// 
  /// [address] - Address string to geocode
  /// 
  /// Returns a list of Location objects
  /// 
  /// Throws [LocationException] if geocoding fails
  static Future<List<Location>> getCoordsFromAddress(String address) async {
    try {
      final locations = await locationFromAddress(address);
      return locations;
    } catch (e) {
      throw LocationException('Failed to get coordinates from address: $e');
    }
  }

  /// Gets the last known cached location
  /// 
  /// Returns => cached Position or null if not available
  static Future<Position?> getCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationData = prefs.getString(_lastLocationKey);
      
      if (locationData != null) {
        final parts = locationData.split(',');
        if (parts.length >= 4) {
          return Position(
            latitude: double.parse(parts[0]),
            longitude: double.parse(parts[1]),
            timestamp: DateTime.tryParse(parts[2]) ?? DateTime.now(),
            accuracy: double.parse(parts[3]),
            altitude: parts.length > 4 ? double.parse(parts[4]) : 0.0,
            altitudeAccuracy: parts.length > 5 ? (double.tryParse(parts[5]) ?? 0.0) : 0.0,
            heading: parts.length > 6 ? (double.tryParse(parts[6]) ?? 0.0) : 0.0,
            headingAccuracy: parts.length > 7 ? (double.tryParse(parts[7]) ?? 0.0) : 0.0,
            speed: parts.length > 8 ? (double.tryParse(parts[8]) ?? 0.0) : 0.0,
            speedAccuracy: parts.length > 9 ? (double.tryParse(parts[9]) ?? 0.0) : 0.0,
            floor: parts.length > 10 ? int.tryParse(parts[10]) : null,
            isMocked: parts.length > 11 ? parts[11] == 'true' : false,
          );
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Gets the last known position from memory
  static Position? get lastKnownPosition => _lastKnownPosition;

  /// Checks if location updates are currently active
  static bool get isUpdating => _isUpdating;

  /// Shows a dialog to open app settings for location permission
  /// 
  /// [context] - BuildContext for showing the dialog
  static Future<void> showLocationSettingsDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
            'Location permission is permanently denied. Please enable location access in app settings to use this feature.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () async {
                Navigator.of(context).pop();
                await _openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  /// Opens app settings
  static Future<void> _openAppSettings() async {
    if (Platform.isAndroid) {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:${AppConfig.environment}',
      );
      await intent.launch();
    } else {
      await openAppSettings();
    }
  }

  /// Caches the last known location
  static Future<void> _cacheLastKnownLocation(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationData = '${position.latitude},${position.longitude},'
          '${position.timestamp.toIso8601String()},${position.accuracy},'
          '${position.altitude},${position.altitudeAccuracy},'
          '${position.heading},${position.headingAccuracy},'
          '${position.speed},${position.speedAccuracy},'
          '${position.floor},${position.isMocked}';
      
      await prefs.setString(_lastLocationKey, locationData);
    } catch (e) {
      // Ignore caching errors
    }
  }

  /// Saves permission status
  static Future<void> _savePermissionStatus(String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_locationPermissionKey, status);
    } catch (e) {
      // Ignore saving errors
    }
  }

  /// Gets the saved permission status
  static Future<String?> getSavedPermissionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_locationPermissionKey);
    } catch (e) {
      return null;
    }
  }

  /// Calculates distance between two coordinates
  static double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Checks if location services are enabled
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Opens location settings
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Opens app settings
  static Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Disposes of location service
  static Future<void> dispose() async {
    await stopLocationUpdates();
  }
}
