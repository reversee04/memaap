import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class PhoneCallService {
  static Future<bool> makePhoneCall({
    required String phoneNumber,
    required BuildContext context,
  }) async {
    final cleanNumber = _cleanPhoneNumber(phoneNumber);
    if (cleanNumber.isEmpty) {
      _showError(context, 'Responder phone number is not available.');
      return false;
    }

    final hasPermission = await _requestPhonePermission(context);
    if (!hasPermission) return false;

    final uri = Uri(scheme: 'tel', path: cleanNumber);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      _showError(context, 'Could not open the phone dialer.');
    }

    return launched;
  }

  static String _cleanPhoneNumber(String phoneNumber) {
    return phoneNumber.trim().replaceAll(RegExp(r'(?!^\+)[^\d]'), '');
  }

  static Future<bool> _requestPhonePermission(BuildContext context) async {
    final status = await Permission.phone.status;

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (context.mounted) _showPermissionDialog(context);
      return false;
    }

    final result = await Permission.phone.request();
    if (result.isGranted || result.isLimited) return true;

    if (result.isPermanentlyDenied || result.isRestricted) {
      if (context.mounted) _showPermissionDialog(context);
    }

    return false;
  }

  static void _showPermissionDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Phone Permission Required'),
        content: const Text(
          'Enable phone permission in app settings to call the assigned responder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static void _showError(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
