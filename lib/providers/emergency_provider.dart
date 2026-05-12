import 'package:flutter/material.dart';
import '../services/emergency_service.dart';
import '../models/emergency_request_model.dart';

enum EmergencyState { idle, loading, success, error }

class EmergencyProvider extends ChangeNotifier {
  final EmergencyService _emergencyService = EmergencyService();

  EmergencyState _state = EmergencyState.idle;
  EmergencyState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _selectedEmergencyType = 'Maternal'; // Default from UI
  String get selectedEmergencyType => _selectedEmergencyType;

  void setEmergencyType(String type) {
    _selectedEmergencyType = type;
    notifyListeners();
  }

  Future<bool> triggerEmergency(BuildContext context) async {
    _setState(EmergencyState.loading);

    // Parse type
    EmergencyType type = EmergencyType.other;
    if (_selectedEmergencyType.toLowerCase().contains('maternal')) {
      type = EmergencyType.medical;
    }

    // Call the service to handle location, network, API, and SMS fallback
    final success = await EmergencyService.sendEmergencyAlert(context, type);

    if (success) {
      _setState(EmergencyState.success);
      return true;
    } else {
      _errorMessage = 'Failed to send emergency request. Please try again or call directly.';
      _setState(EmergencyState.error);
      return false;
    }
  }

  void reset() {
    _state = EmergencyState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  void _setState(EmergencyState newState) {
    _state = newState;
    notifyListeners();
  }
}
