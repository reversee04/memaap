import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import '../models/emergency_request_model.dart';
import '../models/user_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';

/// Service class for handling emergency alerts
/// 
/// Provides core functionality for creating emergency requests with GPS location,
/// user confirmation, and offline fallback for Mobile Emergency Medical Assistance App.
class EmergencyService {
  static const String _defaultDescription = 'Emergency assistance requested';

  /// Sends an emergency alert with user confirmation and GPS location
  /// 
  /// [context] - BuildContext for UI interactions
  /// [type] - Type of emergency
  /// [description] - Optional description of emergency
  /// 
  /// Returns true if alert was sent successfully
  static Future<bool> sendEmergencyAlert(
    BuildContext context,
    EmergencyType type, {
    String? description,
  }) async {
    try {
      // Step 1: Show confirmation bottom sheet
      final confirmed = await _showEmergencyConfirmation(context, type);
      if (!confirmed) return false;

      // Show loading indicator
      _showLoadingDialog(context, 'Getting your location...');

      try {
        // Step 2: Get GPS location
        final position = await LocationService.getCurrentLocation();
        
        // Step 3: Reverse geocode coordinates
        String? address;
        try {
          final placemarks = await LocationService.getAddressFromCoords(
            position.latitude,
            position.longitude,
          );
          
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            address = '${place.street}, ${place.locality}, ${place.country}';
          }
        } catch (e) {
          debugPrint('Geocoding failed: $e');
          // Continue without address
        }

        // Step 4: Build emergency request
        final user = await _getCurrentUser();
        final emergencyRequest = EmergencyRequest(
          id: '', // Will be set by API
          userId: user?.id ?? 'unknown',
          type: type,
          description: description ?? _defaultDescription,
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
          status: EmergencyStatus.pending,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Update loading dialog
        _updateLoadingDialog(context, 'Sending emergency alert...');

        // Step 5: Create request via repository
        final createdRequest = await EmergencyRepository.createRequest(emergencyRequest);

        // Close loading dialog
        Navigator.of(context, rootNavigator: true).pop();

        // Step 6: Show success and navigate
        _showSuccessSnackBar(context, 'Emergency alert sent successfully!');
        
        // Navigate to tracking screen
        _navigateToTrackingScreen(context, createdRequest);
        
        return true;

      } on LocationException catch (e) {
        Navigator.of(context, rootNavigator: true).pop();
        
        if (e.type == LocationExceptionType.permissionDenied ||
            e.type == LocationExceptionType.permissionPermanentlyDenied) {
          // Show settings dialog for permission issues
          await LocationService.showLocationSettingsDialog(context);
          return false;
        } else {
          _showErrorSnackBar(context, 'Location error: ${e.message}');
          return false;
        }
      } catch (e) {
        Navigator.of(context, rootNavigator: true).pop();
        
        // Step 6: Fallback to SMS if offline
        debugPrint('API failed, falling back to SMS: $e');
        return await _fallbackToSMS(context, type, description);
      }

    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackBar(context, 'Failed to send emergency alert');
      return false;
    }
  }

