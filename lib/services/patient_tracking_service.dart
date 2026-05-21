import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/emergency_request_model.dart';
import '../repositories/emergency_repository.dart';
import '../controllers/map_controller.dart';

/// Service class for tracking patient location
/// 
/// Provides live tracking with route drawing, ETA calculation,
/// and position updates for Mobile Emergency Medical Assistance App.
class PatientTrackingService {
  static const Duration _refreshInterval = Duration(seconds: 10);
  static const Duration _staleLocationThreshold = Duration(minutes: 2);
  
  static StreamSubscription<Position>? _locationSubscription;
  static Position? _lastKnownPosition;
  static DateTime? _lastUpdateTime;
  static Timer? _refreshTimer;

  /// Views patient location with live tracking
  /// 
  /// [requestId] - Emergency request ID
  /// [mapController] - Map controller for drawing
  /// 
  /// Returns true if tracking was started successfully
  static Future<bool> viewPatientLocation(
    String requestId,
    MapController mapController,
  ) async {
    try {
      // Get request details
      final request = await EmergencyRepository.getRequestById(requestId);
      if (request == null) {
        debugPrint('Request not found: $requestId');
        return false;
      }

      // Get responder current location
      final responderPosition = await _getResponderCurrentLocation();
      if (responderPosition == null) {
        debugPrint('Responder location not available');
        return false;
      }

      // Add markers for patient and responder
      await _addTrackingMarkers(mapController, request, responderPosition);

      // Draw route between responder and patient
      await _drawRoute(mapController, responderPosition, request);

      // Start live position updates
      await _startPositionUpdates(mapController, request, responderPosition);

      // Start periodic route refresh
      _startRouteRefresh(mapController, request, responderPosition);

      return true;

    } catch (e) {
      debugPrint('Failed to start patient tracking: $e');
      return false;
    }
  }

  /// Gets responder's current location
  static Future<Position?> _getResponderCurrentLocation() async {
    try {
      // This would get the logged-in responder's location
      // For now, we'll return a mock position
      // In production, you'd get this from your auth service or GPS
      return Position(
        latitude: -13.9893, // Blantyre, Malawi
        longitude: 33.7741,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        isMocked: false,
      );
    } catch (e) {
      debugPrint('Failed to get responder location: $e');
      return null;
    }
  }

  /// Adds tracking markers to map
  static Future<void> _addTrackingMarkers(
    MapController mapController,
    EmergencyRequest request,
    Position responderPosition,
  ) async {
    try {
      // Add patient marker (red)
      await mapController.addMarker(
        id: 'patient_${request.id}',
        position: LatLng(request.latitude, request.longitude),
        iconType: 'patient',
        infoTitle: 'Patient Location',
        infoSnippet: request.typeDisplayName,
      );

      // Add responder marker (ambulance)
      await mapController.addMarker(
        id: 'responder_${request.responderId ?? 'unknown'}',
        position: LatLng(responderPosition.latitude, responderPosition.longitude),
        iconType: 'ambulance',
        infoTitle: 'Responder Location',
        infoSnippet: 'GPS Tracking Active',
      );

    } catch (e) {
      debugPrint('Failed to add tracking markers: $e');
    }
  }

  /// Draws route between responder and patient
  static Future<void> _drawRoute(
    MapController mapController,
    Position responderPosition,
    EmergencyRequest request,
  ) async {
    try {
      final patientPosition = LatLng(request.latitude, request.longitude);
      final responderLatLng = LatLng(responderPosition.latitude, responderPosition.longitude);

      // Clear existing route
      mapController.clearRoute();

      // Draw new route
      await mapController.drawRoute(
        responderLatLng,
        patientPosition,
        routeId: 'route_${request.id}',
        color: Colors.blue,
        width: 4.0,
      );

    } catch (e) {
      debugPrint('Failed to draw route: $e');
    }
  }

  /// Starts live position updates for patient
  static Future<void> _startPositionUpdates(
    MapController mapController,
    EmergencyRequest request,
    Position responderPosition,
  ) async {
    try {
      // Cancel existing subscription
      await _locationSubscription?.cancel();

      // Start listening for patient location updates
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen(
        (position) {
          _updatePatientPosition(mapController, position);
        },
        onError: (error) {
          debugPrint('Location update error: $error');
        },
      );

      debugPrint('Started patient location tracking');
    } catch (e) {
      debugPrint('Failed to start position updates: $e');
    }
  }

