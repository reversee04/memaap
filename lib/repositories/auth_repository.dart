import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user_model.dart';
import '../models/user_registration_model.dart';

/// Custom exceptions for authentication
class AuthException implements Exception {
  final String message;
  final int? statusCode;
  
  AuthException(this.message, [this.statusCode]);
  
  @override
  String toString() => 'AuthException: $message';
}

class DuplicatePhoneException extends AuthException {
  DuplicatePhoneException(String message) : super(message, 409);
}

class NetworkException extends AuthException {
  NetworkException(String message) : super(message);
}

class ValidationException extends AuthException {
  ValidationException(String message) : super(message, 400);
}

/// Repository class that handles authentication API calls
/// 
/// Provides methods for user registration, login, and token management
/// for the Mobile Emergency Medical Assistance App.
class AuthRepository {
  static const String _baseUrlKey = 'BASE_API_URL';
  static const Duration _timeout = Duration(seconds: 15);
  
  /// Gets the base API URL from environment configuration
  static String get _baseUrl => dotenv.env[_baseUrlKey] ?? 'https://api.memaap.com';

  /// Registers a new user with the provided registration data
  /// 
  /// [model] - UserRegistrationModel containing registration details
  /// 
  /// Returns the registered UserModel
  /// 
  /// Throws [DuplicatePhoneException] if phone number already exists
  /// Throws [ValidationException] if validation fails
  /// Throws [NetworkException] if network error occurs
  /// Throws [AuthException] for other authentication errors
  static Future<UserModel> register(UserRegistrationModel model) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/register'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(model.toJson()),
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 201:
          return UserModel.fromJson(responseData['user']);
        case 409:
          throw DuplicatePhoneException(responseData['message'] ?? 'Phone number already registered');
        case 400:
          throw ValidationException(responseData['message'] ?? 'Validation failed');
        default:
          throw AuthException(
            responseData['message'] ?? 'Registration failed',
            response.statusCode,
          );
      }
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Logs in a user with phone and password
  /// 
  /// [phone] - User's phone number
  /// [password] - User's password
  /// 
  /// Returns a map containing user data and tokens
  /// 
  /// Throws [AuthException] if credentials are invalid
  /// Throws [NetworkException] if network error occurs
  static Future<Map<String, dynamic>> login(String phone, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'phone': phone,
              'password': password,
            }),
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          return {
            'user': UserModel.fromJson(responseData['user']),
            'token': responseData['token'],
            'refreshToken': responseData['refreshToken'],
          };
        case 401:
          throw AuthException(responseData['message'] ?? 'Invalid credentials', 401);
        case 400:
          throw ValidationException(responseData['message'] ?? 'Invalid input');
        default:
          throw AuthException(
            responseData['message'] ?? 'Login failed',
            response.statusCode,
          );
      }
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Refreshes an access token using a refresh token
  /// 
  /// [refreshToken] - The refresh token
  /// 
  /// Returns a map containing new tokens
  /// 
  /// Throws [AuthException] if refresh token is invalid
  /// Throws [NetworkException] if network error occurs
  static Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          return {
            'token': responseData['token'],
            'refreshToken': responseData['refreshToken'],
          };
        case 401:
          throw AuthException(responseData['message'] ?? 'Invalid refresh token', 401);
        default:
          throw AuthException(
            responseData['message'] ?? 'Token refresh failed',
            response.statusCode,
          );
      }
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Logs out a user by revoking their tokens
  /// 
  /// [userId] - User ID
  /// [token] - Access token to revoke
  /// 
  /// Throws [AuthException] if logout fails
  /// Throws [NetworkException] if network error occurs
  static Future<void> logout(String userId, String token) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'userId': userId}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final responseData = jsonDecode(response.body);
        throw AuthException(
          responseData['message'] ?? 'Logout failed',
          response.statusCode,
        );
      }
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Verifies a token's validity
  /// 
  /// [token] - JWT token to verify
  /// 
  /// Returns the decoded token payload
  /// 
  /// Throws [AuthException] if token is invalid
  /// Throws [NetworkException] if network error occurs
  static Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/auth/verify'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);

      final responseData = jsonDecode(response.body);

      switch (response.statusCode) {
        case 200:
          return responseData;
        case 401:
          throw AuthException(responseData['message'] ?? 'Invalid token', 401);
        default:
          throw AuthException(
            responseData['message'] ?? 'Token verification failed',
            response.statusCode,
          );
      }
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }
}
