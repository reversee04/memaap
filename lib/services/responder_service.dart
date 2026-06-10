import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../repositories/emergency_repository.dart';
import '../services/location_service.dart';

/// Service class for responder operations
///
/// Provides functionality for accepting emergency requests, GPS broadcasting,
/// and notification handling for Mobile Emergency Medical Assistance App.
class ResponderService {
  static BuildContext? _loadingDialogContext;

  /// Accepts an emergency request with optimistic updates
  ///
  /// [context] - BuildContext for UI interactions
  /// [requestId] - ID of emergency request to accept
  /// [responderId] - Current responder's ID
  ///
  /// Returns true if acceptance was successful
  static Future<bool> acceptEmergencyRequest(
    BuildContext context,
    String requestId,
    String responderId,
  ) async {
    try {
      // Show confirmation dialog
      final confirmed = await _showAcceptanceConfirmation(context);
      if (!confirmed) return false;

      // Show loading indicator
      _showLoadingDialog(context, 'Accepting emergency request...');

      try {
        // Step 1: Assign responder through the backend accept endpoint.
        await EmergencyRepository.assignResponder(requestId, responderId);

        // Step 2: Start GPS broadcasting
        await _startGPSBroadcasting(context, requestId);

        // Step 3: Notify patient when notification transport is available.
        await _notifyPatientOfAcceptance(requestId);

        await _dismissLoadingDialog();

        if (context.mounted) {
          _showSuccessSnackBar(context, 'Emergency request accepted!');
        }

        return true;
      } catch (e) {
        await _dismissLoadingDialog();
        if (context.mounted) {
          _showErrorSnackBar(context, 'Failed to accept emergency request');
        }

        return false;
      }
    } catch (e) {
      await _dismissLoadingDialog();
      if (context.mounted) {
        _showErrorSnackBar(context, 'An unexpected error occurred');
      }
      return false;
    }
  }

  /// Shows acceptance confirmation dialog
  static Future<bool> _showAcceptanceConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Accept Emergency Request'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emergency, color: Colors.green, size: 48),
                SizedBox(height: 16),
                Text(
                  'Are you ready to respond to this emergency request?',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'This will assign you as the primary responder and start GPS tracking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Accept'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Starts broadcasting responder's GPS location
  static Future<void> _startGPSBroadcasting(
    BuildContext context,
    String requestId,
  ) async {
    try {
      // Request location permission
      final hasPermission = await LocationService.requestPermission();
      if (!hasPermission) {
        _showErrorSnackBar(
          context,
          'Location permission required for GPS tracking',
        );
        return;
      }

      // Start location updates
      await LocationService.startLocationUpdates(
        distanceFilter: 10, // Update every 10 meters
        callback: (position) {
          // Broadcast location AND persist to local SQLite for patient tracking
          _broadcastResponderLocation(requestId, position);
        },
      );

      _showSuccessSnackBar(context, 'GPS tracking started');
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to start GPS tracking');
      debugPrint('GPS tracking error: $e');
    }
  }

  /// Broadcasts responder location via WebSocket and persists to local SQLite.
  ///
  /// Persisting to SQLite ensures the patient's polling tracker can always
  /// see the responder's current position even when WebSocket is unavailable.
  static Future<void> _broadcastResponderLocation(
    String requestId,
    Position position,
  ) async {
    try {
      debugPrint(
        'Broadcasting location for request $requestId: '
        '\${position.latitude}, \${position.longitude}',
      );

      // Persist coordinates to SQLite so the patient's TrackingScreen
      // polling loop can pick them up in real-time
      await EmergencyRepository.updateResponderLocation(
        requestId,
        position.latitude,
        position.longitude,
      );

      // TODO: Also send over WebSocket when server is available:
      // _webSocketChannel?.sink.add(jsonEncode({
      //   'type': 'responder_location_update',
      //   'requestId': requestId,
      //   'latitude': position.latitude,
      //   'longitude': position.longitude,
      //   'timestamp': DateTime.now().toIso8601String(),
      // }));
    } catch (e) {
      debugPrint('Failed to broadcast responder location: \$e');
    }
  }

  /// Notifies patient of request acceptance
  static Future<void> _notifyPatientOfAcceptance(String requestId) async {
    try {
      // Get request details to find patient ID
      final request = await EmergencyRepository.getRequestById(requestId);
      if (request == null) {
        debugPrint('Request not found: $requestId');
        return;
      }

      // Send notification to patient
      // This would use your notification service
      // For now, we'll simulate the notification
      debugPrint(
        'Notifying patient ${request.userId} of acceptance for request $requestId',
      );

      // In a real implementation:
      // await NotificationService.sendPushNotification(
      //   request.userId,
      //   'Emergency Request Accepted',
      //   'A responder has accepted your emergency request and is on the way.',
      //   {
      //     'type': 'emergency_update',
      //     'requestId': requestId,
      //     'responderId': responderId,
      //   },
      // );
    } catch (e) {
      debugPrint('Failed to notify patient: $e');
    }
  }

  /// Stops GPS broadcasting
  static Future<void> stopGPSBroadcasting() async {
    try {
      await LocationService.stopLocationUpdates();
      debugPrint('GPS broadcasting stopped');
    } catch (e) {
      debugPrint('Failed to stop GPS broadcasting: \$e');
    }
  }

  /// Gets current responder location stream
  static Stream<Position>? getLocationStream() {
    return LocationService.getLocationStream(distanceFilter: 10);
  }

  /// Updates responder availability status
  ///
  /// [responderId] - Responder's ID
  /// [isAvailable] - Availability status
  ///
  /// Returns true if update was successful
  static Future<bool> updateResponderAvailability(
    String responderId,
    bool isAvailable,
  ) async {
    try {
      Position? currentPosition;
      try {
        currentPosition = await LocationService.getCurrentLocation();
      } catch (_) {
        // Availability updates should still work even if GPS lookup fails.
      }

      await ApiClient.put(
        '/emergency/responders/$responderId/availability',
        data: {
          'availability': isAvailable ? 'available' : 'offline',
          if (currentPosition != null) 'latitude': currentPosition.latitude,
          if (currentPosition != null) 'longitude': currentPosition.longitude,
        },
      );

      return true;
    } catch (e) {
      debugPrint('Failed to update responder availability: $e');
      return false;
    }
  }

  /// Shows loading dialog
  static void _showLoadingDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        _loadingDialogContext = dialogContext;

        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _dismissLoadingDialog() async {
    final dialogContext = _loadingDialogContext;
    _loadingDialogContext = null;

    if (dialogContext != null && Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }

    await Future<void>.delayed(Duration.zero);
  }

  /// Shows success snack bar
  static void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shows error snack bar
  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
