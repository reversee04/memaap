import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'location_service.dart';
import 'network_service.dart';

class EmergencyService {
  final LocationService _locationService = LocationService();
  final NetworkService _networkService = NetworkService();
  
  // Replace with the actual Node.js backend URL later
  final String _apiUrl = 'https://mema-api-mock.onrender.com/api/emergency';
  final String _emergencySmsNumber = '112'; // Default SMS number

  Future<bool> sendEmergencyRequest(String emergencyType) async {
    try {
      // 1. Get Location
      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        throw Exception('Location permission denied or service disabled');
      }

      // 2. Check Network Status
      final isOnline = await _networkService.isOnline();

      // Mock Patient ID for now
      const String patientId = '#MW-8821';

      if (isOnline) {
        // 3a. Send via Data (API Request)
        print('Sending Emergency via API...');
        final response = await http.post(
          Uri.parse(_apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'patientId': patientId,
            'emergencyType': emergencyType,
            'location': {
              'lat': position.latitude,
              'lng': position.longitude,
            },
            'requestMethod': 'Data',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          return true; // Success
        } else {
          // If API fails, fallback to SMS
          print('API Failed, falling back to SMS...');
          return await _sendSmsFallback(emergencyType, position.latitude, position.longitude, patientId);
        }
      } else {
        // 3b. Send via SMS (Offline Fallback)
        print('Offline. Sending Emergency via SMS...');
        return await _sendSmsFallback(emergencyType, position.latitude, position.longitude, patientId);
      }
    } catch (e) {
      print('Error in sendEmergencyRequest: $e');
      return false;
    }
  }

  Future<bool> _sendSmsFallback(String type, double lat, double lng, String patientId) async {
    final String message = 'MEMA SOS: $type. Lat:$lat, Lng:$lng. ID:$patientId';
    // URL Encoding for the body
    final Uri smsUri = Uri.parse('sms:$_emergencySmsNumber?body=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
      return true; // We successfully launched the SMS app
    } else {
      print('Could not launch SMS intent');
      return false;
    }
  }
}
