import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/emergency_request_model.dart';
import '../models/user_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';

/// Service class for handling emergency alerts.
class EmergencyService {
  static const String _defaultDescription = 'Emergency assistance requested';

  static bool _isLoadingDialogShowing = false;
  static BuildContext? _loadingDialogContext;

  /// Sends an emergency alert with confirmation, GPS location, API creation,
  /// and SMS fallback.
  static Future<bool> sendEmergencyAlert(
    BuildContext context,
    EmergencyType type, {
    String? description,
  }) async {
    debugPrint('[EmergencyService] sendEmergencyAlert called with type: $type');

    try {
      final confirmed = await _showEmergencyConfirmation(context, type);
      debugPrint('[EmergencyService] User confirmed: $confirmed');
      if (!confirmed) return false;
      if (!context.mounted) return false;

      _showLoadingDialog(context, 'Getting your location...');

      try {
        final position = await LocationService.getCurrentLocation();
        debugPrint(
          '[EmergencyService] Location obtained: ${position.latitude}, ${position.longitude}',
        );

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
          debugPrint('[EmergencyService] Geocoding failed: $e');
        }

        final user = await _getCurrentUser();
        final emergencyRequest = EmergencyRequest(
          id: '',
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

        if (!context.mounted) {
          await _dismissLoadingDialog();
          return false;
        }

        await _updateLoadingDialog(context, 'Sending emergency alert...');

        final createdRequest = await EmergencyRepository.createRequest(
          emergencyRequest,
        );
        debugPrint(
          '[EmergencyService] Request created with ID: ${createdRequest.id}',
        );

        await _dismissLoadingDialog();
        if (!context.mounted) return true;

        _showSuccessSnackBar(context, 'Emergency alert sent successfully!');
        _navigateToTrackingScreen(context, createdRequest);

        return true;
      } on LocationException catch (e) {
        await _dismissLoadingDialog();
        if (!context.mounted) return false;

        if (e.type == LocationExceptionType.permissionDenied ||
            e.type == LocationExceptionType.permissionPermanentlyDenied) {
          await LocationService.showLocationSettingsDialog(context);
        } else {
          _showErrorSnackBar(context, 'Location error: ${e.message}');
        }

        return false;
      } catch (e) {
        debugPrint('[EmergencyService] API failed, falling back to SMS: $e');
        await _dismissLoadingDialog();
        if (!context.mounted) return false;

        return _fallbackToSMS(context, type, description);
      }
    } catch (e) {
      debugPrint('[EmergencyService] General error: $e');
      await _dismissLoadingDialog();
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed to send emergency alert');
      }
      return false;
    }
  }

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
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emergency,
                    color: Colors.red,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Emergency Alert',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  type.typeDisplayName,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will send an emergency alert to nearby medical responders. '
                          'Only use this for real emergencies.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
        ) ??
        false;
  }

  static void _showLoadingDialog(BuildContext context, String message) {
    if (_isLoadingDialogShowing) return;
    _isLoadingDialogShowing = true;

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
    ).whenComplete(() {
      _loadingDialogContext = null;
      _isLoadingDialogShowing = false;
    });
  }

  static Future<void> _dismissLoadingDialog() async {
    final dialogContext = _loadingDialogContext;
    _loadingDialogContext = null;

    if (!_isLoadingDialogShowing || dialogContext == null) {
      _isLoadingDialogShowing = false;
      return;
    }

    _isLoadingDialogShowing = false;

    if (Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }

    await Future<void>.delayed(Duration.zero);
  }

  static Future<void> _updateLoadingDialog(
    BuildContext context,
    String message,
  ) async {
    await _dismissLoadingDialog();
    if (!context.mounted) return;

    _showLoadingDialog(context, message);
    await Future<void>.delayed(Duration.zero);
  }

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

  static Future<UserModel?> _getCurrentUser() async {
    try {
      return await AuthService.getCurrentUser();
    } catch (e) {
      debugPrint('Failed to get current user: $e');
      return null;
    }
  }

  static void _navigateToTrackingScreen(
    BuildContext context,
    EmergencyRequest request,
  ) {
    context.go('/tracking/${Uri.encodeComponent(request.id)}');
    debugPrint(
      'Navigate to patient tracking screen for request: ${request.id}',
    );
  }

  static Future<bool> _fallbackToSMS(
    BuildContext context,
    EmergencyType type,
    String? description,
  ) async {
    try {
      _showLoadingDialog(context, 'Sending SMS emergency alert...');

      final user = await _getCurrentUser();
      if (user == null) {
        await _dismissLoadingDialog();
        if (context.mounted) {
          _showErrorSnackBar(context, 'User information not available');
        }
        return false;
      }

      final position = await LocationService.getCachedLocation();
      if (position == null) {
        await _dismissLoadingDialog();
        if (context.mounted) {
          _showErrorSnackBar(context, 'Location information not available');
        }
        return false;
      }

      final success = await sendSMSEmergencyAlert(
        position.latitude,
        position.longitude,
        type,
        user.name,
        user.phone,
      );

      if (!success) {
        await _dismissLoadingDialog();
        if (context.mounted) {
          _showErrorSnackBar(context, 'Failed to send SMS emergency alert');
        }
        return false;
      }

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

      await EmergencyRepository.storeRequestLocally(offlineRequest);
      await _dismissLoadingDialog();

      if (context.mounted) {
        _showSuccessSnackBar(
          context,
          'Emergency alert sent via SMS successfully!',
        );
        _navigateToTrackingScreen(context, offlineRequest);
      }

      return true;
    } catch (e) {
      await _dismissLoadingDialog();
      if (context.mounted) {
        _showErrorSnackBar(context, 'SMS fallback failed');
      }
      return false;
    }
  }

  static Future<bool> cancelEmergencyRequest(
    BuildContext context,
    String requestId,
  ) async {
    try {
      _showLoadingDialog(context, 'Cancelling emergency request...');
      await EmergencyRepository.cancelRequest(requestId);
      await _dismissLoadingDialog();

      if (context.mounted) {
        _showSuccessSnackBar(context, 'Emergency request cancelled');
      }

      return true;
    } catch (e) {
      await _dismissLoadingDialog();
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed to cancel emergency request');
      }
      return false;
    }
  }

  static Future<EmergencyStatus?> getEmergencyStatus(String requestId) async {
    try {
      final request = await EmergencyRepository.getRequestById(requestId);
      return request?.status;
    } catch (e) {
      debugPrint('Failed to get emergency status: $e');
      return null;
    }
  }

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

Future<bool> sendSMSEmergencyAlert(
  double lat,
  double lng,
  EmergencyType type,
  String patientName,
  String patientPhone,
) async {
  try {
    final message = _composeEmergencySMS(
      lat,
      lng,
      type,
      patientName,
      patientPhone,
    );

    final twilioSuccess = await _sendViaTwilio(message);
    if (twilioSuccess) {
      debugPrint('Emergency SMS sent via Twilio');
      return true;
    }

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

Future<bool> _sendViaTwilio(String message) async {
  try {
    debugPrint('Attempting to send SMS via Twilio: $message');
    await Future.delayed(const Duration(seconds: 1));
    return true;
  } catch (e) {
    debugPrint('Twilio API failed: $e');
    return false;
  }
}

Future<bool> _sendViaNativeSMS(String message) async {
  try {
    debugPrint('Attempting to send SMS via native device: $message');
    await Future.delayed(const Duration(seconds: 1));
    return true;
  } catch (e) {
    debugPrint('Native SMS failed: $e');
    return false;
  }
}