  /// Shows emergency confirmation bottom sheet
  static Future<bool> _showEmergencyConfirmation(
    BuildContext context,
    EmergencyType type,
  ) async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emergency icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emergency,
                color: Colors.red,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            
            // Title
            Text(
              'Emergency Alert',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            
            // Emergency type
            Text(
              type.typeDisplayName,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // Warning message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will send an emergency alert to nearby medical responders. '
                      'Only use this for real emergencies.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.grey),
                    ),
                    child: const Text('CANCEL'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('SEND ALERT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  /// Shows loading dialog
  static void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// Updates loading dialog message
  static void _updateLoadingDialog(BuildContext context, String message) {
    final dialog = context.findAncestorWidgetOfExactType<AlertDialog>();
    if (dialog != null) {
      Navigator.of(context, rootNavigator: true).pop();
      _showLoadingDialog(context, message);
    }
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

  /// Gets the current authenticated user
  static Future<UserModel?> _getCurrentUser() async {
    try {
      return await AuthService.getCurrentUser();
    } catch (e) {
      debugPrint('Failed to get current user: $e');
      return null;
    }
  }

  /// Navigates to tracking screen
  static void _navigateToTrackingScreen(BuildContext context, EmergencyRequest request) {
    context.go('/tracking', extra: {'requestId': request.id});
    debugPrint('Navigate to tracking screen for request: ${request.id}');
  }

  /// Falls back to SMS emergency alert
  static Future<bool> _fallbackToSMS(
    BuildContext context,
    EmergencyType type,
    String? description,
  ) async {
    try {
      _showLoadingDialog(context, 'Sending SMS emergency alert...');
      
      // Get user info
      final user = await _getCurrentUser();
      if (user == null) {
        Navigator.of(context, rootNavigator: true).pop();
        _showErrorSnackBar(context, 'User information not available');
        return false;
      }

      // Get last known location
      final position = await LocationService.getCachedLocation();
      if (position == null) {
        Navigator.of(context, rootNavigator: true).pop();
        _showErrorSnackBar(context, 'Location information not available');
        return false;
      }

      // Send SMS emergency alert
      final success = await sendSMSEmergencyAlert(
        position.latitude,
        position.longitude,
        type,
        user.name,
        user.phone,
      );

      Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        _showSuccessSnackBar(context, 'Emergency alert sent via SMS successfully!');
        
        final offlineRequest = EmergencyRequest(
          id: 'sms_${DateTime.now().millisecondsSinceEpoch}',
          userId: user.id,
          type: type,
          description: description ?? _defaultDescription,
          latitude: position.latitude,
          longitude: position.longitude,
          address: 'Sent via SMS fallback',
          status: EmergencyStatus.pending,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Store locally directly
        await EmergencyRepository.storeRequestLocally(offlineRequest);

        // Navigate to tracking screen
        _navigateToTrackingScreen(context, offlineRequest);
        return true;
      } else {
        _showErrorSnackBar(context, 'Failed to send SMS emergency alert');
        return false;
      }

    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackBar(context, 'SMS fallback failed');
      return false;
    }
  }

  /// Cancels an active emergency request
  /// 
  /// [context] - BuildContext for UI interactions
  /// [requestId] - ID of request to cancel
  /// 
  /// Returns true if cancellation was successful
  static Future<bool> cancelEmergencyRequest(
    BuildContext context,
    String requestId,
  ) async {
    try {
      _showLoadingDialog(context, 'Cancelling emergency request...');

      await EmergencyRepository.cancelRequest(requestId);

      Navigator.of(context, rootNavigator: true).pop();
      _showSuccessSnackBar(context, 'Emergency request cancelled');
      
      return true;
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackBar(context, 'Failed to cancel emergency request');
      return false;
    }
  }

  /// Gets the status of an emergency request
  /// 
  /// [requestId] - ID of emergency request
  /// 
  /// Returns current EmergencyStatus or null if not found
  static Future<EmergencyStatus?> getEmergencyStatus(String requestId) async {
    try {
      final request = await EmergencyRepository.getRequestById(requestId);
      return request?.status;
    } catch (e) {
      debugPrint('Failed to get emergency status: $e');
      return null;
    }
  }

  /// Updates the status of an emergency request
  /// 
  /// [requestId] - ID of emergency request
  /// [status] - New status
  /// 
  /// Returns true if update was successful
  static Future<bool> updateEmergencyStatus(
    String requestId,
    EmergencyStatus status,
  ) async {
    try {
      await EmergencyRepository.updateRequestStatus(requestId, status);
      return true;
    } catch (e) {
      debugPrint('Failed to update emergency status: $e');
      return false;
    }
  }
}

/// Sends SMS emergency alert with Twilio fallback
/// 
/// [lat] - Latitude of emergency location
/// [lng] - Longitude of emergency location
/// [type] - Type of emergency
/// [patientName] - Name of patient
/// [patientPhone] - Phone number of patient
/// 
/// Returns true if SMS was sent successfully
/// 
/// Never throws; returns false on total failure
Future<bool> sendSMSEmergencyAlert(
  double lat,
  double lng,
  EmergencyType type,
  String patientName,
  String patientPhone,
) async {
  try {
    // Compose SMS message
    final message = _composeEmergencySMS(lat, lng, type, patientName, patientPhone);
    
    // Try Twilio API first
    final twilioSuccess = await _sendViaTwilio(message);
    if (twilioSuccess) {
      debugPrint('Emergency SMS sent via Twilio');
      return true;
    }
    
    // Fallback to native SMS
    final nativeSuccess = await _sendViaNativeSMS(message);
    if (nativeSuccess) {
      debugPrint('Emergency SMS sent via native SMS');
      return true;
    }
    
    debugPrint('Both Twilio and native SMS failed');
    return false;
    
  } catch (e) {
    debugPrint('Error in sendSMSEmergencyAlert: $e');
    return false;
  }
}

/// Composes emergency SMS message
String _composeEmergencySMS(
  double lat,
  double lng,
  EmergencyType type,
  String patientName,
  String patientPhone,
) {
  final timestamp = DateTime.now().toIso8601String();
  final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
  
  return 'EMERGENCY [${type.typeDisplayName}] '
         'Patient: $patientName '
         '| Phone: $patientPhone '
         '| Location: $mapsUrl '
         '| Time: $timestamp';
}

/// Sends SMS via Twilio API
Future<bool> _sendViaTwilio(String message) async {
  try {
    // This would use your Twilio configuration
    // For now, we'll simulate the API call
    debugPrint('Attempting to send SMS via Twilio: $message');
    
    // Mock implementation - replace with actual Twilio API call
    await Future.delayed(const Duration(seconds: 1));
    
    // Simulate success/failure (remove this in production)
    return true; // Return true for demo
    
  } catch (e) {
    debugPrint('Twilio API failed: $e');
    return false;
  }
}

/// Sends SMS via native device SMS
Future<bool> _sendViaNativeSMS(String message) async {
  try {
    // This would use the telephony package
    // For now, we'll simulate the native SMS
    debugPrint('Attempting to send SMS via native device: $message');
    
    // Mock implementation - replace with actual telephony package usage
    await Future.delayed(const Duration(seconds: 1));
    
    // Simulate success/failure (remove this in production)
    return true; // Return true for demo
    
  } catch (e) {
    debugPrint('Native SMS failed: $e');
    return false;
  }
}
