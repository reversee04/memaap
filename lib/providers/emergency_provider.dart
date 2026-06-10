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

  // ── Selected emergency type ────────────────────────────────────────────────
  EmergencyType _selectedType = EmergencyType.other;
  EmergencyType get selectedType => _selectedType;

  /// Legacy string accessor kept for backward compatibility with UI tiles that
  /// compare against display name strings.
  String get selectedEmergencyType => _selectedType.typeDisplayName;

  void setEmergencyType(String typeName) {
    // Try to match a preset by display name first
    final preset = kQuickEmergencyPresets.where(
      (p) => p.type.typeDisplayName.toLowerCase() == typeName.toLowerCase(),
    ).firstOrNull;
    if (preset != null) {
      _selectedType = preset.type;
      _selectedSeverity = preset.severity;
      _presetDescription = preset.description;
    } else {
      _selectedType = EmergencyType.other;
    }
    notifyListeners();
  }

  // ── Quick preset selection ─────────────────────────────────────────────────
  void selectPreset(QuickEmergencyPreset preset) {
    _selectedType = preset.type;
    _selectedSeverity = preset.severity;
    _presetDescription = preset.description;
    notifyListeners();
  }

  void setType(EmergencyType type) {
    _selectedType = type;
    notifyListeners();
  }

  // ── Severity ───────────────────────────────────────────────────────────────
  EmergencySeverity _selectedSeverity = EmergencySeverity.urgent;
  EmergencySeverity get selectedSeverity => _selectedSeverity;

  void setSeverity(EmergencySeverity severity) {
    _selectedSeverity = severity;
    notifyListeners();
  }

  // ── Custom description (from preset or free-text) ─────────────────────────
  String? _presetDescription;
  String? get presetDescription => _presetDescription;

  void setDescription(String description) {
    _presetDescription = description;
    notifyListeners();
  }

  // ── Trigger ────────────────────────────────────────────────────────────────

  Future<bool> triggerEmergency(BuildContext context) async {
    debugPrint('[EmergencyProvider] triggerEmergency: type=$_selectedType, severity=$_selectedSeverity');
    _setState(EmergencyState.loading);

    final success = await EmergencyService.sendEmergencyAlert(
      context,
      _selectedType,
      severity: _selectedSeverity,
      description: _presetDescription,
    );

    debugPrint('[EmergencyProvider] sendEmergencyAlert returned: $success');

    if (success) {
      _setState(EmergencyState.success);
      return true;
    } else {
      _errorMessage =
          'Failed to send emergency request. Please try again or call directly.';
      _setState(EmergencyState.error);
      return false;
    }
  }

  void reset() {
    _state = EmergencyState.idle;
    _errorMessage = null;
    _selectedType = EmergencyType.other;
    _selectedSeverity = EmergencySeverity.urgent;
    _presetDescription = null;
    notifyListeners();
  }

  void _setState(EmergencyState newState) {
    _state = newState;
    notifyListeners();
  }
}
