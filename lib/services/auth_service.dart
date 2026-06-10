import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../repositories/auth_repository.dart';
import '../models/user_model.dart';
import '../models/user_registration_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart' hide NetworkException;
import 'package:go_router/go_router.dart';
import '../router.dart';

/// Service class for handling authentication operations in Flutter
///
/// Provides high-level authentication methods with secure storage,
/// state management, and navigation for the Mobile Emergency Medical Assistance App.
class AuthService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Storage keys
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';
  static const String _userRoleKey = 'user_role';
  static const String _userCacheKey = 'user_cache';

  /// Logs in a user with phone and password
  ///
  /// [context] - BuildContext for navigation and showing snack bars
  /// [phone] - User's phone number
  /// [password] - User's password
  ///
  /// Handles validation, API call, secure storage, and navigation.
  /// Shows loading state and error messages appropriately.
  static Future<void> loginUser(
    BuildContext context,
    String phone,
    String password,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      // Set loading state
      authProvider.setLoading(true);
      authProvider.clearError();

      // Validate inputs
      if (phone.isEmpty || password.isEmpty) {
        authProvider.setError('Phone and password are required');
        _showErrorSnackBar(context, 'Phone and password are required');
        return;
      }

      // Validate phone format
      if (!_isValidPhone(phone)) {
        authProvider.setError('Invalid phone number format');
        _showErrorSnackBar(context, 'Please enter a valid phone number');
        return;
      }

      // Validate password length
      if (password.length < 8) {
        authProvider.setError('Password must be at least 8 characters');
        _showErrorSnackBar(context, 'Password must be at least 8 characters');
        return;
      }

      // Call AuthRepository
      final response = await AuthRepository.login(phone, password);
      final user = response['user'] as UserModel;
      final token = response['token'] as String;
      final refreshToken = response['refreshToken'] as String;

      // Store JWT in secure storage and inject into ApiClient
      await _storeAuthData(user, token, refreshToken);
      ApiClient.setAuthToken(token);

      // Update auth provider state
      authProvider.setUser(user);
      authProvider.setAuthenticated(true);

      // Navigate to appropriate dashboard based on role
      _navigateToDashboard(context, user.role);
    } on NetworkException catch (e) {
      authProvider.setError('Network error: ${e.message}');
      _showErrorSnackBar(
        context,
        'Network error: Please check your internet connection',
      );
    } on AuthException catch (e) {
      authProvider.setError(e.message);

      // Handle invalid credentials separately
      if (e.statusCode == 401) {
        _showErrorSnackBar(context, 'Invalid phone number or password');
      } else {
        _showErrorSnackBar(context, e.message);
      }
    } catch (e) {
      authProvider.setError('An unexpected error occurred');
      _showErrorSnackBar(
        context,
        'An unexpected error occurred. Please try again.',
      );
    } finally {
      authProvider.setLoading(false);
    }
  }

  /// Registers a new user and immediately logs them in.
  ///
  /// On success the JWT is stored and the user is navigated to their dashboard.
  /// No OTP step — the backend handles validation server-side.
  static Future<void> registerUser(
    BuildContext context,
    UserRegistrationModel model,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      authProvider.setLoading(true);
      authProvider.clearError();

      // Client-side validation
      final validationError = _validateRegistrationModel(model);
      if (validationError != null) {
        authProvider.setError(validationError);
        _showErrorSnackBar(context, validationError);
        return;
      }

      // Call backend — returns {user, token, refreshToken}
      final response = await AuthRepository.register(model);
      final user = response['user'] as UserModel;
      final token = response['token'] as String;
      final refreshToken = response['refreshToken'] as String;

      // Persist JWT + user meta
      await _storeAuthData(user, token, refreshToken);
      ApiClient.setAuthToken(token);

      // Update provider state
      authProvider.setUser(user);
      authProvider.setAuthenticated(true);

      // Navigate to the right dashboard
      _navigateToDashboard(context, user.role);
    } on DuplicatePhoneException catch (e) {
      authProvider.setError(e.message);
      _showErrorSnackBar(context, 'This phone number is already registered');
    } on ValidationException catch (e) {
      authProvider.setError(e.message);
      _showErrorSnackBar(context, e.message);
    } on NetworkException catch (e) {
      authProvider.setError('Network error: ${e.message}');
      _showErrorSnackBar(
        context,
        'Network error: Please check your internet connection',
      );
    } catch (e) {
      authProvider.setError('Registration failed');
      _showErrorSnackBar(context, 'Registration failed. Please try again.');
    } finally {
      authProvider.setLoading(false);
    }
  }

  /// Logs out the current user and clears stored data
  ///
  /// [context] - BuildContext for navigation
  static Future<void> logout(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final token = await _secureStorage.read(key: _tokenKey);
      final userId = await _secureStorage.read(key: _userIdKey);

      if (token != null && userId != null) {
        // Call logout API to revoke token
        await AuthRepository.logout(userId, token);
      }

      // Clear local storage
      await _clearAuthData();

      // Update auth provider state
      authProvider.clearUser();
      authProvider.setAuthenticated(false);

      // Navigate to login screen
      _navigateToLogin(context);
    } catch (e) {
      // Even if API call fails, clear local data
      await _clearAuthData();
      authProvider.clearUser();
      authProvider.setAuthenticated(false);
      _navigateToLogin(context);
    }
  }

  /// Checks if user is authenticated and has valid token
  ///
  /// Returns true if user is authenticated, false otherwise
  static Future<bool> isAuthenticated() async {
    try {
      final token = await _secureStorage.read(key: _tokenKey);

      if (token == null) return false;

      // Verify token with backend
      await AuthRepository.verifyToken(token);
      return true;
    } catch (e) {
      // Token is invalid, clear auth data
      await _clearAuthData();
      return false;
    }
  }

  /// Gets the current authenticated user by calling the backend profile endpoint.
  ///
  /// Returns UserModel if authenticated, null otherwise.
  static Future<UserModel?> getCurrentUser() async {
    try {
      final token = await _secureStorage.read(key: _tokenKey);
      if (token == null) {
        // Try to load cached user data
        final cached = await _secureStorage.read(key: _userCacheKey);
        if (cached != null) {
          return UserModel.fromJson(jsonDecode(cached));
        }
        return null;
      }

      // Ensure the HTTP client always carries the latest JWT
      ApiClient.setAuthToken(token);

      // Fetch live profile from backend
      final response = await ApiClient.get('/users/profile');
      final user = UserModel.fromJson(response['user']);
      // Update cache with fresh data
      await _secureStorage.write(
        key: _userCacheKey,
        value: jsonEncode(user.toJson()),
      );
      return user;
    } on ApiException catch (e) {
      // 401 → token is expired/invalid; clear local data
      if (e.statusCode == 401) {
        await _clearAuthData();
        ApiClient.setAuthToken(null);
      }
      debugPrint('getCurrentUser API error: $e');
      // Attempt to return cached user if available
      final cached = await _secureStorage.read(key: _userCacheKey);
      if (cached != null) {
        return UserModel.fromJson(jsonDecode(cached));
      }
      return null;
    } catch (e) {
      debugPrint('getCurrentUser error: $e');
      final cached = await _secureStorage.read(key: _userCacheKey);
      if (cached != null) {
        return UserModel.fromJson(jsonDecode(cached));
      }
      return null;
    }
  }

  /// Updates profile details for the current authenticated user.
  static Future<UserModel> updateProfile({
    required String name,
    String? email,
    String? phone,
  }) async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null) {
      throw AuthException('You are not authenticated', 401);
    }

    ApiClient.setAuthToken(token);

    final payload = <String, dynamic>{'name': name.trim()};
    if (email != null) {
      final trimmed = email.trim();
      if (trimmed.isNotEmpty) {
        payload['email'] = trimmed;
      }
    }
    if (phone != null) {
      final trimmed = phone.trim();
      if (trimmed.isNotEmpty) {
        payload['phone'] = trimmed;
      }
    }

    final response = await ApiClient.put('/users/profile', data: payload);
    final updatedUser = UserModel.fromJson(response['user']);

    await _secureStorage.write(
      key: _userCacheKey,
      value: jsonEncode(updatedUser.toJson()),
    );

    return updatedUser;
  }

  /// Refreshes the access token using the stored refresh token
  ///
  /// Returns true if refresh was successful, false otherwise
  static Future<bool> refreshToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);

      if (refreshToken == null) return false;

      final response = await AuthRepository.refreshToken(refreshToken);
      final newToken = response['token'] as String;
      final newRefreshToken = response['refreshToken'] as String;

      // Update stored tokens
      await _secureStorage.write(key: _tokenKey, value: newToken);
      await _secureStorage.write(key: _refreshTokenKey, value: newRefreshToken);

      return true;
    } catch (e) {
      // Refresh failed, clear auth data
      await _clearAuthData();
      return false;
    }
  }

  /// Stores authentication data securely
  static Future<void> _storeAuthData(
    UserModel user,
    String token,
    String refreshToken,
  ) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    await _secureStorage.write(key: _userIdKey, value: user.id);
    await _secureStorage.write(key: _userRoleKey, value: user.role);

    // Store role in SharedPreferences for easy access
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', user.role);
    // Store entire user JSON for offline access
    await _secureStorage.write(
      key: _userCacheKey,
      value: jsonEncode(user.toJson()),
    );
  }

  /// Clears all authentication data
  static Future<void> _clearAuthData() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _userRoleKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
  }

  /// Validates phone number format
  static bool _isValidPhone(String phone) {
    // Basic phone validation - adjust regex based on your requirements
    return RegExp(r'^\+?[1-9]\d{1,14}$').hasMatch(phone);
  }

  /// Validates registration model fields
  static String? _validateRegistrationModel(UserRegistrationModel model) {
    // Name validation
    if (model.name.trim().length < 2) {
      return 'Name must be at least 2 characters long';
    }

    // Phone validation
    if (!_isValidPhone(model.phone)) {
      return 'Invalid phone number format';
    }

    // Email validation (if provided)
    if (model.email != null && model.email!.isNotEmpty) {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(model.email!)) {
        return 'Invalid email format';
      }
    }

    // Password validation
    if (model.password.length < 8) {
      return 'Password must be at least 8 characters long';
    }

    // Password strength validation
    if (!_isStrongPassword(model.password)) {
      return 'Password must contain at least one uppercase letter, one lowercase letter, and one number';
    }

    // Confirm password validation
    if (model.password != model.confirmPassword) {
      return 'Passwords do not match';
    }

    // Role validation
    if (!['patient', 'responder'].contains(model.role)) {
      return 'Invalid role selected';
    }

    return null; // No validation errors
  }

  /// Checks password strength
  static bool _isStrongPassword(String password) {
    return password.contains(RegExp(r'[A-Z]')) && // Uppercase
        password.contains(RegExp(r'[a-z]')) && // Lowercase
        password.contains(RegExp(r'[0-9]')); // Number
  }

  /// Shows error snack bar
  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Navigates to appropriate dashboard based on user role
  static void _navigateToDashboard(BuildContext context, String role) {
    if (role == 'patient') {
      context.go('/home');
    } else if (role == 'responder') {
      context.go('/responder');
    } else {
      context.go('/home'); // Default fallback
    }
  }

  /// Navigates to OTP verification screen
  static void _navigateToOTPVerification(
    BuildContext context,
    String phone,
    String userId,
  ) {
    // This would navigate to your OTP verification screen
    // context.go('/otp-verification', extra: {'phone': phone, 'userId': userId});
    // For now, we'll just print the navigation
    print('Navigate to OTP verification for phone: $phone, userId: $userId');
  }

  /// Navigates to login screen
  static void _navigateToLogin(BuildContext context) {
    context.go('/login');
  }

  /// Sends OTP to the provided phone number
  static Future<void> _sendOTP(String phone) async {
    // This would call your OTP service
    // For now, we'll just simulate the call
    print('Sending OTP to phone: $phone');
    await Future.delayed(const Duration(seconds: 1)); // Simulate API call
  }
}
