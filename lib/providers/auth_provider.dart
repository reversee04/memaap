import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

/// Provider class that manages authentication state
/// 
/// Handles user authentication state, loading states, and error messages
/// for the Mobile Emergency Medical Assistance App.
class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  UserModel? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  bool get isPatient => _user?.role == 'patient';
  bool get isResponder => _user?.role == 'responder';

  /// Sets the current user and updates authentication state
  void setUser(UserModel user) {
    _user = user;
    _isAuthenticated = true;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clears the current user and authentication state
  void clearUser() {
    _user = null;
    _isAuthenticated = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Sets the authentication state
  void setAuthenticated(bool authenticated) {
    _isAuthenticated = authenticated;
    notifyListeners();
  }

  /// Sets the loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Sets the error message
  void setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Clears the error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Updates user information
  void updateUser(UserModel updatedUser) {
    if (_user != null && _user!.id == updatedUser.id) {
      _user = updatedUser;
      notifyListeners();
    }
  }

  /// Resets the provider to initial state
  void reset() {
    _user = null;
    _isAuthenticated = false;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
