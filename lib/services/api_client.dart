import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// Custom exceptions for API operations
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;
  
  ApiException(this.message, [this.statusCode, this.data]);
  
  @override
  String toString() => 'ApiException: $message';
}

class NetworkException extends ApiException {
  NetworkException(String message) : super(message);
}

class ConflictException extends ApiException {
  ConflictException(String message, [dynamic data]) : super(message, 409, data);
}

/// HTTP client for API communication
/// 
/// Provides methods for making HTTP requests with proper error handling,
/// authentication, and timeout management for Mobile Emergency Medical Assistance App.
class ApiClient {
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const String _contentType = 'application/json';
  
  static String? _authToken;
  static WebSocketChannel? _webSocketChannel;

  /// Gets the base API URL from environment configuration
  static String get _baseUrl => AppConfig.baseUrl;

  /// Sets the authentication token for API requests
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Gets the current authentication token
  static String? get authToken => _authToken;

  /// Makes a GET request to the specified endpoint
  /// 
  /// [endpoint] - API endpoint path
  /// [headers] - Optional additional headers
  /// [timeout] - Optional request timeout
  /// 
  /// Returns the response data
  /// 
  /// Throws [ApiException] if the request fails
  static Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl$endpoint'),
            headers: _buildHeaders(headers),
          )
          .timeout(timeout ?? _defaultTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Makes a POST request to the specified endpoint
  /// 
  /// [endpoint] - API endpoint path
  /// [data] - Request body data
  /// [headers] - Optional additional headers
  /// [timeout] - Optional request timeout
  /// 
  /// Returns the response data
  /// 
  /// Throws [ApiException] if the request fails
  static Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: _buildHeaders(headers),
            body: data != null ? jsonEncode(data) : null,
          )
          .timeout(timeout ?? _defaultTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Makes a PUT request to the specified endpoint
  /// 
  /// [endpoint] - API endpoint path
  /// [data] - Request body data
  /// [headers] - Optional additional headers
  /// [timeout] - Optional request timeout
  /// 
  /// Returns the response data
  /// 
  /// Throws [ApiException] if the request fails
  static Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl$endpoint'),
            headers: _buildHeaders(headers),
            body: data != null ? jsonEncode(data) : null,
          )
          .timeout(timeout ?? _defaultTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Makes a DELETE request to the specified endpoint
  /// 
  /// [endpoint] - API endpoint path
  /// [headers] - Optional additional headers
  /// [timeout] - Optional request timeout
  /// 
  /// Returns the response data
  /// 
  /// Throws [ApiException] if the request fails
  static Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_baseUrl$endpoint'),
            headers: _buildHeaders(headers),
          )
          .timeout(timeout ?? _defaultTimeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Uploads a file to the specified endpoint
  /// 
  /// [endpoint] - API endpoint path
  /// [file] - File to upload
  /// [fieldName] - Form field name for the file
  /// [additionalFields] - Additional form fields
  /// [headers] - Optional additional headers
  /// [timeout] - Optional request timeout
  /// 
  /// Returns the response data
  /// 
  /// Throws [ApiException] if the upload fails
  static Future<Map<String, dynamic>> uploadFile(
    String endpoint,
    File file, {
    String fieldName = 'file',
    Map<String, String>? additionalFields,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl$endpoint'),
      );

      // Add headers
      request.headers.addAll(_buildHeaders(headers));

      // Add file
      final fileBytes = await file.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        fieldName,
        fileBytes,
        filename: file.path.split('/').last,
      );
      request.files.add(multipartFile);

      // Add additional fields
      if (additionalFields != null) {
        request.fields.addAll(additionalFields);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException('No internet connection');
    } on HttpException {
      throw NetworkException('Server error');
    } on FormatException {
      throw NetworkException('Invalid response format');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: ${e.toString()}');
    }
  }

  /// Creates a WebSocket connection for real-time updates
  /// 
  /// [endpoint] - WebSocket endpoint path
  /// [onMessage] - Callback for incoming messages
  /// [onError] - Callback for errors
  /// [onDone] - Callback for connection close
  /// 
  /// Returns the WebSocket channel
  static WebSocketChannel createWebSocket(
    String endpoint, {
    required Function(dynamic) onMessage,
    Function(dynamic)? onError,
    Function()? onDone,
  }) {
    try {
      final wsUrl = _baseUrl.replaceFirst('http', 'ws') + endpoint;
      
      if (_authToken != null) {
        final separator = wsUrl.contains('?') ? '&' : '?';
        final urlWithToken = '$wsUrl${separator}token=$_authToken';
        _webSocketChannel = WebSocketChannel.connect(Uri.parse(urlWithToken));
      } else {
        _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      }

      _webSocketChannel!.stream.listen(
        onMessage,
        onError: onError ?? (error) => print('WebSocket error: $error'),
        onDone: onDone ?? () => print('WebSocket closed'),
      );

      return _webSocketChannel!;
    } catch (e) {
      throw ApiException('Failed to create WebSocket: $e');
    }
  }

  /// Closes the WebSocket connection
  static Future<void> closeWebSocket() async {
    try {
      await _webSocketChannel?.sink.close();
      _webSocketChannel = null;
    } catch (e) {
      throw ApiException('Failed to close WebSocket: $e');
    }
  }

  /// Builds request headers with authentication
  static Map<String, String> _buildHeaders([Map<String, String>? additionalHeaders]) {
    final headers = <String, String>{
      'Content-Type': _contentType,
      'Accept': _contentType,
      'User-Agent': 'Memaap-Flutter/1.0',
    };

    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    return headers;
  }

  /// Handles HTTP response and throws appropriate exceptions
  static Map<String, dynamic> _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    
    try {
      final responseData = jsonDecode(response.body);
      
      switch (statusCode) {
        case 200:
        return responseData;
        case 201:
          return responseData;
        case 204:
          return {}; // No content
        case 400:
          throw ApiException(responseData['message'] ?? 'Bad request', statusCode);
        case 401:
          throw ApiException(responseData['message'] ?? 'Unauthorized', statusCode);
        case 403:
          throw ApiException(responseData['message'] ?? 'Forbidden', statusCode);
        case 404:
          throw ApiException(responseData['message'] ?? 'Not found', statusCode);
        case 409:
          throw ConflictException(responseData['message'] ?? 'Conflict', responseData);
        case 422:
          throw ApiException(responseData['message'] ?? 'Validation error', statusCode);
        case 429:
          throw ApiException('Too many requests', statusCode);
        case 500:
          throw ApiException('Internal server error', statusCode);
        case 502:
          throw ApiException('Bad gateway', statusCode);
        case 503:
          throw ApiException('Service unavailable', statusCode);
        default:
          throw ApiException(
            responseData['message'] ?? 'Request failed with status $statusCode',
            statusCode,
          );
      }
    } on FormatException {
      throw ApiException('Invalid response format', statusCode);
    }
  }

  /// Checks if the client has network connectivity
  static Future<bool> hasNetworkConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: _buildHeaders(),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Gets the current time from the server
  static Future<DateTime> getServerTime() async {
    try {
      final response = await get('/time');
      final serverTimeString = response['timestamp'] as String;
      return DateTime.parse(serverTimeString);
    } catch (e) {
      return DateTime.now(); // Fallback to local time
    }
  }
}
