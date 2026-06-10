import 'package:flutter/material.dart';
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

    final uri = Uri.parse('tel:$cleanNumber');
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      _showError(context, 'Could not open the phone dialer.');
    }

    return launched;
  }

  static String _cleanPhoneNumber(String phoneNumber) {
    return phoneNumber.trim().replaceAll(RegExp(r'(?!^\+)[^\d]'), '');
  }

  static void _showError(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