  /// Updates patient position on map
  static Future<void> _updatePatientPosition(
    MapController mapController,
    Position position,
  ) async {
    try {
      _lastKnownPosition = position;
      _lastUpdateTime = DateTime.now();

      // Update patient marker
      mapController.updateMarkerPosition(
        'patient_${_getRequestIdFromMap(mapController)}',
        LatLng(position.latitude, position.longitude),
      );

      // Update route if responder is available
      final responderPosition = await _getResponderCurrentLocation();
      if (responderPosition != null) {
        await _drawRoute(mapController, responderPosition!, _getEmergencyRequestFromMap(mapController));
      }

    } catch (e) {
      debugPrint('Failed to update patient position: $e');
    }
  }

  /// Starts periodic route refresh
  static void _startRouteRefresh(
    MapController mapController,
    EmergencyRequest request,
    Position responderPosition,
  ) {
    _refreshTimer?.cancel();
    
    _refreshTimer = Timer.periodic(_refreshInterval, (timer) async {
      try {
        // Check if patient location is stale
        if (_lastUpdateTime != null && 
            DateTime.now().difference(_lastUpdateTime!) > _staleLocationThreshold) {
          debugPrint('Patient location is stale, refreshing route');
          await _drawRoute(mapController, responderPosition, request);
        }
      } catch (e) {
        debugPrint('Route refresh error: $e');
      }
    });
  }

  /// Calculates ETA from responder to patient
  static Duration _calculateETA(Position responderPosition, Position patientPosition) {
    final distance = Geolocator.distanceBetween(
      responderPosition.latitude,
      responderPosition.longitude,
      patientPosition.latitude,
      patientPosition.longitude,
    );

    // Assume average speed of 30 km/h for emergency vehicles
    const averageSpeed = 30.0; // km/h
    const speedInMetersPerSecond = (averageSpeed * 1000) / 3600;

    final etaSeconds = distance / speedInMetersPerSecond;
    return Duration(seconds: etaSeconds.round());
  }

  /// Gets ETA as formatted string
  static String _formatETA(Duration eta) {
    if (eta.inMinutes <= 1) {
      return 'Arriving now';
    } else if (eta.inMinutes < 60) {
      return '${eta.inMinutes} min';
    } else {
      final hours = eta.inHours;
      final minutes = eta.inMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }

  /// Shows ETA information panel
  static Widget _buildETAPanel(Position responderPosition, EmergencyRequest request) {
    if (_lastKnownPosition == null) return const SizedBox.shrink();

    final eta = _calculateETA(responderPosition, _lastKnownPosition!);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Estimated Arrival',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatETA(eta),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Distance: ${(Geolocator.distanceBetween(
              responderPosition.latitude,
              responderPosition.longitude,
              _lastKnownPosition!.latitude,
              _lastKnownPosition!.longitude,
            ) / 1000).toStringAsFixed(1)} km',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          if (_lastUpdateTime != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated: ${_formatTime(_lastUpdateTime!)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
          // Warning for stale location
          if (_lastUpdateTime != null && 
              DateTime.now().difference(_lastUpdateTime!) > _staleLocationThreshold) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Location data may be outdated',
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Formats time for display
  static String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Extracts request ID from map controller
  static String _getRequestIdFromMap(MapController mapController) {
    // This would extract the request ID from the map's current context
    // For now, we'll return a mock ID
    return 'request_123';
  }

  /// Extracts emergency request from map controller
  static EmergencyRequest _getEmergencyRequestFromMap(MapController mapController) {
    // This would get the current request from the map's context
    // For now, we'll return a mock request
    return EmergencyRequest(
      id: 'request_123',
      userId: 'patient_456',
      type: EmergencyType.medical,
      description: 'Medical emergency',
      latitude: -13.9893,
      longitude: 33.7741,
      status: EmergencyStatus.accepted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Stops patient tracking
  static Future<void> stopTracking() async {
    try {
      await _locationSubscription?.cancel();
      _refreshTimer?.cancel();
      
      debugPrint('Patient tracking stopped');
    } catch (e) {
      debugPrint('Failed to stop patient tracking: $e');
    }
  }

  /// Gets current tracking status
  static Map<String, dynamic> getTrackingStatus() {
    return {
      'isTracking': _locationSubscription != null,
      'lastPosition': _lastKnownPosition != null 
          ? {
              'latitude': _lastKnownPosition!.latitude,
              'longitude': _lastKnownPosition!.longitude,
              'timestamp': _lastUpdateTime!.toIso8601String(),
            }
          : null,
      'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
    };
  }
}
